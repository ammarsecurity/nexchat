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

            if (features.Value.OutboxEnabled)
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
            else
            {
                await oneSignal.SendToUserAsync(recipientUserId, title, body, payload);
            }

            db.UserNotifications.Add(new UserNotification
            {
                UserId = recipientUserId,
                Type = type,
                Title = title,
                Body = body,
                DataJson = JsonSerializer.Serialize(payload)
            });

            await db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to enqueue notification. Type={Type} Recipient={Recipient}", type, recipientUserId);
        }
    }
}
