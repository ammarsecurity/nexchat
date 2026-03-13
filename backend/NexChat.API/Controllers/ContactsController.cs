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

    [HttpDelete("{contactUserId:guid}")]
    public async Task<IActionResult> RemoveContact(Guid contactUserId)
    {
        var rows = await db.Contacts
            .Where(c => c.UserId == CurrentUserId && c.ContactUserId == contactUserId)
            .ExecuteDeleteAsync();
        return rows > 0 ? Ok() : NotFound();
    }
}
