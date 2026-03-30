using System.Collections.Concurrent;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class ConversationHub(AppDbContext db, OneSignalService oneSignal, ILogger<ConversationHub> logger, IWebHostEnvironment env, IConversationMessageCrypto messageCrypto, IProfanityMasker profanity) : Hub
{
    private static readonly HashSet<string> AllowedReactionEmojis = ["❤️", "👍", "😂", "😮", "😢", "🙏"];

    /// <summary>مكالمة فيديو/صوت قيد الانتظار — لإعلام المتصل بـ voiceOnly عند القبول حتى لو لم يعد في مجموعة SignalR.</summary>
    private static readonly ConcurrentDictionary<Guid, bool> PendingConversationCallVoiceOnly = new();

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
            await Clients.Caller.SendAsync("Error", "Conversation not found");
            return;
        }

        var groupName = cid.ToString();
        await Groups.AddToGroupAsync(Context.ConnectionId, groupName);

        var partner = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2 : conv.User1) : null;
        var partnerId = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2Id : conv.User1Id) : null;
        var messagesRaw = await db.ConversationMessages
            .Where(m => m.ConversationId == cid &&
                !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == userId && d.MessageId == m.Id))
            .OrderBy(m => m.SentAt)
            .Select(m => new { m.Id, m.SenderId, m.Content, m.Type, m.SentAt, m.DeletedForEveryone, m.IsRead, m.ReplyToMessageId })
            .ToListAsync();

        var messageIds = messagesRaw.Select(m => m.Id).ToList();
        var reactionsByMessage = messageIds.Count > 0
            ? (await db.MessageReactions
                .Where(r => messageIds.Contains(r.MessageId))
                .Select(r => new { r.MessageId, r.UserId, r.Emoji })
                .ToListAsync())
                .GroupBy(r => r.MessageId)
                .ToDictionary(g => g.Key, g => g.Select(r => (r.UserId, r.Emoji)).ToList())
            : new Dictionary<Guid, List<(Guid UserId, string Emoji)>>();

        var replyIds = messagesRaw.Where(m => m.ReplyToMessageId != null).Select(m => m.ReplyToMessageId!.Value).Distinct().ToList();
        Dictionary<Guid, (string Content, string Type, string? SenderName)> replyData;
        if (replyIds.Count > 0)
        {
            var replyList = await db.ConversationMessages
                .Where(m => replyIds.Contains(m.Id))
                .Select(m => new { m.Id, m.Content, m.Type, SenderName = m.Sender.Name })
                .ToListAsync();
            replyData = replyList.ToDictionary(
                m => m.Id,
                m => (messageCrypto.DecryptFromStorage(m.Content ?? ""), m.Type ?? "text", (string?)m.SenderName));
        }
        else
        {
            replyData = new Dictionary<Guid, (string Content, string Type, string? SenderName)>();
        }

        static string GetReplyPreview(string? content, string type)
        {
            if (type == "audio") return "رسالة صوتية";
            if (type == "image") return "صورة";
            if (string.IsNullOrEmpty(content)) return "";
            return content.Length > 80 ? content[..80] + "…" : content;
        }

        Dictionary<Guid, (string Name, string? Avatar)>? senderNames = null;
        if (conv.Type == ConversationType.Group && messagesRaw.Count > 0)
        {
            var senderIds = messagesRaw.Select(m => m.SenderId).Distinct().ToList();
            var senders = await db.Users.Where(u => senderIds.Contains(u.Id)).Select(u => new { u.Id, u.Name, u.Avatar }).ToListAsync();
            senderNames = senders.ToDictionary(u => u.Id, u => (u.Name ?? "—", u.Avatar));
        }

        var messages = messagesRaw.Select(m =>
        {
            var decryptedContent = messageCrypto.DecryptFromStorage(m.Content ?? "");
            var replyToContent = (string?)null;
            var replyToSenderName = (string?)null;
            if (m.ReplyToMessageId != null && replyData.TryGetValue(m.ReplyToMessageId.Value, out var rd))
            {
                replyToContent = GetReplyPreview(rd.Content, rd.Type);
                replyToSenderName = rd.SenderName ?? "—";
            }
            var senderName = (string?)null;
            var senderAvatar = (string?)null;
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
            return new
            {
                m.Id,
                m.SenderId,
                Content = decryptedContent,
                m.Type,
                m.SentAt,
                m.DeletedForEveryone,
                m.IsRead,
                m.ReplyToMessageId,
                ReplyToContent = replyToContent,
                ReplyToSenderName = replyToSenderName,
                SenderName = senderName,
                SenderAvatar = senderAvatar,
                Reactions = reactions,
                MyReaction = myReaction
            };
        }).ToList();

        await Clients.Caller.SendAsync("ConversationJoined", new
        {
            Id = conv.Id,
            Type = conv.Type,
            Partner = partner != null ? new { partner.Id, partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar, IsOnline = UserOnlineVisibility.VisibleToOthers(partner) } : null,
            GroupName = conv.Type == ConversationType.Group ? conv.Name : null,
            GroupImageUrl = conv.Type == ConversationType.Group ? conv.ImageUrl : null,
            Messages = messages
        });

        var state = await db.UserConversationStates
            .FirstOrDefaultAsync(s => s.UserId == userId && s.ConversationId == cid);
        if (state == null)
        {
            state = new UserConversationState
            {
                UserId = userId,
                ConversationId = cid,
                LastReadAt = DateTime.UtcNow
            };
            db.UserConversationStates.Add(state);
        }
        else
        {
            state.LastReadAt = DateTime.UtcNow;
        }
        state.UpdatedAt = DateTime.UtcNow;

        var messageIdsToMark = conv.Type == ConversationType.Group
            ? await db.ConversationMessages.Where(m => m.ConversationId == cid && m.SenderId != userId && !m.IsRead).Select(m => m.Id).ToListAsync()
            : await db.ConversationMessages.Where(m => m.ConversationId == cid && partnerId.HasValue && m.SenderId == partnerId.Value && !m.IsRead).Select(m => m.Id).ToListAsync();
        if (messageIdsToMark.Count > 0)
        {
            await db.ConversationMessages
                .Where(m => messageIdsToMark.Contains(m.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        await db.SaveChangesAsync();

        if (conv.Type == ConversationType.Group)
        {
            await Clients.Group(cid.ToString()).SendAsync("PartnerReadUpTo", new { LastReadAt = state.LastReadAt, ReaderId = userId });
            if (messageIdsToMark.Count > 0)
                await Clients.Group(cid.ToString()).SendAsync("MessagesRead", new { messageIds = messageIdsToMark });
        }
        else if (partnerId.HasValue)
        {
            await Clients.User(partnerId.Value.ToString()).SendAsync("PartnerReadUpTo", new { LastReadAt = state.LastReadAt });
            if (messageIdsToMark.Count > 0)
            {
                var readPayload = new { messageIds = messageIdsToMark };
                await Clients.User(partnerId.Value.ToString()).SendAsync("MessagesRead", readPayload);
                await Clients.Group(cid.ToString()).SendAsync("MessagesRead", readPayload);
            }
        }
    }

    public async Task MarkAsRead(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == cid);
        if (conv == null) return;
        var partnerId = conv.Type == ConversationType.Private ? (conv.User1Id == userId ? conv.User2Id : conv.User1Id) : (Guid?)null;

        var state = await db.UserConversationStates
            .FirstOrDefaultAsync(s => s.UserId == userId && s.ConversationId == cid);
        if (state == null)
        {
            state = new UserConversationState
            {
                UserId = userId,
                ConversationId = cid,
                LastReadAt = DateTime.UtcNow
            };
            db.UserConversationStates.Add(state);
        }
        else
        {
            state.LastReadAt = DateTime.UtcNow;
        }
        state.UpdatedAt = DateTime.UtcNow;

        var messageIdsToMark = conv.Type == ConversationType.Group
            ? await db.ConversationMessages.Where(m => m.ConversationId == cid && m.SenderId != userId && !m.IsRead).Select(m => m.Id).ToListAsync()
            : await db.ConversationMessages.Where(m => m.ConversationId == cid && partnerId.HasValue && m.SenderId == partnerId.Value && !m.IsRead).Select(m => m.Id).ToListAsync();
        if (messageIdsToMark.Count > 0)
        {
            await db.ConversationMessages
                .Where(m => messageIdsToMark.Contains(m.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        await db.SaveChangesAsync();

        var payload = new { LastReadAt = state.LastReadAt, ReaderId = userId };
        await Clients.Group(cid.ToString()).SendAsync("PartnerReadUpTo", payload);
        if (partnerId.HasValue)
            await Clients.User(partnerId.Value.ToString()).SendAsync("PartnerReadUpTo", payload);
        if (messageIdsToMark.Count > 0)
        {
            var readPayload = new { messageIds = messageIdsToMark };
            await Clients.Group(cid.ToString()).SendAsync("MessagesRead", readPayload);
            if (partnerId.HasValue)
                await Clients.User(partnerId.Value.ToString()).SendAsync("MessagesRead", readPayload);
        }
    }

    public async Task SendMessage(string conversationId, string content, string type = "text", string? replyToMessageId = null)
    {
        try
        {
            logger.LogInformation("SendMessage entered: convId={ConvId}, type={Type}, contentLen={Len}", conversationId, type, content?.Length ?? 0);
            if (string.IsNullOrWhiteSpace(content) || content.Length > 5000) return;
            if (type != "text" && type != "image" && type != "audio") type = "text";

            if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
                return;

            var conv = await db.Conversations
                .FirstOrDefaultAsync(c => c.Id == cid &&
                    (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId)
                     || c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == cid && m.UserId == userId)));

            if (conv == null) return;

            var deleted = await db.UserConversationDeletions
                .AnyAsync(d => d.UserId == userId && d.ConversationId == cid);
            if (deleted) return;

            Guid? replyToId = null;
            string? replyToContent = null;
            string? replyToSenderName = null;
            if (!string.IsNullOrEmpty(replyToMessageId) && Guid.TryParse(replyToMessageId, out var rid))
            {
                var replyTo = await db.ConversationMessages
                    .FirstOrDefaultAsync(m => m.Id == rid && m.ConversationId == cid && !m.DeletedForEveryone);
                if (replyTo != null)
                {
                    replyToId = rid;
                    var rt = replyTo.Type ?? "text";
                    var replyPlain = messageCrypto.DecryptFromStorage(replyTo.Content ?? "");
                    replyToContent = rt == "audio" ? "رسالة صوتية" : rt == "image" ? "صورة" : (replyPlain.Length > 80 ? replyPlain[..80] + "…" : replyPlain);
                    var replySender = await db.Users.FindAsync(replyTo.SenderId);
                    replyToSenderName = replySender?.Name ?? (replyTo.SenderId == userId ? "أنت" : "طرف آخر");
                }
            }

            var plainBody = type == "text" ? content.Trim() : content;
            if (type == "text")
                plainBody = profanity.Mask(plainBody);
            var msg = new ConversationMessage
            {
                ConversationId = cid,
                SenderId = userId,
                Content = messageCrypto.EncryptForStorage(plainBody),
                Type = type,
                ReplyToMessageId = replyToId
            };
            db.ConversationMessages.Add(msg);
            var recipientId = conv.Type == ConversationType.Group ? (Guid?)null : (conv.User1Id == userId ? conv.User2Id : conv.User1Id);
            if (recipientId.HasValue)
            {
                var recipientDeletion = await db.UserConversationDeletions
                    .FirstOrDefaultAsync(d => d.UserId == recipientId.Value && d.ConversationId == cid);
                if (recipientDeletion != null)
                {
                    db.UserConversationDeletions.Remove(recipientDeletion);
                }
            }
            try
            {
                await db.SaveChangesAsync();
            }
            catch (DbUpdateException dbEx)
            {
                var entries = dbEx.Entries?.Select(e => e.Entity.GetType().Name).ToList() ?? [];
                logger.LogError(dbEx, "SendMessage SaveChanges failed: Entries=[{Entries}], Inner={Inner}", string.Join(", ", entries), dbEx.InnerException?.Message);
                throw;
            }
            logger.LogInformation("SendMessage SaveChanges OK");

            var senderUser = conv.Type == ConversationType.Group ? await db.Users.FindAsync(userId) : null;
            object receivePayload;
            if (conv.Type == ConversationType.Group)
            {
                receivePayload = new
                {
                    msg.Id,
                    msg.SenderId,
                    Content = plainBody,
                    msg.Type,
                    msg.SentAt,
                    msg.DeletedForEveryone,
                    msg.ReplyToMessageId,
                    ReplyToContent = replyToContent,
                    ReplyToSenderName = replyToSenderName,
                    IsRead = false,
                    SenderName = senderUser?.Name ?? "—",
                    SenderAvatar = senderUser?.Avatar,
                    Reactions = Array.Empty<object>(),
                    MyReaction = (string?)null
                };
            }
            else
            {
                receivePayload = new
                {
                    msg.Id,
                    msg.SenderId,
                    Content = plainBody,
                    msg.Type,
                    msg.SentAt,
                    msg.DeletedForEveryone,
                    msg.ReplyToMessageId,
                    ReplyToContent = replyToContent,
                    ReplyToSenderName = replyToSenderName,
                    IsRead = false,
                    Reactions = Array.Empty<object>(),
                    MyReaction = (string?)null
                };
            }
            try
            {
                if (conv.Type == ConversationType.Group)
                    await Clients.Group(cid.ToString()).SendAsync("ReceiveMessage", receivePayload);
                else if (recipientId.HasValue)
                {
                    await Clients.User(userId.ToString()).SendAsync("ReceiveMessage", receivePayload);
                    await Clients.User(recipientId.Value.ToString()).SendAsync("ReceiveMessage", receivePayload);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "SendMessage ReceiveMessage failed");
                throw;
            }
            logger.LogInformation("SendMessage ReceiveMessage sent");

            var sender = senderUser ?? await db.Users.FindAsync(userId);
            var preview = type == "text" ? plainBody : (type == "audio" ? "رسالة صوتية" : "صورة");
            if (preview.Length > 80) preview = preview[..80] + "…";
            if (recipientId.HasValue)
                _ = oneSignal.SendNewConversationMessageAsync(recipientId.Value, sender?.Name ?? "شخص", preview, cid);

            var listUpdate = new
            {
                ConversationId = cid,
                LastMessagePreview = preview,
                LastMessageAt = msg.SentAt,
                SenderId = userId
            };
            try
            {
                if (conv.Type == ConversationType.Group)
                    await Clients.Group(cid.ToString()).SendAsync("ConversationListUpdated", listUpdate);
                else
                {
                    await Clients.User(userId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
                    if (recipientId.HasValue)
                        await Clients.User(recipientId.Value.ToString()).SendAsync("ConversationListUpdated", listUpdate);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "SendMessage Clients.User failed");
                throw;
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "SendMessage failed: convId={ConvId}, type={Type}, contentLen={Len}", conversationId, type, content?.Length ?? 0);
            try
            {
                var logEntry = System.Text.Json.JsonSerializer.Serialize(new
                {
                    timestamp = DateTimeOffset.UtcNow.ToString("o"),
                    message = ex.Message,
                    exType = ex.GetType().FullName,
                    innerMessage = ex.InnerException?.Message,
                    stack = ex.StackTrace,
                    convId = conversationId,
                    type,
                    contentLen = content?.Length
                });
                var homeLog = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "nexchat-sendmessage-error.log");
                var projectLog = Path.GetFullPath(Path.Combine(env.ContentRootPath, "..", "..", "nexchat-sendmessage-error.log"));
                try { File.AppendAllText(homeLog, logEntry + Environment.NewLine); } catch { }
                try { File.AppendAllText(projectLog, logEntry + Environment.NewLine); } catch { }
            }
            catch { /* ignore */ }
            var errMsg = env.IsDevelopment() ? $"{ex.GetType().Name}: {ex.Message}" : "حدث خطأ في الإرسال";
            throw new HubException(errMsg);
        }
    }

    public async Task DeleteMessageForMe(string conversationId, string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(messageId, out var mid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        var exists = await db.UserMessageDeletions.AnyAsync(d => d.UserId == userId && d.MessageId == mid);
        if (exists) return;

        db.UserMessageDeletions.Add(new UserMessageDeletion { UserId = userId, MessageId = mid });
        await db.SaveChangesAsync();
        await Clients.Caller.SendAsync("MessageDeletedForMe", mid);
        var (p, at, sid) = await GetLastListPreviewForUserAsync(cid, userId);
        await Clients.Caller.SendAsync("ConversationListUpdated", new
        {
            ConversationId = cid,
            LastMessagePreview = p ?? "",
            LastMessageAt = at,
            SenderId = sid
        });
    }

    public async Task DeleteMessageForEveryone(string conversationId, string messageId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid) || !Guid.TryParse(messageId, out var mid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        var msg = await db.ConversationMessages
            .FirstOrDefaultAsync(m => m.Id == mid && m.ConversationId == cid && m.SenderId == userId);
        if (msg == null) return;

        msg.DeletedForEveryone = true;
        await db.SaveChangesAsync();
        await Clients.Group(cid.ToString()).SendAsync("MessageDeletedForEveryone", mid);
        await NotifyConversationListPreviewToParticipantsAsync(cid);
    }

    public async Task DeleteConversationForMe(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;

        if (!await IsParticipant(cid, userId)) return;

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
        await Clients.Caller.SendAsync("ConversationDeletedForMe", cid);
    }

    public async Task StartTyping(string conversationId)
    {
        if (TryGetUserId(out var userId))
            await Clients.OthersInGroup(conversationId).SendAsync("UserTyping", userId);
    }

    public async Task StopTyping(string conversationId)
    {
        if (TryGetUserId(out var userId))
            await Clients.OthersInGroup(conversationId).SendAsync("UserStoppedTyping", userId);
    }

    public async Task LeaveConversation(string conversationId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, conversationId);
    }

    public async Task RequestVideoCall(string conversationId, bool voiceOnly = false)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;

        var conv = await db.Conversations
            .Include(c => c.User1)
            .Include(c => c.User2)
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));

        if (conv == null) return;

        if (await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == cid))
            return;

        PendingConversationCallVoiceOnly[cid] = voiceOnly;

        var recipientId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        var caller = conv.User1Id == userId ? conv.User1 : conv.User2;
        // إرسال للمستخدم مباشرة — لا يعتمد على JoinConversation (أي صفحة في التطبيق)
        await Clients.User(recipientId.ToString()).SendAsync("IncomingVideoCall", cid.ToString(), voiceOnly, caller?.Name ?? "", caller?.Avatar ?? "");
        _ = oneSignal.SendConversationVideoCallAsync(recipientId, caller?.Name ?? "شخص", cid, voiceOnly);
    }

    public async Task AcceptVideoCall(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        PendingConversationCallVoiceOnly.TryRemove(cid, out var pendingVoiceOnly);

        var conv = await db.Conversations.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return;

        var otherUserId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        await Clients.User(otherUserId.ToString()).SendAsync("VideoCallAccepted", conversationId, pendingVoiceOnly);
    }

    public async Task DeclineVideoCall(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        PendingConversationCallVoiceOnly.TryRemove(cid, out _);

        var conv = await db.Conversations.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return;

        var otherUserId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        await Clients.User(otherUserId.ToString()).SendAsync("VideoCallDeclined", conversationId);
    }

    private async Task<bool> CanPrivateConversationVideoCall(Guid cid, Guid userId)
    {
        var ok = await db.Conversations.AnyAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
            (c.User1Id == userId || c.User2Id == userId));
        if (!ok) return false;
        if (await db.UserConversationDeletions.AnyAsync(d => d.UserId == userId && d.ConversationId == cid))
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
            messageId,
            userId,
            emoji,
            isAdded,
            reactions = reactions
                .GroupBy(r => r.Emoji)
                .Select(gg => new { emoji = gg.Key, count = gg.Count(), userIds = gg.Select(x => x.UserId).ToList() })
                .ToList()
        };
        await Clients.Group(conversationId.ToString()).SendAsync("ReactionUpdated", payload);
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        await base.OnDisconnectedAsync(exception);
    }

    private async Task<bool> IsParticipant(Guid conversationId, Guid userId) =>
        await db.Conversations.AnyAsync(c => c.Id == conversationId &&
            (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId)
             || c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == conversationId && m.UserId == userId)));

    /// <summary>آخر رسالة يظهر معاينتها لهذا المستخدم (تجاهل المحذوفة للجميع ولـ «حذف لي»).</summary>
    private async Task<(string? Preview, DateTime? SentAt, string? SenderId)> GetLastListPreviewForUserAsync(Guid conversationId, Guid viewerUserId)
    {
        var lastMsg = await db.ConversationMessages
            .AsNoTracking()
            .Where(m => m.ConversationId == conversationId &&
                !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == viewerUserId && d.MessageId == m.Id))
            .OrderByDescending(m => m.SentAt)
            .FirstOrDefaultAsync();
        if (lastMsg == null) return (null, null, null);
        return (BuildListPreview(lastMsg), lastMsg.SentAt, lastMsg.SenderId.ToString());
    }

    private string BuildListPreview(ConversationMessage m)
    {
        if (m.Type == "image") return "صورة";
        if (m.Type == "audio") return "رسالة صوتية";
        var c = messageCrypto.DecryptFromStorage(m.Content ?? "");
        return c.Length > 50 ? c[..50] + "…" : c;
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
            var (preview, sentAt, senderId) = await GetLastListPreviewForUserAsync(cid, uid);
            await Clients.User(uid.ToString()).SendAsync("ConversationListUpdated", new
            {
                ConversationId = cid,
                LastMessagePreview = preview ?? "",
                LastMessageAt = sentAt,
                SenderId = senderId
            });
        }
    }
}
