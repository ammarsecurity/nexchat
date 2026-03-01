using System.Text.Json;
using Microsoft.Extensions.Options;

namespace NexChat.Infrastructure.Services;

public class OneSignalOptions
{
    public string AppId { get; set; } = string.Empty;
    public string RestApiKey { get; set; } = string.Empty;
}

public class OneSignalService
{
    private readonly HttpClient _http;
    private readonly OneSignalOptions _opts;

    public OneSignalService(HttpClient http, IOptions<OneSignalOptions> opts)
    {
        _http = http;
        _opts = opts.Value;
        _http.BaseAddress = new Uri("https://api.onesignal.com/");
        _http.DefaultRequestHeaders.Add("Authorization", $"Key {_opts.RestApiKey}");
    }

    public bool IsConfigured => !string.IsNullOrEmpty(_opts.AppId) && !string.IsNullOrEmpty(_opts.RestApiKey);

    /// <summary>
    /// إرسال إشعار لمستخدم واحد عبر external_id (userId)
    /// </summary>
    public async Task<bool> SendToUserAsync(Guid userId, string title, string body, object? data = null)
    {
        if (!IsConfigured) return false;

        var payload = new Dictionary<string, object>
        {
            ["app_id"] = _opts.AppId,
            ["include_aliases"] = new Dictionary<string, object>
            {
                ["external_id"] = new[] { userId.ToString() }
            },
            ["target_channel"] = "push",
            ["headings"] = new Dictionary<string, string> { ["ar"] = title, ["en"] = title },
            ["contents"] = new Dictionary<string, string> { ["ar"] = body, ["en"] = body }
        };

        if (data != null)
        {
            var dataDict = JsonSerializer.Deserialize<Dictionary<string, string>>(
                JsonSerializer.Serialize(data));
            if (dataDict != null)
                payload["data"] = dataDict;
        }

        var json = JsonSerializer.Serialize(payload);
        var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");
        var res = await _http.PostAsync("notifications", content);
        return res.IsSuccessStatusCode;
    }

    /// <summary>
    /// إشعار رسالة جديدة
    /// </summary>
    public Task<bool> SendNewMessageAsync(Guid recipientId, string senderName, string preview, Guid sessionId)
        => SendToUserAsync(
            recipientId,
            senderName,
            preview.Length > 80 ? preview[..80] + "…" : preview,
            new { type = "message", sessionId = sessionId.ToString() });

    /// <summary>
    /// إشعار مكالمة فيديو واردة
    /// </summary>
    public Task<bool> SendVideoCallAsync(Guid recipientId, string callerName, Guid sessionId)
        => SendToUserAsync(
            recipientId,
            "مكالمة فيديو",
            $"{callerName} يطلب مكالمة فيديو",
            new { type = "video_call", sessionId = sessionId.ToString() });

    /// <summary>
    /// إشعار اتصال بالكود
    /// </summary>
    public Task<bool> SendCodeConnectedAsync(Guid recipientId, string connectorName)
        => SendToUserAsync(
            recipientId,
            "اتصال جديد",
            $"{connectorName} اتصل بك عبر الكود",
            new { type = "code_connected" });
}
