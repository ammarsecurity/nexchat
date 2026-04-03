using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[EnableRateLimiting("api")]
public class BlocksController(AppDbContext db) : ControllerBase
{
    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<ActionResult<IEnumerable<BlockedUserDto>>> GetBlocked()
    {
        var list = await db.UserBlocks
            .Where(b => b.BlockerId == CurrentUserId)
            .Include(b => b.BlockedUser)
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => new BlockedUserDto(
                b.Id,
                b.BlockedUserId,
                b.BlockedUser.Name,
                b.BlockedUser.Avatar,
                b.BlockedUser.UniqueCode,
                b.CreatedAt
            ))
            .ToListAsync();
        return Ok(list);
    }

    [HttpPost("{userId:guid}")]
    public async Task<IActionResult> Block(Guid userId)
    {
        if (userId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن حظر نفسك" });

        var target = await db.Users.FindAsync(userId);
        if (target == null)
            return NotFound(new { message = "المستخدم غير موجود" });

        var exists = await db.UserBlocks.AnyAsync(b =>
            b.BlockerId == CurrentUserId && b.BlockedUserId == userId);
        if (exists)
            return Conflict(new { message = "المستخدم محظور مسبقاً" });

        await db.Contacts
            .Where(c =>
                (c.UserId == CurrentUserId && c.ContactUserId == userId) ||
                (c.UserId == userId && c.ContactUserId == CurrentUserId))
            .ExecuteDeleteAsync();

        db.UserBlocks.Add(new UserBlock
        {
            BlockerId = CurrentUserId,
            BlockedUserId = userId
        });
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpDelete("{userId:guid}")]
    public async Task<IActionResult> Unblock(Guid userId)
    {
        var rows = await db.UserBlocks
            .Where(b => b.BlockerId == CurrentUserId && b.BlockedUserId == userId)
            .ExecuteDeleteAsync();
        return rows > 0 ? Ok() : NotFound();
    }
}
