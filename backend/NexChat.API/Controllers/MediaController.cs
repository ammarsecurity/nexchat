using System.Security.Claims;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using NexChat.API.Services;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/media")]
[Authorize]
[EnableRateLimiting("api")]
public class MediaController(
    IWebHostEnvironment env,
    IConfiguration config,
    MediaStorageService storage,
    ViewOnceMediaService viewOnceMedia,
    IMediaFileCrypto mediaCrypto) : ControllerBase
{
    private Guid OwnerId => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : Guid.Empty;

    [HttpGet("view-once/{sessionId:guid}")]
    public async Task<IActionResult> GetViewOnce(Guid sessionId)
    {
        Response.Headers.CacheControl = "private, no-store, max-age=0";
        Response.Headers.Pragma = "no-cache";
        Response.Headers.Expires = "0";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        if (OwnerId == Guid.Empty) return Unauthorized();
        var path = await viewOnceMedia.ResolveAsync(sessionId, OwnerId);
        if (path == null) return NotFound();
        if (!new FileExtensionContentTypeProvider().TryGetContentType(path, out var type)) return NotFound();
        var bytes = await mediaCrypto.ReadAllDecryptedAsync(path);
        // Range processing over in-memory plaintext (encrypted on disk).
        return File(bytes, type, enableRangeProcessing: true);
    }

    [HttpDelete("view-once/{sessionId:guid}")]
    public async Task<IActionResult> CloseViewOnce(Guid sessionId)
    {
        if (OwnerId == Guid.Empty) return Unauthorized();
        await viewOnceMedia.CloseAsync(sessionId, OwnerId);
        return NoContent();
    }

    private static readonly string[] AllowedTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];

    private static bool IsValidImageContent(Stream stream)
    {
        if (!stream.CanRead) return false;
        var header = new byte[12];
        var read = stream.Read(header, 0, header.Length);
        if (stream.CanSeek) stream.Position = 0;
        if (read < 3) return false;

        // JPEG: FF D8 FF
        if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) return true;
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if (read >= 8 && header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47) return true;
        // GIF87a / GIF89a
        if (read >= 6 && header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x38) return true;
        // WebP: RIFF....WEBP
        if (read >= 12 && header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
            && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50) return true;
        return false;
    }

    [HttpPost("upload")]
    public async Task<IActionResult> Upload(IFormFile file, [FromQuery] bool viewOnce = false)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        if (!AllowedTypes.Contains(file.ContentType.ToLower()))
            return BadRequest(new { message = "Only images are allowed (JPEG, PNG, GIF, WebP)" });

        if (file.Length > 5 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 5MB" });

        await using var stream = file.OpenReadStream();
        if (!IsValidImageContent(stream))
            return BadRequest(new { message = "File content does not match image format" });

        if (viewOnce && OwnerId == Guid.Empty) return Unauthorized();
        var uploadsPath = storage.UploadDirectory(OwnerId, viewOnce);

        var ext = Path.GetExtension(file.FileName).ToLower();
        if (!new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" }.Contains(ext))
            ext = ".jpg";

        stream.Position = 0;
        var optimized = await ImageOptimizeService.TryOptimizeAsync(stream, ext);
        string fileName;
        string? thumbUrl = null;
        if (optimized != null)
        {
            fileName = $"{Guid.NewGuid()}{optimized.Extension}";
            var filePath = Path.Combine(uploadsPath, fileName);
            await mediaCrypto.WriteAllEncryptedAsync(filePath, optimized.Bytes);
            if (!viewOnce && optimized.ThumbBytes is { Length: > 0 })
            {
                var thumbName = $"{Path.GetFileNameWithoutExtension(fileName)}_thumb.jpg";
                await mediaCrypto.WriteAllEncryptedAsync(Path.Combine(uploadsPath, thumbName), optimized.ThumbBytes);
                var baseUrlThumb = config["Media:BaseUrl"];
                thumbUrl = !string.IsNullOrEmpty(baseUrlThumb)
                    ? $"{baseUrlThumb.TrimEnd('/')}/uploads/{thumbName}"
                    : $"{Request.Scheme}://{Request.Host}/uploads/{thumbName}";
            }
        }
        else
        {
            fileName = $"{Guid.NewGuid()}{ext}";
            var filePath = Path.Combine(uploadsPath, fileName);
            stream.Position = 0;
            await mediaCrypto.WriteStreamEncryptedAsync(filePath, stream);
        }

        var url = storage.UploadUrl(OwnerId, fileName, viewOnce, Request);
        return Ok(new { url, thumbUrl });
    }

    private static readonly string[] AllowedAudioTypes = ["audio/webm", "audio/mp4", "audio/ogg", "audio/mpeg", "audio/wav", "audio/x-m4a"];

    private static async Task<MemoryStream> BufferUploadAsync(IFormFile file)
    {
        var ms = new MemoryStream();
        await using var src = file.OpenReadStream();
        await src.CopyToAsync(ms);
        ms.Position = 0;
        return ms;
    }

    private static bool IsAllowedStoryImageType(string? contentType)
    {
        var type = (contentType ?? "").ToLowerInvariant();
        if (AllowedTypes.Contains(type)) return true;
        // Canvas blobs from mobile WebViews often arrive without image/jpeg.
        return type is "" or "application/octet-stream" or "binary/octet-stream";
    }

    [HttpPost("upload-story-image")]
    public async Task<IActionResult> UploadStoryImage(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        if (!IsAllowedStoryImageType(file.ContentType))
            return BadRequest(new { message = "Only images are allowed (JPEG, PNG, GIF, WebP)" });

        if (file.Length > 10 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 10MB" });

        await using var stream = await BufferUploadAsync(file);
        if (!IsValidImageContent(stream))
            return BadRequest(new { message = "File content does not match image format" });

        return Ok(new { url = await SaveUploadAsync(stream, file.FileName, [".jpg", ".jpeg", ".png", ".gif", ".webp"], ".jpg") });
    }

    private static readonly string[] AllowedStoryVideoTypes = ["video/mp4", "video/webm", "video/quicktime"];

    [HttpPost("upload-story-video")]
    public async Task<IActionResult> UploadStoryVideo(IFormFile file)
    {
        return await UploadChatVideoInternal(file);
    }

    [HttpPost("upload-chat-video")]
    public async Task<IActionResult> UploadChatVideo(IFormFile file, [FromQuery] bool viewOnce = false)
    {
        if (viewOnce && OwnerId == Guid.Empty) return Unauthorized();
        return await UploadChatVideoInternal(file, viewOnce);
    }

    private async Task<IActionResult> UploadChatVideoInternal(IFormFile file, bool viewOnce = false)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        var contentType = file.ContentType?.ToLower() ?? "";
        if (!AllowedStoryVideoTypes.Contains(contentType) && !contentType.StartsWith("video/"))
            return BadRequest(new { message = "Only video files are allowed (MP4, WebM)" });

        if (file.Length > 30 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 30MB" });

        await using var stream = await BufferUploadAsync(file);
        return Ok(new { url = await SaveUploadAsync(stream, file.FileName, [".mp4", ".webm", ".mov"], ".mp4", viewOnce) });
    }

    private async Task<string> SaveUploadAsync(Stream stream, string originalFileName, string[] allowedExts, string defaultExt, bool viewOnce = false)
    {
        var uploadsPath = storage.UploadDirectory(OwnerId, viewOnce);

        var ext = Path.GetExtension(originalFileName).ToLower();
        if (string.IsNullOrEmpty(ext) || !allowedExts.Contains(ext))
            ext = defaultExt;
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);

        if (stream.CanSeek) stream.Position = 0;
        await mediaCrypto.WriteStreamEncryptedAsync(filePath, stream);

        return storage.UploadUrl(OwnerId, fileName, viewOnce, Request);
    }

    private static readonly HashSet<string> AllowedDocExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".pdf", ".txt", ".doc", ".docx", ".rtf", ".odt", ".zip", ".rar", ".7z"
    };

    private static readonly HashSet<string> AllowedDocContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "application/pdf",
        "text/plain",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/rtf",
        "text/rtf",
        "application/vnd.oasis.opendocument.text",
        "application/zip",
        "application/x-zip-compressed",
        "application/x-rar-compressed",
        "application/vnd.rar",
        "application/x-7z-compressed",
        "application/octet-stream",
    };

    /// <summary>Chat document upload (pdf/txt/doc/docx/zip/rar/…).</summary>
    [HttpPost("upload-file")]
    public async Task<IActionResult> UploadFile(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        if (file.Length > 25 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 25MB" });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (string.IsNullOrEmpty(ext) || !AllowedDocExtensions.Contains(ext))
            return BadRequest(new { message = "Unsupported file type" });

        var contentType = (file.ContentType ?? "").ToLowerInvariant();
        if (!string.IsNullOrEmpty(contentType) &&
            !AllowedDocContentTypes.Contains(contentType) &&
            !contentType.StartsWith("text/") &&
            !contentType.StartsWith("application/"))
            return BadRequest(new { message = "Unsupported file type" });

        await using var stream = await BufferUploadAsync(file);
        var uploadsPath = storage.UploadDirectory(OwnerId, viewOnce: false);
        var safeName = Path.GetFileName(file.FileName);
        if (safeName.Length > 120) safeName = safeName[^120..];
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);
        await mediaCrypto.WriteStreamEncryptedAsync(filePath, stream);

        var url = storage.UploadUrl(OwnerId, fileName, viewOnce: false, Request);
        return Ok(new
        {
            url,
            name = safeName,
            size = file.Length,
            contentType = string.IsNullOrEmpty(contentType) ? "application/octet-stream" : contentType,
        });
    }

    [HttpPost("upload-audio")]
    public async Task<IActionResult> UploadAudio(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        var contentType = file.ContentType?.ToLower() ?? "";
        if (!AllowedAudioTypes.Contains(contentType) && !contentType.StartsWith("audio/"))
            return BadRequest(new { message = "Only audio files are allowed" });

        if (file.Length > 10 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 10MB" });

        var uploadsPath = Path.Combine(env.WebRootPath ?? "wwwroot", "uploads");
        Directory.CreateDirectory(uploadsPath);

        var ext = Path.GetExtension(file.FileName).ToLower();
        if (string.IsNullOrEmpty(ext) || !new[] { ".webm", ".mp4", ".m4a", ".ogg", ".opus", ".mp3", ".wav" }.Contains(ext))
            ext = ".webm";
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);

        await using (var src = file.OpenReadStream())
            await mediaCrypto.WriteStreamEncryptedAsync(filePath, src);

        var baseUrl = config["Media:BaseUrl"];
        var url = !string.IsNullOrEmpty(baseUrl)
            ? $"{baseUrl.TrimEnd('/')}/uploads/{fileName}"
            : $"{Request.Scheme}://{Request.Host}/uploads/{fileName}";
        return Ok(new { url });
    }

    /// <summary>
    /// Proxy for avatar images - enables caching without CORS issues.
    /// GET /api/media/avatar/xxx.png
    /// </summary>
    [HttpGet("avatar/{fileName}")]
    public async Task<IActionResult> GetAvatar(string fileName)
    {
        if (string.IsNullOrEmpty(fileName) || fileName.Contains(".."))
            return BadRequest();
        var uploadsPath = Path.Combine(env.WebRootPath ?? "wwwroot", "uploads");
        var filePath = Path.Combine(uploadsPath, Path.GetFileName(fileName));
        if (!System.IO.File.Exists(filePath))
            return NotFound();
        var contentType = Path.GetExtension(fileName).ToLowerInvariant() switch
        {
            ".png" => "image/png",
            ".gif" => "image/gif",
            ".webp" => "image/webp",
            _ => "image/jpeg"
        };
        Response.Headers.CacheControl = "public,max-age=604800,immutable";
        var bytes = await mediaCrypto.ReadAllDecryptedAsync(filePath);
        return File(bytes, contentType, enableRangeProcessing: true);
    }
}
