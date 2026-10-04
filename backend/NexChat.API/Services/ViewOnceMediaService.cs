using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

public sealed record ViewOnceOpenResult(Guid MessageId, Guid ConversationId, Guid SenderId, string Type, string? Content, Guid? SessionId, bool Opened, bool ReceiptCreated);

/// <summary>Receipt consumption and session creation commit atomically. A session permits range
/// requests only for its authenticated participant until closed or its fixed deadline.</summary>
public sealed class ViewOnceMediaService(AppDbContext db, MediaStorageService storage, IConversationMessageCrypto crypto, TimeProvider clock)
{
    public static readonly TimeSpan SessionLifetime = TimeSpan.FromMinutes(15);

    private async Task<ConversationMessage?> AccessibleMessage(Guid messageId, Guid userId)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var msg = await db.ConversationMessages.AsNoTracking().FirstOrDefaultAsync(m => m.Id == messageId && m.IsViewOnce && !m.DeletedForEveryone && (m.ExpiresAt == null || m.ExpiresAt > now));
        if (msg == null || msg.Type is not ("image" or "video")) return null;
        var participant = await db.Conversations.AnyAsync(c => c.Id == msg.ConversationId &&
            (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId) ||
             c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == c.Id && m.UserId == userId)));
        if (!participant || await db.UserMessageDeletions.AnyAsync(d => d.UserId == userId && d.MessageId == msg.Id) ||
            await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == msg.ConversationId)) return null;
        return msg;
    }

    public async Task<ViewOnceOpenResult?> OpenAsync(Guid messageId, Guid userId)
    {
        var msg = await AccessibleMessage(messageId, userId);
        if (msg == null || !storage.TryPrivatePath(crypto.DecryptFromStorage(msg.Content), out _)) return null;
        var recipient = msg.SenderId != userId;
        ViewOnceOpenResult Already() => new(msg.Id, msg.ConversationId, msg.SenderId, msg.Type, null, null, true, false);
        if (recipient && await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == msg.Id && r.UserId == userId)) return Already();
        var session = new ViewOnceMediaSession { MessageId = msg.Id, UserId = userId, ExpiresAt = clock.GetUtcNow().UtcDateTime + SessionLifetime };
        db.ViewOnceMediaSessions.Add(session);
        ViewOnceReceipt? receipt = null;
        if (recipient)
        {
            receipt = new ViewOnceReceipt { MessageId = msg.Id, UserId = userId, ViewedAt = clock.GetUtcNow().UtcDateTime };
            db.ViewOnceReceipts.Add(receipt);
        }
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException)
        {
            db.Entry(session).State = EntityState.Detached;
            if (receipt != null) db.Entry(receipt).State = EntityState.Detached;
            // Only the unique-receipt race means "already opened"; don't hide storage/database failures.
            if (recipient && await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == msg.Id && r.UserId == userId)) return Already();
            throw;
        }
        return new(msg.Id, msg.ConversationId, msg.SenderId, msg.Type, $"/api/media/view-once/{session.Id:D}", session.Id, false, recipient);
    }

    public async Task<string?> ResolveAsync(Guid sessionId, Guid userId)
    {
        var now = clock.GetUtcNow().UtcDateTime;
        var session = await db.ViewOnceMediaSessions.AsNoTracking().FirstOrDefaultAsync(s => s.Id == sessionId && s.UserId == userId && s.ClosedAt == null && s.ExpiresAt > now);
        if (session == null) return null;
        var msg = await AccessibleMessage(session.MessageId, userId);
        if (msg == null) return null;
        if (msg.SenderId != userId && !await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == msg.Id && r.UserId == userId)) return null;
        return storage.TryPrivatePath(crypto.DecryptFromStorage(msg.Content), out var path) ? path : null;
    }

    public async Task CloseAsync(Guid sessionId, Guid userId)
    {
        var session = await db.ViewOnceMediaSessions.FirstOrDefaultAsync(s => s.Id == sessionId && s.UserId == userId);
        if (session == null || session.ClosedAt != null) return;
        session.ClosedAt = clock.GetUtcNow().UtcDateTime;
        await db.SaveChangesAsync();
    }
}
