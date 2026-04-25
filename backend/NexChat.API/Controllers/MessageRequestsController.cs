using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using NexChat.API.Services;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/message-requests")]
[Authorize]
[EnableRateLimiting("api")]
public class MessageRequestsController(AppDbContext db, NotificationOutboxService notificationOutbox) : ControllerBase
{
    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    /// <summary>عدد الطلبات الواردة المعلقة (للشارات).</summary>
    [HttpGet("pending-count")]
    public async Task<ActionResult<int>> GetPendingCount()
    {
        var n = await db.MessageRequests.CountAsync(r =>
            r.TargetId == CurrentUserId && r.Status == MessageRequestStatus.Pending);
        return Ok(n);
    }

    /// <summary>الطلبات الواردة المعلقة فقط.</summary>
    [HttpGet]
    public async Task<ActionResult<IEnumerable<MessageRequestListItemDto>>> GetIncomingPending()
    {
        var list = await db.MessageRequests
            .AsNoTracking()
            .Where(r => r.TargetId == CurrentUserId && r.Status == MessageRequestStatus.Pending)
            .Include(r => r.Requester)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new MessageRequestListItemDto(
                r.Id,
                r.RequesterId,
                r.Requester.Name ?? "",
                r.Requester.Avatar,
                r.Requester.UniqueCode,
                r.CreatedAt))
            .ToListAsync();
        return Ok(list);
    }

    /// <summary>
    /// إنشاء طلب مراسلة. لا يُضيف جهة اتصال تلقائياً؛ عند قبول المستقبل يُنشأ صف Contact من المُرسل إلى الهدف.
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<object>> Create([FromBody] CreateMessageRequestDto body)
    {
        var targetId = body.TargetUserId;
        if (targetId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن إرسال طلب لنفسك" });

        var targetUser = await db.Users.FindAsync(targetId);
        if (targetUser == null || targetUser.IsBanned)
            return NotFound(new { message = "المستخدم غير متوفر" });

        var isBlocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == CurrentUserId && b.BlockedUserId == targetId) ||
            (b.BlockerId == targetId && b.BlockedUserId == CurrentUserId));
        if (isBlocked)
            return BadRequest(new { message = "لا يمكن إرسال طلب لهذا المستخدم" });

        var iHaveTarget = await db.Contacts.AnyAsync(c =>
            c.UserId == CurrentUserId && c.ContactUserId == targetId);
        var targetHasMe = await db.Contacts.AnyAsync(c =>
            c.UserId == targetId && c.ContactUserId == CurrentUserId);
        if (iHaveTarget && targetHasMe)
            return BadRequest(new { message = "يمكنك بدء المحادثة مباشرة دون طلب مراسلة" });

        var existing = await db.MessageRequests
            .FirstOrDefaultAsync(r => r.RequesterId == CurrentUserId && r.TargetId == targetId);

        if (existing != null)
        {
            if (existing.Status == MessageRequestStatus.Pending)
                return Conflict(new { message = "يوجد طلب معلق مسبقاً" });
            if (existing.Status == MessageRequestStatus.Accepted)
                return BadRequest(new { message = "تم قبول الطلب مسبقاً" });
            // Declined — السماح بإعادة الإرسال
            existing.Status = MessageRequestStatus.Pending;
            existing.CreatedAt = DateTime.UtcNow;
            existing.RespondedAt = null;
            await db.SaveChangesAsync();
            await NotifyTargetAsync(existing.Id, targetId);
            return Ok(new { id = existing.Id, status = existing.Status });
        }

        var row = new MessageRequest
        {
            RequesterId = CurrentUserId,
            TargetId = targetId,
            Status = MessageRequestStatus.Pending
        };
        db.MessageRequests.Add(row);
        await db.SaveChangesAsync();
        await NotifyTargetAsync(row.Id, targetId);
        return Ok(new { id = row.Id, status = row.Status });
    }

    private async Task NotifyTargetAsync(Guid messageRequestId, Guid targetId)
    {
        var requester = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == CurrentUserId);
        var name = requester?.Name ?? "";
        await notificationOutbox.EnqueueAsync(
            targetId,
            "message_request",
            "طلب مراسلة",
            $"{name} يريد مراسلتك",
            new Dictionary<string, string> { ["messageRequestId"] = messageRequestId.ToString() });
    }

    /// <summary>قبول الطلب: إنشاء جهات اتصال متبادلة حتى يعمل CreateOrGetConversation لكلا الطرفين.</summary>
    [HttpPost("{id:guid}/accept")]
    public async Task<ActionResult<object>> Accept(Guid id)
    {
        var req = await db.MessageRequests
            .Include(r => r.Requester)
            .FirstOrDefaultAsync(r => r.Id == id);
        if (req == null) return NotFound();
        if (req.TargetId != CurrentUserId)
            return Forbid();
        if (req.Status != MessageRequestStatus.Pending)
            return BadRequest(new { message = "الطلب لم يعد معلقاً" });

        if (!await db.Contacts.AnyAsync(c =>
                c.UserId == req.RequesterId && c.ContactUserId == req.TargetId))
        {
            db.Contacts.Add(new Contact
            {
                UserId = req.RequesterId,
                ContactUserId = req.TargetId
            });
        }

        if (!await db.Contacts.AnyAsync(c =>
                c.UserId == req.TargetId && c.ContactUserId == req.RequesterId))
        {
            db.Contacts.Add(new Contact
            {
                UserId = req.TargetId,
                ContactUserId = req.RequesterId
            });
        }

        req.Status = MessageRequestStatus.Accepted;
        req.RespondedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return Ok(new { message = "تم القبول" });
    }

    [HttpPost("{id:guid}/decline")]
    public async Task<ActionResult<object>> Decline(Guid id)
    {
        var req = await db.MessageRequests.FirstOrDefaultAsync(r => r.Id == id);
        if (req == null) return NotFound();
        if (req.TargetId != CurrentUserId)
            return Forbid();
        if (req.Status != MessageRequestStatus.Pending)
            return BadRequest(new { message = "الطلب لم يعد معلقاً" });

        req.Status = MessageRequestStatus.Declined;
        req.RespondedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { message = "تم الرفض" });
    }
}
