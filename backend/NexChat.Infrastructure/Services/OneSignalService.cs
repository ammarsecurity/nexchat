using System.Text.Json;
using System.Linq;
using Microsoft.Extensions.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class OneSignalOptions
{
    public string AppId { get; set; } = string.Empty;
    public string RestApiKey { get; set; } = string.Empty;
    /// <summary>قناة Android للإشعارات العاجلة (طلبات الاتصال). أنشئها في OneSignal Dashboard بأهمية Urgent.</summary>
    public string? IncomingCallChannelId { get; set; }
    /// <summary>صوت iOS لطلب الاتصال (مثل default أو اسم ملف مخصص في الـ bundle).</summary>
    public string? IncomingCallSound { get; set; }
}

public class OneSignalService
{
    private readonly HttpClient _http;
    private readonly OneSignalOptions _opts;
    private readonly AppDbContext _db;
    private readonly ILogger<OneSignalService> _logger;

    public OneSignalService(
        HttpClient http,
        IOptions<OneSignalOptions> opts,
        AppDbContext db,
        ILogger<OneSignalService> logger)
    {
        _http = http;
        _opts = opts.Value;
        _db = db;
        _logger = logger;
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

        var result = await SendPayloadWithRetryAsync(payload, "push", GetTypeFromData(data), userId, null);
        return result.Success;
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
    /// إشعار رسالة جديدة في محادثة دائمة
    /// </summary>
    public Task<bool> SendNewConversationMessageAsync(Guid recipientId, string senderName, string preview, Guid conversationId)
        => SendToUserAsync(
            recipientId,
            senderName,
            preview.Length > 80 ? preview[..80] + "…" : preview,
            new { type = "conversation_message", conversationId = conversationId.ToString() });

    /// <summary>
    /// إشعار مكالمة فيديو واردة
    /// </summary>
    public Task<bool> SendVideoCallAsync(Guid recipientId, string callerName, Guid sessionId)
        => SendToUserAsync(
            recipientId,
            "مكالمة فيديو",
            $"{callerName} يطلب مكالمة فيديو",
            new
            {
                type = "video_call",
                sessionId = sessionId.ToString(),
                callerName = callerName ?? ""
            });

    /// <summary>
    /// إشعار مكالمة صوت/فيديو واردة من محادثة دائمة (RoomName = conversationId)
    /// </summary>
    public Task<bool> SendConversationVideoCallAsync(Guid recipientId, string callerName, Guid conversationId, bool voiceOnly = false)
        => SendToUserAsync(
            recipientId,
            voiceOnly ? "مكالمة صوتية" : "مكالمة فيديو",
            voiceOnly ? $"{callerName} يطلب مكالمة صوتية" : $"{callerName} يطلب مكالمة فيديو",
            new { type = "video_call", conversationId = conversationId.ToString() });

    /// <summary>إشعار بطلب مراسلة جديد (يُفتح تطبيق صفحة الطلبات).</summary>
    public Task<bool> SendMessageRequestAsync(Guid recipientId, string requesterName, Guid messageRequestId)
        => SendToUserAsync(
            recipientId,
            "طلب مراسلة",
            $"{requesterName} يريد مراسلتك",
            new { type = "message_request", messageRequestId = messageRequestId.ToString() });

    /// <summary>
    /// إرسال إشعار لأجهزة محددة عبر subscription_ids (أكثر موثوقية من external_id)
    /// </summary>
    public async Task<bool> SendToSubscriptionIdsAsync(
        IEnumerable<string> subscriptionIds,
        string title,
        string body,
        object? data = null)
    {
        if (!IsConfigured) return false;
        var ids = subscriptionIds.Where(s => !string.IsNullOrWhiteSpace(s)).Take(20000).ToArray();
        if (ids.Length == 0) return false;

        var payload = new Dictionary<string, object>
        {
            ["app_id"] = _opts.AppId,
            ["include_subscription_ids"] = ids,
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

        var result = await SendPayloadWithRetryAsync(payload, "push", GetTypeFromData(data), null, ids.FirstOrDefault());
        return result.Success;
    }

    /// <summary>
    /// إشعار اتصال بالكود مع خيارات العجلة (قناة Urgent، time_sensitive، صوت).
    /// </summary>
    public async Task<bool> SendCodeConnectedAsync(
        IEnumerable<string>? subscriptionIds,
        Guid? recipientId,
        string connectorName,
        Guid requesterId,
        string? requesterGender = null,
        string? requesterAvatar = null,
        bool requesterIsFeatured = false)
    {
        if (!IsConfigured) return false;

        var title = "اتصال جديد";
        var body = $"{connectorName} اتصل بك عبر الكود";
        var data = new Dictionary<string, string>
        {
            ["type"] = "code_connected",
            ["requesterId"] = requesterId.ToString(),
            ["requesterName"] = connectorName ?? "",
            ["requesterGender"] = requesterGender ?? "",
            ["requesterAvatar"] = requesterAvatar ?? "",
            ["requesterIsFeatured"] = requesterIsFeatured ? "true" : "false"
        };

        Dictionary<string, object> payload;
        var ids = subscriptionIds?.Where(s => !string.IsNullOrWhiteSpace(s)).ToArray() ?? Array.Empty<string>();

        if (ids.Length > 0)
        {
            payload = new Dictionary<string, object>
            {
                ["app_id"] = _opts.AppId,
                ["include_subscription_ids"] = ids.Take(20000).ToArray(),
                ["target_channel"] = "push",
                ["headings"] = new Dictionary<string, string> { ["ar"] = title, ["en"] = title },
                ["contents"] = new Dictionary<string, string> { ["ar"] = body, ["en"] = body },
                ["data"] = data
            };
        }
        else if (recipientId.HasValue)
        {
            payload = new Dictionary<string, object>
            {
                ["app_id"] = _opts.AppId,
                ["include_aliases"] = new Dictionary<string, object> { ["external_id"] = new[] { recipientId.Value.ToString() } },
                ["target_channel"] = "push",
                ["headings"] = new Dictionary<string, string> { ["ar"] = title, ["en"] = title },
                ["contents"] = new Dictionary<string, string> { ["ar"] = body, ["en"] = body },
                ["data"] = data
            };
        }
        else
            return false;

        AddUrgencyOptions(payload);

        var result = await SendPayloadWithRetryAsync(payload, "push", "code_connected", recipientId, ids.FirstOrDefault());
        return result.Success;
    }

    /// <summary>إضافة خيارات العجلة لإشعار طلب الاتصال.</summary>
    private void AddUrgencyOptions(Dictionary<string, object> payload)
    {
        payload["priority"] = 10;
        payload["ios_interruption_level"] = "time_sensitive";

        if (!string.IsNullOrWhiteSpace(_opts.IncomingCallChannelId))
            payload["android_channel_id"] = _opts.IncomingCallChannelId;

        if (!string.IsNullOrWhiteSpace(_opts.IncomingCallSound))
            payload["ios_sound"] = _opts.IncomingCallSound;
    }

    /// <summary>
    /// إرسال إشعار لجميع الأجهزة المشتركة عبر subscription_ids من قاعدة البيانات.
    /// يرسل على دفعات (20000 كحد أقصى لكل طلب).
    /// </summary>
    /// <param name="subscriptionIds">قائمة OneSignalPlayerId من DeviceSubscriptions</param>
    /// <param name="title">عنوان الإشعار</param>
    /// <param name="body">نص الإشعار</param>
    /// <param name="imageUrl">رابط صورة اختياري (big_picture / large_icon)</param>
    /// <returns>(نجاح، عدد المستلمين، رسالة خطأ إن وجدت)</returns>
    public async Task<(bool Success, int RecipientsCount, string? Error)> SendBroadcastAsync(
        IEnumerable<string> subscriptionIds,
        string title,
        string body,
        string? imageUrl = null)
    {
        if (!IsConfigured)
            return (false, 0, "OneSignal غير مُعد (AppId أو RestApiKey ناقص)");

        var ids = subscriptionIds
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct()
            .ToArray();

        if (ids.Length == 0)
            return (false, 0, "لا توجد أجهزة مشتركة للإرسال");

        var payloadBase = new Dictionary<string, object>
        {
            ["target_channel"] = "push",
            ["headings"] = new Dictionary<string, string> { ["ar"] = title, ["en"] = title },
            ["contents"] = new Dictionary<string, string> { ["ar"] = body, ["en"] = body }
        };

        if (!string.IsNullOrWhiteSpace(imageUrl))
        {
            payloadBase["big_picture"] = imageUrl;
            payloadBase["large_icon"] = imageUrl;
        }

        const int batchSize = 20000;
        var totalSent = 0;

        try
        {
            for (var i = 0; i < ids.Length; i += batchSize)
            {
                var batch = ids.Skip(i).Take(batchSize).ToArray();
                var payload = new Dictionary<string, object>(payloadBase)
                {
                    ["app_id"] = _opts.AppId,
                    ["include_subscription_ids"] = batch
                };

                var send = await SendPayloadWithRetryAsync(payload, "push", "broadcast", null, batch.FirstOrDefault());
                if (!send.Success)
                    return (false, totalSent, $"OneSignal: {send.Error ?? "send failed"}");

                totalSent += batch.Length;
            }

            return (true, totalSent, null);
        }
        catch (Exception ex)
        {
            return (false, totalSent, $"OneSignal: {ex.Message}");
        }
    }

    public async Task<(bool Success, string? ProviderMessageId, string? Error)> SendOutboxItemAsync(NotificationOutboxItem item)
    {
        if (!IsConfigured) return (false, null, "OneSignal not configured");

        var payload = BuildPayloadForOutbox(item);
        if (payload == null)
            return (false, null, $"Unknown outbox type: {item.Type}");

        var firstSub = TryGetFirstSubscriptionId(payload);
        var result = await SendPayloadWithRetryAsync(payload, "push", item.Type, item.RecipientUserId, firstSub);
        return (result.Success, result.ProviderMessageId, result.Error);
    }

    private Dictionary<string, object>? BuildPayloadForOutbox(NotificationOutboxItem item)
    {
        var data = JsonSerializer.Deserialize<Dictionary<string, string>>(item.PayloadJson ?? "{}")
                   ?? new Dictionary<string, string>();
        var title = data.TryGetValue("title", out var t) ? t : "إشعار";
        var body = data.TryGetValue("body", out var b) ? b : "";
        data.Remove("title");
        data.Remove("body");

        return new Dictionary<string, object>
        {
            ["app_id"] = _opts.AppId,
            ["include_aliases"] = new Dictionary<string, object>
            {
                ["external_id"] = new[] { item.RecipientUserId.ToString() }
            },
            ["target_channel"] = "push",
            ["headings"] = new Dictionary<string, string> { ["ar"] = title, ["en"] = title },
            ["contents"] = new Dictionary<string, string> { ["ar"] = body, ["en"] = body },
            ["data"] = data
        };
    }

    private async Task<(bool Success, string? ProviderMessageId, string? Error)> SendPayloadWithRetryAsync(
        Dictionary<string, object> payload,
        string channel,
        string type,
        Guid? recipientUserId,
        string? recipientSubscriptionId)
    {
        var payloadJson = JsonSerializer.Serialize(payload);
        string? providerMessageId = null;
        string? lastError = null;
        int? lastStatus = null;
        const int maxAttempts = 3;

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            try
            {
                var content = new StringContent(payloadJson, System.Text.Encoding.UTF8, "application/json");
                var res = await _http.PostAsync("notifications", content);
                var resBody = await res.Content.ReadAsStringAsync();
                lastStatus = (int)res.StatusCode;
                providerMessageId = TryExtractProviderId(resBody);

                if (res.IsSuccessStatusCode)
                {
                    await PersistDeliveryLogAsync(channel, type, recipientUserId, recipientSubscriptionId, true, lastStatus, attempt, providerMessageId, null, payloadJson);
                    return (true, providerMessageId, null);
                }

                lastError = $"HTTP {(int)res.StatusCode}: {resBody}";
                await PersistDeliveryLogAsync(channel, type, recipientUserId, recipientSubscriptionId, false, lastStatus, attempt, providerMessageId, lastError, payloadJson);
            }
            catch (Exception ex)
            {
                lastError = ex.Message;
                await PersistDeliveryLogAsync(channel, type, recipientUserId, recipientSubscriptionId, false, null, attempt, providerMessageId, ex.Message, payloadJson);
            }

            if (attempt < maxAttempts)
                await Task.Delay(TimeSpan.FromMilliseconds(200 * attempt));
        }

        _logger.LogWarning("OneSignal send failed after retries. Type={Type} Recipient={Recipient} Error={Error}", type, recipientUserId, lastError);
        return (false, providerMessageId, lastError ?? "send failed");
    }

    private async Task PersistDeliveryLogAsync(
        string channel,
        string type,
        Guid? recipientUserId,
        string? recipientSubscriptionId,
        bool success,
        int? statusCode,
        int attempt,
        string? providerMessageId,
        string? error,
        string payloadJson)
    {
        try
        {
            _db.NotificationDeliveryLogs.Add(new NotificationDeliveryLog
            {
                Channel = channel,
                Type = type,
                RecipientUserId = recipientUserId,
                RecipientSubscriptionId = recipientSubscriptionId,
                Success = success,
                HttpStatusCode = statusCode,
                Attempt = attempt,
                ProviderMessageId = providerMessageId,
                Error = error,
                PayloadPreview = payloadJson.Length > 1900 ? payloadJson[..1900] : payloadJson
            });
            await _db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to persist notification delivery log");
        }
    }

    private static string? TryExtractProviderId(string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return null;
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("id", out var idEl))
                return idEl.GetString();
        }
        catch {}
        return null;
    }

    private static string GetTypeFromData(object? data)
    {
        if (data == null) return "generic";
        try
        {
            var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(JsonSerializer.Serialize(data));
            if (dict != null && dict.TryGetValue("type", out var type) && !string.IsNullOrWhiteSpace(type))
                return type;
        }
        catch {}
        return "generic";
    }

    private static string? TryGetFirstSubscriptionId(Dictionary<string, object> payload)
    {
        if (!payload.TryGetValue("include_subscription_ids", out var idsObj) || idsObj is not IEnumerable<string> ids)
            return null;
        return ids.FirstOrDefault();
    }
}
