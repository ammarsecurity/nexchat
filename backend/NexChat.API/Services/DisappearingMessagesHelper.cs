using Microsoft.EntityFrameworkCore;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>Shared disappearing-message expiry helpers (hub + HTTP).</summary>
public static class DisappearingMessagesHelper
{
    /// <summary>
    /// Stamp ExpiresAt on AfterRead messages from others that are now read.
    /// Private chats only — group shared IsRead would wipe messages for unread members.
    /// </summary>
    public static async Task<(List<Guid> Ids, DateTime? ExpiresAt)> ApplyAfterReadExpiryAsync(
        AppDbContext db,
        Guid conversationId,
        Guid readerId,
        int conversationType)
    {
        if (conversationType == ConversationType.Group)
            return ([], null);

        var now = DateTime.UtcNow;
        var ids = await db.ConversationMessages
            .Where(m => m.ConversationId == conversationId
                        && m.SenderId != readerId
                        && m.DisappearMode == DisappearMode.AfterRead
                        && m.ExpiresAt == null
                        && m.IsRead
                        && !m.DeletedForEveryone)
            .Select(m => m.Id)
            .ToListAsync();
        if (ids.Count == 0)
            return ([], null);

        var expires = DisappearMode.ExpiresAtOnRead(now);
        await db.ConversationMessages
            .Where(m => ids.Contains(m.Id))
            .ExecuteUpdateAsync(s => s.SetProperty(m => m.ExpiresAt, expires));
        return (ids, expires);
    }

    /// <summary>AfterRead is private-only; timer modes work everywhere.</summary>
    public static int EffectiveSendMode(int conversationMode, int conversationType)
    {
        if (conversationType == ConversationType.Group && conversationMode == DisappearMode.AfterRead)
            return DisappearMode.Off;
        return conversationMode;
    }
}
