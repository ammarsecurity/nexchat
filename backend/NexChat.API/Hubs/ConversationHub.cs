using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class ConversationHub(AppDbContext db, OneSignalService oneSignal, ILogger<ConversationHub> logger, IWebHostEnvironment env) : Hub
{
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
                (c.User1Id == userId || c.User2Id == userId));

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

        var partner = conv.User1Id == userId ? conv.User2 : conv.User1;
        var partnerId = conv.User1Id == userId ? conv.User2Id : conv.User1Id;
        var messagesRaw = await db.ConversationMessages
            .Where(m => m.ConversationId == cid &&
                !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == userId && d.MessageId == m.Id))
            .OrderBy(m => m.SentAt)
            .Select(m => new { m.Id, m.SenderId, m.Content, m.Type, m.SentAt, m.DeletedForEveryone, m.IsRead, m.ReplyToMessageId })
            .ToListAsync();

        var replyIds = messagesRaw.Where(m => m.ReplyToMessageId != null).Select(m => m.ReplyToMessageId!.Value).Distinct().ToList();
        Dictionary<Guid, (string? Content, string? SenderName)> replyData;
        if (replyIds.Count > 0)
        {
            var replyList = await db.ConversationMessages
                .Where(m => replyIds.Contains(m.Id))
                .Select(m => new { m.Id, m.Content, SenderName = m.Sender.Name })
                .ToListAsync();
            replyData = replyList.ToDictionary(m => m.Id, m => (m.Content, m.SenderName));
        }
        else
        {
            replyData = new Dictionary<Guid, (string? Content, string? SenderName)>();
        }

        var messages = messagesRaw.Select(m =>
        {
            var replyToContent = (string?)null;
            var replyToSenderName = (string?)null;
            if (m.ReplyToMessageId != null && replyData.TryGetValue(m.ReplyToMessageId.Value, out var rd))
            {
                replyToContent = rd.Content?.Length > 80 ? rd.Content[..80] + "…" : rd.Content;
                replyToSenderName = rd.SenderName ?? "—";
            }
            return new
            {
                m.Id,
                m.SenderId,
                m.Content,
                m.Type,
                m.SentAt,
                m.DeletedForEveryone,
                m.IsRead,
                m.ReplyToMessageId,
                ReplyToContent = replyToContent,
                ReplyToSenderName = replyToSenderName
            };
        }).ToList();

        await Clients.Caller.SendAsync("ConversationJoined", new
        {
            Id = conv.Id,
            Partner = new { partner.Id, partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar },
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

        var messageIdsToMark = await db.ConversationMessages
            .Where(m => m.ConversationId == cid && m.SenderId == partnerId && !m.IsRead)
            .Select(m => m.Id)
            .ToListAsync();
        if (messageIdsToMark.Count > 0)
        {
            await db.ConversationMessages
                .Where(m => messageIdsToMark.Contains(m.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        await db.SaveChangesAsync();

        await Clients.User(partnerId.ToString()).SendAsync("PartnerReadUpTo", new { LastReadAt = state.LastReadAt });
        if (messageIdsToMark.Count > 0)
        {
            var readPayload = new { messageIds = messageIdsToMark };
            await Clients.User(partnerId.ToString()).SendAsync("MessagesRead", readPayload);
            await Clients.Group(cid.ToString()).SendAsync("MessagesRead", readPayload);
        }
    }

    public async Task MarkAsRead(string conversationId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(conversationId, out var cid))
            return;

        if (!await IsParticipant(cid, userId)) return;

        var partnerId = (await db.Conversations.FirstOrDefaultAsync(c => c.Id == cid)) is { } conv
            ? (conv.User1Id == userId ? conv.User2Id : conv.User1Id)
            : Guid.Empty;
        if (partnerId == Guid.Empty) return;

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

        var messageIdsToMark = await db.ConversationMessages
            .Where(m => m.ConversationId == cid && m.SenderId == partnerId && !m.IsRead)
            .Select(m => m.Id)
            .ToListAsync();
        if (messageIdsToMark.Count > 0)
        {
            await db.ConversationMessages
                .Where(m => messageIdsToMark.Contains(m.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        await db.SaveChangesAsync();

        var payload = new { LastReadAt = state.LastReadAt, ReaderId = userId };
        await Clients.User(partnerId.ToString()).SendAsync("PartnerReadUpTo", payload);
        await Clients.Group(cid.ToString()).SendAsync("PartnerReadUpTo", payload);
        if (messageIdsToMark.Count > 0)
        {
            var readPayload = new { messageIds = messageIdsToMark };
            await Clients.User(partnerId.ToString()).SendAsync("MessagesRead", readPayload);
            await Clients.Group(cid.ToString()).SendAsync("MessagesRead", readPayload);
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
                    (c.User1Id == userId || c.User2Id == userId));

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
                    replyToContent = replyTo.Content?.Length > 80 ? replyTo.Content[..80] + "…" : replyTo.Content;
                    var replySender = await db.Users.FindAsync(replyTo.SenderId);
                    replyToSenderName = replySender?.Name ?? (replyTo.SenderId == userId ? "أنت" : "طرف آخر");
                }
            }

            var msg = new ConversationMessage
            {
                ConversationId = cid,
                SenderId = userId,
                Content = type == "text" ? content.Trim() : content,
                Type = type,
                ReplyToMessageId = replyToId
            };
            db.ConversationMessages.Add(msg);
            var recipientId = conv.User1Id == userId ? conv.User2Id : conv.User1Id;
            var recipientDeletion = await db.UserConversationDeletions
                .FirstOrDefaultAsync(d => d.UserId == recipientId && d.ConversationId == cid);
            if (recipientDeletion != null)
            {
                db.UserConversationDeletions.Remove(recipientDeletion);
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

            var receivePayload = new
            {
                msg.Id,
                msg.SenderId,
                msg.Content,
                msg.Type,
                msg.SentAt,
                msg.DeletedForEveryone,
                msg.ReplyToMessageId,
                ReplyToContent = replyToContent,
                ReplyToSenderName = replyToSenderName,
                IsRead = false
            };
            try
            {
                await Clients.User(userId.ToString()).SendAsync("ReceiveMessage", receivePayload);
                await Clients.User(recipientId.ToString()).SendAsync("ReceiveMessage", receivePayload);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "SendMessage ReceiveMessage failed");
                throw;
            }
            logger.LogInformation("SendMessage ReceiveMessage sent");

            var sender = await db.Users.FindAsync(userId);
            var preview = type == "text" ? content.Trim() : (type == "audio" ? "رسالة صوتية" : "صورة");
            if (preview.Length > 80) preview = preview[..80] + "…";
            _ = oneSignal.SendNewConversationMessageAsync(recipientId, sender?.Name ?? "شخص", preview, cid);

            var listUpdate = new
            {
                ConversationId = cid,
                LastMessagePreview = preview,
                LastMessageAt = msg.SentAt,
                SenderId = userId
            };
            try
            {
                await Clients.User(userId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
                await Clients.User(recipientId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
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

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        await base.OnDisconnectedAsync(exception);
    }

    private async Task<bool> IsParticipant(Guid conversationId, Guid userId) =>
        await db.Conversations.AnyAsync(c => c.Id == conversationId &&
            (c.User1Id == userId || c.User2Id == userId));
}
