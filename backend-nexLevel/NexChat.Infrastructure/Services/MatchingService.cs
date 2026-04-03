using System.Collections.Concurrent;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Services;

public class MatchingService(AppDbContext db)
{
    private static readonly ConcurrentDictionary<Guid, string> UserConnectionMap = new();
    private static readonly ConcurrentDictionary<Guid, string> UserLastGenderFilter = new();
    private static readonly ConcurrentDictionary<Guid, (Guid U1, Guid U2, bool A1, bool A2)> RandomMatchPending = new();
    private static readonly object RandomMatchStateLock = new();
    private static readonly ConcurrentDictionary<Guid, (Guid TargetId, DateTime CreatedAt, Guid AttemptId)> PendingRequests = new();
    private static readonly ConcurrentQueue<Guid> QueueAll = new();
    private static readonly ConcurrentQueue<Guid> QueueMale = new();
    private static readonly ConcurrentQueue<Guid> QueueFemale = new();
    private static readonly ConcurrentDictionary<Guid, byte> WaitingSet = new();

    public static bool BlocksRandomJoinUntilAccepted(Guid sessionId)
    {
        lock (RandomMatchStateLock)
            return RandomMatchPending.ContainsKey(sessionId);
    }

    /// <summary>
    /// قبول المطابقة العشوائية قبل فتح الدردشة (متطلبات App Store للمحتوى المُنشأ من المستخدمين).
    /// </summary>
    public bool TryAcceptRandomMatch(Guid sessionId, Guid userId, out bool bothAccepted)
    {
        bothAccepted = false;
        lock (RandomMatchStateLock)
        {
            if (!RandomMatchPending.TryGetValue(sessionId, out var p))
                return false;
            var (u1, u2, a1, a2) = p;
            if (userId == u1) a1 = true;
            else if (userId == u2) a2 = true;
            else return false;

            if (a1 && a2)
            {
                RandomMatchPending.TryRemove(sessionId, out _);
                bothAccepted = true;
                return true;
            }

            RandomMatchPending[sessionId] = (u1, u2, a1, a2);
            return true;
        }
    }

    /// <summary>
    /// رفض/تخطي المطابقة العشوائية قبل بدء الدردشة — يحذف الجلسة ويُبلغ الطرف الآخر.
    /// </summary>
    public async Task<(bool Ok, Guid? PartnerId)> TryDeclineRandomMatchAsync(Guid sessionId, Guid userId)
    {
        Guid? partnerId;
        lock (RandomMatchStateLock)
        {
            if (!RandomMatchPending.TryGetValue(sessionId, out var p))
                return (false, null);
            if (p.U1 != userId && p.U2 != userId)
                return (false, null);
            partnerId = p.U1 == userId ? p.U2 : p.U1;
            RandomMatchPending.TryRemove(sessionId, out _);
        }

        await db.Messages.Where(m => m.SessionId == sessionId).ExecuteDeleteAsync();
        await db.ChatSessions.Where(s => s.Id == sessionId && s.Type == "random").ExecuteDeleteAsync();
        return (true, partnerId);
    }

    public async Task<ChatSession?> TryMatchAsync(Guid userId, string genderFilter, string connectionId)
    {
        var filter = string.IsNullOrWhiteSpace(genderFilter) ? "all" : genderFilter;
        UserLastGenderFilter[userId] = filter;
        UserConnectionMap[userId] = connectionId;
        WaitingSet[userId] = 0;

        var queues = GetQueues(filter);

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
                lock (RandomMatchStateLock)
                {
                    RandomMatchPending[session.Id] = (partnerId, userId, false, false);
                }
                return session;
            }
        }

        GetPrimaryQueue(filter).Enqueue(userId);
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
