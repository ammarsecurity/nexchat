using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class SiteContentFeatureService(AppDbContext db, IMemoryCache cache)
{
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(2);

    private async Task<bool> IsEnabledAsync(string key, bool emptyMeansEnabled, CancellationToken ct = default)
    {
        var cacheKey = $"sitecontent:flag:{key}:{emptyMeansEnabled}";
        if (cache.TryGetValue(cacheKey, out bool cached))
            return cached;

        var row = await db.SiteContents.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Key == key, ct);
        var enabled = ParseEnabled(row?.Content, emptyMeansEnabled);
        cache.Set(cacheKey, enabled, CacheTtl);
        return enabled;
    }

    private static bool ParseEnabled(string? content, bool emptyMeansEnabled)
    {
        if (string.IsNullOrWhiteSpace(content)) return emptyMeansEnabled;
        var c = content.Trim().ToLowerInvariant();
        return c is "true" or "1";
    }

    /// Fail-closed: missing/empty SiteContent = off (App Store / random chat).
    public Task<bool> IsRandomChatEnabledAsync(CancellationToken ct = default) =>
        IsEnabledAsync("random_chat_enabled", emptyMeansEnabled: false, ct);

    public Task<bool> IsCodeConnectEnabledAsync(CancellationToken ct = default) =>
        IsEnabledAsync("code_connect_features_enabled", emptyMeansEnabled: false, ct);

    public Task<bool> IsDiscoverSwipeEnabledAsync(CancellationToken ct = default) =>
        IsEnabledAsync("discover_swipe_enabled", emptyMeansEnabled: true, ct);

    /// Call after admin updates SiteContent so hub/API gates pick up the new value immediately.
    public void Invalidate(string key)
    {
        cache.Remove($"sitecontent:flag:{key}:True");
        cache.Remove($"sitecontent:flag:{key}:False");
    }
}
