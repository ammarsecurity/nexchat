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

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        if (TryGetUserId(out var userId))
        {
            // جلسات الدعم لا تُغلق عند انقطاع الاتصال - يبقى المستخدم قادراً على متابعة المحادثة
            var activeSessions = await db.ChatSessions
                .Where(s => (s.User1Id == userId || s.User2Id == userId) &&
                    s.EndedAt == null &&
                    s.Type != "support")
                .Select(s => s.Id)
                .ToListAsync();

            if (activeSessions.Count > 0)
            {
                await db.ChatSessions
                    .Where(s => activeSessions.Contains(s.Id))
                    .ExecuteUpdateAsync(s => s.SetProperty(x => x.EndedAt, DateTime.UtcNow));

                foreach (var sid in activeSessions)
                    await Clients.Group(sid.ToString()).SendAsync("SessionEnded", userId);
            }
        }
        await base.OnDisconnectedAsync(exception);
    }

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

        await Groups.AddToGroupAsync(Context.ConnectionId, sessionId);

        // Send recent messages
        var messages = await db.Messages
            .Where(m => m.SessionId == sid)
            .OrderBy(m => m.SentAt)
            .Select(m => new { m.Id, m.SenderId, m.Content, m.Type, m.SentAt })
            .ToListAsync();

        var partnerUser = session.User1Id == userId ? session.User2 : session.User1;
        await Clients.Caller.SendAsync("SessionJoined", new
        {
            session.Id,
            Partner = new { partnerUser.Id, partnerUser.Name, partnerUser.Gender, partnerUser.UniqueCode, partnerUser.Avatar, IsFeatured = partnerUser.IsFeatured },
            Messages = messages
        });
    }

    public async Task SendMessage(string sessionId, string content, string type = "text")
    {
        if (string.IsNullOrWhiteSpace(content) || content.Length > 5000) return;
        if (type != "text" && type != "image") type = "text";

        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;

        // جلسات الدعم: يُسمح بالإرسال حتى لو كانت منتهية (للمتابعة)
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            (s.EndedAt == null || s.Type == "support"));

        if (session == null) return;

        // إعادة فتح الجلسة إذا كانت منتهية (دعم)
        if (session.EndedAt != null && session.Type == "support")
            session.EndedAt = null;

        var textBody = type == "text" ? content.Trim() : content;
        if (type == "text")
            textBody = profanity.Mask(textBody);

        var message = new Message
        {
            SessionId = sid,
            SenderId = userId,
            Content = textBody,
            Type = type
        };
        db.Messages.Add(message);
        await db.SaveChangesAsync();

        await Clients.Group(sessionId).SendAsync("ReceiveMessage", new
        {
            message.Id,
            message.SenderId,
            message.Content,
            message.Type,
            message.SentAt
        });

        var recipientId = session.User1Id == userId ? session.User2Id : session.User1Id;
        var sender = await db.Users.FindAsync(userId);
        var preview = type == "text" ? textBody : "صورة";
        if (preview.Length > 80) preview = preview[..80] + "…";
        _ = notificationOutbox.EnqueueAsync(
            recipientId,
            "message",
            sender?.Name ?? "شخص",
            preview,
            new Dictionary<string, string> { ["sessionId"] = sid.ToString() });
    }

    public async Task StartTyping(string sessionId)
    {
        if (TryGetUserId(out var userId))
            await Clients.OthersInGroup(sessionId).SendAsync("UserTyping", userId);
    }

    public async Task StopTyping(string sessionId)
    {
        if (TryGetUserId(out var userId))
            await Clients.OthersInGroup(sessionId).SendAsync("UserStoppedTyping", userId);
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
            await Clients.Group(sessionId).SendAsync("SessionEnded", userId);
        }
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, sessionId);
    }

    public async Task RequestVideoCall(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;
        var session = await db.ChatSessions.Include(s => s.User1).Include(s => s.User2)
            .FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            s.EndedAt == null &&
            s.Type != "support"); // دردشة الدعم لا تدعم اتصال الفيديو
        if (session == null) return;
        await Clients.OthersInGroup(sessionId).SendAsync("IncomingVideoCall");
        var recipientId = session.User1Id == userId ? session.User2Id : session.User1Id;
        var caller = session.User1Id == userId ? session.User1 : session.User2;
        _ = notificationOutbox.EnqueueAsync(
            recipientId,
            "video_call",
            "مكالمة فيديو",
            $"{caller?.Name ?? "شخص"} يطلب مكالمة فيديو",
            new Dictionary<string, string>
            {
                ["sessionId"] = sid.ToString(),
                ["callerName"] = caller?.Name ?? ""
            });
    }

    public async Task AcceptVideoCall(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            s.EndedAt == null &&
            s.Type != "support"); // دردشة الدعم لا تدعم اتصال الفيديو
        if (session == null) return;
        await Clients.OthersInGroup(sessionId).SendAsync("VideoCallAccepted");
    }

    public async Task DeclineVideoCall(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            s.EndedAt == null &&
            s.Type != "support"); // دردشة الدعم لا تدعم اتصال الفيديو
        if (session == null) return;
        await Clients.OthersInGroup(sessionId).SendAsync("VideoCallDeclined");
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
