using System.Diagnostics;
using System.Text.Json;
using Livekit.Server.Sdk.Dotnet;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>
/// LiveKit Url/ApiKey/ApiSecret — SiteContent override with appsettings fallback.
/// </summary>
public class LiveKitSettingsService(
    AppDbContext db,
    IMemoryCache cache,
    IConfiguration config,
    IHttpClientFactory httpClientFactory,
    ILogger<LiveKitSettingsService> logger)
{
    public const string SiteContentKey = "livekit_settings";

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public async Task<LiveKitConfigDto> GetConfigAsync(CancellationToken ct = default)
    {
        if (cache.TryGetValue(SiteContentKey, out LiveKitConfigDto? cached) && cached != null)
            return Clone(cached);

        var row = await db.SiteContents.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Key == SiteContentKey, ct);

        LiveKitConfigDto cfg;
        if (!string.IsNullOrWhiteSpace(row?.Content))
        {
            cfg = Parse(row.Content);
            // Fill any blank field from appsettings so partial DB rows still work.
            MergeMissingFromAppsettings(cfg);
        }
        else
        {
            cfg = FromAppsettings();
        }

        cache.Set(SiteContentKey, Clone(cfg), TimeSpan.FromMinutes(1));
        return Clone(cfg);
    }

    public async Task SaveConfigAsync(LiveKitConfigDto cfg, CancellationToken ct = default)
    {
        cfg.Url = NormalizeWsUrl(cfg.Url);
        cfg.ApiKey = (cfg.ApiKey ?? "").Trim();
        cfg.ApiSecret = (cfg.ApiSecret ?? "").Trim();

        if (string.IsNullOrWhiteSpace(cfg.Url))
            throw new ArgumentException("رابط LiveKit مطلوب");
        if (string.IsNullOrWhiteSpace(cfg.ApiKey))
            throw new ArgumentException("ApiKey مطلوب");
        if (string.IsNullOrWhiteSpace(cfg.ApiSecret))
            throw new ArgumentException("ApiSecret مطلوب");
        if (cfg.ApiSecret.Length < 32)
            throw new ArgumentException("ApiSecret يجب ألا يقل عن 32 حرفاً");

        var existing = await db.SiteContents.FirstOrDefaultAsync(c => c.Key == SiteContentKey, ct);
        var json = JsonSerializer.Serialize(cfg, JsonOpts);
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
        cache.Remove(SiteContentKey);
    }

    public static bool IsConfigured(LiveKitConfigDto cfg) =>
        !string.IsNullOrWhiteSpace(cfg.Url)
        && !string.IsNullOrWhiteSpace(cfg.ApiKey)
        && !string.IsNullOrWhiteSpace(cfg.ApiSecret);

    public static string ToHttpHost(string wsUrl)
    {
        var u = (wsUrl ?? "").Trim().TrimEnd('/');
        if (u.StartsWith("wss://", StringComparison.OrdinalIgnoreCase))
            return "https://" + u[6..];
        if (u.StartsWith("ws://", StringComparison.OrdinalIgnoreCase))
            return "http://" + u[5..];
        if (u.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
            u.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
            return u;
        return "https://" + u.TrimStart('/');
    }

    public async Task<LiveKitProbeResultDto> ProbeAsync(CancellationToken ct = default)
    {
        var checks = new List<LiveKitProbeCheckDto>();
        var cfg = await GetConfigAsync(ct);
        var configured = IsConfigured(cfg);
        var httpHost = configured ? ToHttpHost(cfg.Url) : null;

        if (!configured)
        {
            checks.Add(new LiveKitProbeCheckDto("config", false, "Url / ApiKey / ApiSecret غير مكتملة"));
            return new LiveKitProbeResultDto(
                Ok: false,
                Configured: false,
                Url: string.IsNullOrWhiteSpace(cfg.Url) ? null : cfg.Url,
                HttpHost: httpHost,
                LatencyMs: null,
                RoomCount: null,
                Message: "إعدادات LiveKit غير مكتملة",
                Checks: checks);
        }

        checks.Add(new LiveKitProbeCheckDto("config", true, "Url و ApiKey و ApiSecret موجودة"));

        try
        {
            _ = new AccessToken(cfg.ApiKey, cfg.ApiSecret)
                .WithIdentity("nexchat-admin-probe")
                .WithName("NexChat Admin Probe")
                .WithGrants(new VideoGrants { RoomJoin = true, Room = "nexchat-admin-probe", RoomAdmin = true, RoomList = true })
                .WithTtl(TimeSpan.FromMinutes(2))
                .ToJwt();
            checks.Add(new LiveKitProbeCheckDto("jwt", true, "تم توليد توكن بنجاح"));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "LiveKit JWT mint failed");
            checks.Add(new LiveKitProbeCheckDto("jwt", false, ex.Message));
            return new LiveKitProbeResultDto(
                false, true, cfg.Url, httpHost, null, null,
                "فشل توليد التوكن — تحقق من ApiKey و ApiSecret",
                checks);
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var http = httpClientFactory.CreateClient("livekit-admin");
            var roomClient = new RoomServiceClient(httpHost!, cfg.ApiKey, cfg.ApiSecret, http);
            var list = await roomClient.ListRooms(new ListRoomsRequest());
            sw.Stop();
            var count = list.Rooms?.Count ?? 0;
            checks.Add(new LiveKitProbeCheckDto("server", true, $"استجابة السيرفر خلال {sw.ElapsedMilliseconds}ms — غرف نشطة: {count}"));
            return new LiveKitProbeResultDto(
                Ok: true,
                Configured: true,
                Url: cfg.Url,
                HttpHost: httpHost,
                LatencyMs: (int)sw.ElapsedMilliseconds,
                RoomCount: count,
                Message: "LiveKit يعمل بشكل طبيعي",
                Checks: checks);
        }
        catch (TaskCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            checks.Add(new LiveKitProbeCheckDto("server", false, "انتهت مهلة الاتصال بالسيرفر"));
            return new LiveKitProbeResultDto(
                false, true, cfg.Url, httpHost, (int)sw.ElapsedMilliseconds, null,
                "تعذر الوصول لسيرفر LiveKit (timeout)",
                checks);
        }
        catch (Exception ex)
        {
            sw.Stop();
            logger.LogWarning(ex, "LiveKit ListRooms probe failed for {Host}", httpHost);
            checks.Add(new LiveKitProbeCheckDto("server", false, Truncate(ex.Message, 240)));
            return new LiveKitProbeResultDto(
                false, true, cfg.Url, httpHost, (int)sw.ElapsedMilliseconds, null,
                "السيرفر لم يستجب أو المفاتيح غير صحيحة",
                checks);
        }
    }

    public static string MaskSecret(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        if (value.Length <= 4) return "••••••••";
        var tail = Math.Min(4, value.Length);
        return $"{new string('•', Math.Min(8, value.Length - tail))}{value[^tail..]}";
    }

    public static bool LooksMasked(string? value) =>
        string.IsNullOrWhiteSpace(value)
        || value.Contains('\u2022')
        || value.Contains('•')
        || value.StartsWith("****", StringComparison.Ordinal);

    private LiveKitConfigDto FromAppsettings() => new()
    {
        Url = NormalizeWsUrl(config["LiveKit:Url"] ?? ""),
        ApiKey = (config["LiveKit:ApiKey"] ?? "").Trim(),
        ApiSecret = (config["LiveKit:ApiSecret"] ?? "").Trim()
    };

    private void MergeMissingFromAppsettings(LiveKitConfigDto cfg)
    {
        var fallback = FromAppsettings();
        if (string.IsNullOrWhiteSpace(cfg.Url)) cfg.Url = fallback.Url;
        if (string.IsNullOrWhiteSpace(cfg.ApiKey)) cfg.ApiKey = fallback.ApiKey;
        if (string.IsNullOrWhiteSpace(cfg.ApiSecret)) cfg.ApiSecret = fallback.ApiSecret;
    }

    private static LiveKitConfigDto Parse(string content)
    {
        try
        {
            return JsonSerializer.Deserialize<LiveKitConfigDto>(content, JsonOpts) ?? new LiveKitConfigDto();
        }
        catch
        {
            return new LiveKitConfigDto();
        }
    }

    private static LiveKitConfigDto Clone(LiveKitConfigDto c) => new()
    {
        Url = c.Url,
        ApiKey = c.ApiKey,
        ApiSecret = c.ApiSecret
    };

    private static string NormalizeWsUrl(string? url)
    {
        var u = (url ?? "").Trim().TrimEnd('/');
        if (string.IsNullOrEmpty(u)) return "";
        if (u.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return "wss://" + u[8..];
        if (u.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
            return "ws://" + u[7..];
        if (!u.Contains("://", StringComparison.Ordinal))
            return "wss://" + u.TrimStart('/');
        return u;
    }

    private static string Truncate(string s, int max) =>
        string.IsNullOrEmpty(s) || s.Length <= max ? s : s[..max] + "…";
}
