using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class ChatHub(AppDbContext db) : Hub
{
    private bool TryGetUserId(out Guid userId)
    {
        var id = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out userId);
    }

    public async Task JoinSession(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
        {
            await Clients.Caller.SendAsync("Error", "Invalid request");
            return;
        }
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

        await Groups.AddToGroupAsync(Context.ConnectionId, sessionId);

        // Send recent messages
        var messages = await db.Messages
            .Where(m => m.SessionId == sid)
            .OrderBy(m => m.SentAt)
            .Select(m => new { m.Id, m.SenderId, m.Content, m.Type, m.SentAt })
            .ToListAsync();

        await Clients.Caller.SendAsync("SessionJoined", new
        {
            session.Id,
            Partner = session.User1Id == userId
                ? new { session.User2.Name, session.User2.Gender, session.User2.UniqueCode, session.User2.Avatar }
                : new { session.User1.Name, session.User1.Gender, session.User1.UniqueCode, session.User1.Avatar },
            Messages = messages
        });
    }

    public async Task SendMessage(string sessionId, string content, string type = "text")
    {
        if (string.IsNullOrWhiteSpace(content) || content.Length > 5000) return;
        if (type != "text" && type != "image") type = "text";

        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;

        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            (s.EndedAt == null || s.Type == "support"));

        if (session == null) return;

        var message = new Message
        {
            SessionId = sid,
            SenderId = userId,
            Content = type == "text" ? content.Trim() : content,
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
        }

        if (session?.Type != "support")
            await Clients.Group(sessionId).SendAsync("SessionEnded", userId);
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, sessionId);
    }

    public async Task RequestVideoCall(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            (s.EndedAt == null || s.Type == "support"));
        if (session == null) return;
        await Clients.OthersInGroup(sessionId).SendAsync("IncomingVideoCall");
    }

    public async Task AcceptVideoCall(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            (s.EndedAt == null || s.Type == "support"));
        if (session == null) return;
        await Clients.OthersInGroup(sessionId).SendAsync("VideoCallAccepted");
    }

    public async Task DeclineVideoCall(string sessionId)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) &&
            (s.EndedAt == null || s.Type == "support"));
        if (session == null) return;
        await Clients.OthersInGroup(sessionId).SendAsync("VideoCallDeclined");
    }

    public async Task ReportUser(string sessionId, string reason)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionId, out var sid))
            return;

        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId));

        if (session == null) return;

        var reportedId = session.User1Id == userId ? session.User2Id : session.User1Id;

        var alreadyReported = await db.Reports.AnyAsync(r =>
            r.ReporterId == userId && r.ReportedId == reportedId);
        if (alreadyReported) return;

        db.Reports.Add(new Report
        {
            ReporterId = userId,
            ReportedId = reportedId,
            Reason = reason.Length > 500 ? reason[..500] : reason
        });
        await db.SaveChangesAsync();
        await Clients.Caller.SendAsync("ReportSent");
    }
}
