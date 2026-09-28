using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using System.Security.Claims;
using Livekit.Server.Sdk.Dotnet;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/livekit")]
[Authorize]
[EnableRateLimiting("api")]
public class LiveKitController(
    AppDbContext db,
    IConfiguration config,
    OfficialAnnouncementConversationService officialAnnouncements,
    SupportConversationService supportConversations) : ControllerBase
{
    [HttpPost("token")]
    public async Task<IActionResult> GetToken([FromBody] LiveKitTokenRequest req)
    {
        if (string.IsNullOrEmpty(req?.RoomName))
            return BadRequest(new { message = "RoomName مطلوب" });

        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdStr) || !Guid.TryParse(userIdStr, out var userId) || !Guid.TryParse(req.RoomName, out var roomId))
            return Unauthorized();

        var allowed = false;

        var session = await db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == roomId && (s.User1Id == userId || s.User2Id == userId) &&
            s.EndedAt == null &&
            s.Type != "support");

        if (session != null)
        {
            var other = session.User1Id == userId ? session.User2Id : session.User1Id;
            var blocked = await db.UserBlocks.AnyAsync(b =>
                (b.BlockerId == userId && b.BlockedUserId == other) ||
                (b.BlockerId == other && b.BlockedUserId == userId));
            allowed = !blocked;
        }
        else
        {
            var conv = await db.Conversations.FirstOrDefaultAsync(c =>
                c.Id == roomId &&
                c.Type == ConversationType.Private &&
                (c.User1Id == userId || c.User2Id == userId));
            if (conv != null)
            {
                var deleted = await db.UserConversationDeletions
                    .AnyAsync(d => d.UserId == userId && d.ConversationId == roomId);
                var official = await officialAnnouncements.IsOfficialConversationAsync(roomId);
                var support = await supportConversations.IsSupportConversationAsync(roomId);
                var otherId = conv.User1Id == userId ? conv.User2Id : conv.User1Id;
                var blocked = otherId != null && await db.UserBlocks.AnyAsync(b =>
                    (b.BlockerId == userId && b.BlockedUserId == otherId) ||
                    (b.BlockerId == otherId && b.BlockedUserId == userId));
                if (!deleted && !official && !support && !blocked)
                    allowed = true;
            }
        }

        if (!allowed)
            return StatusCode(403, new { message = "لا يمكن الانضمام للمكالمة. تأكد أن الجلسة أو المحادثة نشطة وأنك طرف فيها." });

        var apiKey = config["LiveKit:ApiKey"];
        var apiSecret = config["LiveKit:ApiSecret"];
        var url = config["LiveKit:Url"] ?? "wss://livelik.tanfeeth-iq.tech";

        if (string.IsNullOrEmpty(apiKey) || string.IsNullOrEmpty(apiSecret))
            return StatusCode(500, new { message = "LiveKit غير مُعد بشكل صحيح" });

        var identity = userId.ToString("N");
        var token = new AccessToken(apiKey, apiSecret)
            .WithIdentity(identity)
            .WithGrants(new VideoGrants
            {
                RoomJoin = true,
                Room = req.RoomName,
                CanPublish = true,
                CanSubscribe = true
            })
            .WithTtl(TimeSpan.FromHours(1));

        var jwt = token.ToJwt();

        return Ok(new { token = jwt, url });
    }
}

public record LiveKitTokenRequest(string RoomName);
