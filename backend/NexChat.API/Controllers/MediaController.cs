using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/media")]
[Authorize]
[EnableRateLimiting("api")]
public class MediaController(IWebHostEnvironment env, IConfiguration config) : ControllerBase
{
    private static readonly string[] AllowedTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];

    private static bool IsValidImageContent(Stream stream)
    {
        var header = new byte[12];
        var read = stream.Read(header, 0, header.Length);
        stream.Position = 0;
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
    public async Task<IActionResult> Upload(IFormFile file)
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

        var uploadsPath = Path.Combine(env.WebRootPath ?? "wwwroot", "uploads");
        Directory.CreateDirectory(uploadsPath);

        var ext = Path.GetExtension(file.FileName).ToLower();
        if (!new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" }.Contains(ext))
            ext = ".jpg";
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);

        await using (var dest = new FileStream(filePath, FileMode.Create))
        {
            stream.Position = 0;
            await stream.CopyToAsync(dest);
        }

        var baseUrl = config["Media:BaseUrl"];
        var url = !string.IsNullOrEmpty(baseUrl)
            ? $"{baseUrl.TrimEnd('/')}/uploads/{fileName}"
            : $"{Request.Scheme}://{Request.Host}/uploads/{fileName}";
        return Ok(new { url });
    }
}
