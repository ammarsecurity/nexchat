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
    private Guid CurrentUserId =>
        Guid.Parse(Context.User!.FindFirstValue(ClaimTypes.NameIdentifier)!);

    public override async Task OnConnectedAsync()
    {
        var userId = CurrentUserId;
        await matching.SetUserOnlineAsync(userId, Context.ConnectionId);

        await db.Users
            .Where(u => u.Id == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, true));

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = CurrentUserId;
        await matching.SetUserOfflineAsync(userId);

        await db.Users
            .Where(u => u.Id == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsOnline, false));

        await base.OnDisconnectedAsync(exception);
    }

    public async Task StartSearching(string genderFilter)
    {
        var userId = CurrentUserId;
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
        await matching.RemoveFromQueueAsync(CurrentUserId);
        await Clients.Caller.SendAsync("SearchCancelled");
    }

    public async Task ConnectByCode(string code)
    {
        var userId = CurrentUserId;
        var session = await matching.ConnectByCodeAsync(userId, code.Trim().ToUpper());

        if (session == null)
        {
            await Clients.Caller.SendAsync("CodeError", "User not found or invalid code");
            return;
        }

        var partner = await db.Users.FindAsync(session.User2Id == userId ? session.User1Id : session.User2Id);
        var user = await db.Users.FindAsync(userId);
        var partnerConnectionId = await matching.GetConnectionIdAsync(partner!.Id);

        await Clients.Caller.SendAsync("MatchFound", new
        {
            SessionId = session.Id.ToString(),
            Partner = new { partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar }
        });

        if (partnerConnectionId != null)
            await Clients.Client(partnerConnectionId).SendAsync("MatchFound", new
            {
                SessionId = session.Id.ToString(),
                Partner = new { user!.Name, user.Gender, user.UniqueCode, user.Avatar }
            });
    }
}
