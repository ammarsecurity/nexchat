using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

public class StoryExpiryBackgroundService(
    IServiceProvider sp,
    ILogger<StoryExpiryBackgroundService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromMinutes(15), stoppingToken);
                await PurgeExpiredAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Story expiry purge failed");
            }
        }
    }

    private async Task PurgeExpiredAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var hub = scope.ServiceProvider.GetRequiredService<IHubContext<StoryHub>>();
        var env = scope.ServiceProvider.GetRequiredService<IWebHostEnvironment>();

        var now = DateTime.UtcNow;
        var expired = await db.StorySlides
            .Where(s => s.ExpiresAt <= now)
            .ToListAsync(ct);

        if (expired.Count == 0) return;

        var uploadsPath = Path.Combine(env.WebRootPath ?? "wwwroot", "uploads");
        var byUser = expired.GroupBy(s => s.UserId);

        foreach (var slide in expired)
        {
            TryDeleteUploadFile(uploadsPath, slide.MediaUrl);
        }

        db.StorySlides.RemoveRange(expired);
        await db.SaveChangesAsync(ct);

        foreach (var group in byUser)
        {
            var audience = scope.ServiceProvider.GetRequiredService<StoryAudienceService>();
            var ids = await audience.GetAudienceUserIdsAsync(group.Key);
            ids.Add(group.Key);
            foreach (var slide in group)
            {
                await hub.Clients.Users(ids.Select(i => i.ToString()).Distinct().ToList())
                    .SendAsync("StoryDeleted", new { userId = group.Key, slideId = slide.Id }, ct);
            }
        }

        logger.LogInformation("Purged {Count} expired story slides", expired.Count);
    }

    private static void TryDeleteUploadFile(string uploadsPath, string? mediaUrl)
    {
        if (string.IsNullOrWhiteSpace(mediaUrl)) return;
        try
        {
            var pathPart = Uri.TryCreate(mediaUrl, UriKind.Absolute, out var uri)
                ? uri.AbsolutePath
                : mediaUrl;
            var fileName = Path.GetFileName(pathPart);
            if (string.IsNullOrEmpty(fileName) || fileName.Contains("..")) return;
            var path = Path.Combine(uploadsPath, fileName);
            if (File.Exists(path))
                File.Delete(path);
        }
        catch
        {
            // ignore file delete errors
        }
    }
}
