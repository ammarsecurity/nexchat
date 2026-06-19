using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class SiteContentFeatureService(AppDbContext db, IMemoryCache cache)
{
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(2);

    private async Task<bool> IsEnabledAsync(string key, CancellationToken ct = default)
    {
        var cacheKey = $"sitecontent:flag:{key}";
        if (cache.TryGetValue(cacheKey, out bool cached))
            return cached;

        var row = await db.SiteContents.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Key == key, ct);
        var enabled = ParseEnabled(row?.Content);
        cache.Set(cacheKey, enabled, CacheTtl);
        return enabled;
    }

    private static bool ParseEnabled(string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return true;
        var c = content.Trim().ToLowerInvariant();
        return c is "true" or "1";
    }

    public Task<bool> IsRandomChatEnabledAsync(CancellationToken ct = default) =>
        IsEnabledAsync("random_chat_enabled", ct);

    public Task<bool> IsCodeConnectEnabledAsync(CancellationToken ct = default) =>
        IsEnabledAsync("code_connect_features_enabled", ct);
}
