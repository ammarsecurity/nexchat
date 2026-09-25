using System.Collections.Concurrent;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>
/// Tracks live SignalR connections across hubs with refcounting so IsOnline stays accurate
/// for multi-device and ConversationHub-only (messaging) sessions.
/// </summary>
public class UserPresenceService(IServiceScopeFactory scopeFactory, ILogger<UserPresenceService> logger)
{
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<string, byte>> _connections = new();

    public bool IsConnected(Guid userId) =>
        _connections.TryGetValue(userId, out var set) && !set.IsEmpty;

    public async Task OnConnectedAsync(Guid userId, string connectionId)
    {
        var set = _connections.GetOrAdd(userId, _ => new ConcurrentDictionary<string, byte>());
        if (!set.TryAdd(connectionId, 0)) return;
        if (set.Count != 1) return;

        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await db.Users.Where(u => u.Id == userId)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, true));
            await BroadcastPresenceAsync(scope.ServiceProvider, db, userId, online: true);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to mark user online {UserId}", userId);
        }
    }

    public async Task OnDisconnectedAsync(Guid userId, string connectionId)
    {
        if (!_connections.TryGetValue(userId, out var set)) return;
        set.TryRemove(connectionId, out _);
        if (!set.IsEmpty) return;
        _connections.TryRemove(userId, out _);

        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await db.Users.Where(u => u.Id == userId)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, false));
            await BroadcastPresenceAsync(scope.ServiceProvider, db, userId, online: false);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to mark user offline {UserId}", userId);
        }
    }

    /// <summary>Clear stale DB flags after process restart (in-memory map is empty).</summary>
    public async Task ResetStaleOnlineFlagsAsync()
    {
        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var n = await db.Users.Where(u => u.IsOnline)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, false));
            if (n > 0)
                logger.LogInformation("Reset {Count} stale IsOnline flags on startup", n);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to reset stale IsOnline flags");
        }
    }

    private static async Task BroadcastPresenceAsync(IServiceProvider sp, AppDbContext db, Guid userId, bool online)
    {
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null) return;

        // If they hide status, others always see offline even while connected.
        var payloadOnline = online && user.ShowOnlineStatusToOthers;

        var partnerIds = await db.Conversations.AsNoTracking()
            .Where(c => c.Type == NexChat.Core.Entities.ConversationType.Private &&
                        (c.User1Id == userId || c.User2Id == userId))
            .Select(c => c.User1Id == userId ? c.User2Id : c.User1Id)
            .Where(id => id != null)
            .Select(id => id!.Value)
            .Distinct()
            .ToListAsync();

        if (partnerIds.Count == 0) return;

        var hub = sp.GetRequiredService<IHubContext<ConversationHub>>();
        var payload = new { userId = userId.ToString(), isOnline = payloadOnline };
        foreach (var pid in partnerIds)
            await hub.Clients.User(pid.ToString()).SendAsync("UserPresenceChanged", payload);
    }
}
