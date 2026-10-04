using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

/// <summary>Shared history projection. Callers must authorize conversation access first.</summary>
public static class ConversationMessageHistory
{
    public static async Task<(List<object> Messages, bool HasMore)> LoadAsync(
        AppDbContext db,
        IConversationMessageCrypto messageCrypto,
        Guid cid,
        Guid userId,
        DateTime? beforeSentAt,
        Guid? beforeId,
        int take)
    {
        var rawDesc = await ConversationMessageQueries.VisiblePage(db, cid, userId, beforeSentAt, beforeId)
            .Take(take + 1)
            .Select(m => new { m.Id, m.ConversationId, m.ClientMessageId, m.SenderId, m.Content, m.Type, m.SentAt, m.DeletedForEveryone, m.IsRead, m.ReplyToMessageId, m.DisappearMode, m.ExpiresAt, m.IsViewOnce })
            .ToListAsync();

        var hasMore = rawDesc.Count > take;
        if (hasMore) rawDesc = rawDesc.Take(take).ToList();
        var messagesRaw = rawDesc;
        messagesRaw.Reverse();

        var messageIds = messagesRaw.Select(m => m.Id).ToList();
        var reactionsByMessage = messageIds.Count > 0
            ? (await db.MessageReactions
                .Where(r => messageIds.Contains(r.MessageId))
                .Select(r => new { r.MessageId, r.UserId, r.Emoji })
                .ToListAsync())
                .GroupBy(r => r.MessageId)
                .ToDictionary(g => g.Key, g => g.Select(r => (r.UserId, r.Emoji)).ToList())
            : new Dictionary<Guid, List<(Guid UserId, string Emoji)>>();

        var viewOnceOpenedIds = messageIds.Count > 0
            ? (await db.ViewOnceReceipts
                .Where(r => r.UserId == userId && messageIds.Contains(r.MessageId))
                .Select(r => r.MessageId)
                .ToListAsync())
                .ToHashSet()
            : new HashSet<Guid>();

        var viewOnceAnyOpenedIds = messageIds.Count > 0
            ? (await db.ViewOnceReceipts
                .Where(r => messageIds.Contains(r.MessageId))
                .Select(r => r.MessageId)
                .Distinct()
                .ToListAsync())
                .ToHashSet()
            : new HashSet<Guid>();

        var replyIds = messagesRaw.Where(m => m.ReplyToMessageId != null).Select(m => m.ReplyToMessageId!.Value).Distinct().ToList();
        Dictionary<Guid, (string Content, string Type, string? SenderName, bool IsViewOnce, DateTime? ExpiresAt)> replyData;
        if (replyIds.Count > 0)
        {
            var replyList = await ConversationMessageQueries.VisiblePage(db, cid, userId)
                .Where(m => replyIds.Contains(m.Id))
                .Select(m => new { m.Id, m.Content, m.Type, SenderName = m.Sender.Name, m.IsViewOnce, m.ExpiresAt })
                .ToListAsync();
            replyData = replyList.ToDictionary(
                m => m.Id,
                m => (messageCrypto.DecryptFromStorage(m.Content ?? ""), m.Type ?? "text", (string?)m.SenderName, m.IsViewOnce, m.ExpiresAt));
        }
        else
        {
            replyData = new();
        }

        Dictionary<Guid, (string Name, string? Avatar)>? senderNames = null;
        var isGroup = await db.Conversations.AsNoTracking().AnyAsync(c => c.Id == cid && c.Type == ConversationType.Group);
        if (isGroup && messagesRaw.Count > 0)
        {
            var senderIds = messagesRaw.Select(m => m.SenderId).Distinct().ToList();
            var senders = await db.Users.Where(u => senderIds.Contains(u.Id)).Select(u => new { u.Id, u.Name, u.Avatar }).ToListAsync();
            senderNames = senders.ToDictionary(u => u.Id, u => (u.Name ?? "—", u.Avatar));
        }

        var messages = messagesRaw.Select(m =>
        {
            var decryptedContent = messageCrypto.DecryptFromStorage(m.Content ?? "");
            // Non-senders never get the URL from history; they must call OpenViewOnce (once).
            if (m.IsViewOnce && m.SenderId != userId)
                decryptedContent = "";
            var viewOnceOpened = m.IsViewOnce && (
                m.SenderId == userId
                    ? viewOnceAnyOpenedIds.Contains(m.Id)
                    : viewOnceOpenedIds.Contains(m.Id));
            string? replyToContent = null;
            string? replyToSenderName = null;
            if (m.ReplyToMessageId != null && replyData.TryGetValue(m.ReplyToMessageId.Value, out var rd))
            {
                replyToContent = rd.IsViewOnce
                    ? ConversationPreviewHelper.BuildViewOncePreview(rd.Type)
                    : GetReplyPreview(rd.Content, rd.Type);
                replyToSenderName = rd.SenderName ?? "—";
            }
            string? senderName = null;
            string? senderAvatar = null;
            if (senderNames != null && senderNames.TryGetValue(m.SenderId, out var sn))
            {
                senderName = sn.Name;
                senderAvatar = sn.Avatar;
            }
            string? myReaction = null;
            var reactions = new List<object>();
            if (reactionsByMessage.TryGetValue(m.Id, out var rlist))
            {
                myReaction = rlist.FirstOrDefault(r => r.UserId == userId).Emoji;
                reactions = rlist
                    .GroupBy(r => r.Emoji)
                    .Select(gg => new { emoji = gg.Key, count = gg.Count(), userIds = gg.Select(x => x.UserId).ToList() })
                    .Cast<object>()
                    .ToList();
            }
            return (object)new
            {
                m.Id,
                m.ConversationId,
                m.ClientMessageId,
                m.SenderId,
                Content = decryptedContent,
                m.Type,
                m.SentAt,
                m.DeletedForEveryone,
                m.IsRead,
                m.ReplyToMessageId,
                ReplyToContent = replyToContent,
                ReplyToSenderName = replyToSenderName,
                ReplyToUnavailable = m.ReplyToMessageId.HasValue && !replyData.ContainsKey(m.ReplyToMessageId.Value),
                ReplyToExpiresAt = m.ReplyToMessageId.HasValue && replyData.TryGetValue(m.ReplyToMessageId.Value, out var quote) ? quote.ExpiresAt : null,
                SenderName = senderName,
                SenderAvatar = senderAvatar,
                Reactions = reactions,
                MyReaction = myReaction,
                m.DisappearMode,
                m.ExpiresAt,
                IsViewOnce = m.IsViewOnce,
                ViewOnceOpened = viewOnceOpened
            };
        }).ToList();

        return (messages, hasMore);
    }

    public static string GetReplyPreview(string? content, string type)
    {
        if (type == "audio") return "رسالة صوتية";
        if (type == "image") return "صورة";
        if (type == "video") return "فيديو";
        if (type == "album") return ConversationPreviewHelper.BuildAlbumPreview(content ?? "");
        if (type == "short_film") return "فيلم قصير";
        if (type == "story_share") return ConversationPreviewHelper.BuildStorySharePreview(content ?? "");
        if (type == "story_reply") return ConversationPreviewHelper.BuildStoryReplyPreview(content ?? "");
        if (type == "call") return ConversationPreviewHelper.BuildCallPreview(content ?? "");
        if (type == "location") return ConversationPreviewHelper.BuildLocationPreview(content ?? "");
        if (type == "file") return ConversationPreviewHelper.BuildFilePreview(content ?? "");
        if (string.IsNullOrEmpty(content)) return "";
        return content.Length > 80 ? content[..80] + "…" : content;
    }

}
