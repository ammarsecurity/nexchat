using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[EnableRateLimiting("api")]
public class ContactsController(AppDbContext db) : ControllerBase
{
    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<ActionResult<IEnumerable<ContactDto>>> GetContacts()
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();
        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً لاستخدام جهات الاتصال" });

        var blockedIds = await db.UserBlocks
            .Where(b => b.BlockerId == CurrentUserId)
            .Select(b => b.BlockedUserId)
            .ToListAsync();
        var contacts = await db.Contacts
            .Where(c => c.UserId == CurrentUserId && !blockedIds.Contains(c.ContactUserId))
            .Include(c => c.ContactUser)
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new ContactDto(
                c.Id,
                c.ContactUserId,
                c.ContactUser.Name,
                c.ContactUser.Avatar,
                c.ContactUser.PhoneNumber,
                c.ContactUser.UniqueCode,
                c.CreatedAt
            ))
            .ToListAsync();

        return Ok(contacts);
    }

    /// <summary>
    /// مطابقة أرقام من سجل هاتف الجهاز مع مستخدمي NexChat.
    /// يُرسل العميل قائمة أرقام (مع الاسم الاختياري من الجهاز) ويعيد من لديهم حساب.
    /// </summary>
    [HttpPost("lookup")]
    public async Task<ActionResult<IEnumerable<PhoneLookupMatchDto>>> LookupContacts([FromBody] PhoneLookupRequest req)
    {
        var me = await db.Users.FindAsync(CurrentUserId);
        if (me == null) return NotFound();
        if (string.IsNullOrWhiteSpace(me.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً لاستخدام جهات الاتصال" });

        var items = (req.Contacts ?? Enumerable.Empty<PhoneLookupItemDto>())
            .Select(c => new
            {
                Phone = NormalizeLookupPhone(c.Phone),
                Name = string.IsNullOrWhiteSpace(c.Name) ? null : c.Name.Trim()
            })
            .Where(c => c.Phone.Length >= 8 && c.Phone.Length <= 15)
            .GroupBy(c => c.Phone)
            .Select(g => g.First())
            .Take(800)
            .ToList();

        if (items.Count == 0)
            return Ok(Array.Empty<PhoneLookupMatchDto>());

        var phoneSet = items.Select(i => i.Phone).ToHashSet();
        var deviceNames = items
            .Where(i => i.Name != null)
            .GroupBy(i => i.Phone)
            .ToDictionary(g => g.Key, g => g.First().Name!);

        var matchedUsers = await db.Users.AsNoTracking()
            .Where(u => u.PhoneNumber != null
                        && phoneSet.Contains(u.PhoneNumber)
                        && u.Id != CurrentUserId
                        && !u.IsBanned)
            .Select(u => new { u.Id, u.Name, u.Avatar, u.PhoneNumber, u.UniqueCode })
            .ToListAsync();

        if (matchedUsers.Count == 0)
            return Ok(Array.Empty<PhoneLookupMatchDto>());

        var matchedIds = matchedUsers.Select(u => u.Id).ToList();

        var blockedIds = await db.UserBlocks
            .Where(b =>
                (b.BlockerId == CurrentUserId && matchedIds.Contains(b.BlockedUserId)) ||
                (b.BlockedUserId == CurrentUserId && matchedIds.Contains(b.BlockerId)))
            .Select(b => b.BlockerId == CurrentUserId ? b.BlockedUserId : b.BlockerId)
            .ToListAsync();
        var blockedSet = blockedIds.ToHashSet();

        var existingContacts = await db.Contacts
            .Where(c => c.UserId == CurrentUserId && matchedIds.Contains(c.ContactUserId))
            .Select(c => c.ContactUserId)
            .ToListAsync();
        var contactSet = existingContacts.ToHashSet();

        var pendingOutgoing = await db.MessageRequests
            .Where(r => r.RequesterId == CurrentUserId
                        && matchedIds.Contains(r.TargetId)
                        && r.Status == MessageRequestStatus.Pending)
            .Select(r => r.TargetId)
            .ToListAsync();
        var pendingSet = pendingOutgoing.ToHashSet();

        var result = matchedUsers
            .Where(u => !blockedSet.Contains(u.Id))
            .Select(u => new PhoneLookupMatchDto(
                u.Id,
                u.Name,
                u.Avatar,
                u.PhoneNumber,
                u.UniqueCode,
                u.PhoneNumber != null && deviceNames.TryGetValue(u.PhoneNumber, out var dn) ? dn : null,
                contactSet.Contains(u.Id),
                pendingSet.Contains(u.Id)
            ))
            .OrderBy(m => m.IsContact ? 1 : 0)
            .ThenBy(m => m.Name)
            .ToList();

        return Ok(result);
    }

    private static string NormalizeLookupPhone(string? raw)
    {
        var digits = new string((raw ?? "").Where(char.IsDigit).ToArray());
        while (digits.Length > 1 && digits[0] == '0' && digits.Length > 10)
            digits = digits[1..];
        return digits;
    }

    [HttpPost]
    public async Task<ActionResult<ContactDto>> AddContact([FromBody] AddContactByPhoneRequest req)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();
        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً لإضافة جهات اتصال" });

        var countryCode = (req.CountryCode ?? "").Trim().TrimStart('+').Replace(" ", "");
        var phone = (req.PhoneNumber ?? "").Trim().Replace(" ", "").Replace("-", "");
        if (string.IsNullOrEmpty(countryCode))
            return BadRequest(new { message = "مفتاح الدولة مطلوب" });
        if (!PhoneValidationService.TryValidate(countryCode, phone, out var fullPhone, out var phoneError))
            return BadRequest(new { message = phoneError });

        var targetUser = await db.Users
            .FirstOrDefaultAsync(u => u.PhoneNumber == fullPhone && !u.IsBanned);
        if (targetUser == null)
            return NotFound(new { message = "لم يتم العثور على مستخدم بهذا الرقم" });

        var isBlocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == CurrentUserId && b.BlockedUserId == targetUser.Id) ||
            (b.BlockerId == targetUser.Id && b.BlockedUserId == CurrentUserId));
        if (isBlocked)
            return BadRequest(new { message = "لا يمكن إضافة هذا المستخدم" });

        if (targetUser.Id == CurrentUserId)
            return BadRequest(new { message = "لا يمكن إضافة نفسك" });

        var exists = await db.Contacts.AnyAsync(c =>
            c.UserId == CurrentUserId && c.ContactUserId == targetUser.Id);
        if (exists)
            return Conflict(new { message = "المستخدم مضاف مسبقاً" });

        var contact = new Contact
        {
            UserId = CurrentUserId,
            ContactUserId = targetUser.Id
        };
        db.Contacts.Add(contact);
        await db.SaveChangesAsync();

        return Ok(new ContactDto(
            contact.Id,
            targetUser.Id,
            targetUser.Name,
            targetUser.Avatar,
            targetUser.PhoneNumber,
            targetUser.UniqueCode,
            contact.CreatedAt
        ));
    }

    /// <summary>إضافة مستخدم كجهة اتصال بواسطة معرّفه (من بروفايله أو سجل الهاتف).</summary>
    [HttpPost("by-user/{userId:guid}")]
    public async Task<ActionResult<ContactDto>> AddContactByUserId(Guid userId)
    {
        var me = await db.Users.FindAsync(CurrentUserId);
        if (me == null) return NotFound();
        if (string.IsNullOrWhiteSpace(me.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً لإضافة جهات اتصال" });

        if (userId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن إضافة نفسك" });
        var targetUser = await db.Users.FindAsync(userId);
        if (targetUser == null || targetUser.IsBanned)
            return NotFound(new { message = "المستخدم غير متوفر" });
        var isBlocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == CurrentUserId && b.BlockedUserId == userId) ||
            (b.BlockerId == userId && b.BlockedUserId == CurrentUserId));
        if (isBlocked)
            return BadRequest(new { message = "لا يمكن إضافة هذا المستخدم" });
        var exists = await db.Contacts.AnyAsync(c =>
            c.UserId == CurrentUserId && c.ContactUserId == userId);
        if (exists)
            return Conflict(new { message = "المستخدم مضاف مسبقاً" });
        var contact = new Contact
        {
            UserId = CurrentUserId,
            ContactUserId = userId
        };
        db.Contacts.Add(contact);
        await db.SaveChangesAsync();
        return Ok(new ContactDto(
            contact.Id,
            targetUser.Id,
            targetUser.Name,
            targetUser.Avatar,
            targetUser.PhoneNumber,
            targetUser.UniqueCode,
            contact.CreatedAt
        ));
    }

    [HttpDelete("{contactUserId:guid}")]
    public async Task<IActionResult> RemoveContact(Guid contactUserId)
    {
        var rows = await db.Contacts
            .Where(c => c.UserId == CurrentUserId && c.ContactUserId == contactUserId)
            .ExecuteDeleteAsync();
        return rows > 0 ? Ok() : NotFound();
    }
}
