using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using NexChat.API.Services;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/user-notifications")]
[Authorize]
[EnableRateLimiting("api")]
public class UserNotificationsController(AppDbContext db, IOptions<NotificationFeaturesOptions> features) : ControllerBase
{
    private Guid CurrentUserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    private bool FeatureEnabled => features.Value.ServerNotificationCenterEnabled;

    [HttpGet]
    public async Task<IActionResult> GetList([FromQuery] int take = 30, [FromQuery] int skip = 0)
    {
        if (!FeatureEnabled) return Ok(Array.Empty<object>());
        take = Math.Clamp(take, 1, 100);
        skip = Math.Max(0, skip);

        var list = await db.UserNotifications
            .AsNoTracking()
            .Where(x => x.UserId == CurrentUserId)
            .OrderByDescending(x => x.CreatedAt)
            .Skip(skip)
            .Take(take)
            .Select(x => new
            {
                x.Id,
                x.Type,
                x.Title,
                x.Body,
                x.DataJson,
                x.IsRead,
                x.CreatedAt,
                x.ReadAt
            })
            .ToListAsync();
        return Ok(list);
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> GetUnreadCount()
    {
        if (!FeatureEnabled) return Ok(new { count = 0 });
        var count = await db.UserNotifications.CountAsync(x => x.UserId == CurrentUserId && !x.IsRead);
        return Ok(new { count });
    }

    [HttpPut("{id:guid}/read")]
    public async Task<IActionResult> MarkRead(Guid id)
    {
        if (!FeatureEnabled) return Ok(new { updated = 0 });
        var rows = await db.UserNotifications
            .Where(x => x.Id == id && x.UserId == CurrentUserId && !x.IsRead)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.IsRead, true)
                .SetProperty(x => x.ReadAt, DateTime.UtcNow));
        return Ok(new { updated = rows });
    }

    [HttpPut("read-all")]
    public async Task<IActionResult> MarkAllRead()
    {
        if (!FeatureEnabled) return Ok(new { updated = 0 });
        var rows = await db.UserNotifications
            .Where(x => x.UserId == CurrentUserId && !x.IsRead)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.IsRead, true)
                .SetProperty(x => x.ReadAt, DateTime.UtcNow));
        return Ok(new { updated = rows });
    }
}
