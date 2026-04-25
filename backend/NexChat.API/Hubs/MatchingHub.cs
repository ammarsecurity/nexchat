using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using NexChat.Infrastructure.Services;
using NexChat.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using NexChat.API.Services;
using NexChat.Core.Entities;

namespace NexChat.API.Hubs;

[Authorize]
public class MatchingHub(MatchingService matching, AppDbContext db, NotificationOutboxService notificationOutbox) : Hub
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

        // إرسال طلبات الاتصال المعلقة التي فاتت المستخدم وهو غير متصل
        var pending = matching.GetPendingRequestsForTarget(userId);
        foreach (var (requesterId, _, _) in pending)
        {
            var requester = await db.Users.FindAsync(requesterId);
            if (requester != null)
            {
                await Clients.Caller.SendAsync("IncomingConnectionRequest", new
                {
                    RequesterId = requesterId.ToString(),
                    RequesterName = requester.Name,
                    RequesterGender = requester.Gender,
                    RequesterAvatar = requester.Avatar,
                    RequesterIsFeatured = requester.IsFeatured
                });
                break; // نرسل الأحدث فقط لتجنب تداخل النوافذ
            }
        }

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
                Partner = new { partner!.Id, partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar, IsFeatured = partner.IsFeatured },
                RequiresPairingAccept = true
            });

            if (partnerConnectionId != null)
                await Clients.Client(partnerConnectionId).SendAsync("MatchFound", new
                {
                    SessionId = session.Id.ToString(),
                    Partner = new { user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar, IsFeatured = user.IsFeatured },
                    RequiresPairingAccept = true
                });
        }
    }

    public async Task AcceptRandomMatch(string sessionIdStr)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionIdStr, out var sessionId))
        {
            await Clients.Caller.SendAsync("Error", "Invalid request");
            return;
        }

        if (!matching.TryAcceptRandomMatch(sessionId, userId, out var bothAccepted))
        {
            await Clients.Caller.SendAsync("Error", "Invalid match");
            return;
        }

        if (!bothAccepted)
            return;

        var session = await db.ChatSessions
            .Include(s => s.User1)
            .Include(s => s.User2)
            .FirstOrDefaultAsync(s => s.Id == sessionId && s.Type == "random");
        if (session == null)
            return;

        async Task SendReadyAsync(Guid targetUserId, User partnerUser)
        {
            var conn = await matching.GetConnectionIdAsync(targetUserId);
            if (conn == null) return;
            await Clients.Client(conn).SendAsync("RandomMatchReady", new
            {
                SessionId = session.Id.ToString(),
                Partner = new { partnerUser.Id, partnerUser.Name, partnerUser.Gender, partnerUser.UniqueCode, partnerUser.Avatar, IsFeatured = partnerUser.IsFeatured }
            });
        }

        await SendReadyAsync(session.User1Id, session.User2);
        await SendReadyAsync(session.User2Id, session.User1);
    }

    public async Task DeclineRandomMatch(string sessionIdStr)
    {
        if (!TryGetUserId(out var userId) || !Guid.TryParse(sessionIdStr, out var sessionId))
            return;

        var (ok, partnerId) = await matching.TryDeclineRandomMatchAsync(sessionId, userId);
        if (!ok || !partnerId.HasValue)
            return;

        await Clients.Caller.SendAsync("RandomMatchDeclined");

        var partnerConn = await matching.GetConnectionIdAsync(partnerId.Value);
        if (partnerConn != null)
            await Clients.Client(partnerConn).SendAsync("RandomMatchPartnerDeclined");
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
                RequesterAvatar = user.Avatar,
                RequesterIsFeatured = user.IsFeatured
            });

        if (user != null)
        {
            _ = notificationOutbox.EnqueueAsync(
                targetId!.Value,
                "code_connected",
                "اتصال جديد",
                $"{user.Name} اتصل بك عبر الكود",
                new Dictionary<string, string>
                {
                    ["requesterId"] = userId.ToString(),
                    ["requesterName"] = user.Name,
                    ["requesterGender"] = user.Gender ?? "",
                    ["requesterAvatar"] = user.Avatar ?? "",
                    ["requesterIsFeatured"] = user.IsFeatured ? "true" : "false"
                });
        }
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
            Partner = new { partner!.Id, partner.Name, partner.Gender, partner.UniqueCode, partner.Avatar, IsFeatured = partner.IsFeatured }
        });

        if (partnerConnectionId != null && user != null)
            await Clients.Client(partnerConnectionId).SendAsync("MatchFound", new
            {
                SessionId = session.Id.ToString(),
                Partner = new { user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar, IsFeatured = user.IsFeatured }
            });
    }

    public async Task DeclineConnectionRequest(string requesterIdStr)
    {
        if (!TryGetUserId(out var targetId))
            return;
        if (!Guid.TryParse(requesterIdStr, out var requesterId))
            return;

        if (await matching.DeclineConnectionRequestAsync(targetId, requesterId))
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
        var (success, targetId) = await matching.CancelConnectionRequestAsync(requesterId);
        if (success)
        {
            await Clients.Caller.SendAsync("ConnectionCancelled");
            if (targetId.HasValue)
            {
                var targetConnectionId = await matching.GetConnectionIdAsync(targetId.Value);
                if (targetConnectionId != null)
                    await Clients.Client(targetConnectionId).SendAsync("ConnectionRequestExpired");
            }
        }
    }
}
