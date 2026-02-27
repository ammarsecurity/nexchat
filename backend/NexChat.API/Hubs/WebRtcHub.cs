using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class WebRtcHub(AppDbContext db) : Hub
{
    private Guid CurrentUserId =>
        Guid.Parse(Context.User!.FindFirstValue(ClaimTypes.NameIdentifier)!);

    private const string VideoGroupPrefix = "webrtc:";

    public async Task JoinVideoSession(string sessionId)
    {
        var sid = Guid.Parse(sessionId);
        var userId = CurrentUserId;
        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sid && (s.User1Id == userId || s.User2Id == userId) && s.EndedAt == null);

        if (session == null)
        {
            await Clients.Caller.SendAsync("Error", "Session not found");
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, VideoGroupPrefix + sessionId);
    }

    public async Task SendOffer(string sessionId, object offer)
    {
        await Clients.OthersInGroup(VideoGroupPrefix + sessionId).SendAsync("ReceiveOffer", sessionId, offer);
    }

    public async Task SendAnswer(string sessionId, object answer)
    {
        await Clients.OthersInGroup(VideoGroupPrefix + sessionId).SendAsync("ReceiveAnswer", sessionId, answer);
    }

    public async Task SendIceCandidate(string sessionId, object candidate)
    {
        await Clients.OthersInGroup(VideoGroupPrefix + sessionId).SendAsync("ReceiveIceCandidate", sessionId, candidate);
    }
}
