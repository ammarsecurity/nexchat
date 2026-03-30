using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.API.Services;
using NexChat.Core;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[EnableRateLimiting("api")]
public class UserController(
    AppDbContext db,
    IHubContext<ConversationHub> conversationHub,
    IHubContext<MatchingHub> matchingHub,
    IHubContext<ChatHub> chatHub) : ControllerBase
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

    /// <summary>بروفايل عام لمستخدم آخر (للعرض فقط، بدون هاتف أو تاريخ ميلاد).</summary>
    [HttpGet("profile/{userId:guid}")]
    public async Task<ActionResult<PublicProfileDto>> GetPublicProfile(Guid userId)
    {
        if (userId == CurrentUserId)
            return BadRequest(new { message = "استخدم /user/me لملفك الشخصي" });
        var user = await db.Users.FindAsync(userId);
        if (user == null || user.IsBanned) return NotFound();
        var blocked = await db.UserBlocks
            .AnyAsync(b => (b.BlockerId == CurrentUserId && b.BlockedUserId == userId) ||
                           (b.BlockerId == userId && b.BlockedUserId == CurrentUserId));
        if (blocked) return NotFound();
        var isContact = await db.Contacts
            .AnyAsync(c => c.UserId == CurrentUserId && c.ContactUserId == userId);
        var visibleOnline = UserOnlineVisibility.VisibleToOthers(user);
        return Ok(new PublicProfileDto(
            user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar, user.IsFeatured, visibleOnline,
            user.PhoneNumber, user.Country, isContact
        ));
    }

    [HttpPut("privacy")]
    public async Task<IActionResult> UpdatePrivacy([FromBody] UpdatePrivacyRequest req)
    {
        await db.Users
            .Where(u => u.Id == CurrentUserId)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.ShowOnlineStatusToOthers, req.ShowOnlineStatusToOthers));
        return Ok();
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

        if (!PhoneValidationService.TryValidate(countryCode, phone, out var fullPhone, out var phoneError))
            return BadRequest(new { message = phoneError });

        var duplicatePhone = await db.Users
            .AnyAsync(u => u.PhoneNumber == fullPhone && u.Id != CurrentUserId);
        if (duplicatePhone)
            return Conflict(new { message = "رقم الهاتف مستخدم من قبل حساب آخر" });

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

        var user = await db.Users.AsNoTracking()
            .Select(u => new { u.Id, u.UniqueCode })
            .FirstOrDefaultAsync(u => u.Id == CurrentUserId);
        if (user == null) return Ok();

        var recipients = await GetAvatarNotifyRecipientIdsAsync(CurrentUserId);
        var payload = new { userId = CurrentUserId, avatar, uniqueCode = user.UniqueCode };
        foreach (var rid in recipients)
        {
            var ridStr = rid.ToString();
            await conversationHub.Clients.User(ridStr).SendAsync("UserAvatarUpdated", payload);
            await matchingHub.Clients.User(ridStr).SendAsync("UserAvatarUpdated", payload);
            await chatHub.Clients.User(ridStr).SendAsync("UserAvatarUpdated", payload);
        }

        return Ok();
    }

    /// <summary>جهات الاتصال، شركاء المحادثات، أعضاء المجموعات، وشريك الدردشة العشوائية النشطة.</summary>
    private async Task<List<Guid>> GetAvatarNotifyRecipientIdsAsync(Guid userId)
    {
        var recipients = new HashSet<Guid>();

        var contactPeers = await db.Contacts
            .AsNoTracking()
            .Where(c => c.UserId == userId || c.ContactUserId == userId)
            .Select(c => c.UserId == userId ? c.ContactUserId : c.UserId)
            .ToListAsync();
        foreach (var id in contactPeers) recipients.Add(id);

        var privatePeers = await db.Conversations
            .AsNoTracking()
            .Where(c => c.Type == ConversationType.Private && (c.User1Id == userId || c.User2Id == userId))
            .Select(c => c.User1Id == userId ? c.User2Id!.Value : c.User1Id!.Value)
            .ToListAsync();
        foreach (var id in privatePeers) recipients.Add(id);

        var myGroupConvIds = await db.ConversationMembers
            .AsNoTracking()
            .Where(m => m.UserId == userId)
            .Select(m => m.ConversationId)
            .ToListAsync();
        if (myGroupConvIds.Count > 0)
        {
            var groupPeers = await db.ConversationMembers
                .AsNoTracking()
                .Where(m => myGroupConvIds.Contains(m.ConversationId) && m.UserId != userId)
                .Select(m => m.UserId)
                .ToListAsync();
            foreach (var id in groupPeers) recipients.Add(id);
        }

        var randomPartners = await db.ChatSessions
            .AsNoTracking()
            .Where(s => s.EndedAt == null && (s.User1Id == userId || s.User2Id == userId))
            .Select(s => s.User1Id == userId ? s.User2Id : s.User1Id)
            .ToListAsync();
        foreach (var id in randomPartners) recipients.Add(id);

        recipients.Remove(userId);
        return recipients.ToList();
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

            var convIds = await db.Conversations
                .Where(c => c.User1Id == user.Id || c.User2Id == user.Id)
                .Select(c => c.Id)
                .ToListAsync();
            await db.UserMessageDeletions.Where(d => d.UserId == user.Id).ExecuteDeleteAsync();
            await db.UserConversationDeletions.Where(d => d.UserId == user.Id).ExecuteDeleteAsync();
            await db.UserConversationStates.Where(s => s.UserId == user.Id).ExecuteDeleteAsync();
            await db.ConversationMessages.Where(m => convIds.Contains(m.ConversationId)).ExecuteDeleteAsync();
            await db.Conversations.Where(c => c.User1Id == user.Id || c.User2Id == user.Id).ExecuteDeleteAsync();
            await db.Contacts.Where(c => c.UserId == user.Id || c.ContactUserId == user.Id).ExecuteDeleteAsync();

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
