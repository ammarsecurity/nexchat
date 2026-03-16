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
public class ConversationsController(AppDbContext db) : ControllerBase
{
    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<ActionResult<IEnumerable<ConversationListItemDto>>> GetConversations(
        [FromQuery] string filter = "all",
        [FromQuery] string? search = null)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();
        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً" });

        var convQuery = db.Conversations
            .Where(c => c.User1Id == CurrentUserId || c.User2Id == CurrentUserId);

        var deletedIds = await db.UserConversationDeletions
            .Where(d => d.UserId == CurrentUserId)
            .Select(d => d.ConversationId)
            .ToListAsync();
        convQuery = convQuery.Where(c => !deletedIds.Contains(c.Id));

        var f = (filter ?? "all").ToLowerInvariant();
        if (f == "unread")
        {
            var allConvIds = await convQuery.Select(c => c.Id).ToListAsync();
            var unreadConvIds = new List<Guid>();
            foreach (var cid in allConvIds)
            {
                var lastRead = await db.UserConversationStates
                    .Where(s => s.UserId == CurrentUserId && s.ConversationId == cid)
                    .Select(s => s.LastReadAt)
                    .FirstOrDefaultAsync();
                var hasUnread = await db.ConversationMessages
                    .AnyAsync(m => m.ConversationId == cid &&
                        m.SenderId != CurrentUserId &&
                        !m.DeletedForEveryone &&
                        !db.UserMessageDeletions.Any(d => d.UserId == CurrentUserId && d.MessageId == m.Id) &&
                        (lastRead == null || m.SentAt > lastRead));
                if (hasUnread) unreadConvIds.Add(cid);
            }
            convQuery = convQuery.Where(c => unreadConvIds.Contains(c.Id));
        }
        else if (f == "archived")
        {
            var archivedIds = await db.UserConversationStates
                .Where(s => s.UserId == CurrentUserId && s.IsArchived)
                .Select(s => s.ConversationId)
                .ToListAsync();
            convQuery = convQuery.Where(c => archivedIds.Contains(c.Id));
        }
        else
        {
            var archivedIds = await db.UserConversationStates
                .Where(s => s.UserId == CurrentUserId && s.IsArchived)
                .Select(s => s.ConversationId)
                .ToListAsync();
            convQuery = convQuery.Where(c => !archivedIds.Contains(c.Id));
        }

        var convs = await convQuery
            .Include(c => c.User1)
            .Include(c => c.User2)
            .ToListAsync();

        var convIds = convs.Select(c => c.Id).ToList();
        var lastMessages = await db.ConversationMessages
            .Where(m => convIds.Contains(m.ConversationId) && !m.DeletedForEveryone)
            .GroupBy(m => m.ConversationId)
            .Select(g => new { ConvId = g.Key, Msg = g.OrderByDescending(m => m.SentAt).First() })
            .ToListAsync();

        var searchLower = search?.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(searchLower))
        {
            convs = convs.Where(c =>
            {
                var partner = c.User1Id == CurrentUserId ? c.User2 : c.User1;
                return (partner.Name?.ToLowerInvariant().Contains(searchLower) ?? false) ||
                       (partner.PhoneNumber?.Contains(searchLower) ?? false) ||
                       (partner.UniqueCode?.ToLowerInvariant().Contains(searchLower) ?? false);
            }).ToList();
        }

        var lastMsgDict = lastMessages.ToDictionary(x => x.ConvId, x => x.Msg);
        var result = new List<ConversationListItemDto>();
        foreach (var c in convs)
        {
            var partner = c.User1Id == CurrentUserId ? c.User2 : c.User1;
            lastMsgDict.TryGetValue(c.Id, out var lastMsgObj);
            var lastMsg = lastMsgObj;
            var state = await db.UserConversationStates
                .FirstOrDefaultAsync(s => s.UserId == CurrentUserId && s.ConversationId == c.Id);
            var lastRead = state?.LastReadAt;

            var unreadCount = await db.ConversationMessages
                .CountAsync(m => m.ConversationId == c.Id &&
                    m.SenderId != CurrentUserId &&
                    !m.DeletedForEveryone &&
                    !db.UserMessageDeletions.Any(d => d.UserId == CurrentUserId && d.MessageId == m.Id) &&
                    (lastRead == null || m.SentAt > lastRead));

            var preview = lastMsg == null ? null :
                lastMsg.DeletedForEveryone ? "تم حذف هذه الرسالة" :
                lastMsg.Type == "image" ? "صورة" :
                lastMsg.Type == "audio" ? "رسالة صوتية" :
                lastMsg.Content.Length > 50 ? lastMsg.Content[..50] + "…" : lastMsg.Content;

            result.Add(new ConversationListItemDto(
                c.Id,
                partner.Id,
                partner.Name,
                partner.Avatar,
                partner.PhoneNumber,
                partner.UniqueCode,
                preview,
                lastMsg?.SentAt,
                unreadCount,
                state?.IsPinned ?? false,
                state?.IsArchived ?? false
            ));
        }

        result = result
            .OrderByDescending(x => x.IsPinned)
            .ThenByDescending(x => x.LastMessageAt ?? DateTime.MinValue)
            .ToList();

        return Ok(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<object>> GetConversation(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var conv = await db.Conversations
            .Include(c => c.User1)
            .Include(c => c.User2)
            .FirstOrDefaultAsync(c => c.Id == id);
        if (conv == null) return NotFound();
        var deleted = await db.UserConversationDeletions
            .AnyAsync(d => d.UserId == CurrentUserId && d.ConversationId == id);
        if (deleted) return NotFound();
        var partner = conv.User1Id == CurrentUserId ? conv.User2 : conv.User1;
        return Ok(new { id = conv.Id, partnerId = partner.Id, partnerName = partner.Name, partnerAvatar = partner.Avatar });
    }

    [HttpPost]
    public async Task<ActionResult<object>> CreateOrGetConversation([FromBody] CreateConversationRequest req)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();
        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً" });

        var isContact = await db.Contacts.AnyAsync(c =>
            c.UserId == CurrentUserId && c.ContactUserId == req.ContactUserId);
        if (!isContact)
            return BadRequest(new { message = "يجب إضافة المستخدم كجهة اتصال أولاً" });

        var isBlocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == CurrentUserId && b.BlockedUserId == req.ContactUserId) ||
            (b.BlockerId == req.ContactUserId && b.BlockedUserId == CurrentUserId));
        if (isBlocked)
            return BadRequest(new { message = "لا يمكن إنشاء محادثة مع هذا المستخدم" });

        if (req.ContactUserId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن إنشاء محادثة مع نفسك" });

        var u1 = CurrentUserId;
        var u2 = req.ContactUserId;
        if (u1.CompareTo(u2) > 0) (u1, u2) = (u2, u1);

        var conv = await db.Conversations
            .FirstOrDefaultAsync(c => c.User1Id == u1 && c.User2Id == u2);

        if (conv == null)
        {
            conv = new Conversation { User1Id = u1, User2Id = u2 };
            db.Conversations.Add(conv);
            await db.SaveChangesAsync();
        }
        else
        {
            var deletion = await db.UserConversationDeletions
                .FirstOrDefaultAsync(d => d.UserId == CurrentUserId && d.ConversationId == conv.Id);
            if (deletion != null)
            {
                db.UserConversationDeletions.Remove(deletion);
                await db.SaveChangesAsync();
            }
        }

        var partner = await db.Users.FindAsync(req.ContactUserId);
        return Ok(new { id = conv.Id, partnerId = partner?.Id, partnerName = partner?.Name, partnerAvatar = partner?.Avatar });
    }

    [HttpPut("{id:guid}/pin")]
    public async Task<IActionResult> TogglePin(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var state = await GetOrCreateState(id);
        state.IsPinned = !state.IsPinned;
        state.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { isPinned = state.IsPinned });
    }

    [HttpPut("{id:guid}/archive")]
    public async Task<IActionResult> ToggleArchive(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var state = await GetOrCreateState(id);
        state.IsArchived = !state.IsArchived;
        state.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(new { isArchived = state.IsArchived });
    }

    [HttpPut("{id:guid}/read")]
    public async Task<IActionResult> MarkAsRead(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var state = await GetOrCreateState(id);
        state.LastReadAt = DateTime.UtcNow;
        state.UpdatedAt = DateTime.UtcNow;

        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id);
        if (conv != null)
        {
            var partnerId = conv.User1Id == CurrentUserId ? conv.User2Id : conv.User1Id;
            await db.ConversationMessages
                .Where(m => m.ConversationId == id && m.SenderId == partnerId && !m.IsRead)
                .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteForMe(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var exists = await db.UserConversationDeletions
            .AnyAsync(d => d.UserId == CurrentUserId && d.ConversationId == id);
        if (exists) return Ok();
        db.UserConversationDeletions.Add(new UserConversationDeletion
        {
            UserId = CurrentUserId,
            ConversationId = id
        });
        var messageIds = await db.ConversationMessages
            .Where(m => m.ConversationId == id)
            .Select(m => m.Id)
            .ToListAsync();
        var existingDeletions = await db.UserMessageDeletions
            .Where(d => d.UserId == CurrentUserId && messageIds.Contains(d.MessageId))
            .Select(d => d.MessageId)
            .ToListAsync();
        foreach (var mid in messageIds.Where(id => !existingDeletions.Contains(id)))
        {
            db.UserMessageDeletions.Add(new UserMessageDeletion { UserId = CurrentUserId, MessageId = mid });
        }
        await db.SaveChangesAsync();
        return Ok();
    }

    private async Task<bool> IsParticipant(Guid conversationId) =>
        await db.Conversations.AnyAsync(c => c.Id == conversationId &&
            (c.User1Id == CurrentUserId || c.User2Id == CurrentUserId));

    private async Task<UserConversationState> GetOrCreateState(Guid conversationId)
    {
        var state = await db.UserConversationStates
            .FirstOrDefaultAsync(s => s.UserId == CurrentUserId && s.ConversationId == conversationId);
        if (state == null)
        {
            state = new UserConversationState
            {
                UserId = CurrentUserId,
                ConversationId = conversationId
            };
            db.UserConversationStates.Add(state);
            await db.SaveChangesAsync();
        }
        return state;
    }
}
