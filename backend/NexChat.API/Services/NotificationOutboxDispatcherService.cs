using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

public class NotificationOutboxDispatcherService(IServiceProvider sp, ILogger<NotificationOutboxDispatcherService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = sp.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var oneSignal = scope.ServiceProvider.GetRequiredService<OneSignalService>();
                var features = scope.ServiceProvider.GetRequiredService<IOptions<NotificationFeaturesOptions>>().Value;
                if (!features.OutboxEnabled)
                {
                    await Task.Delay(1500, stoppingToken);
                    continue;
                }

                // Reclaim items stuck in Processing (crash mid-send).
                var stuckBefore = DateTime.UtcNow.AddMinutes(-2);
                var stuck = await db.NotificationOutboxItems
                    .Where(x => x.Status == NotificationOutboxStatus.Processing && x.LastAttemptAt != null && x.LastAttemptAt < stuckBefore)
                    .Take(50)
                    .ToListAsync(stoppingToken);
                foreach (var s in stuck)
                {
                    s.Status = NotificationOutboxStatus.Pending;
                    s.NextAttemptAt = DateTime.UtcNow;
                }
                if (stuck.Count > 0)
                    await db.SaveChangesAsync(stoppingToken);

                // Prefer urgent call items so ringing is not stuck behind chat/story pushes.
                var batch = await db.NotificationOutboxItems
                    .Where(x => (x.Status == NotificationOutboxStatus.Pending || x.Status == NotificationOutboxStatus.Failed) &&
                                x.NextAttemptAt <= DateTime.UtcNow)
                    .OrderByDescending(x => x.Type == "video_call" || x.Type == "call_cancel")
                    .ThenBy(x => x.CreatedAt)
                    .Take(20)
                    .ToListAsync(stoppingToken);

                var sentCount = 0;
                var failCount = 0;
                var deadCount = 0;
                foreach (var item in batch)
                {
                    item.Status = NotificationOutboxStatus.Processing;
                    item.LastAttemptAt = DateTime.UtcNow;
                    item.AttemptCount += 1;
                    await db.SaveChangesAsync(stoppingToken);

                    var send = await oneSignal.SendOutboxItemAsync(item);
                    if (send.Success)
                    {
                        item.Status = NotificationOutboxStatus.Sent;
                        item.LastProviderMessageId = send.ProviderMessageId;
                        item.LastError = null;
                        sentCount += 1;
                    }
                    else
                    {
                        item.LastError = send.Error;
                        var terminal = item.AttemptCount >= 5;
                        item.Status = terminal ? NotificationOutboxStatus.DeadLetter : NotificationOutboxStatus.Failed;
                        if (!terminal)
                            item.NextAttemptAt = DateTime.UtcNow.AddSeconds(Math.Min(120, 5 * item.AttemptCount));
                        if (terminal) deadCount += 1;
                        else failCount += 1;
                    }
                    await db.SaveChangesAsync(stoppingToken);
                }

                if (batch.Count > 0)
                    logger.LogInformation("Notification outbox cycle processed={Count} sent={Sent} failed={Failed} dead={Dead}", batch.Count, sentCount, failCount, deadCount);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Notification outbox dispatcher cycle failed");
            }

            await Task.Delay(1000, stoppingToken);
        }
    }
}
