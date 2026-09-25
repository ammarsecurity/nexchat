using System.Text.Json;
using Microsoft.Extensions.Options;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

/// <summary>
/// Enqueues push + in-app notification rows on a fresh DI scope so fire-and-forget
/// from SignalR hubs cannot race the hub's disposed <see cref="AppDbContext"/>.
/// </summary>
public class NotificationOutboxService(
    IServiceScopeFactory scopeFactory,
    IOptions<NotificationFeaturesOptions> features,
    ILogger<NotificationOutboxService> logger)
{
    public async Task EnqueueAsync(Guid recipientUserId, string type, string title, string body, Dictionary<string, string>? data = null)
    {
        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var oneSignal = scope.ServiceProvider.GetRequiredService<OneSignalService>();

            var payload = data != null
                ? new Dictionary<string, string>(data)
                : new Dictionary<string, string>();
            payload["type"] = type;
            payload["title"] = title;
            payload["body"] = body;

            // Cancel pushes must not create history rows — they only collapse the ringing UI.
            var skipHistory = type is "call_cancel";
            UserNotification? notif = null;
            if (!skipHistory)
            {
                notif = new UserNotification
                {
                    UserId = recipientUserId,
                    Type = type,
                    Title = title,
                    Body = body,
                    DataJson = null,
                };
                payload["notificationId"] = notif.Id.ToString();
                payload["createdAt"] = notif.CreatedAt.ToUniversalTime().ToString("o");
                notif.DataJson = JsonSerializer.Serialize(payload);
                db.UserNotifications.Add(notif);
            }

            // Incoming calls (and cancels) must leave immediately — outbox lag kills ringing.
            var immediate = type is "video_call" or "call_cancel" || !features.Value.OutboxEnabled;
            if (immediate)
            {
                await oneSignal.SendToUserAsync(recipientUserId, title, body, payload);
            }
            else
            {
                db.NotificationOutboxItems.Add(new NotificationOutboxItem
                {
                    RecipientUserId = recipientUserId,
                    Type = type,
                    PayloadJson = JsonSerializer.Serialize(payload),
                    Status = NotificationOutboxStatus.Pending,
                    NextAttemptAt = DateTime.UtcNow
                });
            }

            await db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to enqueue notification. Type={Type} Recipient={Recipient}", type, recipientUserId);
        }
    }

    public Task CancelCallPushAsync(Guid recipientUserId, Guid conversationId) =>
        EnqueueAsync(
            recipientUserId,
            "call_cancel",
            " ",
            " ",
            new Dictionary<string, string>
            {
                ["conversationId"] = conversationId.ToString(),
            });
}
