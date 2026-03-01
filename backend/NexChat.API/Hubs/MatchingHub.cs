using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using NexChat.Infrastructure.Services;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class MatchingHub(MatchingService matching, AppDbContext db) : Hub
{
    private bool TryGetUserId(out Guid userId)
    {
        var id = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out userId);
    }

    public override async Task OnConnectedAsync()
    {
        if (!TryGetUserId(out var userId))
        {
            Context.Abort();
            return;
        }
        await matching.SetUserOnlineAsync(userId, Context.ConnectionId);

        await db.Users
            .Where(u => u.Id == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, true));

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        if (!TryGetUserId(out var userId))
        {
            await base.OnDisconnectedAsync(exception);
            return;
        }
        await matching.SetUserOfflineAsync(userId);

        await db.Users
            .Where(u => u.Id == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, false));

        await base.OnDisconnectedAsync(exception);
    }

    public async Task StartSearching(string genderFilter)
    {
        if (!TryGetUserId(out var userId))
        {
            await Clients.Caller.SendAsync("Error", "Invalid request");
            return;
        }
        var user = await db.Users.FindAsync(userId);
        if (user == null || user.IsBanned)
        {
            await Clients.Caller.SendAsync("Error", "Access denied");
            return;
        }

        await Clients.Caller.SendAsync("SearchStarted");

        var session = await matching.TryMatchAsync(userId, genderFilter, Context.ConnectionId);

        if (session != null)
        {
            var partnerId = session.User1Id == userId ? session.User2Id : session.User1Id;
            var partner = await db.Users.FindAsync(partnerId);
            var partnerConnectionId = await matching.GetConnectionIdAsync(partnerId);

            await Clients.Caller.SendAsync("MatchFound", new
            {
                SessionId = session.Id.ToString(),
                Partner = new { partner!.Name, partner.Gender, partner.UniqueCode, partner.Avatar }
            });

            if (partnerConnectionId != null)
                await Clients.Client(partnerConnectionId).SendAsync("MatchFound", new
                {
                    SessionId = session.Id.ToString(),
                    Partner = new { user.Name, user.Gender, user.UniqueCode, user.Avatar }
                });
        }
    }

    public async Task CancelSearching()
    {
        if (!TryGetUserId(out var userId))
            return;
        await matching.RemoveFromQueueAsync(userId);
        await Clients.Caller.SendAsync("SearchCancelled");
    }

    public async Task ConnectByCode(string code)
    {
        if (!TryGetUserId(out var userId))
        {
            await Clients.Caller.SendAsync("CodeError", "Invalid request");
            return;
        }
        var (requestSent, targetId, error) = await matching.RequestConnectionByCodeAsync(userId, code.Trim().ToUpper());

        if (!requestSent)
        {
            await Clients.Caller.SendAsync("CodeError", error ?? "المستخدم غير موجود أو الكود غير صحيح");
            return;
        }

        var targetConnectionId = await matching.GetConnectionIdAsync(targetId!.Value);
        var user = await db.Users.FindAsync(userId);

        await Clients.Caller.SendAsync("ConnectionRequestSent");

        if (targetConnectionId != null && user != null)
            await Clients.Client(targetConnectionId).SendAsync("IncomingConnectionRequest", new
            {
                RequesterId = userId.ToString(),
                RequesterName = user.Name,
                RequesterGender = user.Gender,
                RequesterAvatar = user.Avatar
            });
    }

    public async Task AcceptConnectionRequest(string requesterIdStr)
    {
        if (!TryGetUserId(out var targetId))
        {
            await Clients.Caller.SendAsync("CodeError", "Invalid request");
            return;
        }
        if (!Guid.TryParse(requesterIdStr, out var requesterId))
        {
            await Clients.Caller.SendAsync("CodeError", "Invalid request");
            return;
        }

        var session = await matching.AcceptConnectionRequestAsync(targetId, requesterId);
        if (session == null)
        {
            await Clients.Caller.SendAsync("CodeError", "Request expired or invalid");
            return;
        }

        var partner = await db.Users.FindAsync(requesterId);
        var user = await db.Users.FindAsync(targetId);
        var partnerConnectionId = await matching.GetConnectionIdAsync(requesterId);

        await Clients.Caller.SendAsync("MatchFound", new
        {
            SessionId = session.Id.ToString(),
            Partner = new { partner!.Name, partner.Gender, partner.UniqueCode, partner.Avatar }
        });

        if (partnerConnectionId != null && user != null)
            await Clients.Client(partnerConnectionId).SendAsync("MatchFound", new
            {
                SessionId = session.Id.ToString(),
                Partner = new { user.Name, user.Gender, user.UniqueCode, user.Avatar }
            });
    }

    public async Task DeclineConnectionRequest(string requesterIdStr)
    {
        if (!TryGetUserId(out var targetId))
            return;
        if (!Guid.TryParse(requesterIdStr, out var requesterId))
            return;

        if (matching.DeclineConnectionRequest(targetId, requesterId))
        {
            var requesterConnectionId = await matching.GetConnectionIdAsync(requesterId);
            if (requesterConnectionId != null)
                await Clients.Client(requesterConnectionId).SendAsync("ConnectionDeclined");
        }
    }

    public async Task CancelConnectionRequest()
    {
        if (!TryGetUserId(out var requesterId))
            return;
        if (matching.CancelConnectionRequest(requesterId))
        {
            await Clients.Caller.SendAsync("ConnectionCancelled");
        }
    }
}
