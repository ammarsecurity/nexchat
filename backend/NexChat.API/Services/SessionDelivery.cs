using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

public static class SessionDelivery
{
    public static async Task EndedAsync(AppDbContext db, IHubClients<IClientProxy> clients, Guid sessionId, Guid userId)
    {
        // Scalar legacy consumers rely on room membership to identify the session.
        await clients.Group(sessionId.ToString()).SendAsync("SessionEnded", userId);
        var session = await db.ChatSessions.AsNoTracking().FirstOrDefaultAsync(s => s.Id == sessionId);
        if (session == null) return;
        var payload = new { SessionId = sessionId, UserId = userId };
        foreach (var participant in new[] { session.User1Id, session.User2Id }.Distinct())
            await clients.User(participant.ToString()).SendAsync("SessionEndedV2", payload);
    }
}
