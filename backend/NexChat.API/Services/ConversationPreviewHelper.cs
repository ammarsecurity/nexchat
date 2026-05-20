using System.Text.Json;
using NexChat.Core.Entities;

namespace NexChat.API.Services;

public static class ConversationPreviewHelper
{
    public static string BuildShortFilmPreview(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var title = doc.RootElement.TryGetProperty("title", out var t) ? t.GetString() : null;
            if (!string.IsNullOrWhiteSpace(title))
            {
                var preview = $"🎬 {title.Trim()}";
                return preview.Length > 50 ? preview[..50] + "…" : preview;
            }
        }
        catch { /* legacy or invalid payload */ }
        return "🎬 فيلم قصير";
    }

    public static string BuildListPreview(ConversationMessage m, Func<string, string> decrypt)
    {
        if (m.Type == "image") return "صورة";
        if (m.Type == "audio") return "رسالة صوتية";
        if (m.Type == "short_film") return BuildShortFilmPreview(decrypt(m.Content ?? ""));
        var c = decrypt(m.Content ?? "");
        return c.Length > 50 ? c[..50] + "…" : c;
    }

    public static string BuildListPreview(string? type, string? encryptedContent, Func<string, string> decrypt)
    {
        if (type == "image") return "صورة";
        if (type == "audio") return "رسالة صوتية";
        if (type == "short_film")
            return BuildShortFilmPreview(decrypt(encryptedContent ?? ""));
        var c = decrypt(encryptedContent ?? "");
        return c.Length > 50 ? c[..50] + "…" : c;
    }
}
