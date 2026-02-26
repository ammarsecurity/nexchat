using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using NexChat.Infrastructure.Services;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class WebRtcHub(AppDbContext db, MatchingService matching) : Hub
{
    private Guid CurrentUserId =>
        Guid.Parse(Context.User!.FindFirstValue(ClaimTypes.NameIdentifier)!);

    private async Task<string?> GetPartnerConnectionId(Guid sessionId)
    {
        var userId = CurrentUserId;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sessionId && (s.User1Id == userId || s.User2Id == userId));

        if (session == null) return null;

        var partnerId = session.User1Id == userId ? session.User2Id : session.User1Id;
        return await matching.GetConnectionIdAsync(partnerId);
    }

    public async Task SendOffer(string sessionId, object offer)
    {
        var partnerConn = await GetPartnerConnectionId(Guid.Parse(sessionId));
        if (partnerConn != null)
            await Clients.Client(partnerConn).SendAsync("ReceiveOffer", sessionId, offer);
    }

    public async Task SendAnswer(string sessionId, object answer)
    {
        var partnerConn = await GetPartnerConnectionId(Guid.Parse(sessionId));
        if (partnerConn != null)
            await Clients.Client(partnerConn).SendAsync("ReceiveAnswer", sessionId, answer);
    }

    public async Task SendIceCandidate(string sessionId, object candidate)
    {
        var partnerConn = await GetPartnerConnectionId(Guid.Parse(sessionId));
        if (partnerConn != null)
            await Clients.Client(partnerConn).SendAsync("ReceiveIceCandidate", sessionId, candidate);
    }
}
