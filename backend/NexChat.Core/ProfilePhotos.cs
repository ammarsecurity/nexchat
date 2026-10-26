using System.Text.Json;

namespace NexChat.Core;

public static class ProfilePhotos
{
    public const int MaxCount = 4;

    public static bool IsPhotoUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        var a = url.Trim();
        return a.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || a.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            || a.StartsWith('/');
    }

    public static IReadOnlyList<string> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Array.Empty<string>();
        try
        {
            var list = JsonSerializer.Deserialize<List<string>>(json);
            if (list == null) return Array.Empty<string>();
            return list
                .Where(IsPhotoUrl)
                .Select(u => u.Trim())
                .Distinct(StringComparer.Ordinal)
                .Take(MaxCount)
                .ToList();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    /// <summary>Normalize input + derive primary avatar (first photo).</summary>
    public static (string? json, string? avatar) Normalize(IEnumerable<string?>? photos)
    {
        var clean = (photos ?? Enumerable.Empty<string?>())
            .Where(IsPhotoUrl)
            .Select(u => u!.Trim())
            .Distinct(StringComparer.Ordinal)
            .Take(MaxCount)
            .ToList();
        if (clean.Count == 0) return (null, null);
        return (JsonSerializer.Serialize(clean), clean[0]);
    }

    public static IReadOnlyList<string> Resolve(string? profilePhotosJson, string? avatar, string? coverImageUrl = null)
    {
        var fromJson = Parse(profilePhotosJson);
        if (fromJson.Count > 0) return fromJson;

        var fallback = new List<string>();
        if (IsPhotoUrl(avatar)) fallback.Add(avatar!.Trim());
        if (IsPhotoUrl(coverImageUrl) && !fallback.Contains(coverImageUrl!.Trim(), StringComparer.Ordinal))
            fallback.Add(coverImageUrl.Trim());
        return fallback;
    }
}
