using System.Text;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace NexChat.API.Services;

/// <summary>
/// يحمّل الفيديو والصورة من روابط خارجية إلى uploads ثم ينشئ ShortFilm.
/// </summary>
public class ShortFilmIngestService(
    HttpClient http,
    AppDbContext db,
    IWebHostEnvironment env,
    IConfiguration config,
    ILogger<ShortFilmIngestService> logger)
{
    private const long MaxVideoBytes = 100L * 1024 * 1024;
    private const long MaxThumbBytes = 10L * 1024 * 1024;

    public async Task<ShortFilm> IngestAsync(
        HttpRequest httpRequest,
        string title,
        string? description,
        string videoUrl,
        string? thumbnailUrl,
        int? durationSeconds,
        Guid? sectionId,
        int sortOrder,
        bool isActive,
        bool isFeatured,
        string? seriesTitle = null,
        Guid? seriesId = null,
        int? episodeNumber = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(title))
            throw new ArgumentException("Title is required");
        if (string.IsNullOrWhiteSpace(videoUrl))
            throw new ArgumentException("VideoUrl is required");

        var trimmedTitle = title.Trim();
        ShortFilmSeries? series = null;

        if (seriesId is Guid sidExplicit)
        {
            series = await db.ShortFilmSeries.FirstOrDefaultAsync(s => s.Id == sidExplicit, ct)
                ?? throw new ArgumentException("SeriesId not found");
        }
        else if (!string.IsNullOrWhiteSpace(seriesTitle))
        {
            var st = seriesTitle.Trim();
            series = await db.ShortFilmSeries.FirstOrDefaultAsync(s => s.Title == st, ct);
            if (series == null)
            {
                series = new ShortFilmSeries
                {
                    Title = st,
                    Description = null,
                    CoverUrl = null,
                    SectionId = sectionId,
                    SortOrder = 0,
                    IsActive = true,
                    IsFeatured = false,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };
                db.ShortFilmSeries.Add(series);
                await db.SaveChangesAsync(ct);
            }
        }

        if (series != null)
        {
            var ep = episodeNumber is > 0 ? episodeNumber.Value : 1;
            var dupEpisode = await db.ShortFilms.AsNoTracking()
                .AnyAsync(f => f.SeriesId == series.Id && f.EpisodeNumber == ep, ct);
            if (dupEpisode)
                throw new DuplicateShortFilmEpisodeException(series.Title, ep);
            episodeNumber = ep;
        }
        else
        {
            var duplicate = await db.ShortFilms.AsNoTracking()
                .AnyAsync(f => f.Title == trimmedTitle && f.SeriesId == null, ct);
            if (duplicate)
                throw new DuplicateShortFilmTitleException(trimmedTitle);
            episodeNumber = null;
        }

        if (sectionId is Guid secId)
        {
            var ok = await db.ShortFilmSections.AnyAsync(s => s.Id == secId, ct);
            if (!ok) throw new ArgumentException("SectionId not found");
        }

        var sourceVideo = videoUrl.Trim();
        var sourceThumb = string.IsNullOrWhiteSpace(thumbnailUrl) ? null : thumbnailUrl.Trim();

        if (IsHlsUrl(sourceVideo))
            throw new ArgumentException(
                "VideoUrl is HLS (.m3u8). Send a direct progressive file (.mp4 / .webm / .mov) instead.");

        logger.LogInformation(
            "Ingest short film title={Title} series={Series} ep={Episode} video={Video}",
            trimmedTitle, series?.Title, episodeNumber, sourceVideo);

        string savedVideo;
        if (IsAlreadyLocalUpload(sourceVideo))
        {
            savedVideo = sourceVideo;
        }
        else
        {
            if (!Uri.TryCreate(sourceVideo, UriKind.Absolute, out var vu) ||
                (vu.Scheme != Uri.UriSchemeHttp && vu.Scheme != Uri.UriSchemeHttps))
                throw new ArgumentException("VideoUrl must be an absolute http(s) URL or a local uploads path");

            savedVideo = await DownloadToUploadsAsync(
                httpRequest, sourceVideo, [".mp4", ".webm", ".mov"], ".mp4", MaxVideoBytes, ct);
        }

        string? savedThumb = null;
        if (!string.IsNullOrWhiteSpace(sourceThumb))
        {
            if (IsAlreadyLocalUpload(sourceThumb))
            {
                savedThumb = sourceThumb;
            }
            else
            {
                try
                {
                    savedThumb = await DownloadToUploadsAsync(
                        httpRequest, sourceThumb, [".jpg", ".jpeg", ".png", ".webp", ".gif"], ".jpg",
                        MaxThumbBytes, ct);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Thumbnail download failed for {Url}", sourceThumb);
                }
            }
        }

        if (series != null && string.IsNullOrWhiteSpace(series.CoverUrl) && !string.IsNullOrWhiteSpace(savedThumb))
        {
            series.CoverUrl = savedThumb;
            series.UpdatedAt = DateTime.UtcNow;
        }

        var film = new ShortFilm
        {
            Title = trimmedTitle,
            Description = string.IsNullOrWhiteSpace(description) ? null : description.Trim(),
            VideoUrl = savedVideo,
            ThumbnailUrl = savedThumb,
            DurationSeconds = durationSeconds > 0 ? durationSeconds : null,
            SectionId = sectionId ?? series?.SectionId,
            SeriesId = series?.Id,
            EpisodeNumber = episodeNumber,
            SortOrder = sortOrder,
            IsActive = isActive,
            IsFeatured = isFeatured,
            CreatedByAdminId = null,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.ShortFilms.Add(film);
        await db.SaveChangesAsync(ct);
        await db.Entry(film).Reference(f => f.Section).LoadAsync(ct);
        await db.Entry(film).Reference(f => f.Series).LoadAsync(ct);

        // Episode 1 also gets a standalone short-film card titled with the series name (no "episode 1").
        if (series != null && episodeNumber == 1)
            await EnsureStandaloneSeriesTeaserAsync(series, ct);

        return film;
    }

    public async Task<(ShortFilmSeries Series, List<ShortFilm> Created, List<object> Skipped, ShortFilm? ShortsTeaser)> IngestSeriesAsync(
        HttpRequest httpRequest,
        string? seriesTitle,
        Guid? seriesId,
        string? description,
        string? coverUrl,
        Guid? sectionId,
        int sortOrder,
        bool isActive,
        bool isFeatured,
        IReadOnlyList<SeriesEpisodeIngestItem> episodes,
        CancellationToken ct = default)
    {
        if (episodes.Count == 0)
            throw new ArgumentException("episodes array is required and must not be empty");
        if (seriesId is null && string.IsNullOrWhiteSpace(seriesTitle))
            throw new ArgumentException("series_title (or seriesTitle) or series_id is required");

        if (sectionId is Guid secId)
        {
            var ok = await db.ShortFilmSections.AnyAsync(s => s.Id == secId, ct);
            if (!ok) throw new ArgumentException("SectionId not found");
        }

        ShortFilmSeries series;
        var createdNew = false;
        if (seriesId is Guid sidExplicit)
        {
            series = await db.ShortFilmSeries.FirstOrDefaultAsync(s => s.Id == sidExplicit, ct)
                ?? throw new ArgumentException("SeriesId not found");
        }
        else
        {
            var st = seriesTitle!.Trim();
            var existing = await db.ShortFilmSeries.FirstOrDefaultAsync(s => s.Title == st, ct);
            if (existing != null)
            {
                series = existing;
            }
            else
            {
                series = new ShortFilmSeries
                {
                    Title = st,
                    Description = string.IsNullOrWhiteSpace(description) ? null : description.Trim(),
                    CoverUrl = null,
                    SectionId = sectionId,
                    SortOrder = sortOrder,
                    IsActive = isActive,
                    IsFeatured = isFeatured,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };
                db.ShortFilmSeries.Add(series);
                await db.SaveChangesAsync(ct);
                createdNew = true;
            }
        }

        // Refresh series metadata when provided (cover downloaded below if remote URL).
        var dirty = false;
        if (!string.IsNullOrWhiteSpace(description))
        {
            series.Description = description.Trim();
            dirty = true;
        }
        if (sectionId.HasValue)
        {
            series.SectionId = sectionId;
            dirty = true;
        }
        if (createdNew == false)
        {
            series.SortOrder = sortOrder;
            series.IsActive = isActive;
            series.IsFeatured = isFeatured;
            dirty = true;
        }
        if (dirty)
        {
            series.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        if (!string.IsNullOrWhiteSpace(coverUrl))
        {
            try
            {
                var source = coverUrl.Trim();
                string savedCover;
                if (IsAlreadyLocalUpload(source))
                {
                    savedCover = source;
                }
                else
                {
                    savedCover = await DownloadToUploadsAsync(
                        httpRequest, source, [".jpg", ".jpeg", ".png", ".webp", ".gif"], ".jpg",
                        MaxThumbBytes, ct);
                }
                series.CoverUrl = savedCover;
                series.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Series cover download failed for {Url}", coverUrl);
            }
        }

        var created = new List<ShortFilm>(episodes.Count);
        var skipped = new List<object>();

        // Stable episode order: explicit numbers first, else index+1
        var ordered = episodes
            .Select((ep, idx) => (ep, idx, num: ep.EpisodeNumber is > 0 ? ep.EpisodeNumber.Value : idx + 1))
            .OrderBy(x => x.num)
            .ThenBy(x => x.idx)
            .ToList();

        foreach (var (ep, _, epNum) in ordered)
        {
            if (string.IsNullOrWhiteSpace(ep.Title) || string.IsNullOrWhiteSpace(ep.VideoUrl))
            {
                skipped.Add(new
                {
                    skipped = true,
                    reason = "missing_title_or_video_url",
                    episodeNumber = epNum,
                    title = ep.Title
                });
                continue;
            }

            try
            {
                var film = await IngestAsync(
                    httpRequest,
                    ep.Title,
                    ep.Description,
                    ep.VideoUrl,
                    ep.ThumbnailUrl,
                    ep.DurationSeconds,
                    ep.SectionId ?? sectionId ?? series.SectionId,
                    ep.SortOrder ?? epNum,
                    ep.IsActive ?? true,
                    ep.IsFeatured ?? false,
                    seriesTitle: null,
                    seriesId: series.Id,
                    episodeNumber: epNum,
                    ct);
                created.Add(film);
            }
            catch (DuplicateShortFilmEpisodeException ex)
            {
                skipped.Add(new
                {
                    skipped = true,
                    reason = "duplicate_episode",
                    message = ex.Message,
                    seriesTitle = ex.SeriesTitle,
                    episodeNumber = ex.EpisodeNumber,
                    title = ep.Title
                });
            }
            catch (ArgumentException ex)
            {
                skipped.Add(new
                {
                    skipped = true,
                    reason = "validation",
                    message = ex.Message,
                    episodeNumber = epNum,
                    title = ep.Title
                });
            }
            catch (InvalidOperationException ex)
            {
                skipped.Add(new
                {
                    skipped = true,
                    reason = "download_failed",
                    message = ex.Message,
                    episodeNumber = epNum,
                    title = ep.Title
                });
            }
        }

        await db.Entry(series).Reference(s => s.Section).LoadAsync(ct);
        var teaser = await EnsureStandaloneSeriesTeaserAsync(series, ct);
        return (series, created, skipped, teaser);
    }

    /// <summary>
    /// نسخة في الأفلام القصيرة من الحلقة 1: نفس الفيديو، العنوان = اسم المسلسل (بدون "الحلقة 1").
    /// </summary>
    private async Task<ShortFilm?> EnsureStandaloneSeriesTeaserAsync(ShortFilmSeries series, CancellationToken ct)
    {
        var teaserTitle = series.Title.Trim();
        if (string.IsNullOrEmpty(teaserTitle))
            return null;

        var ep1 = await db.ShortFilms.AsNoTracking()
            .Where(f => f.SeriesId == series.Id && f.EpisodeNumber == 1 && f.IsActive)
            .OrderBy(f => f.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (ep1 == null)
            return null;

        // Prefer the standalone copy that already shares episode-1 video.
        var byVideo = await db.ShortFilms
            .Include(f => f.Section)
            .FirstOrDefaultAsync(f =>
                f.SeriesId == null &&
                f.VideoUrl == ep1.VideoUrl, ct);
        if (byVideo != null)
        {
            if (!string.Equals(byVideo.Title, teaserTitle, StringComparison.Ordinal))
            {
                byVideo.Title = teaserTitle;
                byVideo.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }
            return byVideo;
        }

        var byTitle = await db.ShortFilms
            .Include(f => f.Section)
            .FirstOrDefaultAsync(f => f.SeriesId == null && f.Title == teaserTitle, ct);
        if (byTitle != null)
        {
            // Same title but different video → unrelated short; don't overwrite.
            if (!string.Equals(byTitle.VideoUrl, ep1.VideoUrl, StringComparison.OrdinalIgnoreCase))
            {
                logger.LogWarning(
                    "Standalone short already uses series title {Title}; skipping teaser create",
                    teaserTitle);
                return null;
            }
            return byTitle;
        }

        var teaser = new ShortFilm
        {
            Title = teaserTitle,
            Description = string.IsNullOrWhiteSpace(series.Description) ? ep1.Description : series.Description,
            VideoUrl = ep1.VideoUrl,
            ThumbnailUrl = ep1.ThumbnailUrl ?? series.CoverUrl,
            DurationSeconds = ep1.DurationSeconds,
            SectionId = series.SectionId ?? ep1.SectionId,
            SeriesId = null,
            EpisodeNumber = null,
            SortOrder = series.SortOrder,
            IsActive = series.IsActive && ep1.IsActive,
            IsFeatured = series.IsFeatured,
            CreatedByAdminId = null,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.ShortFilms.Add(teaser);
        await db.SaveChangesAsync(ct);
        await db.Entry(teaser).Reference(f => f.Section).LoadAsync(ct);
        logger.LogInformation(
            "Created standalone shorts teaser for series {SeriesTitle} from episode 1 (filmId={FilmId})",
            series.Title, teaser.Id);
        return teaser;
    }

    private static bool IsHlsUrl(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        var path = Uri.TryCreate(url.Trim(), UriKind.Absolute, out var u)
            ? u.AbsolutePath
            : url;
        return path.Contains(".m3u8", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsAlreadyLocalUpload(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        var u = url.Trim();
        if (u.StartsWith("/uploads/", StringComparison.OrdinalIgnoreCase) ||
            u.StartsWith("uploads/", StringComparison.OrdinalIgnoreCase))
            return true;
        if (Uri.TryCreate(u, UriKind.Absolute, out var abs))
        {
            var path = abs.AbsolutePath.TrimStart('/');
            return path.StartsWith("uploads/", StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    private async Task<string> DownloadToUploadsAsync(
        HttpRequest httpRequest,
        string downloadUrl,
        string[] allowedExts,
        string defaultExt,
        long maxBytes,
        CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, downloadUrl);
        req.Headers.TryAddWithoutValidation("Accept", "*/*");
        using var res = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!res.IsSuccessStatusCode)
            throw new InvalidOperationException($"Download failed ({(int)res.StatusCode}) for {downloadUrl}");

        var contentLength = res.Content.Headers.ContentLength;
        if (contentLength.HasValue && contentLength.Value > maxBytes)
            throw new InvalidOperationException($"File exceeds max size ({maxBytes / (1024 * 1024)}MB)");

        await using var network = await res.Content.ReadAsStreamAsync(ct);
        await using var buffer = new MemoryStream();
        var chunk = new byte[81920];
        long total = 0;
        int read;
        while ((read = await network.ReadAsync(chunk, ct)) > 0)
        {
            total += read;
            if (total > maxBytes)
                throw new InvalidOperationException($"File exceeds max size ({maxBytes / (1024 * 1024)}MB)");
            buffer.Write(chunk, 0, read);
        }

        if (buffer.Length == 0)
            throw new InvalidOperationException("Downloaded file is empty");

        buffer.Position = 0;
        var mediaType = res.Content.Headers.ContentType?.MediaType;
        if (IsPlaylistPayload(mediaType, buffer))
            throw new ArgumentException(
                "Downloaded content is an HLS/playlist, not a video file. Use a direct .mp4 / .webm / .mov URL.");

        var ext = GuessExtension(downloadUrl, mediaType) ?? defaultExt;
        if (!allowedExts.Contains(ext, StringComparer.OrdinalIgnoreCase))
            ext = defaultExt;

        var fileName = $"ingest{ext}";
        return await UploadFileHelper.SaveUploadAsync(
            env, config, httpRequest, buffer, fileName, allowedExts, defaultExt,
            UploadFileHelper.ShortFilmSubfolder);
    }

    private static bool IsPlaylistPayload(string? mediaType, MemoryStream buffer)
    {
        var mt = mediaType?.ToLowerInvariant() ?? "";
        if (mt.Contains("mpegurl") || mt.Contains("m3u8") || mt == "application/vnd.apple.mpegurl")
            return true;

        var peekLen = (int)Math.Min(64, buffer.Length);
        if (peekLen == 0) return false;
        var peek = new byte[peekLen];
        buffer.Position = 0;
        _ = buffer.Read(peek, 0, peekLen);
        buffer.Position = 0;
        var head = Encoding.UTF8.GetString(peek).TrimStart();
        return head.StartsWith("#EXTM3U", StringComparison.OrdinalIgnoreCase);
    }

    private static string? GuessExtension(string url, string? contentType)
    {
        try
        {
            var path = Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.AbsolutePath : url;
            var fromUrl = Path.GetExtension(path);
            if (!string.IsNullOrEmpty(fromUrl) && fromUrl.Length <= 5)
                return fromUrl.ToLowerInvariant();
        }
        catch { /* ignore */ }

        return contentType?.ToLowerInvariant() switch
        {
            "video/mp4" => ".mp4",
            "video/webm" => ".webm",
            "video/quicktime" => ".mov",
            "image/jpeg" => ".jpg",
            "image/png" => ".png",
            "image/webp" => ".webp",
            "image/gif" => ".gif",
            _ => null
        };
    }
}

public sealed class DuplicateShortFilmTitleException(string title) : Exception($"Film already exists: {title}")
{
    public string Title { get; } = title;
}

public sealed class DuplicateShortFilmEpisodeException(string seriesTitle, int episodeNumber)
    : Exception($"Episode {episodeNumber} already exists in series: {seriesTitle}")
{
    public string SeriesTitle { get; } = seriesTitle;
    public int EpisodeNumber { get; } = episodeNumber;
}

public sealed class SeriesEpisodeIngestItem
{
    public required string Title { get; init; }
    public string? Description { get; init; }
    public required string VideoUrl { get; init; }
    public string? ThumbnailUrl { get; init; }
    public int? DurationSeconds { get; init; }
    public int? EpisodeNumber { get; init; }
    public int? SortOrder { get; init; }
    public Guid? SectionId { get; init; }
    public bool? IsActive { get; init; }
    public bool? IsFeatured { get; init; }
}
