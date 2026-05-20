using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services.StockVideo;

public class StockVideoImportService(
    HttpClient http,
    AppDbContext db,
    IWebHostEnvironment env,
    IConfiguration config,
    IOptions<StockVideoOptions> options,
    ILogger<StockVideoImportService> logger)
{
    private readonly StockVideoOptions _opts = options.Value;

    public async Task<ShortFilm> ImportAsync(
        HttpRequest httpRequest,
        string provider,
        string externalId,
        string title,
        string? description,
        string videoDownloadUrl,
        string? thumbnailUrl,
        int? durationSeconds,
        Guid? sectionId,
        int sortOrder,
        bool isActive,
        bool isFeatured,
        Guid? adminUserId,
        CancellationToken ct = default)
    {
        provider = provider.Trim().ToLowerInvariant();
        if (provider is not "pexels" and not "pixabay")
            throw new ArgumentException("Unknown provider");

        if (string.IsNullOrWhiteSpace(title))
            throw new ArgumentException("Title is required");

        if (!StockVideoUrlValidator.IsAllowedVideoUrl(videoDownloadUrl))
            throw new ArgumentException("Video URL is not from an allowed stock provider");

        if (!string.IsNullOrWhiteSpace(thumbnailUrl) &&
            !StockVideoUrlValidator.IsAllowedImageUrl(thumbnailUrl))
            throw new ArgumentException("Thumbnail URL is not from an allowed stock provider");

        var exists = await db.ShortFilms.AnyAsync(
            f => f.StockProvider == provider && f.StockExternalId == externalId, ct);
        if (exists)
            throw new InvalidOperationException("This video was already imported");

        var fullDescription = string.IsNullOrWhiteSpace(description) ? null : description.Trim();

        logger.LogInformation("Importing stock video {Provider}/{Id}", provider, externalId);

        var videoUrl = await DownloadToUploadsAsync(
            httpRequest, videoDownloadUrl, [".mp4", ".webm", ".mov"], ".mp4", _opts.MaxVideoBytes, ct);

        string? savedThumb = null;
        if (!string.IsNullOrWhiteSpace(thumbnailUrl))
        {
            try
            {
                savedThumb = await DownloadToUploadsAsync(
                    httpRequest, thumbnailUrl, [".jpg", ".jpeg", ".png", ".webp"], ".jpg",
                    _opts.MaxThumbnailBytes, ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Thumbnail download failed for {Provider}/{Id}", provider, externalId);
            }
        }

        var film = new ShortFilm
        {
            Title = title.Trim(),
            Description = fullDescription,
            StockProvider = provider,
            StockExternalId = externalId,
            VideoUrl = videoUrl,
            ThumbnailUrl = savedThumb,
            DurationSeconds = durationSeconds > 0 ? durationSeconds : null,
            SectionId = sectionId,
            SortOrder = sortOrder,
            IsActive = isActive,
            IsFeatured = isFeatured,
            CreatedByAdminId = adminUserId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.ShortFilms.Add(film);
        await db.SaveChangesAsync(ct);
        await db.Entry(film).Reference(f => f.Section).LoadAsync(ct);
        return film;
    }

    private async Task<string> DownloadToUploadsAsync(
        HttpRequest httpRequest,
        string downloadUrl,
        string[] allowedExts,
        string defaultExt,
        long maxBytes,
        CancellationToken ct)
    {
        using var res = await http.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        res.EnsureSuccessStatusCode();

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

        buffer.Position = 0;
        var ext = GuessExtension(downloadUrl, res.Content.Headers.ContentType?.MediaType) ?? defaultExt;
        if (!allowedExts.Contains(ext, StringComparer.OrdinalIgnoreCase))
            ext = defaultExt;

        var fileName = $"stock{ext}";
        return await UploadFileHelper.SaveUploadAsync(
            env, config, httpRequest, buffer, fileName, allowedExts, defaultExt,
            UploadFileHelper.ShortFilmSubfolder);
    }

    private static string? GuessExtension(string url, string? contentType)
    {
        var fromUrl = Path.GetExtension(url);
        if (!string.IsNullOrEmpty(fromUrl) && fromUrl.Length <= 5)
            return fromUrl.ToLowerInvariant();

        return contentType?.ToLowerInvariant() switch
        {
            "video/mp4" => ".mp4",
            "video/webm" => ".webm",
            "video/quicktime" => ".mov",
            "image/jpeg" => ".jpg",
            "image/png" => ".png",
            "image/webp" => ".webp",
            _ => null
        };
    }
}
