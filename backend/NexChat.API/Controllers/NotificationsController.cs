using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;
using NexChat.Core.Entities;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class NotificationsController(AppDbContext db) : ControllerBase
{
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterDeviceRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.PlayerId))
            return BadRequest(new { message = "playerId مطلوب" });

        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(userIdStr, out var userId))
            return Unauthorized();

        var existing = await db.DeviceSubscriptions
            .FirstOrDefaultAsync(d => d.UserId == userId && d.OneSignalPlayerId == req.PlayerId);

        if (existing != null)
        {
            existing.Platform = req.Platform;
            existing.CreatedAt = DateTime.UtcNow;
        }
        else
        {
            db.DeviceSubscriptions.Add(new DeviceSubscription
            {
                UserId = userId,
                OneSignalPlayerId = req.PlayerId,
                Platform = req.Platform?.Length > 20 ? req.Platform[..20] : req.Platform
            });
        }

        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpPost("unregister")]
    public async Task<IActionResult> Unregister([FromBody] RegisterDeviceRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.PlayerId))
            return BadRequest(new { message = "playerId مطلوب" });

        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(userIdStr, out var userId))
            return Unauthorized();

        var rows = await db.DeviceSubscriptions
            .Where(d => d.UserId == userId && d.OneSignalPlayerId == req.PlayerId)
            .ExecuteDeleteAsync();

        return Ok(new { removed = rows });
    }
}

public record RegisterDeviceRequest(string PlayerId, string? Platform);
