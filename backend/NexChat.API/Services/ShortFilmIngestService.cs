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
        return film;
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
