using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using NexChat.API.Services;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class ConversationHub(AppDbContext db, NotificationOutboxService notificationOutbox, UserPresenceService presence, ILogger<ConversationHub> logger, IWebHostEnvironment env, IConversationMessageCrypto messageCrypto, IProfanityMasker profanity) : Hub
{
    private static readonly HashSet<string> AllowedReactionEmojis = ["❤️", "👍", "😂", "😮", "😢", "🙏"];
    private const int MessagePageSize = 60;

    /// <summary>مكالمة فيديو/صوت قيد الانتظار — لإعلام المتصل بـ voiceOnly عند القبول حتى لو لم يعد في مجموعة SignalR.</summary>
    private static readonly ConcurrentDictionary<Guid, PendingConversationCall> PendingConversationCalls = new();

    /// <summary>userId → busy entry للمستخدمين المشغولين (رنين صادر أو مكالمة جارية).</summary>
    private static readonly ConcurrentDictionary<Guid, BusyCall> UsersBusyInCall = new();

    /// <summary>رنين العميل ~60ث — نسمح بهامش ثم نعتبر الحالة عالقة.</summary>
    private static readonly TimeSpan RingingStaleAfter = TimeSpan.FromSeconds(75);

    /// <summary>سقف أمان لمكالمة مقبولة بلا EndVideoCall (انقطاع/قتل التطبيق).</summary>
    private static readonly TimeSpan InCallStaleAfter = TimeSpan.FromMinutes(45);

    private sealed record PendingConversationCall(Guid CallerId, bool VoiceOnly, bool Accepted, DateTime StartedUtc);

    private sealed record BusyCall(Guid ConversationId, DateTime SinceUtc);

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

        var page = await LoadMessagePageAsync(cid, userId, beforeSentAt: null, beforeId: null, take: MessagePageSize);
        var messages = page.Messages;

        await Clients.Caller.SendAsync("ConversationJoined", new
        {
            Id = conv.Id,
            Type = conv.Type,
            Partner = partner != null ? new { partner.Id, partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar, IsOnline = UserOnlineVisibility.VisibleToOthers(partner) } : null,
            GroupName = conv.Type == ConversationType.Group ? conv.Name : null,
            GroupImageUrl = conv.Type == ConversationType.Group ? conv.ImageUrl : null,
            Messages = messages,
            HasMore = page.HasMore
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
        var page = await LoadMessagePageAsync(cid, userId, before.SentAt, before.Id, pageSize);
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
            if (type != "text" && type != "image" && type != "audio" && type != "short_film" && type != "video" && type != "album")
                type = "text";

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
                    replyToContent = GetReplyPreview(replyPlain, rt);
                    var replySender = await db.Users.FindAsync(replyTo.SenderId);
                    replyToSenderName = replySender?.Name ?? (replyTo.SenderId == userId ? "أنت" : "طرف آخر");
                }
            }

            var plainBody = type == "text" ? content.Trim() : content;
            if (type == "text")
                plainBody = profanity.Mask(plainBody);
            if (type == "album" && !IsValidAlbumPayload(plainBody))
                return;
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
            var preview = type switch
            {
                "text" => plainBody.Length > 80 ? plainBody[..80] + "…" : plainBody,
                "audio" => "رسالة صوتية",
                "image" => "صورة",
                "video" => "فيديو",
                "album" => ConversationPreviewHelper.BuildAlbumPreview(plainBody),
                "short_film" => ConversationPreviewHelper.BuildShortFilmPreview(plainBody),
                _ => plainBody
            };
            if (preview.Length > 80) preview = preview[..80] + "…";
            if (recipientId.HasValue)
                await notificationOutbox.EnqueueAsync(
                    recipientId.Value,
                    "conversation_message",
                    sender?.Name ?? "شخص",
                    preview,
                    new Dictionary<string, string>
                    {
                        ["conversationId"] = cid.ToString(),
                        ["userId"] = userId.ToString(),
                        ["senderName"] = sender?.Name ?? "",
                        ["senderAvatar"] = sender?.Avatar ?? ""
                    });

            var listUpdate = new
            {
                ConversationId = cid,
                LastMessagePreview = preview,
                LastMessageType = type,
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
        var (p, at, sid, lt) = await GetLastListPreviewForUserAsync(cid, userId);
        await Clients.Caller.SendAsync("ConversationListUpdated", new
        {
            ConversationId = cid,
            LastMessagePreview = p ?? "",
            LastMessageType = lt,
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

        var recipientId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;

        PurgeStaleCallState();
        ReleaseGhostBusy(userId);
        ReleaseGhostBusy(recipientId);

        // المتصل مشغول بمكالمة أخرى حقيقية → لا نبدأ طلباً جديداً.
        if (UsersBusyInCall.TryGetValue(userId, out var callerBusy) && callerBusy.ConversationId != cid)
        {
            await Clients.Caller.SendAsync("VideoCallBusy", cid.ToString());
            return;
        }

        // الطرف الآخر مشغول بمكالمة أخرى حقيقية → لا نرنّ.
        if (UsersBusyInCall.TryGetValue(recipientId, out var busyConv) && busyConv.ConversationId != cid)
        {
            await PersistCallSystemMessageAsync(cid, userId, recipientId, voiceOnly, "busy", durationSec: 0);
            await Clients.Caller.SendAsync("VideoCallBusy", cid.ToString());
            return;
        }

        // مكالمة قائمة على نفس المحادثة.
        if (PendingConversationCalls.TryGetValue(cid, out var existingPending))
        {
            // مكالمة مقبولة عالقة (بدون End) — أي طلب جديد من أحد الطرفين يستبدلها.
            if (existingPending.Accepted)
            {
                logger.LogInformation(
                    "Replacing accepted stuck call state conv={Conv} requester={User}",
                    cid, userId);
                ClearCallState(cid);
            }
            else if (existingPending.CallerId == userId)
            {
                // نفس المتصل يعيد الطلب أثناء الرنين → تجاهل بصمت (يتجنب دفع مزدوج).
                return;
            }
            else
            {
                // الطرف الآخر يحاول الاتصال أثناء رنين وارد لنفس المحادثة.
                await Clients.Caller.SendAsync("VideoCallBusy", cid.ToString());
                return;
            }
        }

        var now = DateTime.UtcNow;
        PendingConversationCalls[cid] = new PendingConversationCall(userId, voiceOnly, Accepted: false, now);
        UsersBusyInCall[userId] = new BusyCall(cid, now);

        var caller = conv.User1Id == userId ? conv.User1 : conv.User2;
        // إرسال للمستخدم مباشرة — لا يعتمد على JoinConversation (أي صفحة في التطبيق)
        await Clients.User(recipientId.ToString()).SendAsync("IncomingVideoCall", cid.ToString(), voiceOnly, caller?.Name ?? "", caller?.Avatar ?? "");
        await notificationOutbox.EnqueueAsync(
            recipientId,
            "video_call",
            voiceOnly ? "مكالمة صوتية" : "مكالمة فيديو",
            voiceOnly ? $"{caller?.Name ?? "شخص"} يطلب مكالمة صوتية" : $"{caller?.Name ?? "شخص"} يطلب مكالمة فيديو",
            new Dictionary<string, string>
            {
                ["conversationId"] = cid.ToString(),
                ["voiceOnly"] = voiceOnly ? "true" : "false",
                ["callerName"] = caller?.Name ?? "",
                ["callerAvatar"] = caller?.Avatar ?? ""
            });
    }

    /// يُستدعى من جهاز المستلم عندما يبدأ الرنين فعلياً → يحوّل شاشة المتصل من «جاري الاتصال» إلى «رنين».
    public async Task NotifyVideoCallRinging(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!PendingConversationCalls.TryGetValue(cid, out var pending)) return;
        if (pending.CallerId == userId) return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        await Clients.User(pending.CallerId.ToString()).SendAsync("VideoCallRinging", conversationId);
    }

    public async Task AcceptVideoCall(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        if (PendingConversationCalls.TryGetValue(cid, out var existing))
            PendingConversationCalls[cid] = existing with { Accepted = true, StartedUtc = DateTime.UtcNow };
        PendingConversationCalls.TryGetValue(cid, out var pending);
        var pendingVoiceOnly = pending?.VoiceOnly ?? false;

        var conv = await db.Conversations.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return;

        var otherUserId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        var now = DateTime.UtcNow;
        UsersBusyInCall[userId] = new BusyCall(cid, now);
        UsersBusyInCall[otherUserId] = new BusyCall(cid, now);
        // Stop ringing on the callee device (and collapse any duplicate pushes).
        await notificationOutbox.CancelCallPushAsync(userId, cid);
        await Clients.User(otherUserId.ToString()).SendAsync("VideoCallAccepted", conversationId, pendingVoiceOnly);
    }

    public async Task DeclineVideoCall(string conversationId, bool busy = false, string? outcome = null)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        PendingConversationCalls.TryRemove(cid, out var pending);

        var conv = await db.Conversations.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return;

        var otherUserId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        var callerId = pending?.CallerId ?? userId;
        var voiceOnly = pending?.VoiceOnly ?? false;
        // Explicit outcome (e.g. missed/no_answer) wins; else infer from busy / who declined.
        var normalized = (outcome ?? "").Trim().ToLowerInvariant();
        string status;
        if (busy)
            status = "busy";
        else if (normalized is "missed" or "no_answer" or "noanswer")
            status = "missed";
        else if (normalized is "cancelled" or "declined" or "ended")
            status = normalized;
        else
            status = pending == null || pending.CallerId == userId ? "cancelled" : "declined";

        var peerId = callerId == userId ? otherUserId : userId;

        ClearBusyForConversation(cid, userId, otherUserId);

        // Skip history if the call was already accepted (hangup uses EndVideoCall).
        if (pending is not { Accepted: true })
            await PersistCallSystemMessageAsync(cid, callerId, peerId, voiceOnly, status, durationSec: 0);

        await notificationOutbox.CancelCallPushAsync(otherUserId, cid);
        await notificationOutbox.CancelCallPushAsync(userId, cid);
        if (busy && pending != null && pending.CallerId != userId)
            await Clients.User(callerId.ToString()).SendAsync("VideoCallBusy", conversationId);
        else
            await Clients.User(otherUserId.ToString()).SendAsync("VideoCallDeclined", conversationId);
    }

    /// <summary>يُستدعى عند إنهاء مكالمة ناجحة (بعد القبول) لحفظ مدة المكالمة في الدردشة.</summary>
    public async Task EndVideoCall(string conversationId, int durationSec = 0)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        var conv = await db.Conversations.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == cid && c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
        if (conv == null) return;

        var otherUserId = conv.User1Id == userId ? conv.User2Id!.Value : conv.User1Id!.Value;
        ClearBusyForConversation(cid, userId, otherUserId);

        // First hangup wins — avoids duplicate "ended" rows from both sides.
        if (!PendingConversationCalls.TryRemove(cid, out var pending))
        {
            await notificationOutbox.CancelCallPushAsync(otherUserId, cid);
            await notificationOutbox.CancelCallPushAsync(userId, cid);
            return;
        }

        var callerId = pending.CallerId;
        var peerId = callerId == userId ? otherUserId : userId;
        var voiceOnly = pending.VoiceOnly;
        var secs = Math.Max(0, durationSec);
        await PersistCallSystemMessageAsync(cid, callerId, peerId, voiceOnly, "ended", secs);
        await notificationOutbox.CancelCallPushAsync(otherUserId, cid);
        await notificationOutbox.CancelCallPushAsync(userId, cid);
        await Clients.User(otherUserId.ToString()).SendAsync("VideoCallEnded", conversationId, secs);
    }

    /// <summary>
    /// يحرّر busy/pending العالق من جهة العميل بدون كتابة سجل مكالمة
    /// (بعد رفض/إنهاء محلي فشل إشعاره للسيرفر، أو activeCall شبح).
    /// </summary>
    public async Task ReleaseVideoCallBusy(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;
        if (!await CanPrivateConversationVideoCall(cid, userId)) return;

        PurgeStaleCallState();

        if (PendingConversationCalls.TryGetValue(cid, out var pending) && pending.Accepted)
        {
            UsersBusyInCall.TryRemove(userId, out _);
            var anyoneBusy = UsersBusyInCall.Any(kv => kv.Value.ConversationId == cid);
            if (!anyoneBusy)
                PendingConversationCalls.TryRemove(cid, out _);
            return;
        }

        if (UsersBusyInCall.TryGetValue(userId, out var busy) && busy.ConversationId == cid)
        {
            ClearCallState(cid);
            return;
        }

        if (PendingConversationCalls.TryGetValue(cid, out var ringing) &&
            !ringing.Accepted &&
            ringing.CallerId == userId)
        {
            ClearCallState(cid);
        }
    }

    private static void ClearBusyForConversation(Guid cid, Guid a, Guid b)
    {
        if (UsersBusyInCall.TryGetValue(a, out var ca) && ca.ConversationId == cid)
            UsersBusyInCall.TryRemove(a, out _);
        if (UsersBusyInCall.TryGetValue(b, out var cb) && cb.ConversationId == cid)
            UsersBusyInCall.TryRemove(b, out _);
    }

    private static void ClearCallState(Guid cid)
    {
        PendingConversationCalls.TryRemove(cid, out _);
        foreach (var kv in UsersBusyInCall)
        {
            if (kv.Value.ConversationId == cid)
                UsersBusyInCall.TryRemove(kv.Key, out _);
        }
    }

    /// <summary>يحذف حالات busy/pending العالقة بعد مهلة الرنين أو سقف المكالمة.</summary>
    private void PurgeStaleCallState()
    {
        var now = DateTime.UtcNow;
        foreach (var kv in PendingConversationCalls.ToArray())
        {
            var limit = kv.Value.Accepted ? InCallStaleAfter : RingingStaleAfter;
            if (now - kv.Value.StartedUtc <= limit) continue;
            logger.LogInformation(
                "Purging stale call state conv={Conv} accepted={Accepted} ageSec={Age}",
                kv.Key, kv.Value.Accepted, (now - kv.Value.StartedUtc).TotalSeconds);
            ClearCallState(kv.Key);
        }

        foreach (var kv in UsersBusyInCall.ToArray())
        {
            var hasPending = PendingConversationCalls.TryGetValue(kv.Value.ConversationId, out var p);
            var limit = hasPending && p!.Accepted ? InCallStaleAfter : RingingStaleAfter;
            if (now - kv.Value.SinceUtc <= limit) continue;
            UsersBusyInCall.TryRemove(kv.Key, out _);
        }
    }

    /// <summary>
    /// إن كان المستخدم معلّماً كمشغول لكنه غير متصل بـ SignalR، فحالته ghost
    /// (انقطع بدون Decline/End) — نحرّره فوراً.
    /// </summary>
    private void ReleaseGhostBusy(Guid userId)
    {
        if (presence.IsConnected(userId)) return;
        if (!UsersBusyInCall.TryRemove(userId, out var busy)) return;

        if (PendingConversationCalls.TryGetValue(busy.ConversationId, out var pending))
        {
            // رنين بلا قبول: إن كان المتصل أوفلاين امسح الـ pending كاملاً.
            if (!pending.Accepted && pending.CallerId == userId)
            {
                ClearCallState(busy.ConversationId);
                return;
            }
            // مكالمة مقبولة: امسح busy لهذا المستخدم فقط؛ الطرف الآخر يبقى حتى End أو TTL.
        }
    }

    /// <summary>عند انقطاع آخر اتصال SignalR: امسح رنين صادر عالق للمتصل.</summary>
    private void ReleaseRingingOnCallerOffline(Guid userId)
    {
        if (presence.IsConnected(userId)) return;

        foreach (var kv in PendingConversationCalls.ToArray())
        {
            if (kv.Value.Accepted || kv.Value.CallerId != userId) continue;
            logger.LogInformation("Clearing ringing call after caller offline conv={Conv}", kv.Key);
            ClearCallState(kv.Key);
        }

        // busy بلا pending (حالة يتيمة) — امسحه.
        if (UsersBusyInCall.TryGetValue(userId, out var busy) &&
            !PendingConversationCalls.ContainsKey(busy.ConversationId))
        {
            UsersBusyInCall.TryRemove(userId, out _);
        }
    }

    private async Task PersistCallSystemMessageAsync(
        Guid cid,
        Guid callerId,
        Guid otherUserId,
        bool voiceOnly,
        string status,
        int durationSec)
    {
        try
        {
            // Ensure otherUserId is the non-caller participant.
            if (otherUserId == callerId)
                return;

            var plain = JsonSerializer.Serialize(new
            {
                status,
                voiceOnly,
                durationSec,
            });
            var msg = new ConversationMessage
            {
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

    public override async Task OnConnectedAsync()
    {
        if (TryGetUserId(out var userId))
            await presence.OnConnectedAsync(userId, Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        // لا نمسح busy لمكالمة مقبولة فوراً (LiveKit قد يستمر مع انقطاع SignalR قصير).
        // نمسح فقط رنين صادر عالق عندما يختفي آخر اتصال للمستخدم، + TTL/ghost عند RequestVideoCall.
        if (TryGetUserId(out var userId))
        {
            await presence.OnDisconnectedAsync(userId, Context.ConnectionId);
            ReleaseRingingOnCallerOffline(userId);
        }
        await base.OnDisconnectedAsync(exception);
    }

    private async Task<bool> IsParticipant(Guid conversationId, Guid userId) =>
        await db.Conversations.AnyAsync(c => c.Id == conversationId &&
            (c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId)
             || c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == conversationId && m.UserId == userId)));

    /// <summary>آخر رسالة يظهر معاينتها لهذا المستخدم (تجاهل المحذوفة للجميع ولـ «حذف لي»).</summary>
    private async Task<(string? Preview, DateTime? SentAt, string? SenderId, string? Type)> GetLastListPreviewForUserAsync(Guid conversationId, Guid viewerUserId)
    {
        var lastMsg = await db.ConversationMessages
            .AsNoTracking()
            .Where(m => m.ConversationId == conversationId &&
                !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == viewerUserId && d.MessageId == m.Id))
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
                SenderId = senderId
            });
        }
    }

    private async Task<(List<object> Messages, bool HasMore)> LoadMessagePageAsync(
        Guid cid,
        Guid userId,
        DateTime? beforeSentAt,
        Guid? beforeId,
        int take)
    {
        var q = db.ConversationMessages.AsNoTracking()
            .Where(m => m.ConversationId == cid &&
                        !m.DeletedForEveryone &&
                        !db.UserMessageDeletions.Any(d => d.UserId == userId && d.MessageId == m.Id));

        if (beforeSentAt.HasValue && beforeId.HasValue)
        {
            var at = beforeSentAt.Value;
            var bid = beforeId.Value;
            // Cursor: strictly older than the anchor message (same-second peers excluded by id).
            q = q.Where(m => m.SentAt < at || (m.SentAt == at && m.Id != bid));
        }

        var rawDesc = await q
            .OrderByDescending(m => m.SentAt)
            .ThenByDescending(m => m.Id)
            .Take(take + 1)
            .Select(m => new { m.Id, m.SenderId, m.Content, m.Type, m.SentAt, m.DeletedForEveryone, m.IsRead, m.ReplyToMessageId })
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
            string? replyToContent = null;
            string? replyToSenderName = null;
            if (m.ReplyToMessageId != null && replyData.TryGetValue(m.ReplyToMessageId.Value, out var rd))
            {
                replyToContent = GetReplyPreview(rd.Content, rd.Type);
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

        return (messages, hasMore);
    }

    private static string GetReplyPreview(string? content, string type)
    {
        if (type == "audio") return "رسالة صوتية";
        if (type == "image") return "صورة";
        if (type == "video") return "فيديو";
        if (type == "album") return ConversationPreviewHelper.BuildAlbumPreview(content ?? "");
        if (type == "short_film") return "فيلم قصير";
        if (type == "story_reply") return ConversationPreviewHelper.BuildStoryReplyPreview(content ?? "");
        if (type == "call") return ConversationPreviewHelper.BuildCallPreview(content ?? "");
        if (string.IsNullOrEmpty(content)) return "";
        return content.Length > 80 ? content[..80] + "…" : content;
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
