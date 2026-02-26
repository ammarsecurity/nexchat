using System.Collections.Concurrent;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace NexChat.Infrastructure.Services;

public class MatchingService(AppDbContext db)
{
    private static readonly ConcurrentDictionary<Guid, string> UserConnectionMap = new();
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
        return Task.CompletedTask;
    }

    public async Task<ChatSession?> ConnectByCodeAsync(Guid requesterId, string code)
    {
        var targetUser = await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == code && !u.IsBanned);
        if (targetUser == null || targetUser.Id == requesterId) return null;

        var session = new ChatSession
        {
            User1Id = requesterId,
            User2Id = targetUser.Id,
            Type = "code"
        };
        db.ChatSessions.Add(session);
        await db.SaveChangesAsync();
        return session;
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
