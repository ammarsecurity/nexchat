using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/media")]
[Authorize]
public class MediaController(IWebHostEnvironment env, IConfiguration config) : ControllerBase
{
    private static readonly string[] AllowedTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];

    [HttpPost("upload")]
    public async Task<IActionResult> Upload(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest("No file provided");

        if (!AllowedTypes.Contains(file.ContentType.ToLower()))
            return BadRequest("Only images are allowed");

        if (file.Length > 5 * 1024 * 1024)
            return BadRequest("Max file size is 5MB");

        var uploadsPath = Path.Combine(env.WebRootPath ?? "wwwroot", "uploads");
        Directory.CreateDirectory(uploadsPath);

        var ext = Path.GetExtension(file.FileName).ToLower();
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);

        await using var stream = new FileStream(filePath, FileMode.Create);
        await file.CopyToAsync(stream);

        var baseUrl = config["Media:BaseUrl"];
        var url = !string.IsNullOrEmpty(baseUrl)
            ? $"{baseUrl.TrimEnd('/')}/uploads/{fileName}"
            : $"{Request.Scheme}://{Request.Host}/uploads/{fileName}";
        return Ok(new { url });
    }
}
