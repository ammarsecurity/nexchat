using System.Collections.Concurrent;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class MatchingService(AppDbContext db)
{
    private static readonly ConcurrentDictionary<Guid, string> UserConnectionMap = new();
    private static readonly ConcurrentDictionary<Guid, (Guid TargetId, DateTime CreatedAt, Guid AttemptId)> PendingRequests = new();
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
            return (false, null, "المستخدم غير موجود أو الكود غير صحيح");

        if (PendingRequests.ContainsKey(requesterId))
            return (false, null, "لديك طلب قيد الانتظار");

        var attempt = new CodeConnectionAttempt
        {
            RequesterId = requesterId,
            TargetId = targetUser.Id,
            Status = "Pending"
        };
        db.CodeConnectionAttempts.Add(attempt);
        await db.SaveChangesAsync();

        PendingRequests[requesterId] = (targetUser.Id, attempt.CreatedAt, attempt.Id);
        return (true, targetUser.Id, null);
    }

    /// <summary>
    /// جلب طلبات الاتصال المعلقة للمستخدم (عندما يكون هو المستهدف)
    /// يُستدعى عند اتصال المستخدم لإرسال الطلبات التي فاتته وهو غير متصل
    /// </summary>
    public IReadOnlyList<(Guid RequesterId, DateTime CreatedAt, Guid AttemptId)> GetPendingRequestsForTarget(Guid targetId)
    {
        var now = DateTime.UtcNow;
        var result = new List<(Guid RequesterId, DateTime CreatedAt, Guid AttemptId)>();
        foreach (var kv in PendingRequests.ToArray())
        {
            if (kv.Value.TargetId != targetId) continue;
            if ((now - kv.Value.CreatedAt).TotalSeconds > RequestTimeoutSeconds) continue;
            result.Add((kv.Key, kv.Value.CreatedAt, kv.Value.AttemptId));
        }
        return result.OrderByDescending(x => x.CreatedAt).ToList();
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

        await db.CodeConnectionAttempts
            .Where(a => a.Id == pending.AttemptId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(a => a.Status, "Accepted")
                .SetProperty(a => a.SessionId, session.Id));

        return session;
    }

    public async Task<bool> DeclineConnectionRequestAsync(Guid targetId, Guid requesterId)
    {
        if (!PendingRequests.TryGetValue(requesterId, out var pending) || pending.TargetId != targetId)
            return false;
        if (!PendingRequests.TryRemove(requesterId, out _))
            return false;
        await db.CodeConnectionAttempts
            .Where(a => a.Id == pending.AttemptId)
            .ExecuteUpdateAsync(s => s.SetProperty(a => a.Status, "Declined"));
        return true;
    }

    public async Task<(bool Success, Guid? TargetId)> CancelConnectionRequestAsync(Guid requesterId)
    {
        if (!PendingRequests.TryRemove(requesterId, out var pending))
            return (false, null);
        var targetId = pending.TargetId;
        await db.CodeConnectionAttempts
            .Where(a => a.Id == pending.AttemptId)
            .ExecuteUpdateAsync(s => s.SetProperty(a => a.Status, "Cancelled"));
        return (true, targetId);
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
