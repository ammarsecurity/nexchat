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
            user.UniqueCode, user.IsOnline, user.Avatar, user.CreatedAt, user.IsFeatured, user.BirthDate,
            user.Country, user.PhoneNumber
        ));
    }

    [HttpPut("birth-date")]
    public async Task<IActionResult> UpdateBirthDate([FromBody] UpdateBirthDateRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.BirthDate))
            return BadRequest(new { message = "تاريخ الميلاد مطلوب" });

        if (!DateOnly.TryParse(req.BirthDate, out var birthDate))
            return BadRequest(new { message = "تاريخ الميلاد غير صالح" });

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var age = today.Year - birthDate.Year;
        if (birthDate > today.AddYears(-age)) age--;
        if (age < 18)
            return BadRequest(new { message = "يجب أن يكون عمرك 18 عاماً أو أكثر" });

        await db.Users
            .Where(u => u.Id == CurrentUserId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.BirthDate, birthDate));

        return Ok();
    }

    [HttpPut("profile-contact")]
    public async Task<IActionResult> UpdateProfileContact([FromBody] UpdateProfileContactRequest req)
    {
        var country = (req.Country ?? "").Trim().ToUpperInvariant();
        var countryCode = (req.CountryCode ?? "").Trim().TrimStart('+');
        var phone = (req.PhoneNumber ?? "").Trim().Replace(" ", "").Replace("-", "");

        if (country.Length != 2)
            return BadRequest(new { message = "كود الدولة يجب أن يكون حرفين (مثل IQ, SA)" });

        if (string.IsNullOrEmpty(countryCode) || countryCode.Length > 4)
            return BadRequest(new { message = "مفتاح الدولة غير صالح" });

        if (string.IsNullOrEmpty(phone) || phone.Length < 7 || phone.Length > 15)
            return BadRequest(new { message = "رقم الهاتف يجب أن يكون بين 7 و 15 رقماً" });

        if (!phone.All(char.IsDigit))
            return BadRequest(new { message = "رقم الهاتف يجب أن يحتوي على أرقام فقط" });

        var fullPhone = countryCode + phone;
        if (fullPhone.Length > 20)
            return BadRequest(new { message = "رقم الهاتف طويل جداً" });

        await db.Users
            .Where(u => u.Id == CurrentUserId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.Country, country)
                .SetProperty(u => u.PhoneNumber, fullPhone));

        return Ok();
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
        if (user == null)
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
        if (user == null)
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
        if (user == null)
            return Forbid();

        var normalized = code.Trim().ToUpper();
        var rows = await db.SavedCodes
            .Where(s => s.UserId == CurrentUserId && s.Code == normalized)
            .ExecuteDeleteAsync();

        return rows > 0 ? Ok() : NotFound();
    }

    /// <summary>
    /// سجل اتصالات الكود: sent=المرسلة، received=المستلمة (المقبولة)، missed=الفائتة
    /// </summary>
    [HttpGet("connection-history")]
    public async Task<ActionResult<IEnumerable<object>>> GetConnectionHistory([FromQuery] string filter = "sent")
    {
        var userId = CurrentUserId;
        var f = filter.ToLowerInvariant();

        if (f == "sent")
        {
            var list = await db.CodeConnectionAttempts
                .Where(a => a.RequesterId == userId)
                .OrderByDescending(a => a.CreatedAt)
                .Select(a => new { a.Id, a.Status, a.CreatedAt, a.SessionId, OtherUserId = a.TargetId, OtherName = a.Target!.Name, OtherCode = a.Target.UniqueCode, OtherAvatar = a.Target.Avatar })
                .Take(100)
                .ToListAsync();
            return Ok(list);
        }
        if (f == "received")
        {
            var list = await db.CodeConnectionAttempts
                .Where(a => a.TargetId == userId && a.Status == "Accepted")
                .OrderByDescending(a => a.CreatedAt)
                .Select(a => new { a.Id, a.Status, a.CreatedAt, a.SessionId, OtherUserId = a.RequesterId, OtherName = a.Requester!.Name, OtherCode = a.Requester.UniqueCode, OtherAvatar = a.Requester.Avatar })
                .Take(100)
                .ToListAsync();
            return Ok(list);
        }
        if (f == "missed")
        {
            var list = await db.CodeConnectionAttempts
                .Where(a => a.TargetId == userId && a.Status == "Cancelled")
                .OrderByDescending(a => a.CreatedAt)
                .Select(a => new { a.Id, a.Status, a.CreatedAt, OtherUserId = a.RequesterId, OtherName = a.Requester!.Name, OtherCode = a.Requester.UniqueCode, OtherAvatar = a.Requester.Avatar })
                .Take(100)
                .ToListAsync();
            return Ok(list);
        }
        return Ok(Array.Empty<object>());
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
            await db.CodeConnectionAttempts.Where(a => a.RequesterId == user.Id || a.TargetId == user.Id).ExecuteDeleteAsync();
            await db.SavedCodes.Where(s => s.UserId == user.Id).ExecuteDeleteAsync();
            await db.DeviceSubscriptions.Where(d => d.UserId == user.Id).ExecuteDeleteAsync();
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
