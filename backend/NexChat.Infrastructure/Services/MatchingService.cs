using System.Collections.Concurrent;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace NexChat.Infrastructure.Services;

public class MatchingService(AppDbContext db)
{
    private static readonly ConcurrentDictionary<Guid, string> UserConnectionMap = new();
    private static readonly ConcurrentDictionary<Guid, (Guid TargetId, DateTime CreatedAt)> PendingRequests = new();
    private static readonly ConcurrentQueue<Guid> QueueAll = new();
    private static readonly ConcurrentQueue<Guid> QueueMale = new();
    private static readonly ConcurrentQueue<Guid> QueueFemale = new();
    private static readonly ConcurrentDictionary<Guid, byte> WaitingSet = new();

    public async Task<ChatSession?> TryMatchAsync(Guid userId, string genderFilter, string connectionId)
    {
        UserConnectionMap[userId] = connectionId;
        WaitingSet[userId] = 0;

        var queues = GetQueues(genderFilter);

        foreach (var queue in queues)
        {
            while (queue.TryDequeue(out var partnerId))
            {
                if (partnerId == userId || !WaitingSet.ContainsKey(partnerId))
                    continue;

                WaitingSet.TryRemove(userId, out _);
                WaitingSet.TryRemove(partnerId, out _);

                var session = new ChatSession
                {
                    User1Id = partnerId,
                    User2Id = userId,
                    Type = "random"
                };
                db.ChatSessions.Add(session);
                await db.SaveChangesAsync();
                return session;
            }
        }

        GetPrimaryQueue(genderFilter).Enqueue(userId);
        return null;
    }

    public Task RemoveFromQueueAsync(Guid userId)
    {
        WaitingSet.TryRemove(userId, out _);
        UserConnectionMap.TryRemove(userId, out _);
        return Task.CompletedTask;
    }

    public Task<string?> GetConnectionIdAsync(Guid userId)
    {
        UserConnectionMap.TryGetValue(userId, out var connId);
        return Task.FromResult(connId);
    }

    public Task SetUserOnlineAsync(Guid userId, string connectionId)
    {
        UserConnectionMap[userId] = connectionId;
        return Task.CompletedTask;
    }

    public Task SetUserOfflineAsync(Guid userId)
    {
        WaitingSet.TryRemove(userId, out _);
        UserConnectionMap.TryRemove(userId, out _);
        RemovePendingRequestsForUser(userId);
        return Task.CompletedTask;
    }

    public async Task<(bool RequestSent, Guid? TargetId, string? Error)> RequestConnectionByCodeAsync(Guid requesterId, string code)
    {
        var targetUser = await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == code && !u.IsBanned);
        if (targetUser == null || targetUser.Id == requesterId)
            return (false, null, "User not found or invalid code");

        var targetOnline = UserConnectionMap.ContainsKey(targetUser.Id);
        if (!targetOnline)
            return (false, null, "المستخدم غير متصل حالياً");

        if (PendingRequests.ContainsKey(requesterId))
            return (false, null, "لديك طلب قيد الانتظار");

        PendingRequests[requesterId] = (targetUser.Id, DateTime.UtcNow);
        return (true, targetUser.Id, null);
    }

    private const int RequestTimeoutSeconds = 60;

    public async Task<ChatSession?> AcceptConnectionRequestAsync(Guid targetId, Guid requesterId)
    {
        if (!PendingRequests.TryRemove(requesterId, out var pending) || pending.TargetId != targetId)
            return null;
        if ((DateTime.UtcNow - pending.CreatedAt).TotalSeconds > RequestTimeoutSeconds)
            return null;

        var session = new ChatSession
        {
            User1Id = requesterId,
            User2Id = targetId,
            Type = "code"
        };
        db.ChatSessions.Add(session);
        await db.SaveChangesAsync();
        return session;
    }

    public bool DeclineConnectionRequest(Guid targetId, Guid requesterId)
    {
        if (!PendingRequests.TryGetValue(requesterId, out var pending) || pending.TargetId != targetId)
            return false;
        return PendingRequests.TryRemove(requesterId, out _);
    }

    public bool CancelConnectionRequest(Guid requesterId)
    {
        return PendingRequests.TryRemove(requesterId, out _);
    }

    private static void RemovePendingRequestsForUser(Guid userId)
    {
        foreach (var kv in PendingRequests.ToArray())
        {
            if (kv.Value.TargetId == userId || kv.Key == userId)
                PendingRequests.TryRemove(kv.Key, out _);
        }
    }

    private static ConcurrentQueue<Guid> GetPrimaryQueue(string genderFilter) => genderFilter switch
    {
        "male" => QueueMale,
        "female" => QueueFemale,
        _ => QueueAll
    };

    private static IEnumerable<ConcurrentQueue<Guid>> GetQueues(string genderFilter) => genderFilter switch
    {
        "male" => [QueueMale, QueueAll],
        "female" => [QueueFemale, QueueAll],
        _ => [QueueAll, QueueMale, QueueFemale]
    };
}
