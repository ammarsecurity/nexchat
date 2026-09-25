using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class EvolutionWhatsAppService(
    HttpClient http,
    AppDbContext db,
    IMemoryCache cache,
    ILogger<EvolutionWhatsAppService> logger)
{
    public const string SiteContentKey = "evolution_whatsapp";
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public async Task<EvolutionWhatsAppConfigDto> GetConfigAsync(CancellationToken ct = default)
    {
        if (cache.TryGetValue(SiteContentKey, out EvolutionWhatsAppConfigDto? cached) && cached != null)
            return cached;

        var row = await db.SiteContents.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Key == SiteContentKey, ct);

        var cfg = Parse(row?.Content);
        cache.Set(SiteContentKey, cfg, TimeSpan.FromMinutes(1));
        return cfg;
    }

    public async Task SaveConfigAsync(EvolutionWhatsAppConfigDto cfg, CancellationToken ct = default)
    {
        cfg.BaseUrl = (cfg.BaseUrl ?? "").Trim().TrimEnd('/');
        cfg.ApiKey = (cfg.ApiKey ?? "").Trim();
        cfg.InstanceName = (cfg.InstanceName ?? "").Trim();
        cfg.MessageTemplate = string.IsNullOrWhiteSpace(cfg.MessageTemplate)
            ? "اسم الدخول: {name}\nرمز التحقق في NexChat هو: {code}\nصالح لمدة {minutes} دقائق. لا تشاركه مع أحد."
            : cfg.MessageTemplate.Trim();
        if (cfg.OtpExpiryMinutes < 1) cfg.OtpExpiryMinutes = 5;
        if (cfg.OtpExpiryMinutes > 30) cfg.OtpExpiryMinutes = 30;
        if (cfg.OtpLength < 4) cfg.OtpLength = 4;
        if (cfg.OtpLength > 8) cfg.OtpLength = 8;

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

    public async Task<EvolutionWhatsAppStatusDto> GetStatusAsync(CancellationToken ct = default)
    {
        var cfg = await GetConfigAsync(ct);
        return new EvolutionWhatsAppStatusDto(cfg.Enabled, IsConfigured(cfg));
    }

    public static bool IsConfigured(EvolutionWhatsAppConfigDto cfg) =>
        !string.IsNullOrWhiteSpace(cfg.BaseUrl)
        && !string.IsNullOrWhiteSpace(cfg.ApiKey)
        && !string.IsNullOrWhiteSpace(cfg.InstanceName);

    public async Task<(bool Ok, string? Error)> SendTextAsync(string phoneDigits, string text, CancellationToken ct = default)
    {
        var cfg = await GetConfigAsync(ct);
        if (!cfg.Enabled)
            return (false, "خدمة واتساب غير مفعّلة");
        if (!IsConfigured(cfg))
            return (false, "إعدادات Evolution غير مكتملة");

        var number = new string((phoneDigits ?? "").Where(char.IsDigit).ToArray());
        if (number.Length < 8)
            return (false, "رقم الهاتف غير صالح");

        var client = http;
        var url = $"{cfg.BaseUrl}/message/sendText/{Uri.EscapeDataString(cfg.InstanceName)}";

        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("apikey", cfg.ApiKey);
        req.Content = JsonContent.Create(new { number, text });

        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            if (!res.IsSuccessStatusCode)
            {
                logger.LogWarning("Evolution sendText failed {Status}: {Body}", (int)res.StatusCode, body);
                return (false, "فشل إرسال رسالة واتساب. تحقق من اتصال الـ Instance.");
            }
            return (true, null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Evolution sendText exception");
            return (false, "تعذر الاتصال بخادم Evolution");
        }
    }

    public string BuildOtpMessage(EvolutionWhatsAppConfigDto cfg, string code, string? loginName = null)
    {
        var name = (loginName ?? "").Trim();
        var text = (cfg.MessageTemplate ?? "")
            .Replace("{code}", code, StringComparison.OrdinalIgnoreCase)
            .Replace("{minutes}", cfg.OtpExpiryMinutes.ToString(), StringComparison.OrdinalIgnoreCase)
            .Replace("{name}", name, StringComparison.OrdinalIgnoreCase);

        // قوالب قديمة بلا {name}: أضف اسم الدخول في رسالة استعادة كلمة المرور
        if (!string.IsNullOrEmpty(name)
            && !(cfg.MessageTemplate ?? "").Contains("{name}", StringComparison.OrdinalIgnoreCase))
        {
            text = $"اسم الدخول: {name}\n{text}";
        }

        return text;
    }

    public static string GenerateCode(int length)
    {
        length = Math.Clamp(length, 4, 8);
        var max = (int)Math.Pow(10, length);
        var n = RandomNumberGenerator.GetInt32(0, max);
        return n.ToString($"D{length}");
    }

    public static string HashCode(string code, string? pepper = null)
    {
        var key = string.IsNullOrWhiteSpace(pepper) ? "NexChat-OTP" : pepper;
        var bytes = HMACSHA256.HashData(
            Encoding.UTF8.GetBytes(key),
            Encoding.UTF8.GetBytes((code ?? "").Trim()));
        return Convert.ToHexString(bytes);
    }

    private static EvolutionWhatsAppConfigDto Parse(string? content)
    {
        if (string.IsNullOrWhiteSpace(content))
            return new EvolutionWhatsAppConfigDto();
        try
        {
            return JsonSerializer.Deserialize<EvolutionWhatsAppConfigDto>(content, JsonOpts)
                   ?? new EvolutionWhatsAppConfigDto();
        }
        catch
        {
            return new EvolutionWhatsAppConfigDto();
        }
    }
}
