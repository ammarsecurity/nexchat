using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>
/// يغلق الجلسات غير النشطة تلقائياً إذا مرت أكثر من ساعة بدون رسالة.
/// لا يغلق جلسات الدعم (support).
/// يرسل SessionEnded للعملاء المتصلين قبل إغلاق الجلسة.
/// </summary>
public class InactiveSessionCleanupService(IServiceScopeFactory scopeFactory) : BackgroundService
{
    private static readonly TimeSpan InactivityThreshold = TimeSpan.FromHours(1);
    private static readonly TimeSpan RunInterval = TimeSpan.FromMinutes(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CloseInactiveSessionsAsync();
            }
            catch (Exception ex)
            {
                // Log but don't crash
                Console.WriteLine($"[InactiveSessionCleanup] Error: {ex.Message}");
            }

            await Task.Delay(RunInterval, stoppingToken);
        }
    }

    private async Task CloseInactiveSessionsAsync()
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var hubContext = scope.ServiceProvider.GetRequiredService<IHubContext<ChatHub>>();

        var cutoff = DateTime.UtcNow - InactivityThreshold;

        // جلسات مفتوحة (ليست support) حيث آخر نشاط قبل ساعة
        var toClose = await db.ChatSessions
            .Where(s => s.EndedAt == null && s.Type != "support")
            .Select(s => new
            {
                s.Id,
                LastActivity = s.Messages.Any()
                    ? s.Messages.Max(m => m.SentAt)
                    : s.StartedAt
            })
            .Where(x => x.LastActivity < cutoff)
            .Select(x => x.Id)
            .ToListAsync();

        if (toClose.Count > 0)
        {
            await db.ChatSessions
                .Where(s => toClose.Contains(s.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.EndedAt, DateTime.UtcNow));

            foreach (var sid in toClose)
                await hubContext.Clients.Group(sid.ToString()).SendAsync("SessionEnded", Guid.Empty);
        }
    }
}
