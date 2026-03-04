using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[EnableRateLimiting("api")]
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
            user.UniqueCode, user.IsOnline, user.Avatar, user.CreatedAt, user.IsFeatured
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

    [HttpGet("saved-codes")]
    public async Task<ActionResult<IEnumerable<object>>> GetSavedCodes()
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null || !user.IsFeatured)
            return Forbid();

        var codes = await db.SavedCodes
            .Where(s => s.UserId == CurrentUserId)
            .OrderByDescending(s => s.AddedAt)
            .Select(s => new { s.Code, s.Label, s.AddedAt })
            .ToListAsync();

        return Ok(codes);
    }

    [HttpPost("saved-codes")]
    public async Task<IActionResult> AddSavedCode([FromBody] AddSavedCodeRequest req)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null || !user.IsFeatured)
            return Forbid();

        var code = (req.Code ?? "").Trim().ToUpper();
        if (string.IsNullOrEmpty(code) || !code.StartsWith("NX-") || code.Length != 7)
            return BadRequest(new { message = "كود غير صالح" });

        var targetExists = await db.Users.AnyAsync(u => u.UniqueCode == code);
        if (!targetExists)
            return BadRequest(new { message = "المستخدم غير موجود" });

        if (code == user.UniqueCode)
            return BadRequest(new { message = "لا يمكن إضافة كودك" });

        var exists = await db.SavedCodes.AnyAsync(s => s.UserId == CurrentUserId && s.Code == code);
        if (exists)
            return Conflict(new { message = "الكود مضاف مسبقاً" });

        db.SavedCodes.Add(new NexChat.Core.Entities.SavedCode
        {
            UserId = CurrentUserId,
            Code = code,
            Label = req.Label?.Length > 50 ? req.Label[..50] : req.Label
        });
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpDelete("saved-codes/{code}")]
    public async Task<IActionResult> RemoveSavedCode(string code)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null || !user.IsFeatured)
            return Forbid();

        var normalized = code.Trim().ToUpper();
        var rows = await db.SavedCodes
            .Where(s => s.UserId == CurrentUserId && s.Code == normalized)
            .ExecuteDeleteAsync();

        return rows > 0 ? Ok() : NotFound();
    }

    [HttpDelete("account")]
    public async Task<IActionResult> DeleteAccount([FromBody] DeleteAccountRequest req)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();

        if (!BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
            return BadRequest(new { message = "كلمة المرور غير صحيحة" });

        if (user.IsAdmin)
            return BadRequest(new { message = "لا يمكن حذف حساب الأدمن" });

        using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            var sessions = await db.ChatSessions
                .Where(s => s.User1Id == user.Id || s.User2Id == user.Id)
                .Select(s => s.Id)
                .ToListAsync();
            await db.Messages.Where(m => sessions.Contains(m.SessionId)).ExecuteDeleteAsync();
            await db.ChatSessions.Where(s => s.User1Id == user.Id || s.User2Id == user.Id).ExecuteDeleteAsync();
            await db.Reports.Where(r => r.ReporterId == user.Id || r.ReportedId == user.Id).ExecuteDeleteAsync();
            await db.Users.Where(u => u.Id == user.Id).ExecuteDeleteAsync();
            await transaction.CommitAsync();
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }

        return Ok();
    }
}
