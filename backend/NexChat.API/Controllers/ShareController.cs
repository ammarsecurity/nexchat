using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;
using System.Net;
using System.Text;

namespace NexChat.API.Controllers;

[ApiController]
public class ShareController(AppDbContext db, IConfiguration config) : ControllerBase
{
    private string FrontendOrigin =>
        (config["PublicApp:BaseUrl"] ?? config["App:PublicUrl"] ?? "").TrimEnd('/');

    private string ShareOrigin =>
        (config["PublicApp:ShareBaseUrl"] ?? config["Media:BaseUrl"] ?? "").TrimEnd('/');

    private string ResolveFrontendOrigin()
    {
        if (!string.IsNullOrWhiteSpace(FrontendOrigin))
            return FrontendOrigin;
        return ResolveShareOrigin();
    }

    private string ResolveShareOrigin()
    {
        if (!string.IsNullOrWhiteSpace(ShareOrigin))
            return ShareOrigin;
        return $"{Request.Scheme}://{Request.Host}";
    }

    private static string EscapeHtml(string? s) =>
        WebUtility.HtmlEncode(s ?? string.Empty);

    private string AbsoluteUrl(string? pathOrUrl)
    {
        if (string.IsNullOrWhiteSpace(pathOrUrl)) return string.Empty;
        if (pathOrUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            pathOrUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return pathOrUrl;
        var origin = ResolveShareOrigin();
        return pathOrUrl.StartsWith('/') ? $"{origin}{pathOrUrl}" : $"{origin}/{pathOrUrl}";
    }

    [HttpGet("/join/{code}")]
    [AllowAnonymous]
    public async Task<IActionResult> InvitePage(string code)
    {
        code = (code ?? "").Trim().ToUpperInvariant();
        if (!IsValidInviteCode(code))
            return NotFound();

        var user = await db.Users.AsNoTracking()
            .Where(u => u.UniqueCode == code && !u.IsBanned)
            .Select(u => new { u.Name, u.Avatar })
            .FirstOrDefaultAsync();

        var origin = ResolveShareOrigin();
        var appOrigin = ResolveFrontendOrigin();
        var appHash = $"{appOrigin}/#/join/{Uri.EscapeDataString(code)}";
        var title = user?.Name != null
            ? $"انضم إلى {user.Name} على NexChat"
            : "انضم إلى NexChat";
        var desc = user?.Name != null
            ? $"تواصل مع {user.Name} عبر كود الاتصال {code}"
            : $"استخدم كود الاتصال {code} للتواصل على NexChat";
        var image = AbsoluteUrl(user?.Avatar);

        return Content(BuildOgHtml(title, desc, appHash, image, $"انضم — {code}"), "text/html; charset=utf-8");
    }

    [HttpGet("/share/film/{id:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> FilmSharePage(Guid id)
    {
        var film = await db.ShortFilms.AsNoTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.IsActive);
        if (film == null) return NotFound();

        var origin = ResolveShareOrigin();
        var appOrigin = ResolveFrontendOrigin();
        var appHash = $"{appOrigin}/#/short-films/watch?start={id}";
        var title = string.IsNullOrWhiteSpace(film.Title) ? "فيلم قصير على NexChat" : film.Title;
        var desc = string.IsNullOrWhiteSpace(film.Description)
            ? "شاهد هذا الفيلم القصير على NexChat"
            : film.Description;
        var image = AbsoluteUrl(film.ThumbnailUrl);

        return Content(BuildOgHtml(title, desc, appHash, image, title), "text/html; charset=utf-8");
    }

    [HttpGet("/share/story/{userId:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> StorySharePage(Guid userId)
    {
        var user = await db.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == userId && !u.IsBanned);
        if (user == null) return NotFound();

        var hasActive = await db.StorySlides.AsNoTracking()
            .AnyAsync(s => s.UserId == userId && s.ExpiresAt > DateTime.UtcNow);

        var origin = ResolveShareOrigin();
        var appOrigin = ResolveFrontendOrigin();
        var appHash = $"{appOrigin}/#/stories/view/{userId}";
        var title = $"ستوري {user.Name} على NexChat";
        var desc = hasActive
            ? $"شاهد ستوريات {user.Name} على NexChat"
            : $"افتح ستوريات {user.Name} على NexChat";
        var image = AbsoluteUrl(user.Avatar);

        return Content(BuildOgHtml(title, desc, appHash, image, user.Name), "text/html; charset=utf-8");
    }

    [HttpGet("api/share/invite/{code}")]
    [AllowAnonymous]
    public async Task<IActionResult> InviteMeta(string code)
    {
        code = (code ?? "").Trim().ToUpperInvariant();
        if (!IsValidInviteCode(code)) return NotFound();

        var user = await db.Users.AsNoTracking()
            .Where(u => u.UniqueCode == code && !u.IsBanned)
            .Select(u => new { u.Name, u.Avatar })
            .FirstOrDefaultAsync();

        var shareOrigin = ResolveShareOrigin();
        var appOrigin = ResolveFrontendOrigin();
        return Ok(new
        {
            code,
            name = user?.Name,
            avatarUrl = AbsoluteUrl(user?.Avatar),
            webUrl = $"{shareOrigin}/join/{Uri.EscapeDataString(code)}",
            appUrl = $"{appOrigin}/#/join/{Uri.EscapeDataString(code)}"
        });
    }

    [HttpGet("api/share/film/{id:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> FilmMeta(Guid id)
    {
        var film = await db.ShortFilms.AsNoTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.IsActive);
        if (film == null) return NotFound();

        var shareOrigin = ResolveShareOrigin();
        var appOrigin = ResolveFrontendOrigin();
        return Ok(new
        {
            id = film.Id,
            title = film.Title,
            description = film.Description,
            thumbnailUrl = AbsoluteUrl(film.ThumbnailUrl),
            webUrl = $"{shareOrigin}/share/film/{id}",
            appUrl = $"{appOrigin}/#/short-films/watch?start={id}"
        });
    }

    [HttpGet("api/share/story/{userId:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> StoryMeta(Guid userId)
    {
        var user = await db.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == userId && !u.IsBanned);
        if (user == null) return NotFound();

        var shareOrigin = ResolveShareOrigin();
        var appOrigin = ResolveFrontendOrigin();
        return Ok(new
        {
            userId = user.Id,
            name = user.Name,
            avatarUrl = AbsoluteUrl(user.Avatar),
            webUrl = $"{shareOrigin}/share/story/{userId}",
            appUrl = $"{appOrigin}/#/stories/view/{userId}"
        });
    }

    private static bool IsValidInviteCode(string code) =>
        code.Length == 7 && code.StartsWith("NX-", StringComparison.Ordinal);

    private static string BuildOgHtml(string title, string description, string redirectUrl, string? imageUrl, string bodyTitle)
    {
        var img = string.IsNullOrWhiteSpace(imageUrl)
            ? ""
            : $"""<meta property="og:image" content="{EscapeHtml(imageUrl)}" />""";

        var jsRedirect = System.Text.Json.JsonSerializer.Serialize(redirectUrl);
        return $$"""
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{{EscapeHtml(title)}}</title>
  <meta property="og:type" content="website" />
  <meta property="og:title" content="{{EscapeHtml(title)}}" />
  <meta property="og:description" content="{{EscapeHtml(description)}}" />
  <meta property="og:url" content="{{EscapeHtml(redirectUrl)}}" />
  {{img}}
  <meta name="twitter:card" content="summary_large_image" />
  <meta http-equiv="refresh" content="0;url={{EscapeHtml(redirectUrl)}}" />
  <style>
    body { font-family: system-ui, sans-serif; background: #0d0d1a; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 24px; text-align: center; }
    a { color: #6c63ff; }
  </style>
</head>
<body>
  <div>
    <h1 style="font-size:1.25rem;font-weight:600;">{{EscapeHtml(bodyTitle)}}</h1>
    <p style="opacity:.85;">{{EscapeHtml(description)}}</p>
    <p><a href="{{EscapeHtml(redirectUrl)}}">فتح في NexChat</a></p>
  </div>
  <script>location.replace({{jsRedirect}});</script>
</body>
</html>
""";
    }
}
