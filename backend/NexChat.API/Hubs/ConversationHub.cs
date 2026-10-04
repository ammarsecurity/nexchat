using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using NexChat.API.Services;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class ConversationHub(
    AppDbContext db,
    NotificationOutboxService notificationOutbox,
    UserPresenceService presence,
    ILogger<ConversationHub> logger,
    IWebHostEnvironment env,
    IConversationMessageCrypto messageCrypto,
    IProfanityMasker profanity,
    OfficialAnnouncementConversationService officialAnnouncements,
    SupportConversationService supportConversations,
    MediaStorageService mediaStorage,
    ViewOnceMediaService viewOnceMedia) : Hub
{
    private static readonly HashSet<string> AllowedReactionEmojis = ["❤️", "👍", "😂", "😮", "😢", "🙏"];
    private const int MessagePageSize = 60;

    // Call busy/pending shared with ChatHub via CallPresenceStore (in-proc; Redis needed for multi-instance).

    /// <summary>تشخيص: التأكد أن استدعاءات الـ Hub تصل للـ backend.</summary>
    public Task<string> Ping() => Task.FromResult($"pong-{DateTime.UtcNow:HHmmss}");

    private bool TryGetUserId(out Guid userId)
    {
        var id = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out userId);
    }

    public async Task JoinConversation(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
        {
            await Clients.Caller.SendAsync("Error", "Invalid request");
            return;
        }

        var conv = await db.Conversations
            .Include(c => c.User1)
            .Include(c => c.User2)
            .FirstOrDefaultAsync(c => c.Id == cid &&
                (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId)
                 || c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == cid && m.UserId == userId)));

        if (conv == null)
        {
            await Clients.Caller.SendAsync("Error", "Conversation not found");
            return;
        }

        var deleted = await db.UserConversationDeletions
            .AnyAsync(d => d.UserId == userId && d.ConversationId == cid);
        if (deleted)
        {
            // Support chat is permanent — restore instead of blocking join.
            var isSupport = conv.Type == ConversationType.Private &&
                ((conv.User1 != null && conv.User1.UniqueCode == SupportConversationService.SupportUniqueCode) ||
                 (conv.User2 != null && conv.User2.UniqueCode == SupportConversationService.SupportUniqueCode));
            if (!isSupport)
            {
                await Clients.Caller.SendAsync("Error", "Conversation not found");
                return;
            }
            var del = await db.UserConversationDeletions
                .FirstOrDefaultAsync(d => d.UserId == userId && d.ConversationId == cid);
            if (del != null)
            {
                db.UserConversationDeletions.Remove(del);
                await db.SaveChangesAsync();
            }
        }

        var groupName = cid.ToString();
        await Groups.AddToGroupAsync(Context.ConnectionId, groupName);
        ConversationDelivery.Joined(cid, userId, Context.ConnectionId);
        if (!await IsParticipant(cid, userId))
        {
            await ConversationDelivery.EjectAsync(Groups, Clients, cid, userId);
            throw new HubException("Conversation membership removed");
        }

        var partner = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2 : conv.User1) : null;
        var partnerId = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2Id : conv.User1Id) : null;

        var page = await ConversationMessageHistory.LoadAsync(db, messageCrypto, cid, userId, beforeSentAt: null, beforeId: null, take: MessagePageSize);
        var messages = page.Messages;

        await Clients.Caller.SendAsync("ConversationJoined", new
        {
            Id = conv.Id,
            ConversationId = conv.Id,
            Type = conv.Type,
            Partner = partner != null ? new { partner.Id, partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar, IsOnline = UserOnlineVisibility.VisibleToOthers(partner) } : null,
            GroupName = conv.Type == ConversationType.Group ? conv.Name : null,
            GroupImageUrl = conv.Type == ConversationType.Group ? conv.ImageUrl : null,
            DisappearMode = conv.DisappearMode,
            Messages = messages,
            HasMore = page.HasMore
        });

        var state = await ConversationDelivery.MarkReadAsync(db, cid, userId);

        var messageIdsToMark = conv.Type == ConversationType.Group
            ? await db.ConversationMessages.Where(m => m.ConversationId == cid && m.SenderId != userId && m.SentAt <= state.LastReadAt && !m.IsRead).Select(m => m.Id).ToListAsync()
            : null;

        if (conv.Type == ConversationType.Group)
        {
            if (messageIdsToMark is { Count: > 0 })
            {
                await db.ConversationMessages
                    .Where(m => messageIdsToMark.Contains(m.Id))
                    .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
            }
        }
        else if (partnerId.HasValue)
        {
            await db.ConversationMessages
                .Where(m => m.ConversationId == cid && m.SenderId == partnerId.Value && m.SentAt <= state.LastReadAt && !m.IsRead)
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        var (expiringOnJoin, joinExpiresAt) = await DisappearingMessagesHelper.ApplyAfterReadExpiryAsync(db, cid, userId, conv.Type);
        await db.SaveChangesAsync();

        await Clients.User(userId.ToString()).SendAsync("ConversationRead", new { ConversationId = cid, LastReadAt = state.LastReadAt, UnreadCount = await ConversationDelivery.UnreadCountAsync(db, cid, userId) });
        if (expiringOnJoin.Count > 0 && joinExpiresAt.HasValue)
            await ConversationDelivery.SendAsync(db, Clients, cid, "MessagesExpiring", new { ConversationId = cid, messageIds = expiringOnJoin, expiresAt = joinExpiresAt });

        await ConversationDelivery.SendAsync(db, Clients, cid, "PartnerReadUpTo", new { ConversationId = cid, LastReadAt = state.LastReadAt, ReaderId = userId });
        if (conv.Type == ConversationType.Group && messageIdsToMark is { Count: > 0 })
            await ConversationDelivery.SendAsync(db, Clients, cid, "MessagesRead", new { ConversationId = cid, ReaderId = userId, messageIds = messageIdsToMark });
    }

    /// <summary>تحميل رسائل أقدم من رسالة معيّنة (ترقيم صفحات للشات الطويل).</summary>
    public async Task GetOlderMessages(string conversationId, string beforeMessageId, int take = MessagePageSize)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(beforeMessageId, out var beforeId))
            return;
        if (!await IsParticipant(cid, userId)) return;
        if (await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == cid))
            return;

        var before = await db.ConversationMessages.AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == beforeId && m.ConversationId == cid);
        if (before == null) return;

        var pageSize = Math.Clamp(take <= 0 ? MessagePageSize : take, 10, 100);
        var page = await ConversationMessageHistory.LoadAsync(db, messageCrypto, cid, userId, before.SentAt, before.Id, pageSize);
        await Clients.Caller.SendAsync("OlderMessages", new
        {
            ConversationId = cid,
            Messages = page.Messages,
            HasMore = page.HasMore,
            BeforeMessageId = beforeId
        });
    }

    public async Task MarkAsRead(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == cid);
        if (conv == null) return;
        var partnerId = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2Id : conv.User1Id) : (Guid?)null;

        var state = await ConversationDelivery.MarkReadAsync(db, cid, userId);

        var messageIdsToMark = conv.Type == ConversationType.Group
            ? await db.ConversationMessages.Where(m => m.ConversationId == cid && m.SenderId != userId && m.SentAt <= state.LastReadAt && !m.IsRead).Select(m => m.Id).ToListAsync()
            : null;

        if (conv.Type == ConversationType.Group)
        {
            if (messageIdsToMark is { Count: > 0 })
            {
                await db.ConversationMessages
                    .Where(m => messageIdsToMark.Contains(m.Id))
                    .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
            }
        }
        else if (partnerId.HasValue)
        {
            // Private: mark unread without collecting IDs; clients use PartnerReadUpTo / LastReadAt.
            await db.ConversationMessages
                .Where(m => m.ConversationId == cid && m.SenderId == partnerId.Value && m.SentAt <= state.LastReadAt && !m.IsRead)
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        var (expiringOnRead, readExpiresAt) = await DisappearingMessagesHelper.ApplyAfterReadExpiryAsync(db, cid, userId, conv.Type);
        await db.SaveChangesAsync();

        await Clients.User(userId.ToString()).SendAsync("ConversationRead", new { ConversationId = cid, LastReadAt = state.LastReadAt, UnreadCount = await ConversationDelivery.UnreadCountAsync(db, cid, userId) });
        if (expiringOnRead.Count > 0 && readExpiresAt.HasValue)
            await ConversationDelivery.SendAsync(db, Clients, cid, "MessagesExpiring", new { ConversationId = cid, messageIds = expiringOnRead, expiresAt = readExpiresAt });

        var payload = new { ConversationId = cid, LastReadAt = state.LastReadAt, ReaderId = userId };
        await ConversationDelivery.SendAsync(db, Clients, cid, "PartnerReadUpTo", payload);
        if (conv.Type == ConversationType.Group && messageIdsToMark is { Count: > 0 })
            await ConversationDelivery.SendAsync(db, Clients, cid, "MessagesRead", new { ConversationId = cid, ReaderId = userId, messageIds = messageIdsToMark });
    }

    // Keep the legacy SignalR binder arity; new clients opt into a durable retry key.
    public Task<object> SendMessage(string conversationId, string content, string type = "text", string? replyToMessageId = null, bool viewOnce = false) =>
        SendMessageCore(conversationId, content, type, replyToMessageId, viewOnce, null);

    public Task<object> SendMessageWithClientId(string conversationId, string content, string type, string? replyToMessageId, bool viewOnce, string clientMessageId)
    {
        if (string.IsNullOrWhiteSpace(clientMessageId) || clientMessageId.Length > 80 || clientMessageId.Any(char.IsWhiteSpace))
            throw new HubException("Invalid client message ID");
        return SendMessageCore(conversationId, content, type, replyToMessageId, viewOnce, clientMessageId);
    }

    private async Task<object> SendMessageCore(string conversationId, string content, string type, string? replyToMessageId, bool viewOnce, string? clientMessageId)
    {
        if (string.IsNullOrWhiteSpace(content) || content.Length > 5000)
            throw new HubException("Message must contain between 1 and 5000 characters");
        if (type is not ("text" or "image" or "audio" or "short_film" or "video" or "album" or "story_share"))
            throw new HubException("Unsupported message type");
        if (viewOnce && type is not ("image" or "video"))
            throw new HubException("View-once requires an image or video");
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            throw new HubException("Invalid request");

        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == cid &&
            (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId)
             || c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == cid && m.UserId == userId)));
        if (conv == null) throw new HubException("Conversation not found or membership removed");
        if (await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == cid))
            throw new HubException("Conversation deleted");
        var recipientId = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2Id : conv.User1Id) : null;
        if (recipientId.HasValue && await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == userId && b.BlockedUserId == recipientId.Value) ||
            (b.BlockerId == recipientId.Value && b.BlockedUserId == userId)))
            throw new HubException("Messaging is unavailable for this conversation");
        if (await officialAnnouncements.IsOfficialConversationAsync(cid))
        {
            var official = await officialAnnouncements.GetOfficialUserAsync();
            if (official == null || userId != official.Id)
                throw new HubException("محادثة NexChat الرسمية للقراءة فقط — لا يمكن الرد");
        }

        if (clientMessageId != null)
        {
            var accepted = await db.ConversationMessages.AsNoTracking().FirstOrDefaultAsync(m =>
                m.ConversationId == cid && m.SenderId == userId && m.ClientMessageId == clientMessageId);
            if (accepted != null) return await BuildAcceptedMessageAsync(accepted, userId, conv.Type);
        }

        Guid? replyToId = null;
        if (!string.IsNullOrEmpty(replyToMessageId))
        {
            if (!Guid.TryParse(replyToMessageId, out var rid) ||
                !await VisibleMessages(cid, userId).AnyAsync(m => m.Id == rid))
                throw new HubException("Reply target is no longer available");
            replyToId = rid;
        }
        var plainBody = type == "text" ? profanity.Mask(content.Trim()) : content;
        if (type == "album" && !IsValidAlbumPayload(plainBody))
            throw new HubException("Invalid album");
        if (!mediaStorage.ValidateMessageMedia(plainBody, type, viewOnce, userId, Context.GetHttpContext()?.Request))
            throw new HubException("Invalid media attachment");
        var sentAt = DateTime.UtcNow;
        var disappearMode = DisappearingMessagesHelper.EffectiveSendMode(conv.DisappearMode, conv.Type);
        var msg = new ConversationMessage
        {
            ConversationId = cid,
            SenderId = userId,
            ClientMessageId = clientMessageId,
            Content = messageCrypto.EncryptForStorage(plainBody),
            Type = type,
            ReplyToMessageId = replyToId,
            SentAt = sentAt,
            DisappearMode = disappearMode,
            ExpiresAt = DisappearMode.ExpiresAtOnSend(disappearMode, sentAt),
            IsViewOnce = viewOnce
        };
        db.ConversationMessages.Add(msg);
        var participantIds = await ConversationDelivery.ParticipantsAsync(db, cid);
        var recipientDeletions = await db.UserConversationDeletions
            .Where(d => d.ConversationId == cid && d.UserId != userId && participantIds.Contains(d.UserId)).ToListAsync();
        db.UserConversationDeletions.RemoveRange(recipientDeletions);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) when (clientMessageId != null)
        {
            // The database unique index resolves races across connections/processes, not an in-memory lock.
            db.ChangeTracker.Clear();
            var accepted = await db.ConversationMessages.AsNoTracking().FirstOrDefaultAsync(m =>
                m.ConversationId == cid && m.SenderId == userId && m.ClientMessageId == clientMessageId);
            if (accepted != null) return await BuildAcceptedMessageAsync(accepted, userId, conv.Type);
            throw new HubException("Message could not be saved");
        }

        var senderPayload = await BuildAcceptedMessageAsync(msg, userId, conv.Type);
        // Once committed, delivery/notification failures cannot turn an accepted send into a rejection.
        try
        {
            var participants = await ConversationDelivery.ParticipantsAsync(db, cid);
            var sender = await db.Users.FindAsync(userId);
            var preview = ConversationPreviewHelper.BuildListPreview(msg, messageCrypto.DecryptFromStorage);
            foreach (var participant in participants)
            {
                try
                {
                    var payload = participant == userId ? senderPayload : await BuildAcceptedMessageAsync(msg, participant, conv.Type);
                    await Clients.User(participant.ToString()).SendAsync("ReceiveMessage", payload);
                    await Clients.User(participant.ToString()).SendAsync("ConversationListUpdated", new
                    {
                        ConversationId = cid,
                        LastMessagePreview = preview,
                        LastMessageType = type,
                        LastMessageAt = msg.SentAt,
                        SenderId = userId,
                        UnreadCount = await ConversationDelivery.UnreadCountAsync(db, cid, participant)
                    });
                }
                catch (Exception ex) { logger.LogWarning(ex, "Live delivery failed for {MessageId} to {UserId}", msg.Id, participant); }
                if (participant != userId && !await IsHiddenForUserAsync(cid, participant))
                    await notificationOutbox.EnqueueAsync(participant, "conversation_message", sender?.Name ?? "شخص", preview,
                        new Dictionary<string, string>
                        {
                            ["conversationId"] = cid.ToString(), ["userId"] = userId.ToString(),
                            ["senderName"] = sender?.Name ?? "", ["senderAvatar"] = sender?.Avatar ?? ""
                        });
            }
        }
        catch (Exception ex) { logger.LogWarning(ex, "Post-save message delivery failed for {MessageId}", msg.Id); }
        return senderPayload;
    }

    private IQueryable<ConversationMessage> VisibleMessages(Guid cid, Guid userId) =>
        db.ConversationMessages.AsNoTracking().Where(m => m.ConversationId == cid && !m.DeletedForEveryone &&
            (m.ExpiresAt == null || m.ExpiresAt > DateTime.UtcNow) &&
            !db.UserMessageDeletions.Any(d => d.UserId == userId && d.MessageId == m.Id));

    private async Task<object> BuildAcceptedMessageAsync(ConversationMessage msg, Guid viewerId, int conversationType)
    {
        var visible = !msg.DeletedForEveryone && (msg.ExpiresAt == null || msg.ExpiresAt > DateTime.UtcNow) &&
            !await db.UserMessageDeletions.AnyAsync(d => d.UserId == viewerId && d.MessageId == msg.Id);
        var reply = msg.ReplyToMessageId.HasValue
            ? await VisibleMessages(msg.ConversationId, viewerId).Include(m => m.Sender).FirstOrDefaultAsync(m => m.Id == msg.ReplyToMessageId.Value)
            : null;
        var sender = conversationType == ConversationType.Group ? await db.Users.FindAsync(msg.SenderId) : null;
        var opened = msg.IsViewOnce && await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == msg.Id && (msg.SenderId == viewerId || r.UserId == viewerId));
        var reactions = await db.MessageReactions.AsNoTracking().Where(r => r.MessageId == msg.Id).Select(r => new { r.UserId, r.Emoji }).ToListAsync();
        return new
        {
            msg.Id, msg.ConversationId, msg.ClientMessageId, msg.SenderId,
            Content = visible && (!msg.IsViewOnce || msg.SenderId == viewerId) ? messageCrypto.DecryptFromStorage(msg.Content) : "",
            msg.Type, msg.SentAt, DeletedForEveryone = !visible, msg.IsRead, msg.ReplyToMessageId,
            ReplyToContent = reply == null ? null : reply.IsViewOnce ? ConversationPreviewHelper.BuildViewOncePreview(reply.Type) : ConversationMessageHistory.GetReplyPreview(messageCrypto.DecryptFromStorage(reply.Content), reply.Type),
            ReplyToSenderName = reply?.Sender.Name,
            ReplyToUnavailable = msg.ReplyToMessageId.HasValue && reply == null,
            ReplyToExpiresAt = reply?.ExpiresAt,
            SenderName = sender?.Name, SenderAvatar = sender?.Avatar,
            Reactions = reactions.GroupBy(r => r.Emoji).Select(g => new { emoji = g.Key, count = g.Count(), userIds = g.Select(r => r.UserId).ToList() }).ToList(),
            MyReaction = reactions.FirstOrDefault(r => r.UserId == viewerId)?.Emoji,
            msg.DisappearMode, msg.ExpiresAt, msg.IsViewOnce, ViewOnceOpened = opened
        };
    }

    /// <summary>
    /// Returns view-once media URL for the caller. For recipients, the one view is burned
    /// on the first successful open (receipt + ViewOnceOpened). Sender may reopen freely.
    /// </summary>
    public async Task<object?> OpenViewOnce(string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(messageId, out var mid)) return null;
        var result = await viewOnceMedia.OpenAsync(mid, userId);
        if (result == null) return null;
        if (result.ReceiptCreated)
        {
            var payload = new { messageId = result.MessageId, conversationId = result.ConversationId, userId };
            await ConversationDelivery.SendAsync(db, Clients, result.ConversationId, "ViewOnceOpened", payload);
        }
        return new { messageId = result.MessageId, content = result.Content, type = result.Type, sessionId = result.SessionId, opened = result.Opened };
    }

    public async Task CloseViewOnce(string sessionId)
    {
        if (TryGetUserId(out var userId) && Guid.TryParse(sessionId, out var sid))
            await viewOnceMedia.CloseAsync(sid, userId);
    }

    /// <summary>
    /// Legacy client ack. Receipt is created in <see cref="OpenViewOnce"/>; this only
    /// fills a missing receipt without re-broadcasting if already opened.
    /// </summary>
    public async Task ConfirmViewOnceOpened(string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(messageId, out var mid))
            return;

        var msg = await db.ConversationMessages.AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == mid && m.IsViewOnce && !m.DeletedForEveryone);
        if (msg == null) return;
        if (msg.SenderId == userId) return;
        if (msg.Type != "image" && msg.Type != "video") return;
        if (msg.ExpiresAt != null && msg.ExpiresAt <= DateTime.UtcNow) return;
        if (!await IsParticipant(msg.ConversationId, userId)) return;
        if (await db.UserMessageDeletions.AnyAsync(d => d.UserId == userId && d.MessageId == mid))
            return;

        var already = await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == mid && r.UserId == userId);
        if (already) return;

        db.ViewOnceReceipts.Add(new ViewOnceReceipt
        {
            MessageId = mid,
            UserId = userId,
            ViewedAt = DateTime.UtcNow
        });
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            foreach (var entry in db.ChangeTracker.Entries<ViewOnceReceipt>().ToList())
                entry.State = EntityState.Detached;
            return;
        }

        if (!await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == mid && r.UserId == userId))
            return;

        var payload = new
        {
            messageId = msg.Id,
            conversationId = msg.ConversationId,
            userId
        };
        await ConversationDelivery.SendAsync(db, Clients, msg.ConversationId, "ViewOnceOpened", payload);
    }

    /// <summary>Recipient reports a screenshot while viewing view-once media (iOS). Notifies the sender.</summary>
    public async Task ReportViewOnceScreenshot(string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(messageId, out var mid))
            return;

        var msg = await db.ConversationMessages.AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == mid && m.IsViewOnce && !m.DeletedForEveryone);
        if (msg == null) return;
        if (msg.SenderId == userId) return;
        if (!await IsParticipant(msg.ConversationId, userId)) return;
        // Only after the recipient has actually opened (confirmed) the media.
        if (!await db.ViewOnceReceipts.AnyAsync(r => r.MessageId == mid && r.UserId == userId))
            return;

        await Clients.User(msg.SenderId.ToString()).SendAsync("ViewOnceScreenshot", new
        {
            messageId = msg.Id,
            conversationId = msg.ConversationId,
            userId
        });
    }

    public async Task DeleteMessageForMe(string conversationId, string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(messageId, out var mid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        if (await officialAnnouncements.IsOfficialConversationAsync(cid))
        {
            await Clients.Caller.SendAsync("Error", "لا يمكن حذف رسائل محادثة NexChat الرسمية");
            return;
        }

        if (!await db.ConversationMessages.AnyAsync(m => m.Id == mid && m.ConversationId == cid))
            throw new HubException("Message not found");
        var exists = await db.UserMessageDeletions.AnyAsync(d => d.UserId == userId && d.MessageId == mid);
        if (exists) return;

        db.UserMessageDeletions.Add(new UserMessageDeletion { UserId = userId, MessageId = mid });
        await db.SaveChangesAsync();
        await Clients.Caller.SendAsync("MessageDeletedForMe", mid);
        await Clients.User(userId.ToString()).SendAsync("MessageDeletedForMeV2", new { ConversationId = cid, MessageId = mid, ReplyToMessageId = mid });
        await Clients.User(userId.ToString()).SendAsync("ReplyPreviewsRedacted", new { ConversationId = cid, MessageIds = new[] { mid } });
        var (p, at, sid, lt) = await GetLastListPreviewForUserAsync(cid, userId);
        await Clients.User(userId.ToString()).SendAsync("ConversationListUpdated", new
        {
            ConversationId = cid,
            LastMessagePreview = p ?? "",
            LastMessageType = lt,
            LastMessageAt = at,
            SenderId = sid,
            UnreadCount = await ConversationDelivery.UnreadCountAsync(db, cid, userId)
        });
    }

    public async Task DeleteMessageForEveryone(string conversationId, string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(messageId, out var mid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        if (await officialAnnouncements.IsOfficialConversationAsync(cid))
        {
            var official = await officialAnnouncements.GetOfficialUserAsync();
            if (official == null || userId != official.Id)
            {
                await Clients.Caller.SendAsync("Error", "لا يمكن حذف رسائل محادثة NexChat الرسمية");
                return;
            }
        }

        var msg = await db.ConversationMessages
            .FirstOrDefaultAsync(m => m.Id == mid && m.ConversationId == cid && m.SenderId == userId);
        if (msg == null) return;

        msg.DeletedForEveryone = true;
        await db.SaveChangesAsync();
        await ConversationDelivery.DeletedAsync(db, Clients, cid, mid);
        await NotifyConversationListPreviewToParticipantsAsync(cid);
    }

    public async Task DeleteConversationForMe(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        var supportId = await db.Users.AsNoTracking()
            .Where(u => u.UniqueCode == SupportConversationService.SupportUniqueCode)
            .Select(u => (Guid?)u.Id)
            .FirstOrDefaultAsync();
        if (supportId is Guid sid &&
            await db.Conversations.AnyAsync(c =>
                c.Id == cid &&
                c.Type == ConversationType.Private &&
                (c.User1Id == sid || c.User2Id == sid)))
        {
            await Clients.Caller.SendAsync("Error", "لا يمكن حذف محادثة الدعم");
            return;
        }

        if (await officialAnnouncements.IsOfficialConversationAsync(cid))
        {
            await Clients.Caller.SendAsync("Error", "لا يمكن حذف محادثة NexChat الرسمية");
            return;
        }

        var exists = await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == cid);
        if (!exists)
        {
            db.UserConversationDeletions.Add(new UserConversationDeletion
            {
                UserId = userId,
                ConversationId = cid
            });
            var messageIds = await db.ConversationMessages
                .Where(m => m.ConversationId == cid)
                .Select(m => m.Id)
                .ToListAsync();
            var existingDeletions = await db.UserMessageDeletions
                .Where(d => d.UserId == userId && messageIds.Contains(d.MessageId))
                .Select(d => d.MessageId)
                .ToListAsync();
            foreach (var mid in messageIds.Where(id => !existingDeletions.Contains(id)))
            {
                db.UserMessageDeletions.Add(new UserMessageDeletion { UserId = userId, MessageId = mid });
            }
            await db.SaveChangesAsync();
        }
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, conversationId);
        ConversationDelivery.Left(cid, userId, Context.ConnectionId);
        await Clients.Caller.SendAsync("ConversationDeletedForMe", cid);
        await Clients.User(userId.ToString()).SendAsync("ConversationDeletedForMeV2", new { ConversationId = cid });
    }

    public async Task StartTyping(string conversationId)
    {
        if (TryGetUserId(out var userId) && Guid.TryParse(conversationId, out var cid) && await IsParticipant(cid, userId))
        {
            await Clients.OthersInGroup(cid.ToString()).SendAsync("UserTyping", userId);
            foreach (var participant in (await ConversationDelivery.ParticipantsAsync(db, cid)).Where(id => id != userId))
                await Clients.User(participant.ToString()).SendAsync("UserTypingV2", new { ConversationId = cid, UserId = userId });
        }
    }

    public async Task StopTyping(string conversationId)
    {
        if (TryGetUserId(out var userId) && Guid.TryParse(conversationId, out var cid) && await IsParticipant(cid, userId))
        {
            await Clients.OthersInGroup(cid.ToString()).SendAsync("UserStoppedTyping", userId);
            foreach (var participant in (await ConversationDelivery.ParticipantsAsync(db, cid)).Where(id => id != userId))
                await Clients.User(participant.ToString()).SendAsync("UserStoppedTypingV2", new { ConversationId = cid, UserId = userId });
        }
    }

    public async Task LeaveConversation(string conversationId)
    {
        if (!Guid.TryParse(conversationId, out var cid)) return;
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, cid.ToString());
        if (TryGetUserId(out var userId)) ConversationDelivery.Left(cid, userId, Context.ConnectionId);
    }

    // Keep old signatures for deployed clients. Flutter uses the correlated V2 methods.
    private string CurrentCallId(string roomId) => Guid.TryParse(roomId, out var id) &&
        CallPresenceStore.TryGetPending(id, out var p) ? p!.CallId.ToString() : Guid.Empty.ToString();
    public Task RequestVideoCall(string conversationId, bool voiceOnly = false) =>
        RequestVideoCallV2(conversationId, voiceOnly, Guid.NewGuid().ToString());
    public Task AcceptVideoCall(string conversationId) => AcceptVideoCallV2(conversationId, CurrentCallId(conversationId));
    public Task DeclineVideoCall(string conversationId, bool busy = false, string? outcome = null) =>
        DeclineVideoCallV2(conversationId, busy, outcome, CurrentCallId(conversationId));
    public Task EndVideoCall(string conversationId, int durationSec = 0) => EndVideoCallV2(conversationId, durationSec, CurrentCallId(conversationId));
    public Task NotifyVideoCallRinging(string conversationId) => NotifyVideoCallRingingV2(conversationId, CurrentCallId(conversationId));
    public Task ReleaseVideoCallBusy(string conversationId) => ReleaseVideoCallBusyV2(conversationId, CurrentCallId(conversationId));

    public async Task RequestVideoCallV2(string conversationId, bool voiceOnly, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) ||
            !Guid.TryParse(callId, out var attempt) || attempt == Guid.Empty) return;
        if (!await CanPrivateConversationVideoCall(cid, userId) || await db.ConversationMessages.AnyAsync(m => m.Id == attempt))
        {
            await Clients.Caller.SendAsync("VideoCallEnded", conversationId, 0, callId);
            return;
        }
        var conv = await db.Conversations.Include(c => c.User1).Include(c => c.User2)
            .FirstOrDefaultAsync(c => c.Id == cid);
        if (conv == null) return;
        var recipientId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        await PurgeStaleCallStateAsync();
        if (CallPresenceStore.TryGetPending(cid, out var existing) && existing!.CallId == attempt && existing.CallerId == userId) return;
        if (await IsHiddenForUserAsync(cid, recipientId) ||
            !CallPresenceStore.TryStart(cid, userId, recipientId, voiceOnly, attempt, out _))
        {
            if (CallPresenceStore.TryGetPending(cid, out var same) && same!.CallId == attempt && same.CallerId == userId) return;
            await PersistCallSystemMessageAsync(cid, userId, recipientId, voiceOnly, "busy", 0, attempt);
            await Clients.Caller.SendAsync("VideoCallBusy", conversationId, callId);
            return;
        }
        var caller = conv.User1Id == userId ? conv.User1 : conv.User2;
        await Clients.User(recipientId.ToString()).SendAsync("IncomingVideoCall", conversationId, voiceOnly,
            caller?.Name ?? "", caller?.Avatar ?? "", callId);
        await notificationOutbox.EnqueueAsync(recipientId, "video_call",
            voiceOnly ? "مكالمة صوتية" : "مكالمة فيديو",
            voiceOnly ? $"{caller?.Name ?? "شخص"} يطلب مكالمة صوتية" : $"{caller?.Name ?? "شخص"} يطلب مكالمة فيديو",
            new Dictionary<string, string> { ["conversationId"] = conversationId, ["callId"] = callId,
                ["voiceOnly"] = voiceOnly ? "true" : "false", ["callerName"] = caller?.Name ?? "", ["callerAvatar"] = caller?.Avatar ?? "" });
    }

    public async Task NotifyVideoCallRingingV2(string conversationId, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(callId, out var attempt)) return;
        if (!CallPresenceStore.TryGetPending(cid, out var p) || p!.CallId != attempt || p.RecipientId != userId || p.Accepted) return;
        await Clients.User(p.CallerId.ToString()).SendAsync("VideoCallRinging", conversationId, callId);
    }

    public async Task<bool> AcceptVideoCallV2(string conversationId, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(callId, out var attempt)) return false;
        if (!await CanPrivateConversationVideoCall(cid, userId) || !CallPresenceStore.TryAccept(cid, attempt, userId, out var p))
        {
            await Clients.Caller.SendAsync("VideoCallEnded", conversationId, 0, callId);
            return false;
        }
        await notificationOutbox.CancelCallPushAsync(userId, cid, p!.CallId, "answered");
        await Clients.User(p.CallerId.ToString()).SendAsync("VideoCallAccepted", conversationId, p.VoiceOnly, callId);
        return true;
    }

    public Task<bool> HeartbeatVideoCall(string conversationId, string callId) => Task.FromResult(
        TryGetUserId(out var userId) && Guid.TryParse(conversationId, out var cid) && Guid.TryParse(callId, out var attempt) &&
        CallPresenceStore.Heartbeat(cid, attempt, userId));

    public async Task DeclineVideoCallV2(string conversationId, bool busy, string? outcome, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(callId, out var attempt)) return;
        // The attempt stores both authorized participants. A later block/hide must not prevent cleanup.
        if (!await db.Conversations.AnyAsync(c => c.Id == cid && c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId))) return;
        if (!CallPresenceStore.TryEnd(cid, attempt, userId, out var p)) return;
        await CompleteCallAsync(cid, p!, CallOutcome(p!, userId, busy, outcome));
    }

    public async Task EndVideoCallV2(string conversationId, int durationSec, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(callId, out var attempt)) return;
        if (!await db.Conversations.AnyAsync(c => c.Id == cid && c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId))) return;
        if (!CallPresenceStore.TryEnd(cid, attempt, userId, out var p)) return;
        await CompleteCallAsync(cid, p!, p!.Accepted ? "ended" : "cancelled");
    }

    public Task ReleaseVideoCallBusyV2(string conversationId, string callId) =>
        DeclineVideoCallV2(conversationId, false, "cancelled", callId);

    private static string CallOutcome(CallPresenceStore.PendingCall p, Guid actor, bool busy, string? outcome)
    {
        if (p.Accepted) return "ended";
        if (busy) return "busy";
        var value = (outcome ?? "").Trim().ToLowerInvariant();
        return value switch { "missed" or "no_answer" or "noanswer" => "missed",
            "cancelled" or "declined" or "ended" => value, _ => actor == p.CallerId ? "cancelled" : "declined" };
    }

    private async Task CompleteCallAsync(Guid cid, CallPresenceStore.PendingCall p, string status)
    {
        var secs = CallPresenceStore.Duration(p);
        await PersistCallSystemMessageAsync(cid, p.CallerId, p.RecipientId, p.VoiceOnly, status, secs, p.CallId);
        await notificationOutbox.CancelCallPushAsync(p.CallerId, cid, p.CallId);
        await notificationOutbox.CancelCallPushAsync(p.RecipientId, cid, p.CallId);
        // Both endpoints (including another device of the same user) see the same terminal attempt.
        foreach (var user in new[] { p.CallerId, p.RecipientId })
            await Clients.User(user.ToString()).SendAsync("VideoCallEnded", cid.ToString(), secs, p.CallId.ToString());
    }

    private Task PurgeStaleCallStateAsync() =>
        CallLifecycleMaintenance.PurgeAsync(db, notificationOutbox, Context.GetHttpContext()!.RequestServices);

    // SignalR connectivity is not media liveness. A reconnect or minimized app must not end a call.
    private void ReleaseRingingOnCallerOffline(Guid userId) { }
    private void ReleaseGhostBusy(Guid userId) { }

    public static async Task<bool> DeclineFromHttpAsync(IServiceScopeFactory scopes, Guid userId,
        Guid conversationId, bool busy, string? outcome, Guid? callId = null)
    {
        // An uncorrelated/replayed native action must never consume a newer call in this conversation.
        if (callId == null || callId == Guid.Empty) return true;
        await using var scope = scopes.CreateAsyncScope();
        var sp = scope.ServiceProvider;
        var db = sp.GetRequiredService<AppDbContext>();
        var conv = await db.Conversations.AsNoTracking().FirstOrDefaultAsync(c => c.Id == conversationId &&
            c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return false;
        if (!CallPresenceStore.TryEnd(conversationId, callId.Value, userId, out var p)) return true;
        var outbox = sp.GetRequiredService<NotificationOutboxService>();
        var hub = sp.GetRequiredService<IHubContext<ConversationHub>>();
        var secs = CallPresenceStore.Duration(p!);
        await PersistCallSystemMessageStaticAsync(db, sp.GetRequiredService<IConversationMessageCrypto>(), hub,
            sp.GetRequiredService<ILogger<ConversationHub>>(), conversationId, p!.CallerId, p.RecipientId,
            p.VoiceOnly, CallOutcome(p, userId, busy, outcome), secs, p.CallId);
        await outbox.CancelCallPushAsync(p.CallerId, conversationId, p.CallId);
        await outbox.CancelCallPushAsync(p.RecipientId, conversationId, p.CallId);
        foreach (var user in new[] { p.CallerId, p.RecipientId })
            await hub.Clients.User(user.ToString()).SendAsync("VideoCallEnded", conversationId.ToString(), secs, p.CallId.ToString());
        return true;
    }

    private static async Task PersistCallSystemMessageStaticAsync(
        AppDbContext db,
        IConversationMessageCrypto messageCrypto,
        IHubContext<ConversationHub> hub,
        ILogger logger,
        Guid cid,
        Guid callerId,
        Guid otherUserId,
        bool voiceOnly,
        string status,
        int durationSec,
        Guid callId)
    {
        try
        {
            if (otherUserId == callerId || await db.ConversationMessages.AnyAsync(m => m.Id == callId)) return;
            var plain = JsonSerializer.Serialize(new { status, voiceOnly, durationSec });
            var msg = new ConversationMessage
            {
                Id = callId,
                ConversationId = cid,
                SenderId = callerId,
                Content = messageCrypto.EncryptForStorage(plain),
                Type = "call",
            };
            db.ConversationMessages.Add(msg);
            await db.SaveChangesAsync();

            var receivePayload = new
            {
                msg.Id,
                msg.ConversationId,
                msg.ClientMessageId,
                msg.SenderId,
                Content = plain,
                msg.Type,
                msg.SentAt,
                msg.DeletedForEveryone,
                ReplyToMessageId = (Guid?)null,
                ReplyToContent = (string?)null,
                ReplyToSenderName = (string?)null,
                IsRead = false,
                Reactions = Array.Empty<object>(),
                MyReaction = (string?)null
            };
            await hub.Clients.User(callerId.ToString()).SendAsync("ReceiveMessage", receivePayload);
            await hub.Clients.User(otherUserId.ToString()).SendAsync("ReceiveMessage", receivePayload);

            var preview = ConversationPreviewHelper.BuildCallPreview(plain);
            var listUpdate = new
            {
                ConversationId = cid,
                LastMessagePreview = preview,
                LastMessageType = "call",
                LastMessageAt = msg.SentAt,
                SenderId = callerId
            };
            await hub.Clients.User(callerId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
            await hub.Clients.User(otherUserId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "PersistCallSystemMessage (HTTP) failed conv={Conv} status={Status}", cid, status);
        }
    }

    private async Task PersistCallSystemMessageAsync(
        Guid cid,
        Guid callerId,
        Guid otherUserId,
        bool voiceOnly,
        string status,
        int durationSec,
        Guid callId)
    {
        try
        {
            // Ensure otherUserId is the non-caller participant.
            if (otherUserId == callerId || await db.ConversationMessages.AnyAsync(m => m.Id == callId))
                return;

            var plain = JsonSerializer.Serialize(new
            {
                status,
                voiceOnly,
                durationSec,
            });
            var msg = new ConversationMessage
            {
                Id = callId,
                ConversationId = cid,
                SenderId = callerId,
                Content = messageCrypto.EncryptForStorage(plain),
                Type = "call",
            };
            db.ConversationMessages.Add(msg);
            await db.SaveChangesAsync();

            var receivePayload = new
            {
                msg.Id,
                msg.ConversationId,
                msg.ClientMessageId,
                msg.SenderId,
                Content = plain,
                msg.Type,
                msg.SentAt,
                msg.DeletedForEveryone,
                ReplyToMessageId = (Guid?)null,
                ReplyToContent = (string?)null,
                ReplyToSenderName = (string?)null,
                IsRead = false,
                Reactions = Array.Empty<object>(),
                MyReaction = (string?)null
            };
            await Clients.User(callerId.ToString()).SendAsync("ReceiveMessage", receivePayload);
            await Clients.User(otherUserId.ToString()).SendAsync("ReceiveMessage", receivePayload);

            var preview = ConversationPreviewHelper.BuildCallPreview(plain);
            var listUpdate = new
            {
                ConversationId = cid,
                LastMessagePreview = preview,
                LastMessageType = "call",
                LastMessageAt = msg.SentAt,
                SenderId = callerId
            };
            await Clients.User(callerId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
            await Clients.User(otherUserId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "PersistCallSystemMessage failed conv={Conv} status={Status}", cid, status);
        }
    }

    private async Task<bool> CanPrivateConversationVideoCall(Guid cid, Guid userId)
    {
        var conv = await db.Conversations.AsNoTracking()
            .Include(c => c.User1)
            .Include(c => c.User2)
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return false;
        if (await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == cid))
            return false;
        if (await officialAnnouncements.IsOfficialConversationAsync(cid))
            return false;
        if (await supportConversations.IsSupportConversationAsync(cid))
            return false;

        var otherId = conv.User1Id == userId ? conv.User2Id : conv.User1Id;
        if (otherId == null) return false;
        if (await db.UserBlocks.AnyAsync(b =>
                (b.BlockerId == userId && b.BlockedUserId == otherId) ||
                (b.BlockerId == otherId && b.BlockedUserId == userId)))
            return false;

        return true;
    }

    public async Task AddReaction(string conversationId, string messageId, string emoji)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(messageId, out var mid))
            return;
        if (!await IsParticipant(cid, userId)) return;

        var trimmed = (emoji ?? "").Trim();
        if (string.IsNullOrEmpty(trimmed) || trimmed.Length > 20 || !AllowedReactionEmojis.Contains(trimmed))
            return;

        var msg = await db.ConversationMessages
            .FirstOrDefaultAsync(m => m.Id == mid && m.ConversationId == cid && !m.DeletedForEveryone);
        if (msg == null) return;

        var existing = await db.MessageReactions.FindAsync(mid, userId);
        if (existing != null)
        {
            if (existing.Emoji == trimmed)
            {
                db.MessageReactions.Remove(existing);
                await db.SaveChangesAsync();
                await BroadcastReactionUpdated(cid, mid, userId, existing.Emoji, isAdded: false);
                return;
            }
            existing.Emoji = trimmed;
        }
        else
        {
            db.MessageReactions.Add(new MessageReaction { MessageId = mid, UserId = userId, Emoji = trimmed });
        }
        await db.SaveChangesAsync();
        await BroadcastReactionUpdated(cid, mid, userId, trimmed, isAdded: true);
    }

    public async Task RemoveReaction(string conversationId, string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(messageId, out var mid))
            return;
        if (!await IsParticipant(cid, userId)) return;
        if (!await VisibleMessages(cid, userId).AnyAsync(m => m.Id == mid)) return;

        var existing = await db.MessageReactions.FindAsync(mid, userId);
        if (existing == null) return;

        var emoji = existing.Emoji;
        db.MessageReactions.Remove(existing);
        await db.SaveChangesAsync();
        await BroadcastReactionUpdated(cid, mid, userId, emoji, isAdded: false);
    }

    private async Task BroadcastReactionUpdated(Guid conversationId, Guid messageId, Guid userId, string emoji, bool isAdded)
    {
        var reactions = await db.MessageReactions
            .Where(r => r.MessageId == messageId)
            .Select(r => new { r.UserId, r.Emoji })
            .ToListAsync();
        var payload = new
        {
            conversationId,
            messageId,
            userId,
            emoji,
            isAdded,
            reactions = reactions
                .GroupBy(r => r.Emoji)
                .Select(gg => new { emoji = gg.Key, count = gg.Count(), userIds = gg.Select(x => x.UserId).ToList() })
                .ToList()
        };
        await ConversationDelivery.SendAsync(db, Clients, conversationId, "ReactionUpdated", payload);
    }

    public override async Task OnConnectedAsync()
    {
        if (TryGetUserId(out var userId))
            await presence.OnConnectedAsync(userId, Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        ConversationDelivery.Disconnected(Context.ConnectionId);
        // عند اختفاء آخر اتصال: امسح رنين عالق + busy اليتيم؛ accepted يبقى لـ TTL القصير (5د).
        if (TryGetUserId(out var userId))
        {
            await presence.OnDisconnectedAsync(userId, Context.ConnectionId);
            ReleaseRingingOnCallerOffline(userId);
            ReleaseGhostBusy(userId);
        }
        await base.OnDisconnectedAsync(exception);
    }

    private async Task<bool> IsHiddenForUserAsync(Guid conversationId, Guid userId) =>
        await db.UserConversationStates.AsNoTracking()
            .AnyAsync(s => s.UserId == userId && s.ConversationId == conversationId && s.IsHidden);

    private async Task<bool> IsParticipant(Guid conversationId, Guid userId) =>
        await db.Conversations.AnyAsync(c => c.Id == conversationId &&
            (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId)
             || c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == conversationId && m.UserId == userId)));

    /// <summary>آخر رسالة يظهر معاينتها لهذا المستخدم (تجاهل المحذوفة للجميع ولـ «حذف لي»).</summary>
    private async Task<(string? Preview, DateTime? SentAt, string? SenderId, string? Type)> GetLastListPreviewForUserAsync(Guid conversationId, Guid viewerUserId)
    {
        var now = DateTime.UtcNow;
        var lastMsg = await db.ConversationMessages
            .AsNoTracking()
            .Where(m => m.ConversationId == conversationId &&
                !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == viewerUserId && d.MessageId == m.Id) &&
                (m.ExpiresAt == null || m.ExpiresAt > now))
            .OrderByDescending(m => m.SentAt)
            .FirstOrDefaultAsync();
        if (lastMsg == null) return (null, null, null, null);
        return (ConversationPreviewHelper.BuildListPreview(lastMsg, messageCrypto.DecryptFromStorage), lastMsg.SentAt, lastMsg.SenderId.ToString(), lastMsg.Type);
    }

    /// <summary>بعد حذف للجميع: تحديث معاينة القائمة لكل مشارك حسب آخر رسالة مرئية لديه.</summary>
    private async Task NotifyConversationListPreviewToParticipantsAsync(Guid cid)
    {
        var conv = await db.Conversations.AsNoTracking().FirstOrDefaultAsync(c => c.Id == cid);
        if (conv == null) return;
        List<Guid> userIds;
        if (conv.Type == ConversationType.Group)
        {
            userIds = await db.ConversationMembers
                .Where(m => m.ConversationId == cid)
                .Select(m => m.UserId)
                .ToListAsync();
        }
        else
        {
            userIds = new List<Guid>();
            if (conv.User1Id.HasValue) userIds.Add(conv.User1Id.Value);
            if (conv.User2Id.HasValue) userIds.Add(conv.User2Id.Value);
        }
        foreach (var uid in userIds.Distinct())
        {
            var (preview, sentAt, senderId, lastType) = await GetLastListPreviewForUserAsync(cid, uid);
            await Clients.User(uid.ToString()).SendAsync("ConversationListUpdated", new
            {
                ConversationId = cid,
                LastMessagePreview = preview ?? "",
                LastMessageType = lastType,
                LastMessageAt = sentAt,
                SenderId = senderId,
                UnreadCount = await ConversationDelivery.UnreadCountAsync(db, cid, uid)
            });
        }
    }

    private static bool IsValidAlbumPayload(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("urls", out var urls) || urls.ValueKind != JsonValueKind.Array)
                return false;
            return urls.GetArrayLength() > 0 && urls.GetArrayLength() <= 10;
        }
        catch
        {
            return false;
        }
    }
}
