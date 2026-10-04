using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

public sealed record LegacyMediaReference(string Kind, Guid Id);
public sealed record LegacyMediaPreflight(string FileName, List<Guid> ViewOnceMessageIds, bool PublicFileExists, List<LegacyMediaReference> SharedReferences);

/// <summary>Private media is never written under the static-file root.</summary>
public sealed partial class MediaStorageService(IWebHostEnvironment env, IConfiguration config)
{
    public const string PrivatePrefix = "/api/media/private/";
    public string PublicRoot => Path.GetFullPath(Path.Combine(env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot"), "uploads"));
    public string PrivateRoot
    {
        get
        {
            var root = Path.GetFullPath(config["Media:PrivatePath"] ?? Path.Combine(env.ContentRootPath, "App_Data", "view-once"));
            var webRoot = Path.GetFullPath(env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot"));
            if (root.Equals(webRoot, StringComparison.OrdinalIgnoreCase) || root.StartsWith(webRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Media:PrivatePath must be outside wwwroot");
            return root;
        }
    }

    [GeneratedRegex(@"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.(jpg|jpeg|png|gif|webp|mp4|webm|mov|m4a|ogg|opus|mp3|wav)$", RegexOptions.IgnoreCase)]
    private static partial Regex UploadName();

    public string UploadDirectory(Guid owner, bool viewOnce)
    {
        var path = viewOnce ? Path.Combine(PrivateRoot, owner.ToString("D")) : PublicRoot;
        Directory.CreateDirectory(path);
        return path;
    }

    public string UploadUrl(Guid owner, string name, bool viewOnce, HttpRequest request) => viewOnce
        ? $"{PrivatePrefix}{owner:D}/{name}"
        : $"{(config["Media:BaseUrl"] ?? $"{request.Scheme}://{request.Host}").TrimEnd('/')}/uploads/{name}";

    public bool TryPrivatePath(string reference, out string path, Guid? owner = null)
    {
        path = "";
        if (!reference.StartsWith(PrivatePrefix, StringComparison.Ordinal)) return false;
        var pieces = reference[PrivatePrefix.Length..].Split('/');
        if (pieces.Length != 2 || !UploadName().IsMatch(pieces[1])) return false;
        if (owner.HasValue ? pieces[0] != owner.Value.ToString("D") : pieces[0] != "legacy" && !Guid.TryParseExact(pieces[0], "D", out _)) return false;
        path = Path.Combine(PrivateRoot, pieces[0], pieces[1]);
        return File.Exists(path);
    }

    public bool IsPublicUpload(string value, HttpRequest? request)
    {
        var path = value;
        if (!value.StartsWith("/", StringComparison.Ordinal) && Uri.TryCreate(value, UriKind.Absolute, out var uri))
        {
            if (uri.Scheme is not ("http" or "https") || !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment)) return false;
            var origins = new[] { config["Media:BaseUrl"], request == null ? null : $"{request.Scheme}://{request.Host}" };
            if (!origins.Any(origin => Uri.TryCreate(origin, UriKind.Absolute, out var allowed) && SameOrigin(uri, allowed))) return false;
            path = uri.AbsolutePath;
        }
        if (!path.StartsWith("/uploads/", StringComparison.Ordinal)) return false;
        var name = path["/uploads/".Length..];
        return UploadName().IsMatch(name) && File.Exists(Path.Combine(PublicRoot, name));
    }

    public static bool SameOrigin(Uri a, Uri b) => a.Scheme == b.Scheme && a.Host.Equals(b.Host, StringComparison.OrdinalIgnoreCase) && a.Port == b.Port;

    public bool ValidateMessageMedia(string content, string type, bool viewOnce, Guid owner, HttpRequest? request)
    {
        if (viewOnce) return (type is "image" or "video") && TryPrivatePath(content, out _, owner);
        if (type is "image" or "video" or "audio") return IsPublicUpload(content, request);
        if (type != "album") return true;
        try
        {
            using var doc = JsonDocument.Parse(content);
            if (doc.RootElement.ValueKind != JsonValueKind.Object || !doc.RootElement.TryGetProperty("urls", out var urls) || urls.ValueKind != JsonValueKind.Array || urls.GetArrayLength() is < 1 or > 10) return false;
            return urls.EnumerateArray().All(url => url.ValueKind == JsonValueKind.String && IsPublicUpload(url.GetString()!, request));
        }
        catch (JsonException) { return false; }
    }

    /// <summary>Read-only inventory for an operator to review before any legacy relocation.
    /// Reports identifiers rather than private message text. External links/caches are not enumerable.</summary>
    public async Task<IReadOnlyList<LegacyMediaPreflight>> PreflightLegacyViewOnceAsync(AppDbContext db, IConversationMessageCrypto crypto)
    {
        var reports = new Dictionary<string, LegacyMediaPreflight>(StringComparer.Ordinal);
        var legacy = await db.ConversationMessages.AsNoTracking().Where(m => m.IsViewOnce).Select(m => new { m.Id, m.Content }).ToListAsync();
        foreach (var msg in legacy)
        {
            var reference = crypto.DecryptFromStorage(msg.Content);
            var path = Uri.TryCreate(reference, UriKind.Absolute, out var uri) ? uri.AbsolutePath : reference;
            if (!path.StartsWith("/uploads/", StringComparison.Ordinal)) continue;
            var name = path["/uploads/".Length..];
            if (!UploadName().IsMatch(name)) continue;
            if (!reports.TryGetValue(name, out var report))
                reports[name] = report = new(name, [], File.Exists(Path.Combine(PublicRoot, name)), []);
            report.ViewOnceMessageIds.Add(msg.Id);
        }
        if (reports.Count == 0) return [];
        void Check(string kind, Guid id, string? text)
        {
            if (string.IsNullOrEmpty(text)) return;
            foreach (var report in reports.Values)
                if (text.Contains("/uploads/" + report.FileName, StringComparison.Ordinal))
                    report.SharedReferences.Add(new(kind, id));
        }
        foreach (var msg in await db.ConversationMessages.AsNoTracking().Where(m => !m.IsViewOnce).Select(m => new { m.Id, m.Content }).ToListAsync())
            Check("message", msg.Id, crypto.DecryptFromStorage(msg.Content));
        foreach (var user in await db.Users.AsNoTracking().Select(u => new { u.Id, u.Avatar, u.CoverImageUrl }).ToListAsync())
        {
            Check("avatar", user.Id, user.Avatar);
            Check("cover", user.Id, user.CoverImageUrl);
        }
        foreach (var item in await db.StorySlides.AsNoTracking().Select(s => new { s.Id, s.MediaUrl, s.OverlayJson }).ToListAsync())
        {
            Check("story", item.Id, item.MediaUrl);
            Check("story-overlay", item.Id, item.OverlayJson);
        }
        foreach (var item in await db.Conversations.AsNoTracking().Select(c => new { c.Id, c.ImageUrl }).ToListAsync()) Check("conversation-image", item.Id, item.ImageUrl);
        foreach (var item in await db.Banners.AsNoTracking().Select(c => new { c.Id, c.ImageUrl }).ToListAsync()) Check("banner", item.Id, item.ImageUrl);
        foreach (var item in await db.ShortFilms.AsNoTracking().Select(c => new { c.Id, c.VideoUrl, c.ThumbnailUrl }).ToListAsync())
        {
            Check("film", item.Id, item.VideoUrl);
            Check("film-thumbnail", item.Id, item.ThumbnailUrl);
        }
        foreach (var item in await db.OfficialChatBroadcasts.AsNoTracking().Select(c => new { c.Id, c.Content }).ToListAsync()) Check("broadcast", item.Id, crypto.DecryptFromStorage(item.Content));
        return reports.Values.OrderBy(r => r.FileName).ToList();
    }

    /// <summary>Explicit operator maintenance only: remove historical view-once originals AND thumbnails.
    /// Refuse the entire operation if known ordinary references share an old public URL.
    /// Existing browser/CDN copies cannot be recalled; operators must purge their upload caches.</summary>
    public async Task QuarantineLegacyViewOnceAsync(AppDbContext db, IConversationMessageCrypto crypto)
    {
        var preflight = await PreflightLegacyViewOnceAsync(db, crypto);
        if (preflight.Any(item => item.SharedReferences.Count > 0))
            throw new InvalidOperationException("Legacy view-once media shares public references. Review --media-preflight and migrate those uses before quarantine.");
        var offset = 0;
        while (true)
        {
            var batch = await db.ConversationMessages.Where(m => m.IsViewOnce).OrderBy(m => m.Id).Skip(offset).Take(100).ToListAsync();
            if (batch.Count == 0) break;
            foreach (var msg in batch)
            {
                var reference = crypto.DecryptFromStorage(msg.Content);
                if (reference.StartsWith(PrivatePrefix, StringComparison.Ordinal)) continue;
                var path = Uri.TryCreate(reference, UriKind.Absolute, out var uri) ? uri.AbsolutePath : reference;
                if (!path.StartsWith("/uploads/", StringComparison.Ordinal)) continue;
                var name = path["/uploads/".Length..];
                if (!UploadName().IsMatch(name)) continue;
                var dest = Path.Combine(PrivateRoot, "legacy");
                Directory.CreateDirectory(dest);
                var source = Path.Combine(PublicRoot, name);
                var target = Path.Combine(dest, name);
                if (File.Exists(source)) File.Move(source, target, overwrite: true);
                var thumb = Path.GetFileNameWithoutExtension(name) + "_thumb.jpg";
                if (File.Exists(Path.Combine(PublicRoot, thumb))) File.Move(Path.Combine(PublicRoot, thumb), Path.Combine(dest, thumb), overwrite: true);
                if (File.Exists(target)) msg.Content = crypto.EncryptForStorage(PrivatePrefix + "legacy/" + name);
            }
            await db.SaveChangesAsync();
            foreach (var msg in batch) db.Entry(msg).State = EntityState.Detached;
            offset += batch.Count;
        }
    }
}
