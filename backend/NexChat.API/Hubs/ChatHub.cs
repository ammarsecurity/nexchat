using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using NexChat.Infrastructure.Services;
using NexChat.API.Services;

namespace NexChat.API.Hubs;

[Authorize]
public class ChatHub(AppDbContext db, NotificationOutboxService notificationOutbox, IProfanityMasker profanity) : Hub
{
    private bool TryGetUserId(out Guid userId)
    {
        var id = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out userId);
    }

    // A transport interruption is not a request to abandon a resumable session.
    // Explicit LeaveSession, administrative closure and the existing one-hour inactivity cleanup end sessions.
    public override Task OnDisconnectedAsync(Exception? exception) => base.OnDisconnectedAsync(exception);

    public async Task JoinSession(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
        {
            await Clients.Caller.SendAsync("Error", "Invalid request");
            return;
        }
        // جلسات الدعم: يُسمح بالانضمام حتى لو كانت منتهية (للمتابعة)
        var session = await db.ChatSessions
            .Include(s => s.User1)
            .Include(s => s.User2)
            .FirstOrDefaultAsync(s => s.Id == sid &&
                (s.User1Id == userId || s.User2Id == userId) &&
                (s.EndedAt == null || s.Type == "support"));

        if (session == null)
        {
            await Clients.Caller.SendAsync("Error", "Session not found");
            return;
        }

        if (session.Type == "random" && MatchingService.BlocksRandomJoinUntilAccepted(sid))
        {
            await Clients.Caller.SendAsync("Error", "Match not confirmed");
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, sid.ToString());

        // Send recent messages
        var messages = await db.Messages
            .Where(m => m.SessionId == sid)
            .OrderBy(m => m.SentAt)
            .Select(m => new { m.Id, m.SessionId, m.ClientMessageId, m.SenderId, m.Content, m.Type, m.SentAt })
            .ToListAsync();

        var partnerUser = session.User1Id == userId ? session.User2 : session.User1;
        await Clients.Caller.SendAsync("SessionJoined", new
        {
            session.Id,
            SessionId = session.Id,
            Partner = new { partnerUser.Id, partnerUser.Name, partnerUser.Gender, partnerUser.UniqueCode, partnerUser.Avatar, IsFeatured = partnerUser.IsFeatured },
            Messages = messages
        });
    }

    public Task<object> SendMessage(string sessionId, string content, string type = "text") =>
        SendMessageCore(sessionId, content, type, null);

    public Task<object> SendMessageWithClientId(string sessionId, string content, string type, string clientMessageId)
    {
        if (string.IsNullOrWhiteSpace(clientMessageId) || clientMessageId.Length > 80 || clientMessageId.Any(char.IsWhiteSpace))
            throw new HubException("Invalid client message ID");
        return SendMessageCore(sessionId, content, type, clientMessageId);
    }

    private async Task<object> SendMessageCore(string sessionId, string content, string type, string? clientMessageId)
    {
        if (string.IsNullOrWhiteSpace(content) || content.Length > 5000)
            throw new HubException("Message must contain between 1 and 5000 characters");
        if (type is not ("text" or "image")) throw new HubException("Unsupported message type");
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            throw new HubException("Invalid request");
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) && (s.EndedAt == null || s.Type == "support"));
        if (session == null) throw new HubException("Session not found or ended");
        if (session.Type == "random" && MatchingService.BlocksRandomJoinUntilAccepted(sid))
            throw new HubException("Match not confirmed");
        var recipientId = session.User1Id == userId ? session.User2Id : session.User1Id;
        if (await db.UserBlocks.AnyAsync(b => (b.BlockerId == userId && b.BlockedUserId == recipientId) ||
            (b.BlockerId == recipientId && b.BlockedUserId == userId)))
            throw new HubException("Messaging is unavailable for this session");
        if (clientMessageId != null)
        {
            var accepted = await db.Messages.AsNoTracking().FirstOrDefaultAsync(m =>
                m.SessionId == sid && m.SenderId == userId && m.ClientMessageId == clientMessageId);
            if (accepted != null) return MessagePayload(accepted);
        }
        if (session.EndedAt != null && session.Type == "support") session.EndedAt = null;
        var textBody = type == "text" ? profanity.Mask(content.Trim()) : content;
        var message = new Message { SessionId = sid, SenderId = userId, ClientMessageId = clientMessageId, Content = textBody, Type = type };
        db.Messages.Add(message);
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) when (clientMessageId != null)
        {
            db.ChangeTracker.Clear();
            var accepted = await db.Messages.AsNoTracking().FirstOrDefaultAsync(m =>
                m.SessionId == sid && m.SenderId == userId && m.ClientMessageId == clientMessageId);
            if (accepted != null) return MessagePayload(accepted);
            throw new HubException("Message could not be saved");
        }
        var payload = MessagePayload(message);
        try
        {
            foreach (var target in new[] { userId, recipientId }.Distinct())
            {
                try { await Clients.User(target.ToString()).SendAsync("ReceiveMessage", payload); }
                catch (Exception) { /* A failed socket must not suppress the other participant or push. */ }
            }
            var sender = await db.Users.FindAsync(userId);
            var preview = type == "text" ? textBody : "صورة";
            if (preview.Length > 80) preview = preview[..80] + "…";
            await notificationOutbox.EnqueueAsync(recipientId, "message", sender?.Name ?? "شخص", preview,
                new Dictionary<string, string> { ["sessionId"] = sid.ToString() });
        }
        catch (Exception)
        {
            // Persistence is the acceptance boundary. Reconnect history recovers missed live events.
        }
        return payload;
    }

    private static object MessagePayload(Message message) => new
    {
        message.Id, message.SessionId, message.ClientMessageId, message.SenderId,
        message.Content, message.Type, message.SentAt
    };

    private async Task<bool> IsSessionParticipant(Guid sid, Guid userId) =>
        await db.ChatSessions.AnyAsync(s => s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            (s.EndedAt == null || s.Type == "support"));

    public Task StartTyping(string sessionId) => SendTypingAsync(sessionId, "UserTyping", "UserTypingV2");

    public Task StopTyping(string sessionId) => SendTypingAsync(sessionId, "UserStoppedTyping", "UserStoppedTypingV2");

    private async Task SendTypingAsync(string sessionId, string legacyEvent, string scopedEvent)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid) || !await IsSessionParticipant(sid, userId)) return;
        var session = await db.ChatSessions.AsNoTracking().FirstAsync(s => s.Id == sid);
        await Clients.OthersInGroup(sid.ToString()).SendAsync(legacyEvent, userId);
        var recipient = session.User1Id == userId ? session.User2Id : session.User1Id;
        await Clients.User(recipient.ToString()).SendAsync(scopedEvent, new { SessionId = sid, UserId = userId });
    }

    public async Task LeaveSession(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;

        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId));

        if (session != null && session.Type != "support")
        {
            session.EndedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
            CallPresenceStore.ClearRoom(sid);
            await SessionDelivery.EndedAsync(db, Clients, sid, userId);
        }
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, sessionId);
    }

    private string CurrentCallId(string roomId) => Guid.TryParse(roomId, out var id) &&
        CallPresenceStore.TryGetPending(id, out var p) ? p!.CallId.ToString() : Guid.Empty.ToString();
    public Task RequestVideoCall(string sessionId, bool voiceOnly = false) => RequestVideoCallV2(sessionId, voiceOnly, Guid.NewGuid().ToString());
    public Task AcceptVideoCall(string sessionId) => AcceptVideoCallV2(sessionId, CurrentCallId(sessionId));
    public Task DeclineVideoCall(string sessionId, string? outcome = null) => DeclineVideoCallV2(sessionId, outcome, CurrentCallId(sessionId));
    public Task EndVideoCall(string sessionId, int durationSec = 0) => EndVideoCallV2(sessionId, durationSec, CurrentCallId(sessionId));

    public async Task RequestVideoCallV2(string sessionId, bool voiceOnly, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid) || !Guid.TryParse(callId, out var attempt) || attempt == Guid.Empty) return;
        var session = await db.ChatSessions.Include(s => s.User1).Include(s => s.User2).FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) && s.EndedAt == null && s.Type != "support");
        if (session == null || await db.Messages.AnyAsync(m => m.Id == attempt))
        { await Clients.Caller.SendAsync("VideoCallEnded", 0, sessionId, callId); return; }
        var recipientId = session.User1Id == userId ? session.User2Id : session.User1Id;
        if (await db.UserBlocks.AnyAsync(b => (b.BlockerId == userId && b.BlockedUserId == recipientId) ||
            (b.BlockerId == recipientId && b.BlockedUserId == userId))) return;
        await CallLifecycleMaintenance.PurgeAsync(db, notificationOutbox, Context.GetHttpContext()!.RequestServices);
        if (CallPresenceStore.TryGetPending(sid, out var existing) && existing!.CallId == attempt && existing.CallerId == userId) return;
        if (!CallPresenceStore.TryStart(sid, userId, recipientId, voiceOnly, attempt, out _))
        {
            if (CallPresenceStore.TryGetPending(sid, out var same) && same!.CallId == attempt && same.CallerId == userId) return;
            await PersistCallMessageAsync(sid, userId, recipientId, voiceOnly, "busy", 0, attempt);
            await Clients.Caller.SendAsync("VideoCallBusy", sessionId, callId); return;
        }
        await Clients.User(recipientId.ToString()).SendAsync("IncomingVideoCall", voiceOnly, sessionId, callId);
        var caller = session.User1Id == userId ? session.User1 : session.User2;
        await notificationOutbox.EnqueueAsync(recipientId, "video_call", voiceOnly ? "مكالمة صوتية" : "مكالمة فيديو",
            $"{caller?.Name ?? "شخص"} يطلب مكالمة", new Dictionary<string, string> {
                ["sessionId"] = sessionId, ["callId"] = callId, ["voiceOnly"] = voiceOnly ? "true" : "false", ["callerName"] = caller?.Name ?? "" });
    }

    public async Task<bool> AcceptVideoCallV2(string sessionId, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid) || !Guid.TryParse(callId, out var attempt)) return false;
        if (!await db.ChatSessions.AnyAsync(s => s.Id == sid && s.EndedAt == null && s.Type != "support" && (s.User1Id == userId || s.User2Id == userId)) ||
            !CallPresenceStore.TryAccept(sid, attempt, userId, out var p))
        { await Clients.Caller.SendAsync("VideoCallEnded", 0, sessionId, callId); return false; }
        await notificationOutbox.CancelCallPushAsync(userId, sid, p!.CallId, "answered");
        await Clients.User(p.CallerId.ToString()).SendAsync("VideoCallAccepted", sessionId, callId, p.VoiceOnly);
        return true;
    }
    public Task<bool> HeartbeatVideoCall(string sessionId, string callId) => Task.FromResult(
        TryGetUserId(out var userId) && Guid.TryParse(sessionId, out var sid) && Guid.TryParse(callId, out var attempt) &&
        CallPresenceStore.Heartbeat(sid, attempt, userId));
    public async Task DeclineVideoCallV2(string sessionId, string? outcome, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid) || !Guid.TryParse(callId, out var attempt)) return;
        if (!await db.ChatSessions.AnyAsync(s => s.Id == sid && s.Type != "support" && (s.User1Id == userId || s.User2Id == userId))) return;
        if (!CallPresenceStore.TryEnd(sid, attempt, userId, out var p)) return;
        var normalized = (outcome ?? "").Trim().ToLowerInvariant();
        var status = p!.Accepted ? "ended" : normalized switch { "missed" or "no_answer" or "noanswer" => "missed",
            "cancelled" or "declined" or "ended" or "busy" => normalized, _ => userId == p.CallerId ? "cancelled" : "declined" };
        await CompleteCallAsync(sid, p, status);
    }
    public async Task EndVideoCallV2(string sessionId, int durationSec, string callId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid) || !Guid.TryParse(callId, out var attempt)) return;
        if (!await db.ChatSessions.AnyAsync(s => s.Id == sid && s.Type != "support" && (s.User1Id == userId || s.User2Id == userId))) return;
        if (!CallPresenceStore.TryEnd(sid, attempt, userId, out var p)) return;
        await CompleteCallAsync(sid, p!, p!.Accepted ? "ended" : "cancelled");
    }
    private async Task CompleteCallAsync(Guid sid, CallPresenceStore.PendingCall p, string status)
    {
        var secs = CallPresenceStore.Duration(p);
        // Recipient comes from the attempt, never from the identity of the hangup actor.
        await PersistCallMessageAsync(sid, p.CallerId, p.RecipientId, p.VoiceOnly, status, secs, p.CallId);
        await notificationOutbox.CancelCallPushAsync(p.CallerId, sid, p.CallId);
        await notificationOutbox.CancelCallPushAsync(p.RecipientId, sid, p.CallId);
        foreach (var user in new[] { p.CallerId, p.RecipientId })
            await Clients.User(user.ToString()).SendAsync("VideoCallEnded", secs, sid.ToString(), p.CallId.ToString());
    }

    public static async Task<bool> DeclineFromHttpAsync(IServiceScopeFactory scopes, Guid userId, Guid sessionId,
        string? outcome, Guid? callId)
    {
        if (callId == null || callId == Guid.Empty) return true;
        await using var scope = scopes.CreateAsyncScope();
        var sp = scope.ServiceProvider;
        var db = sp.GetRequiredService<AppDbContext>();
        if (!await db.ChatSessions.AnyAsync(s => s.Id == sessionId && s.Type != "support" && (s.User1Id == userId || s.User2Id == userId))) return false;
        if (!CallPresenceStore.TryEnd(sessionId, callId.Value, userId, out var p)) return true;
        var secs = CallPresenceStore.Duration(p!);
        var normalized = (outcome ?? "").Trim().ToLowerInvariant();
        var status = p!.Accepted ? "ended" : normalized switch { "missed" or "no_answer" or "noanswer" => "missed",
            "cancelled" or "declined" or "busy" => normalized, _ => userId == p.CallerId ? "cancelled" : "declined" };
        var hub = sp.GetRequiredService<IHubContext<ChatHub>>();
        try
        {
            if (!await db.Messages.AnyAsync(m => m.Id == p.CallId))
            {
                var msg = new Message { Id = p.CallId, SessionId = sessionId, SenderId = p.CallerId, Type = "call",
                    Content = JsonSerializer.Serialize(new { status, voiceOnly = p.VoiceOnly, durationSec = secs }) };
                db.Messages.Add(msg); await db.SaveChangesAsync();
                await hub.Clients.Group(sessionId.ToString()).SendAsync("ReceiveMessage", new { msg.Id, msg.SessionId,
                    msg.SenderId, msg.Type, msg.Content, msg.SentAt, ClientMessageId = (string?)null });
            }
        }
        catch (Exception ex) { sp.GetRequiredService<ILogger<ChatHub>>().LogError(ex, "Persist native random call {CallId}", p.CallId); }
        var outbox = sp.GetRequiredService<NotificationOutboxService>();
        await outbox.CancelCallPushAsync(p.CallerId, sessionId, p.CallId);
        await outbox.CancelCallPushAsync(p.RecipientId, sessionId, p.CallId);
        foreach (var user in new[] { p.CallerId, p.RecipientId })
            await hub.Clients.User(user.ToString()).SendAsync("VideoCallEnded", secs, sessionId.ToString(), p.CallId.ToString());
        return true;
    }

    private async Task PersistCallMessageAsync(
        Guid sessionId,
        Guid callerId,
        Guid otherUserId,
        bool voiceOnly,
        string status,
        int durationSec,
        Guid callId)
    {
        try
        {
            if (otherUserId == callerId || await db.Messages.AnyAsync(m => m.Id == callId)) return;
            var plain = JsonSerializer.Serialize(new { status, voiceOnly, durationSec });
            var message = new Message
            {
                Id = callId,
                SessionId = sessionId,
                SenderId = callerId,
                Content = plain,
                Type = "call",
            };
            db.Messages.Add(message);
            await db.SaveChangesAsync();
            await Clients.Group(sessionId.ToString()).SendAsync("ReceiveMessage", new
            {
                message.Id,
                message.SessionId,
                message.ClientMessageId,
                message.SenderId,
                message.Content,
                message.Type,
                message.SentAt
            });
        }
        catch
        {
            // Don't fail signaling if history write fails.
        }
    }

    public async Task ReportUser(string sessionId, string reason, string? reportedMessageContent = null)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;

        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId));

        if (session == null) return;

        var reportedId = session.User1Id == userId ? session.User2Id : session.User1Id;
        var reportedUser = await db.Users.FindAsync(reportedId);
        if (reportedUser?.IsFeatured == true)
            return;

        var alreadyReported = await db.Reports.AnyAsync(r =>
            r.ReporterId == userId && r.ReportedId == reportedId);
        if (alreadyReported) return;

        var r = reason.Trim();
        if (!string.IsNullOrWhiteSpace(reportedMessageContent))
        {
            var snap = reportedMessageContent.Length > 350
                ? reportedMessageContent[..350] + "…"
                : reportedMessageContent;
            r = $"[Content] {snap}\n{r}";
        }

        if (r.Length > 500)
            r = r[..500];

        db.Reports.Add(new Report
        {
            ReporterId = userId,
            ReportedId = reportedId,
            Reason = r
        });
        await db.SaveChangesAsync();
        await Clients.Caller.SendAsync("ReportSent");
    }
}
