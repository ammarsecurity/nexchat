using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class UserController(AppDbContext db) : ControllerBase
{
    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("me")]
    public async Task<ActionResult<UserProfileDto>> GetMe()
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();

        return Ok(new UserProfileDto(
            user.Id, user.Name, user.Gender,
            user.UniqueCode, user.IsOnline, user.Avatar, user.CreatedAt
        ));
    }

    [HttpPut("avatar")]
    public async Task<IActionResult> UpdateAvatar([FromBody] UpdateAvatarRequest req)
    {
        var avatar = req.Avatar?.Length > 500 ? req.Avatar[..500] : req.Avatar;

        await db.Users
            .Where(u => u.Id == CurrentUserId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.Avatar, avatar));

        return Ok();
    }
}
