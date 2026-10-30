using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class DiscoverBotsSettingsService(AppDbContext db, IMemoryCache cache)
{
    public const string SiteContentKey = "discover_bots_config";
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(2);
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public async Task<DiscoverBotsConfigDto> GetConfigAsync(CancellationToken ct = default)
    {
        if (cache.TryGetValue(SiteContentKey, out DiscoverBotsConfigDto? cached) && cached != null)
            return cached;

        var row = await db.SiteContents.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Key == SiteContentKey, ct);
        var cfg = Parse(row?.Content);
        cache.Set(SiteContentKey, cfg, CacheTtl);
        return cfg;
    }

    public async Task SaveConfigAsync(DiscoverBotsConfigDto cfg, CancellationToken ct = default)
    {
        cfg = Normalize(cfg);
        var json = JsonSerializer.Serialize(cfg, JsonOpts);
        var existing = await db.SiteContents.FirstOrDefaultAsync(c => c.Key == SiteContentKey, ct);
        if (existing != null)
        {
            existing.Content = json;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            db.SiteContents.Add(new SiteContent { Key = SiteContentKey, Content = json });
        }
        await db.SaveChangesAsync(ct);
        cache.Set(SiteContentKey, cfg, CacheTtl);
    }

    public void Invalidate() => cache.Remove(SiteContentKey);

    public static DiscoverBotsConfigDto Parse(string? content)
    {
        if (string.IsNullOrWhiteSpace(content))
            return Normalize(new DiscoverBotsConfigDto());
        try
        {
            var cfg = JsonSerializer.Deserialize<DiscoverBotsConfigDto>(content, JsonOpts);
            return Normalize(cfg ?? new DiscoverBotsConfigDto());
        }
        catch
        {
            return Normalize(new DiscoverBotsConfigDto());
        }
    }

    public static DiscoverBotsConfigDto Normalize(DiscoverBotsConfigDto cfg)
    {
        cfg.FemaleTarget = Math.Clamp(cfg.FemaleTarget, 0, 500);
        cfg.MaleTarget = Math.Clamp(cfg.MaleTarget, 0, 500);
        cfg.MatchPercent = Math.Clamp(cfg.MatchPercent, 0, 100);
        cfg.AgeMin = Math.Clamp(cfg.AgeMin <= 0 ? 18 : cfg.AgeMin, 18, 60);
        cfg.AgeMax = Math.Clamp(cfg.AgeMax <= 0 ? 45 : cfg.AgeMax, 18, 60);
        if (cfg.AgeMin > cfg.AgeMax) (cfg.AgeMin, cfg.AgeMax) = (cfg.AgeMax, cfg.AgeMin);
        cfg.Country = string.IsNullOrWhiteSpace(cfg.Country) ? "IQ" : cfg.Country.Trim().ToUpperInvariant();
        if (cfg.Country.Length > 2) cfg.Country = cfg.Country[..2];
        return cfg;
    }
}
