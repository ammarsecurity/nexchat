using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace NexChat.API.Services;

/// <summary>
/// Sends iOS PushKit VoIP pushes so CallKit can ring when the app is killed.
/// Requires ApnsVoip config (p8 key). Silent no-op when not configured.
/// </summary>
public class ApnsVoipService(IOptions<ApnsVoipOptions> options, IHttpClientFactory httpClientFactory, ILogger<ApnsVoipService> logger)
{
    private string? _cachedJwt;
    private DateTime _jwtExpires = DateTime.MinValue;

    public bool IsConfigured
    {
        get
        {
            var o = options.Value;
            return !string.IsNullOrWhiteSpace(o.KeyPath)
                && !string.IsNullOrWhiteSpace(o.KeyId)
                && !string.IsNullOrWhiteSpace(o.TeamId)
                && File.Exists(o.KeyPath);
        }
    }

    public async Task SendVoipAsync(string deviceTokenHex, Dictionary<string, string> data, CancellationToken ct = default)
    {
        if (!IsConfigured) return;
        if (string.IsNullOrWhiteSpace(deviceTokenHex)) return;

        var o = options.Value;
        var host = o.UseSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
        var token = deviceTokenHex.Replace(" ", "").Trim();
        var url = $"https://{host}/3/device/{token}";

        // Custom keys under "data" (VoipPushManager reads data[] or root).
        var payload = new Dictionary<string, object>
        {
            ["aps"] = new Dictionary<string, object>
            {
                ["content-available"] = 1,
            },
            ["data"] = data,
        };
        foreach (var kv in data)
            payload[kv.Key] = kv.Value;

        var json = JsonSerializer.Serialize(payload);
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Version = new Version(2, 0);
        req.Headers.Authorization = new AuthenticationHeaderValue("bearer", GetJwt());
        req.Headers.TryAddWithoutValidation("apns-topic", $"{o.BundleId}.voip");
        req.Headers.TryAddWithoutValidation("apns-push-type", "voip");
        req.Headers.TryAddWithoutValidation("apns-priority", "10");
        req.Headers.TryAddWithoutValidation("apns-expiration", "0");
        req.Content = new StringContent(json, Encoding.UTF8, "application/json");

        try
        {
            var client = httpClientFactory.CreateClient("apns-voip");
            var res = await client.SendAsync(req, ct);
            if (!res.IsSuccessStatusCode)
            {
                var body = await res.Content.ReadAsStringAsync(ct);
                logger.LogWarning("APNs VoIP failed {Status}: {Body}", (int)res.StatusCode, body);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "APNs VoIP send error");
        }
    }

    private string GetJwt()
    {
        if (_cachedJwt != null && DateTime.UtcNow < _jwtExpires)
            return _cachedJwt;

        var o = options.Value;
        var keyText = File.ReadAllText(o.KeyPath!);
        var ecdsa = ECDsa.Create();
        ecdsa.ImportFromPem(keyText);
        var credentials = new SigningCredentials(new ECDsaSecurityKey(ecdsa), SecurityAlgorithms.EcdsaSha256);
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            issuer: o.TeamId,
            claims: null,
            notBefore: now,
            expires: now.AddMinutes(50),
            signingCredentials: credentials);
        token.Header["kid"] = o.KeyId;
        _cachedJwt = new JwtSecurityTokenHandler().WriteToken(token);
        _jwtExpires = now.AddMinutes(40);
        return _cachedJwt;
    }
}
