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
[Route("api/[controller]")]
[Authorize]
[EnableRateLimiting("api")]
public class ConversationsController(AppDbContext db, NotificationOutboxService notificationOutbox, IConversationMessageCrypto messageCrypto) : ControllerBase
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
            .Where(c => (c.Type == ConversationType.Private && (c.User1Id == CurrentUserId || c.User2Id == CurrentUserId))
                || (c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == c.Id && m.UserId == CurrentUserId)));

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
            .Where(m => convIds.Contains(m.ConversationId) && !m.DeletedForEveryone &&
                !db.UserMessageDeletions.Any(d => d.UserId == CurrentUserId && d.MessageId == m.Id))
            .GroupBy(m => m.ConversationId)
            .Select(g => new { ConvId = g.Key, Msg = g.OrderByDescending(m => m.SentAt).First() })
            .ToListAsync();

        var searchLower = search?.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(searchLower))
        {
            convs = convs.Where(c =>
            {
                if (c.Type == ConversationType.Group)
                    return (c.Name?.ToLowerInvariant().Contains(searchLower) ?? false);
                var partner = c.User1Id == CurrentUserId ? c.User2 : c.User1;
                return partner != null && ((partner.Name?.ToLowerInvariant().Contains(searchLower) ?? false) ||
                       (partner.PhoneNumber?.Contains(searchLower) ?? false) ||
                       (partner.UniqueCode?.ToLowerInvariant().Contains(searchLower) ?? false));
            }).ToList();
        }

        var lastMsgDict = lastMessages.ToDictionary(x => x.ConvId, x => x.Msg);
        var result = new List<ConversationListItemDto>();
        foreach (var c in convs)
        {
            Guid partnerId;
            string partnerName;
            string? partnerAvatar;
            string? partnerPhone = null;
            string? partnerUniqueCode = null;
            if (c.Type == ConversationType.Group)
            {
                partnerId = c.Id;
                partnerName = c.Name ?? "مجموعة";
                partnerAvatar = c.ImageUrl;
            }
            else
            {
                var partner = c.User1Id == CurrentUserId ? c.User2 : c.User1;
                if (partner == null) continue;
                partnerId = partner.Id;
                partnerName = partner.Name ?? "";
                partnerAvatar = partner.Avatar;
                partnerPhone = partner.PhoneNumber;
                partnerUniqueCode = partner.UniqueCode;
            }
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

            string? preview = null;
            if (lastMsg != null)
            {
                if (lastMsg.Type == "image") preview = "صورة";
                else if (lastMsg.Type == "audio") preview = "رسالة صوتية";
                else
                {
                    var plain = messageCrypto.DecryptFromStorage(lastMsg.Content ?? "");
                    preview = plain.Length > 50 ? plain[..50] + "…" : plain;
                }
            }

            result.Add(new ConversationListItemDto(
                c.Id,
                partnerId,
                partnerName,
                partnerAvatar,
                partnerPhone,
                partnerUniqueCode,
                preview,
                lastMsg?.SentAt,
                unreadCount,
                state?.IsPinned ?? false,
                state?.IsArchived ?? false,
                c.Type == ConversationType.Group
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
        if (conv.Type == ConversationType.Group)
            return Ok(new { id = conv.Id, type = "group", groupName = conv.Name ?? "مجموعة", groupImageUrl = conv.ImageUrl });
        var partner = conv.User1Id == CurrentUserId ? conv.User2 : conv.User1;
        if (partner == null) return NotFound();
        return Ok(new { id = conv.Id, type = "private", partnerId = partner.Id, partnerName = partner.Name, partnerAvatar = partner.Avatar });
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

        // محادثات خاصة أنشئت قبل هذا الشرط قد تبقى في DB؛ القيد يطبق على إنشاء محادثة جديدة فقط.
        var partnerHasMe = await db.Contacts.AnyAsync(c =>
            c.UserId == req.ContactUserId && c.ContactUserId == CurrentUserId);
        if (!partnerHasMe)
        {
            var acceptedRequest = await db.MessageRequests.AnyAsync(r =>
                r.Status == MessageRequestStatus.Accepted &&
                ((r.RequesterId == CurrentUserId && r.TargetId == req.ContactUserId) ||
                 (r.RequesterId == req.ContactUserId && r.TargetId == CurrentUserId)));
            if (!acceptedRequest)
                return Conflict(new
                {
                    code = "NEEDS_MESSAGE_REQUEST",
                    message = "يجب أن يضيفك الطرف كجهة اتصال أو قبول طلب المراسلة أولاً"
                });
        }

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
            .FirstOrDefaultAsync(c => c.Type == ConversationType.Private && c.User1Id == u1 && c.User2Id == u2);

        if (conv == null)
        {
            conv = new Conversation { Type = ConversationType.Private, User1Id = u1, User2Id = u2 };
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

    /// <summary>
    /// مسار واحد للعميل: فتح محادثة خاصة عند التبادل أو إنشاء/تأكيد طلب مراسلة.
    /// يُرجع دائماً 200 للحالات المتوقعة (بدون Conflict 409) لتجنب تسجيل المتصفح لأخطاء وهمية في الـ console.
    /// </summary>
    [HttpPost("open-private-or-request")]
    public async Task<ActionResult<object>> OpenPrivateOrRequest([FromBody] CreateConversationRequest req)
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

        var partnerHasMe = await db.Contacts.AnyAsync(c =>
            c.UserId == req.ContactUserId && c.ContactUserId == CurrentUserId);
        var acceptedRequest = await db.MessageRequests.AnyAsync(r =>
            r.Status == MessageRequestStatus.Accepted &&
            ((r.RequesterId == CurrentUserId && r.TargetId == req.ContactUserId) ||
             (r.RequesterId == req.ContactUserId && r.TargetId == CurrentUserId)));

        if (partnerHasMe || acceptedRequest)
        {
            var u1 = CurrentUserId;
            var u2 = req.ContactUserId;
            if (u1.CompareTo(u2) > 0) (u1, u2) = (u2, u1);

            var conv = await db.Conversations
                .FirstOrDefaultAsync(c => c.Type == ConversationType.Private && c.User1Id == u1 && c.User2Id == u2);

            if (conv == null)
            {
                conv = new Conversation { Type = ConversationType.Private, User1Id = u1, User2Id = u2 };
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
            return Ok(new
            {
                result = "opened",
                id = conv.Id,
                partnerId = partner?.Id,
                partnerName = partner?.Name,
                partnerAvatar = partner?.Avatar
            });
        }

        var targetId = req.ContactUserId;
        var targetUser = await db.Users.FindAsync(targetId);
        if (targetUser == null || targetUser.IsBanned)
            return NotFound(new { message = "المستخدم غير متوفر" });

        var iHaveTarget = await db.Contacts.AnyAsync(c =>
            c.UserId == CurrentUserId && c.ContactUserId == targetId);
        var targetHasMeCheck = await db.Contacts.AnyAsync(c =>
            c.UserId == targetId && c.ContactUserId == CurrentUserId);
        if (iHaveTarget && targetHasMeCheck)
            return BadRequest(new { message = "يمكنك بدء المحادثة مباشرة دون طلب مراسلة" });

        var existing = await db.MessageRequests
            .FirstOrDefaultAsync(r => r.RequesterId == CurrentUserId && r.TargetId == targetId);

        if (existing != null)
        {
            if (existing.Status == MessageRequestStatus.Pending)
                return Ok(new { result = "messageRequestPending" });
            if (existing.Status == MessageRequestStatus.Accepted)
            {
                var u1b = CurrentUserId;
                var u2b = req.ContactUserId;
                if (u1b.CompareTo(u2b) > 0) (u1b, u2b) = (u2b, u1b);
                var convB = await db.Conversations
                    .FirstOrDefaultAsync(c => c.Type == ConversationType.Private && c.User1Id == u1b && c.User2Id == u2b);
                if (convB == null)
                {
                    convB = new Conversation { Type = ConversationType.Private, User1Id = u1b, User2Id = u2b };
                    db.Conversations.Add(convB);
                    await db.SaveChangesAsync();
                }
                var partnerB = await db.Users.FindAsync(req.ContactUserId);
                return Ok(new
                {
                    result = "opened",
                    id = convB.Id,
                    partnerId = partnerB?.Id,
                    partnerName = partnerB?.Name,
                    partnerAvatar = partnerB?.Avatar
                });
            }

            existing.Status = MessageRequestStatus.Pending;
            existing.CreatedAt = DateTime.UtcNow;
            existing.RespondedAt = null;
            await db.SaveChangesAsync();
            await NotifyMessageRequestAsync(targetId, existing.Id);
            return Ok(new { result = "messageRequestCreated", messageRequestId = existing.Id });
        }

        var row = new MessageRequest
        {
            RequesterId = CurrentUserId,
            TargetId = targetId,
            Status = MessageRequestStatus.Pending
        };
        db.MessageRequests.Add(row);
        await db.SaveChangesAsync();
        await NotifyMessageRequestAsync(targetId, row.Id);
        return Ok(new { result = "messageRequestCreated", messageRequestId = row.Id });
    }

    private async Task NotifyMessageRequestAsync(Guid targetId, Guid messageRequestId)
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
            var partnerId = conv.Type == ConversationType.Private ? (conv.User1Id == CurrentUserId ? conv.User2Id : conv.User1Id) : null;
            if (partnerId.HasValue)
                await db.ConversationMessages
                    .Where(m => m.ConversationId == id && m.SenderId == partnerId.Value && !m.IsRead)
                    .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
            else if (conv.Type == ConversationType.Group)
                await db.ConversationMessages
                    .Where(m => m.ConversationId == id && m.SenderId != CurrentUserId && !m.IsRead)
                    .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));
        }

        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpPut("read-all")]
    public async Task<IActionResult> MarkAllAsRead()
    {
        var convIds = await db.Conversations
            .Where(c => (c.Type == ConversationType.Private && (c.User1Id == CurrentUserId || c.User2Id == CurrentUserId))
                || (c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == c.Id && m.UserId == CurrentUserId)))
            .Select(c => c.Id)
            .ToListAsync();

        if (convIds.Count == 0) return Ok(new { updated = 0 });

        var now = DateTime.UtcNow;
        var states = await db.UserConversationStates
            .Where(s => s.UserId == CurrentUserId && convIds.Contains(s.ConversationId))
            .ToListAsync();

        var statesByConv = states.ToDictionary(s => s.ConversationId, s => s);
        var added = 0;
        foreach (var convId in convIds)
        {
            if (statesByConv.TryGetValue(convId, out var st))
            {
                st.LastReadAt = now;
                st.UpdatedAt = now;
            }
            else
            {
                db.UserConversationStates.Add(new UserConversationState
                {
                    UserId = CurrentUserId,
                    ConversationId = convId,
                    LastReadAt = now,
                    UpdatedAt = now
                });
                added += 1;
            }
        }

        await db.ConversationMessages
            .Where(m => convIds.Contains(m.ConversationId) && m.SenderId != CurrentUserId && !m.IsRead)
            .ExecuteUpdateAsync(s => s.SetProperty(m => m.IsRead, true));

        await db.SaveChangesAsync();
        return Ok(new { updated = convIds.Count, statesAdded = added });
    }

    [HttpPost("group")]
    public async Task<ActionResult<object>> CreateGroup([FromBody] CreateGroupRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length > 100)
            return BadRequest(new { message = "اسم المجموعة مطلوب (حتى 100 حرف)" });
        var memberIds = (req.MemberUserIds ?? new List<Guid>()).Distinct().Where(id => id != CurrentUserId).Take(255).ToList();
        var isContact = memberIds.Count == 0 || await db.Contacts
            .CountAsync(c => c.UserId == CurrentUserId && memberIds.Contains(c.ContactUserId)) == memberIds.Count;
        if (!isContact)
            return BadRequest(new { message = "يجب أن يكون جميع الأعضاء من جهات الاتصال" });
        var conv = new Conversation
        {
            Type = ConversationType.Group,
            Name = req.Name.Trim(),
            ImageUrl = req.ImageUrl?.Trim().Length > 0 ? req.ImageUrl.Trim() : null,
            CreatedById = CurrentUserId
        };
        db.Conversations.Add(conv);
        await db.SaveChangesAsync();
        db.ConversationMembers.Add(new ConversationMember { ConversationId = conv.Id, UserId = CurrentUserId, Role = "Admin" });
        foreach (var uid in memberIds)
            db.ConversationMembers.Add(new ConversationMember { ConversationId = conv.Id, UserId = uid, Role = "Member" });
        await db.SaveChangesAsync();
        return Ok(new { id = conv.Id, groupName = conv.Name, groupImageUrl = conv.ImageUrl });
    }

    [HttpPut("{id:guid}/group")]
    public async Task<ActionResult<object>> UpdateGroup(Guid id, [FromBody] UpdateGroupRequest req)
    {
        if (!await IsParticipant(id)) return NotFound();
        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id);
        if (conv?.Type != ConversationType.Group) return NotFound();
        var myMember = await db.ConversationMembers.FirstOrDefaultAsync(m => m.ConversationId == id && m.UserId == CurrentUserId);
        if (myMember?.Role != "Admin") return Forbid();
        if (req.Name != null)
        {
            var name = req.Name.Trim();
            if (name.Length == 0 || name.Length > 100)
                return BadRequest(new { message = "اسم المجموعة يجب أن يكون بين 1 و 100 حرف" });
            conv.Name = name;
        }
        if (req.ImageUrl != null)
            conv.ImageUrl = req.ImageUrl.Trim().Length > 0 ? req.ImageUrl.Trim() : null;
        await db.SaveChangesAsync();
        return Ok(new { groupName = conv.Name, groupImageUrl = conv.ImageUrl });
    }

    [HttpGet("{id:guid}/members")]
    public async Task<ActionResult<IEnumerable<GroupMemberDto>>> GetMembers(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id);
        if (conv?.Type != ConversationType.Group) return NotFound();
        var members = await db.ConversationMembers
            .Where(m => m.ConversationId == id)
            .Include(m => m.User)
            .OrderBy(m => m.Role == "Admin" ? 0 : 1).ThenBy(m => m.JoinedAt)
            .Select(m => new GroupMemberDto(m.UserId, m.User!.Name ?? "", m.User.Avatar, m.Role, m.JoinedAt))
            .ToListAsync();
        return Ok(members);
    }

    [HttpPost("{id:guid}/members")]
    public async Task<IActionResult> AddMember(Guid id, [FromBody] Guid userId)
    {
        if (!await IsParticipant(id)) return NotFound();
        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id);
        if (conv?.Type != ConversationType.Group) return NotFound();
        var isContact = await db.Contacts.AnyAsync(c => c.UserId == CurrentUserId && c.ContactUserId == userId);
        if (!isContact) return BadRequest(new { message = "يجب إضافة المستخدم كجهة اتصال أولاً" });
        if (await db.ConversationMembers.AnyAsync(m => m.ConversationId == id && m.UserId == userId))
            return BadRequest(new { message = "المستخدم عضو بالفعل" });
        db.ConversationMembers.Add(new ConversationMember { ConversationId = id, UserId = userId, Role = "Member" });
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpDelete("{id:guid}/members/{memberUserId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid id, Guid memberUserId)
    {
        if (!await IsParticipant(id)) return NotFound();
        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id);
        if (conv?.Type != ConversationType.Group) return NotFound();
        var myMember = await db.ConversationMembers.FirstOrDefaultAsync(m => m.ConversationId == id && m.UserId == CurrentUserId);
        if (myMember?.Role != "Admin" && memberUserId != CurrentUserId) return Forbid();
        var toRemove = await db.ConversationMembers.FirstOrDefaultAsync(m => m.ConversationId == id && m.UserId == memberUserId);
        if (toRemove == null) return NotFound();
        if (myMember!.Role != "Admin" && memberUserId == CurrentUserId) { db.ConversationMembers.Remove(toRemove); await db.SaveChangesAsync(); return Ok(); }
        if (toRemove.Role == "Admin")
        {
            var adminCount = await db.ConversationMembers.CountAsync(m => m.ConversationId == id && m.Role == "Admin");
            if (adminCount <= 1) return BadRequest(new { message = "يجب أن يبقى مدير واحد على الأقل" });
        }
        db.ConversationMembers.Remove(toRemove);
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpPost("{id:guid}/leave")]
    public async Task<IActionResult> LeaveGroup(Guid id)
    {
        if (!await IsParticipant(id)) return NotFound();
        var conv = await db.Conversations.FirstOrDefaultAsync(c => c.Id == id);
        if (conv?.Type != ConversationType.Group) return NotFound();
        var myMember = await db.ConversationMembers.FirstOrDefaultAsync(m => m.ConversationId == id && m.UserId == CurrentUserId);
        if (myMember == null) return NotFound();
        var adminCount = await db.ConversationMembers.CountAsync(m => m.ConversationId == id && m.Role == "Admin");
        if (adminCount == 1 && myMember.Role == "Admin")
        {
            var next = await db.ConversationMembers.Where(m => m.ConversationId == id && m.UserId != CurrentUserId).OrderBy(m => m.JoinedAt).FirstOrDefaultAsync();
            if (next != null) next.Role = "Admin";
        }
        db.ConversationMembers.Remove(myMember);
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
            (c.Type == ConversationType.Private && (c.User1Id == CurrentUserId || c.User2Id == CurrentUserId))
            || (c.Type == ConversationType.Group && db.ConversationMembers.Any(m => m.ConversationId == conversationId && m.UserId == CurrentUserId)));

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
