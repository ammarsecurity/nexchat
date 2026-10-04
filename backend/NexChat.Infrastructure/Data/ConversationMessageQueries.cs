using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;

namespace NexChat.Infrastructure.Data;

public static class ConversationMessageQueries
{
    /// <summary>Cursor and sort use the same database GUID/string ordering, including timestamp ties.</summary>
    public static IOrderedQueryable<ConversationMessage> VisiblePage(
        AppDbContext db, Guid conversationId, Guid viewerId, DateTime? beforeSentAt = null, Guid? beforeId = null)
    {
        IQueryable<ConversationMessage> source = db.ConversationMessages;
        if (beforeSentAt.HasValue && beforeId.HasValue)
        {
            var at = beforeSentAt.Value;
            var bid = beforeId.Value;
            source = db.ConversationMessages.FromSqlInterpolated($"SELECT * FROM `ConversationMessages` WHERE `SentAt` < {at} OR (`SentAt` = {at} AND `Id` < {bid})");
        }
        return source.AsNoTracking()
            .Where(m => m.ConversationId == conversationId && !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == viewerId && d.MessageId == m.Id) &&
                (m.ExpiresAt == null || m.ExpiresAt > DateTime.UtcNow))
            .OrderByDescending(m => m.SentAt).ThenByDescending(m => m.Id);
    }
}
