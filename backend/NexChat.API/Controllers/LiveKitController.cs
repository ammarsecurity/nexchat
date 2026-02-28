using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;
using System.Security.Claims;
using Livekit.Server.Sdk.Dotnet;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/livekit")]
[Authorize]
public class LiveKitController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;

    public LiveKitController(AppDbContext db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    [HttpPost("token")]
    public async Task<IActionResult> GetToken([FromBody] LiveKitTokenRequest req)
    {
        if (string.IsNullOrEmpty(req?.RoomName))
            return BadRequest(new { message = "RoomName مطلوب" });

        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdStr))
            return Unauthorized();

        var userId = Guid.Parse(userIdStr);
        var sessionId = Guid.Parse(req.RoomName);

        var session = await _db.ChatSessions.FirstOrDefaultAsync(s =>
            s.Id == sessionId && (s.User1Id == userId || s.User2Id == userId) && s.EndedAt == null);

        if (session == null)
            return Forbid();

        var apiKey = _config["LiveKit:ApiKey"];
        var apiSecret = _config["LiveKit:ApiSecret"];
        var url = _config["LiveKit:Url"] ?? "wss://livelik.tanfeeth-iq.tech";

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
