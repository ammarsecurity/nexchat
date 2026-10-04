using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>Account-addressed events are independent of whether a conversation screen is open.</summary>
public static class ConversationDelivery
{
    // Tracks only ConversationHub connections. A distributed deployment needs distributed room membership.
    private static readonly object RoomGate = new();
    private static readonly Dictionary<(Guid ConversationId, Guid UserId), HashSet<string>> Rooms = new();

    public static void Joined(Guid conversationId, Guid userId, string connectionId)
    {
        lock (RoomGate)
        {
            if (!Rooms.TryGetValue((conversationId, userId), out var connections))
                Rooms[(conversationId, userId)] = connections = [];
            connections.Add(connectionId);
        }
    }

    public static void Left(Guid conversationId, Guid userId, string connectionId)
    {
        lock (RoomGate)
        {
            if (!Rooms.TryGetValue((conversationId, userId), out var connections)) return;
            connections.Remove(connectionId);
            if (connections.Count == 0) Rooms.Remove((conversationId, userId));
        }
    }

    public static void Disconnected(string connectionId)
    {
        lock (RoomGate)
        {
            foreach (var entry in Rooms.ToList())
            {
                entry.Value.Remove(connectionId);
                if (entry.Value.Count == 0) Rooms.Remove(entry.Key);
            }
        }
    }

    public static async Task EjectAsync(IGroupManager groups, IHubClients<IClientProxy> clients, Guid conversationId, Guid userId)
    {
        List<string> connections;
        lock (RoomGate)
        {
            connections = Rooms.Remove((conversationId, userId), out var current) ? current.ToList() : [];
        }
        foreach (var connectionId in connections)
            await groups.RemoveFromGroupAsync(connectionId, conversationId.ToString());
        await clients.User(userId.ToString()).SendAsync("ConversationRemoved", new { ConversationId = conversationId, UserId = userId });
    }

    public static async Task<List<Guid>> ParticipantsAsync(AppDbContext db, Guid conversationId)
    {
        var conv = await db.Conversations.AsNoTracking().FirstOrDefaultAsync(c => c.Id == conversationId);
        if (conv == null) return [];
        if (conv.Type == ConversationType.Group)
            return await db.ConversationMembers.Where(m => m.ConversationId == conversationId).Select(m => m.UserId).Distinct().ToListAsync();
        return new[] { conv.User1Id, conv.User2Id }.Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
    }

    public static async Task<UserConversationState> MarkReadAsync(AppDbContext db, Guid conversationId, Guid userId, DateTime? readAt = null)
    {
        var now = readAt ?? DateTime.UtcNow;
        if (!await db.UserConversationStates.AnyAsync(s => s.UserId == userId && s.ConversationId == conversationId))
        {
            var created = new UserConversationState { UserId = userId, ConversationId = conversationId, LastReadAt = now, UpdatedAt = now };
            db.UserConversationStates.Add(created);
            try { await db.SaveChangesAsync(); }
            catch (DbUpdateException)
            {
                db.Entry(created).State = EntityState.Detached;
                if (!await db.UserConversationStates.AnyAsync(s => s.UserId == userId && s.ConversationId == conversationId)) throw;
            }
            db.Entry(created).State = EntityState.Detached;
        }
        // Atomic MAX preserves a later watermark even when a slower request finishes last.
        await db.UserConversationStates.Where(s => s.UserId == userId && s.ConversationId == conversationId)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(s => s.LastReadAt, s => s.LastReadAt == null || s.LastReadAt < now ? now : s.LastReadAt)
                .SetProperty(s => s.UpdatedAt, s => s.UpdatedAt < now ? now : s.UpdatedAt));
        return await db.UserConversationStates.AsNoTracking().SingleAsync(s => s.UserId == userId && s.ConversationId == conversationId);
    }

    public static async Task<int> UnreadCountAsync(AppDbContext db, Guid conversationId, Guid userId)
    {
        var now = DateTime.UtcNow;
        return await db.ConversationMessages.CountAsync(m => m.ConversationId == conversationId &&
            m.SenderId != userId && !m.DeletedForEveryone && (m.ExpiresAt == null || m.ExpiresAt > now) &&
            !db.UserMessageDeletions.Any(d => d.UserId == userId && d.MessageId == m.Id) &&
            !db.UserConversationStates.Any(s => s.UserId == userId && s.ConversationId == conversationId &&
                s.LastReadAt != null && m.SentAt <= s.LastReadAt));
    }

    public static async Task SendAsync(AppDbContext db, IHubClients<IClientProxy> clients, Guid conversationId, string method, object payload)
    {
        foreach (var userId in await ParticipantsAsync(db, conversationId))
            await clients.User(userId.ToString()).SendAsync(method, payload);
    }

    public static async Task DeletedAsync(AppDbContext db, IHubClients<IClientProxy> clients, Guid conversationId, Guid messageId)
    {
        // Keep room-scoped scalar events for older clients; modern clients consume only V2.
        await clients.Group(conversationId.ToString()).SendAsync("MessageDeletedForEveryone", messageId);
        await SendAsync(db, clients, conversationId, "MessageDeletedForEveryoneV2", new { ConversationId = conversationId, MessageId = messageId, ReplyToMessageId = messageId });
        await SendAsync(db, clients, conversationId, "ReplyPreviewsRedacted", new { ConversationId = conversationId, MessageIds = new[] { messageId } });
    }
}
