using System.Text.Json;
using Microsoft.Extensions.Options;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

public class NotificationOutboxService(
    AppDbContext db,
    IOptions<NotificationFeaturesOptions> features,
    OneSignalService oneSignal)
{
    public async Task EnqueueAsync(Guid recipientUserId, string type, string title, string body, Dictionary<string, string>? data = null)
    {
        var payload = data ?? new Dictionary<string, string>();
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
}
