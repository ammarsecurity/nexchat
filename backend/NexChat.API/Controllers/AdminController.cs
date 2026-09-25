using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "AdminOnly")]
public class AdminController(
    AppDbContext db,
    IHubContext<ChatHub> hubContext,
    IHubContext<StoryHub> storyHub,
    StoryAudienceService storyAudience,
    OneSignalService oneSignal,
    EvolutionWhatsAppService evolution,
    IWebHostEnvironment env,
    IConfiguration config,
    IConversationMessageCrypto messageCrypto) : ControllerBase
{
    [HttpGet("stats")]
    public async Task<ActionResult<AdminStatsDto>> GetStats()
    {
        var today = IraqTime.TodayUtcStart;

        var stats = new AdminStatsDto(
            TotalUsers: await db.Users.CountAsync(),
            OnlineUsers: await db.Users.CountAsync(u => u.IsOnline),
            ActiveSessions: await db.ChatSessions.CountAsync(s => s.EndedAt == null),
            TotalSessionsToday: await db.ChatSessions.CountAsync(s => s.StartedAt >= today),
            TotalMessagesToday: await db.Messages.CountAsync(m => m.SentAt >= today),
            PendingReports: await db.Reports.CountAsync(r => !r.IsReviewed),
            TotalConversations: await db.Conversations.CountAsync(),
            TotalConversationMessagesToday: await db.ConversationMessages.CountAsync(m => m.SentAt >= today),
            TotalContacts: await db.Contacts.CountAsync(),
            TotalBlocks: await db.UserBlocks.CountAsync()
        );

        return Ok(stats);
    }

    [HttpGet("users")]
    public async Task<ActionResult<PagedResult<AdminUserDto>>> GetUsers(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null)
    {
        var query = db.Users.AsQueryable();
        if (!string.IsNullOrEmpty(search))
            query = query.Where(u => u.Name.Contains(search) || u.UniqueCode.Contains(search));

        var total = await query.CountAsync();
        var users = await query
            .OrderByDescending(u => u.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(u => new AdminUserDto(u.Id, u.Name, u.Gender, u.UniqueCode, u.IsOnline, u.IsBanned, u.IsFeatured, u.CreatedAt, u.BirthDate, u.PhoneNumber, u.Avatar))
            .ToListAsync();

        return Ok(new PagedResult<AdminUserDto>(users, total, page, pageSize));
    }

    /// <summary>
    /// إغلاق الجلسات غير النشطة. minutes: مدة عدم النشاط (افتراضي 15). closeAll: true = إغلاق الكل.
    /// يشمل جميع الجلسات بما فيها جلسات الدعم.
    /// </summary>
    [HttpPost("close-inactive-sessions")]
    public async Task<ActionResult<object>> CloseInactiveSessions(
        [FromQuery] int minutes = 15,
        [FromQuery] bool closeAll = false)
    {
        var query = db.ChatSessions
            .Where(s => s.EndedAt == null);

        List<Guid> toClose;
        if (closeAll)
        {
            toClose = await query.Select(s => s.Id).ToListAsync();
        }
        else
        {
            var threshold = Math.Clamp(minutes, 1, 1440); // 1 دقيقة إلى 24 ساعة
            var cutoff = DateTime.UtcNow.AddMinutes(-threshold);
            toClose = await query
                .Select(s => new
                {
                    s.Id,
                    LastActivity = s.Messages.Any()
                        ? s.Messages.Max(m => m.SentAt)
                        : s.StartedAt
                })
                .Where(x => x.LastActivity < cutoff)
                .Select(x => x.Id)
                .ToListAsync();
        }

        if (toClose.Count > 0)
        {
            await db.ChatSessions
                .Where(s => toClose.Contains(s.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.EndedAt, DateTime.UtcNow));

            foreach (var sid in toClose)
                await hubContext.Clients.Group(sid.ToString()).SendAsync("SessionEnded", Guid.Empty);
        }

        var msg = closeAll
            ? $"تم إغلاق {toClose.Count} جلسة"
            : $"تم إغلاق {toClose.Count} جلسة (غير نشطة منذ {minutes} دقيقة)";
        return Ok(new { closedCount = toClose.Count, message = msg });
    }

    [HttpPut("users/{id}/ban")]
    public async Task<IActionResult> BanUser(Guid id, [FromBody] bool ban)
    {
        var user = await db.Users.FindAsync(id);
        if (user == null) return NotFound();
        if (user.IsFeatured && ban)
            return BadRequest(new { message = "لا يمكن حظر الحسابات المميزة" });

        await db.Users
            .Where(u => u.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsBanned, ban));

        return Ok();
    }

    [HttpPut("users/{id}/featured")]
    public async Task<IActionResult> SetUserFeatured(Guid id, [FromBody] SetFeaturedRequest req)
    {
        var rows = await db.Users
            .Where(u => u.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsFeatured, req.Featured));

        return rows > 0 ? Ok() : NotFound();
    }

    /// <summary>
    /// تعيين كلمة مرور جديدة لمستخدم (من لوحة الأدمن).
    /// </summary>
    [HttpPut("users/{id}/password")]
    public async Task<IActionResult> SetUserPassword(Guid id, [FromBody] AdminSetPasswordRequest req)
    {
        var password = (req.Password ?? string.Empty).Trim();
        if (password.Length < 6)
            return BadRequest(new { message = "كلمة المرور يجب أن تكون 6 أحرف على الأقل" });
        if (password.Length > 72)
            return BadRequest(new { message = "كلمة المرور طويلة جداً" });

        var user = await db.Users.FindAsync(id);
        if (user == null) return NotFound();
        if (user.IsAdmin)
            return BadRequest(new { message = "لا يمكن تغيير كلمة مرور الأدمن من هنا" });

        var hash = BCrypt.Net.BCrypt.HashPassword(password);
        await db.Users
            .Where(u => u.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.PasswordHash, hash));

        return Ok(new { message = "تم تحديث كلمة المرور بنجاح" });
    }

    /// <summary>
    /// حذف مستخدم واحد. لا يمكن حذف الأدمن.
    /// </summary>
    [HttpDelete("users/{id}")]
    public async Task<IActionResult> DeleteUser(Guid id)
    {
        var user = await db.Users.FindAsync(id);
        if (user == null) return NotFound();
        if (user.IsAdmin)
            return BadRequest(new { message = "لا يمكن حذف حساب الأدمن" });

        await DeleteUserCascade(user.Id);
        return Ok();
    }

    /// <summary>
    /// حذف مجموعة مستخدمين. يتم تخطي حسابات الأدمن.
    /// </summary>
    [HttpDelete("users")]
    public async Task<ActionResult<object>> DeleteUsers([FromBody] DeleteUsersRequest req)
    {
        var ids = (req.Ids ?? Enumerable.Empty<Guid>()).Distinct().ToList();
        if (ids.Count == 0)
            return BadRequest(new { message = "لم يتم تحديد أي حسابات" });

        var toDelete = await db.Users
            .Where(u => ids.Contains(u.Id) && !u.IsAdmin)
            .Select(u => u.Id)
            .ToListAsync();

        var skipped = ids.Count - toDelete.Count;
        foreach (var userId in toDelete)
            await DeleteUserCascade(userId);

        return Ok(new
        {
            deleted = toDelete.Count,
            skipped,
            message = $"تم حذف {toDelete.Count} حساب" + (skipped > 0 ? $"، تم تخطي {skipped} (أدمن)" : "")
        });
    }

    private async Task DeleteUserCascade(Guid userId)
    {
        // 1. إيقاف الجلسات وإشعار العملاء قبل الحذف
        var sessions = await db.ChatSessions
            .Where(s => s.User1Id == userId || s.User2Id == userId)
            .Select(s => s.Id)
            .ToListAsync();

        if (sessions.Count > 0)
        {
            await db.ChatSessions
                .Where(s => sessions.Contains(s.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.EndedAt, DateTime.UtcNow));

            foreach (var sid in sessions)
                await hubContext.Clients.Group(sid.ToString()).SendAsync("SessionEnded", userId);
        }

        // 2. حذف كل ما يرتبط بالمستخدم (ترتيب يحترم Restrict FKs)
        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            // طلبات الرسائل / الاتصال بالكود / البلاغات
            await db.MessageRequests
                .Where(r => r.RequesterId == userId || r.TargetId == userId)
                .ExecuteDeleteAsync();
            await db.CodeConnectionAttempts
                .Where(a => a.RequesterId == userId || a.TargetId == userId)
                .ExecuteDeleteAsync();
            await db.Reports
                .Where(r => r.ReporterId == userId || r.ReportedId == userId)
                .ExecuteDeleteAsync();

            // تفاعلات ورسائل المحادثات التي أرسلها المستخدم (SenderId = Restrict)
            await db.MessageReactions.Where(r => r.UserId == userId).ExecuteDeleteAsync();
            await db.ConversationMessages.Where(m => m.SenderId == userId).ExecuteDeleteAsync();

            // محادثات خاصة يكون طرفاً فيها + مجموعات أنشأها أو عضو فيها
            var privateConvIds = await db.Conversations
                .Where(c => c.User1Id == userId || c.User2Id == userId)
                .Select(c => c.Id)
                .ToListAsync();

            var memberConvIds = await db.ConversationMembers
                .Where(m => m.UserId == userId)
                .Select(m => m.ConversationId)
                .ToListAsync();

            var allRelatedConvIds = privateConvIds
                .Concat(memberConvIds)
                .Distinct()
                .ToList();

            if (allRelatedConvIds.Count > 0)
            {
                var relatedMessageIds = await db.ConversationMessages
                    .Where(m => allRelatedConvIds.Contains(m.ConversationId))
                    .Select(m => m.Id)
                    .ToListAsync();

                if (relatedMessageIds.Count > 0)
                {
                    await db.MessageReactions
                        .Where(r => relatedMessageIds.Contains(r.MessageId))
                        .ExecuteDeleteAsync();
                    await db.UserMessageDeletions
                        .Where(d => relatedMessageIds.Contains(d.MessageId))
                        .ExecuteDeleteAsync();
                }

                await db.UserConversationDeletions
                    .Where(d => allRelatedConvIds.Contains(d.ConversationId))
                    .ExecuteDeleteAsync();
                await db.UserConversationStates
                    .Where(s => allRelatedConvIds.Contains(s.ConversationId))
                    .ExecuteDeleteAsync();
            }

            // حذف ما تبقى من سجلات خاصة بالمستخدم حتى لو خارج المحادثات أعلاه
            await db.UserMessageDeletions.Where(d => d.UserId == userId).ExecuteDeleteAsync();
            await db.UserConversationDeletions.Where(d => d.UserId == userId).ExecuteDeleteAsync();
            await db.UserConversationStates.Where(s => s.UserId == userId).ExecuteDeleteAsync();
            await db.ConversationMembers.Where(m => m.UserId == userId).ExecuteDeleteAsync();

            // للخاص: احذف الرسائل المتبقية ثم المحادثة بالكامل
            if (privateConvIds.Count > 0)
            {
                await db.ConversationMessages
                    .Where(m => privateConvIds.Contains(m.ConversationId))
                    .ExecuteDeleteAsync();
                await db.Conversations
                    .Where(c => privateConvIds.Contains(c.Id))
                    .ExecuteDeleteAsync();
            }

            // للمجموعات: أزل مرجع المنشئ بدل كسر Restrict
            await db.Conversations
                .Where(c => c.CreatedById == userId)
                .ExecuteUpdateAsync(s => s.SetProperty(c => c.CreatedById, (Guid?)null));

            // جلسات الدردشة العشوائية ورسائلها (SenderId = Restrict)
            if (sessions.Count > 0)
            {
                await db.Messages
                    .Where(m => sessions.Contains(m.SessionId) || m.SenderId == userId)
                    .ExecuteDeleteAsync();
                await db.ChatSessions
                    .Where(s => sessions.Contains(s.Id))
                    .ExecuteDeleteAsync();
            }
            else
            {
                await db.Messages.Where(m => m.SenderId == userId).ExecuteDeleteAsync();
            }

            await db.UserBlocks
                .Where(b => b.BlockerId == userId || b.BlockedUserId == userId)
                .ExecuteDeleteAsync();
            await db.Contacts
                .Where(c => c.UserId == userId || c.ContactUserId == userId)
                .ExecuteDeleteAsync();
            await db.SavedCodes.Where(s => s.UserId == userId).ExecuteDeleteAsync();
            await db.DeviceSubscriptions.Where(d => d.UserId == userId).ExecuteDeleteAsync();
            await db.UserNotifications.Where(n => n.UserId == userId).ExecuteDeleteAsync();
            var userPhone = await db.Users.AsNoTracking()
                .Where(u => u.Id == userId)
                .Select(u => u.PhoneNumber)
                .FirstOrDefaultAsync();
            await db.OtpChallenges
                .Where(o => o.UserId == userId || (userPhone != null && o.PhoneNumber == userPhone))
                .ExecuteDeleteAsync();

            // الستوريز (المشاهدات Cascade من السلايد، لكن نمسح مشاهداته أيضاً)
            await db.StoryViews.Where(v => v.ViewerUserId == userId).ExecuteDeleteAsync();
            var slideIds = await db.StorySlides
                .Where(s => s.UserId == userId)
                .Select(s => s.Id)
                .ToListAsync();
            if (slideIds.Count > 0)
            {
                await db.StoryViews.Where(v => slideIds.Contains(v.StorySlideId)).ExecuteDeleteAsync();
                await db.StorySlides.Where(s => slideIds.Contains(s.Id)).ExecuteDeleteAsync();
            }

            await db.NotificationDeliveryLogs
                .Where(l => l.RecipientUserId == userId)
                .ExecuteDeleteAsync();

            // أفلام قصيرة أنشأها كأدمن — SetNull على المستوى المنطقي احتياطاً
            await db.ShortFilms
                .Where(f => f.CreatedByAdminId == userId)
                .ExecuteUpdateAsync(s => s.SetProperty(f => f.CreatedByAdminId, (Guid?)null));

            await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();
            await transaction.CommitAsync();
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    [HttpGet("sessions")]
    public async Task<ActionResult<PagedResult<AdminSessionDto>>> GetSessions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null)
    {
        var query = db.ChatSessions.AsQueryable();
        if (!string.IsNullOrEmpty(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(sess =>
                sess.User1.Name.ToLower().Contains(s) ||
                sess.User2.Name.ToLower().Contains(s));
        }
        var total = await query.CountAsync();
        var sessions = await query
            .Include(s => s.User1)
            .Include(s => s.User2)
            .OrderByDescending(s => s.StartedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(s => new AdminSessionDto(
                s.Id, s.User1.Name, s.User2.Name, s.Type,
                s.StartedAt, s.EndedAt,
                s.Messages.Count,
                s.User1.Avatar,
                s.User2.Avatar
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminSessionDto>(sessions, total, page, pageSize));
    }

    /// <summary>
    /// حذف جلسة واحدة كاملاً (hard delete) - يشمل جميع الرسائل
    /// </summary>
    [HttpDelete("sessions/{id}")]
    public async Task<IActionResult> DeleteSession(Guid id)
    {
        var exists = await db.ChatSessions.AnyAsync(s => s.Id == id);
        if (!exists) return NotFound();

        await db.Messages.Where(m => m.SessionId == id).ExecuteDeleteAsync();
        await db.ChatSessions.Where(s => s.Id == id).ExecuteDeleteAsync();
        return Ok(new { message = "تم حذف الجلسة" });
    }

    /// <summary>
    /// حذف مجموعة جلسات (hard delete)
    /// </summary>
    [HttpDelete("sessions")]
    public async Task<ActionResult<object>> DeleteSessions([FromBody] DeleteSessionsRequest req)
    {
        var ids = (req.Ids ?? Enumerable.Empty<Guid>()).Distinct().ToList();
        if (ids.Count == 0)
            return BadRequest(new { message = "لم يتم تحديد أي جلسات" });

        var existing = await db.ChatSessions
            .Where(s => ids.Contains(s.Id))
            .Select(s => s.Id)
            .ToListAsync();

        await db.Messages.Where(m => ids.Contains(m.SessionId)).ExecuteDeleteAsync();
        await db.ChatSessions.Where(s => ids.Contains(s.Id)).ExecuteDeleteAsync();
        return Ok(new { deleted = existing.Count, message = $"تم حذف {existing.Count} جلسة" });
    }

    /// <summary>
    /// حذف رسالة واحدة داخل جلسة (hard delete)
    /// </summary>
    [HttpDelete("sessions/{sessionId}/messages/{messageId}")]
    public async Task<IActionResult> DeleteSessionMessage(Guid sessionId, Guid messageId)
    {
        var rows = await db.Messages
            .Where(m => m.SessionId == sessionId && m.Id == messageId)
            .ExecuteDeleteAsync();
        return rows > 0 ? Ok(new { message = "تم حذف الرسالة" }) : NotFound();
    }

    /// <summary>
    /// حذف مجموعة رسائل داخل جلسة (hard delete)
    /// </summary>
    [HttpDelete("sessions/{sessionId}/messages")]
    public async Task<ActionResult<object>> DeleteSessionMessages(Guid sessionId, [FromBody] DeleteMessagesRequest req)
    {
        var ids = (req.Ids ?? Enumerable.Empty<Guid>()).Distinct().ToList();
        if (ids.Count == 0)
            return BadRequest(new { message = "لم يتم تحديد أي رسائل" });

        var rows = await db.Messages
            .Where(m => m.SessionId == sessionId && ids.Contains(m.Id))
            .ExecuteDeleteAsync();
        return Ok(new { deleted = rows, message = $"تم حذف {rows} رسالة" });
    }

    [HttpGet("reports")]
    public async Task<ActionResult<PagedResult<AdminReportDto>>> GetReports(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool onlyPending = true)
    {
        var query = db.Reports.AsQueryable();
        if (onlyPending) query = query.Where(r => !r.IsReviewed);

        var total = await query.CountAsync();
        var reports = await query
            .Include(r => r.Reporter)
            .Include(r => r.Reported)
            .OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new AdminReportDto(
                r.Id, r.Reporter.Name, r.Reported.Name,
                r.Reason, r.IsReviewed, r.CreatedAt,
                r.Reporter.Avatar, r.Reported.Avatar
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminReportDto>(reports, total, page, pageSize));
    }

    [HttpPut("reports/{id}/review")]
    public async Task<IActionResult> ReviewReport(Guid id)
    {
        var rows = await db.Reports
            .Where(r => r.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(r => r.IsReviewed, true));

        return rows > 0 ? Ok() : NotFound();
    }

    [HttpGet("stats/chart")]
    public async Task<ActionResult<IEnumerable<ChartPointDto>>> GetChartData()
    {
        var iraqToday = IraqTime.Now.Date;
        var rangeStartUtc = IraqTime.TodayUtcStart.AddDays(-6);
        var days = Enumerable.Range(0, 7)
            .Select(i => iraqToday.AddDays(-6 + i))
            .ToList();

        var sessionCounts = await db.ChatSessions
            .Where(s => s.StartedAt >= rangeStartUtc)
            .GroupBy(s => s.StartedAt.AddHours(3).Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        var userCounts = await db.Users
            .Where(u => u.CreatedAt >= rangeStartUtc)
            .GroupBy(u => u.CreatedAt.AddHours(3).Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        var conversationCounts = await db.Conversations
            .Where(c => c.CreatedAt >= rangeStartUtc)
            .GroupBy(c => c.CreatedAt.AddHours(3).Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        var contactCounts = await db.Contacts
            .Where(c => c.CreatedAt >= rangeStartUtc)
            .GroupBy(c => c.CreatedAt.AddHours(3).Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        var result = days.Select(day => new ChartPointDto(
            day.ToString("MM/dd"),
            sessionCounts.FirstOrDefault(x => x.Date == day)?.Count ?? 0,
            userCounts.FirstOrDefault(x => x.Date == day)?.Count ?? 0,
            conversationCounts.FirstOrDefault(x => x.Date == day)?.Count ?? 0,
            contactCounts.FirstOrDefault(x => x.Date == day)?.Count ?? 0
        ));

        return Ok(result);
    }

    [HttpGet("support/avatar")]
    public async Task<ActionResult<object>> GetSupportAvatar()
    {
        var supportUser = await db.Users
            .Where(u => u.UniqueCode == "NX-SUPPORT")
            .Select(u => new { u.Avatar })
            .FirstOrDefaultAsync();
        if (supportUser == null)
            return Ok(new { avatar = (string?)null });
        return Ok(new { avatar = supportUser.Avatar });
    }

    [HttpPut("support/avatar")]
    public async Task<IActionResult> UpdateSupportAvatar([FromBody] UpdateSupportAvatarDto dto)
    {
        var avatar = dto.Avatar?.Length > 500 ? dto.Avatar[..500] : dto.Avatar;
        var rows = await db.Users
            .Where(u => u.UniqueCode == "NX-SUPPORT")
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.Avatar, avatar));
        return rows > 0 ? Ok() : NotFound(new { message = "مستخدم الدعم غير موجود" });
    }

    [HttpGet("support/sessions")]
    public async Task<ActionResult<PagedResult<AdminSessionDto>>> GetSupportSessions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30,
        [FromQuery] string? search = null)
    {
        var query = db.ChatSessions
            .Include(s => s.User1)
            .Include(s => s.User2)
            .Where(s => s.Type == "support");

        if (!string.IsNullOrEmpty(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(sess => sess.User2.Name.ToLower().Contains(s));
        }

        var total = await query.CountAsync();
        var sessions = await query
            .OrderByDescending(s => s.StartedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(s => new AdminSessionDto(
                s.Id, s.User1.Name, s.User2.Name, s.Type,
                s.StartedAt, s.EndedAt,
                s.Messages.Count,
                s.User1.Avatar,
                s.User2.Avatar
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminSessionDto>(sessions, total, page, pageSize));
    }

    [HttpPost("support/send")]
    public async Task<IActionResult> SendSupportMessage([FromBody] SupportSendDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Content) || dto.Content.Length > 5000)
            return BadRequest(new { message = "محتوى الرسالة غير صالح" });

        var supportUser = await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == "NX-SUPPORT");
        if (supportUser == null)
            return StatusCode(500, new { message = "خدمة الدعم غير متاحة" });

        var session = await db.ChatSessions
            .FirstOrDefaultAsync(s => s.Id == dto.SessionId && s.Type == "support");
        if (session == null)
            return NotFound(new { message = "الجلسة غير موجودة" });

        if (session.EndedAt != null)
        {
            session.EndedAt = null;
        }

        var message = new Message
        {
            SessionId = dto.SessionId,
            SenderId = supportUser.Id,
            Content = dto.Content.Trim(),
            Type = "text"
        };
        db.Messages.Add(message);
        await db.SaveChangesAsync();

        await hubContext.Clients.Group(dto.SessionId.ToString()).SendAsync("ReceiveMessage", new
        {
            message.Id,
            message.SenderId,
            message.Content,
            message.Type,
            message.SentAt
        });

        return Ok(new { message.Id, message.SentAt });
    }

    [HttpGet("messages")]
    public async Task<ActionResult<PagedResult<AdminMessageDto>>> GetMessages(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30,
        [FromQuery] string? search = null,
        [FromQuery] string? type = null,
        [FromQuery] Guid? sessionId = null,
        [FromQuery] Guid? userId = null,
        [FromQuery] DateTime? dateFrom = null,
        [FromQuery] DateTime? dateTo = null)
    {
        var query = db.Messages.Include(m => m.Sender).AsQueryable();

        if (!string.IsNullOrEmpty(search))
            query = query.Where(m => m.Content.Contains(search));

        if (!string.IsNullOrEmpty(type))
            query = query.Where(m => m.Type == type);

        if (sessionId.HasValue)
            query = query.Where(m => m.SessionId == sessionId.Value);

        if (userId.HasValue)
            query = query.Where(m => m.SenderId == userId.Value);

        if (dateFrom.HasValue)
            query = query.Where(m => m.SentAt >= dateFrom.Value);

        if (dateTo.HasValue)
            query = query.Where(m => m.SentAt <= dateTo.Value.AddDays(1));

        var total = await query.CountAsync();
        var messages = await query
            .OrderByDescending(m => m.SentAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(m => new AdminMessageDto(
                m.Id,
                m.Sender.Name,
                m.SessionId.ToString(),
                m.Content,
                m.Type,
                m.SentAt,
                m.Sender.Avatar
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminMessageDto>(messages, total, page, pageSize));
    }

    /// <summary>قائمة المحادثات للإدارة.</summary>
    /// <param name="kind">private = ثنائية فقط (افتراضي)، group = مجموعات فقط</param>
    [HttpGet("conversations")]
    public async Task<ActionResult<PagedResult<AdminConversationDto>>> GetConversations(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] string? kind = null)
    {
        var isGroupList = string.Equals(kind, "group", StringComparison.OrdinalIgnoreCase);

        var query = db.Conversations
            .Include(c => c.User1)
            .Include(c => c.User2)
            .AsQueryable();

        if (isGroupList)
            query = query.Where(c => c.Type == ConversationType.Group);
        else
            query = query.Where(c => c.Type == ConversationType.Private);

        if (!string.IsNullOrEmpty(search))
        {
            var s = search.Trim().ToLower();
            if (isGroupList)
                query = query.Where(c => c.Name != null && c.Name.ToLower().Contains(s));
            else
                query = query.Where(c =>
                    (c.User1 != null && c.User1.Name.ToLower().Contains(s)) ||
                    (c.User2 != null && c.User2.Name.ToLower().Contains(s)));
        }

        var total = await query.CountAsync();
        var conversations = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new AdminConversationDto(
                c.Id,
                c.Type,
                c.User1 != null ? c.User1.Name : null,
                c.User2 != null ? c.User2.Name : null,
                c.Type == ConversationType.Group ? c.Name : null,
                c.CreatedAt,
                c.Messages.Count,
                c.Messages.Any() ? c.Messages.Max(m => m.SentAt) : (DateTime?)null,
                c.User1 != null ? c.User1.Avatar : null,
                c.User2 != null ? c.User2.Avatar : null
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminConversationDto>(conversations, total, page, pageSize));
    }

    [HttpGet("conversations/{id}/messages")]
    public async Task<ActionResult<PagedResult<AdminConversationMessageDto>>> GetConversationMessages(
        Guid id,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var query = db.ConversationMessages
            .Include(m => m.Sender)
            .Where(m => m.ConversationId == id);

        var total = await query.CountAsync();
        var rows = await query
            .OrderBy(m => m.SentAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(m => new { m.Id, SenderName = m.Sender.Name, SenderAvatar = m.Sender.Avatar, m.Content, m.Type, m.SentAt })
            .ToListAsync();

        var messages = rows
            .Select(m => new AdminConversationMessageDto(
                m.Id,
                m.SenderName,
                messageCrypto.DecryptFromStorage(m.Content ?? ""),
                m.Type,
                m.SentAt,
                m.SenderAvatar))
            .ToList();

        return Ok(new PagedResult<AdminConversationMessageDto>(messages, total, page, pageSize));
    }

    /// <summary>
    /// حذف محادثة واحدة كاملاً (hard delete)
    /// </summary>
    [HttpDelete("conversations/{id}")]
    public async Task<IActionResult> DeleteConversation(Guid id)
    {
        var exists = await db.Conversations.AnyAsync(c => c.Id == id);
        if (!exists) return NotFound();

        await DeleteConversationsCascade(new[] { id });
        return Ok(new { message = "تم حذف المحادثة" });
    }

    /// <summary>
    /// حذف مجموعة محادثات (hard delete)
    /// </summary>
    [HttpDelete("conversations")]
    public async Task<ActionResult<object>> DeleteConversations([FromBody] DeleteConversationsRequest req)
    {
        var ids = (req.Ids ?? Enumerable.Empty<Guid>()).Distinct().ToList();
        if (ids.Count == 0)
            return BadRequest(new { message = "لم يتم تحديد أي محادثات" });

        var existing = await db.Conversations
            .Where(c => ids.Contains(c.Id))
            .Select(c => c.Id)
            .ToListAsync();

        await DeleteConversationsCascade(existing);
        return Ok(new { deleted = existing.Count, message = $"تم حذف {existing.Count} محادثة" });
    }

    /// <summary>
    /// حذف رسالة واحدة داخل محادثة (hard delete)
    /// </summary>
    [HttpDelete("conversations/{conversationId}/messages/{messageId}")]
    public async Task<IActionResult> DeleteConversationMessage(Guid conversationId, Guid messageId)
    {
        var msg = await db.ConversationMessages
            .FirstOrDefaultAsync(m => m.Id == messageId && m.ConversationId == conversationId);
        if (msg == null) return NotFound();

        await db.UserMessageDeletions.Where(d => d.MessageId == messageId).ExecuteDeleteAsync();
        await db.ConversationMessages.Where(m => m.Id == messageId).ExecuteDeleteAsync();
        return Ok(new { message = "تم حذف الرسالة" });
    }

    /// <summary>
    /// حذف مجموعة رسائل داخل محادثة (hard delete)
    /// </summary>
    [HttpDelete("conversations/{conversationId}/messages")]
    public async Task<ActionResult<object>> DeleteConversationMessages(Guid conversationId, [FromBody] DeleteMessagesRequest req)
    {
        var ids = (req.Ids ?? Enumerable.Empty<Guid>()).Distinct().ToList();
        if (ids.Count == 0)
            return BadRequest(new { message = "لم يتم تحديد أي رسائل" });

        var toDelete = await db.ConversationMessages
            .Where(m => m.ConversationId == conversationId && ids.Contains(m.Id))
            .Select(m => m.Id)
            .ToListAsync();

        await db.UserMessageDeletions.Where(d => toDelete.Contains(d.MessageId)).ExecuteDeleteAsync();
        await db.ConversationMessages.Where(m => toDelete.Contains(m.Id)).ExecuteDeleteAsync();
        return Ok(new { deleted = toDelete.Count, message = $"تم حذف {toDelete.Count} رسالة" });
    }

    private async Task DeleteConversationsCascade(IEnumerable<Guid> conversationIds)
    {
        var ids = conversationIds.ToList();
        if (ids.Count == 0) return;

        var messageIds = await db.ConversationMessages
            .Where(m => ids.Contains(m.ConversationId))
            .Select(m => m.Id)
            .ToListAsync();

        await db.UserMessageDeletions.Where(d => messageIds.Contains(d.MessageId)).ExecuteDeleteAsync();
        await db.UserConversationDeletions.Where(d => ids.Contains(d.ConversationId)).ExecuteDeleteAsync();
        await db.UserConversationStates.Where(s => ids.Contains(s.ConversationId)).ExecuteDeleteAsync();
        await db.ConversationMessages.Where(m => ids.Contains(m.ConversationId)).ExecuteDeleteAsync();
        await db.Conversations.Where(c => ids.Contains(c.Id)).ExecuteDeleteAsync();
    }

    [HttpGet("blocks")]
    public async Task<ActionResult<PagedResult<AdminBlockDto>>> GetBlocks(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null)
    {
        var query = db.UserBlocks
            .Include(b => b.Blocker)
            .Include(b => b.BlockedUser)
            .AsQueryable();

        if (!string.IsNullOrEmpty(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(b =>
                b.Blocker.Name.ToLower().Contains(s) ||
                b.BlockedUser.Name.ToLower().Contains(s));
        }

        var total = await query.CountAsync();
        var blocks = await query
            .OrderByDescending(b => b.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(b => new AdminBlockDto(
                b.Id,
                b.Blocker.Name,
                b.BlockedUser.Name,
                b.CreatedAt,
                b.Blocker.Avatar,
                b.BlockedUser.Avatar
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminBlockDto>(blocks, total, page, pageSize));
    }

    [HttpDelete("blocks/{id}")]
    public async Task<IActionResult> DeleteBlock(Guid id)
    {
        var rows = await db.UserBlocks.Where(b => b.Id == id).ExecuteDeleteAsync();
        return rows > 0 ? Ok() : NotFound();
    }

    [HttpGet("contacts")]
    public async Task<ActionResult<PagedResult<AdminContactDto>>> GetContacts(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null)
    {
        var query = db.Contacts
            .Include(c => c.User)
            .Include(c => c.ContactUser)
            .AsQueryable();

        if (!string.IsNullOrEmpty(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(c =>
                c.User.Name.ToLower().Contains(s) ||
                c.ContactUser.Name.ToLower().Contains(s));
        }

        var total = await query.CountAsync();
        var contacts = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new AdminContactDto(
                c.Id,
                c.User.Name,
                c.ContactUser.Name,
                c.CreatedAt,
                c.User.Avatar,
                c.ContactUser.Avatar
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminContactDto>(contacts, total, page, pageSize));
    }

    [HttpGet("banners")]
    public async Task<ActionResult<IEnumerable<BannerDto>>> GetBanners([FromQuery] string? placement = null)
    {
        var query = db.Banners.AsQueryable();
        if (!string.IsNullOrEmpty(placement))
            query = query.Where(b => b.Placement == placement);

        var banners = await query
            .OrderBy(b => b.Order)
            .ThenBy(b => b.CreatedAt)
            .Select(b => new BannerDto(b.Id, b.ImageUrl, b.Placement, b.Order, b.IsActive, b.Link, b.CreatedAt))
            .ToListAsync();

        return Ok(banners);
    }

    [HttpPost("banners")]
    public async Task<ActionResult<BannerDto>> CreateBanner([FromBody] CreateBannerDto dto)
    {
        var banner = new Banner
        {
            ImageUrl = dto.ImageUrl,
            Placement = dto.Placement,
            Order = dto.Order,
            IsActive = dto.IsActive,
            Link = dto.Link
        };
        db.Banners.Add(banner);
        await db.SaveChangesAsync();
        return Ok(new BannerDto(banner.Id, banner.ImageUrl, banner.Placement, banner.Order, banner.IsActive, banner.Link, banner.CreatedAt));
    }

    [HttpPut("banners/{id}")]
    public async Task<IActionResult> UpdateBanner(Guid id, [FromBody] UpdateBannerDto dto)
    {
        var banner = await db.Banners.FindAsync(id);
        if (banner == null) return NotFound();

        if (dto.ImageUrl != null) banner.ImageUrl = dto.ImageUrl;
        if (dto.Placement != null) banner.Placement = dto.Placement;
        if (dto.Order.HasValue) banner.Order = dto.Order.Value;
        if (dto.IsActive.HasValue) banner.IsActive = dto.IsActive.Value;
        if (dto.Link != null) banner.Link = dto.Link;

        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpDelete("banners/{id}")]
    public async Task<IActionResult> DeleteBanner(Guid id)
    {
        var rows = await db.Banners.Where(b => b.Id == id).ExecuteDeleteAsync();
        return rows > 0 ? Ok() : NotFound();
    }

    [HttpGet("site-content/{key}")]
    public async Task<ActionResult<object>> GetSiteContent(string key)
    {
        var content = await db.SiteContents.FirstOrDefaultAsync(c => c.Key == key);
        if (content == null) return Ok(new { content = "", updatedAt = (DateTime?)null });
        return Ok(new { content.Content, content.UpdatedAt });
    }

    [HttpPut("site-content/{key}")]
    public async Task<IActionResult> UpdateSiteContent(string key, [FromBody] UpdateSiteContentDto dto)
    {
        var existing = await db.SiteContents.FirstOrDefaultAsync(c => c.Key == key);
        if (existing != null)
        {
            existing.Content = dto.Content;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            db.SiteContents.Add(new Core.Entities.SiteContent { Key = key, Content = dto.Content });
        }
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpGet("evolution-whatsapp")]
    public async Task<ActionResult<object>> GetEvolutionWhatsApp()
    {
        var cfg = await evolution.GetConfigAsync();
        var maskedKey = string.IsNullOrEmpty(cfg.ApiKey)
            ? ""
            : (cfg.ApiKey.Length <= 4
                ? "••••••••"
                : $"{new string('•', Math.Min(8, cfg.ApiKey.Length - 4))}{cfg.ApiKey[^Math.Min(4, cfg.ApiKey.Length)..]}");
        return Ok(new
        {
            cfg.Enabled,
            cfg.BaseUrl,
            ApiKey = maskedKey,
            cfg.InstanceName,
            cfg.MessageTemplate,
            cfg.OtpExpiryMinutes,
            cfg.OtpLength,
            HasApiKey = !string.IsNullOrWhiteSpace(cfg.ApiKey)
        });
    }

    [HttpPut("evolution-whatsapp")]
    public async Task<IActionResult> UpdateEvolutionWhatsApp([FromBody] EvolutionWhatsAppConfigDto dto)
    {
        if (dto == null)
            return BadRequest(new { message = "بيانات غير صالحة" });

        var current = await evolution.GetConfigAsync();
        // الإبقاء على المفتاح القديم إذا أُرسل فارغاً أو مقنّعاً
        if (string.IsNullOrWhiteSpace(dto.ApiKey) || dto.ApiKey.Contains('\u2022') || dto.ApiKey.StartsWith("****"))
            dto.ApiKey = current.ApiKey;

        await evolution.SaveConfigAsync(dto);
        return Ok(new { message = "تم حفظ إعدادات واتساب Evolution" });
    }

    [HttpPost("evolution-whatsapp/test")]
    public async Task<IActionResult> TestEvolutionWhatsApp([FromBody] EvolutionTestMessageRequest req)
    {
        if (!PhoneValidationService.TryValidate(req.CountryCode, req.PhoneNumber, out var fullPhone, out var phoneError))
            return BadRequest(new { message = phoneError });

        var cfg = await evolution.GetConfigAsync();
        if (!cfg.Enabled || !EvolutionWhatsAppService.IsConfigured(cfg))
            return BadRequest(new { message = "فعّل الإعدادات وأكمل Base URL و Instance و API Key أولاً" });

        var text = $"اختبار NexChat Evolution — {DateTime.UtcNow:HH:mm} UTC";
        var (ok, error) = await evolution.SendTextAsync(fullPhone, text);
        if (!ok)
            return StatusCode(502, new { message = error });
        return Ok(new { message = "تم إرسال رسالة الاختبار عبر واتساب" });
    }

    [HttpPost("notifications/upload-image")]
    public async Task<IActionResult> UploadNotificationImage(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "لم يتم تحديد ملف" });

        var allowed = new[] { "image/jpeg", "image/png", "image/gif", "image/webp" };
        if (!allowed.Contains(file.ContentType.ToLower()))
            return BadRequest(new { message = "الصور المسموحة: JPEG, PNG, GIF, WebP" });

        if (file.Length > 5 * 1024 * 1024)
            return BadRequest(new { message = "الحد الأقصى 5 ميجابايت" });

        var uploadsPath = Path.Combine(env.WebRootPath ?? "wwwroot", "uploads");
        Directory.CreateDirectory(uploadsPath);

        var ext = Path.GetExtension(file.FileName).ToLower();
        if (!new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" }.Contains(ext))
            ext = ".jpg";
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);

        await using (var dest = new FileStream(filePath, FileMode.Create))
        {
            await file.CopyToAsync(dest);
        }

        var baseUrl = config["Media:BaseUrl"];
        var url = !string.IsNullOrEmpty(baseUrl)
            ? $"{baseUrl.TrimEnd('/')}/uploads/{fileName}"
            : $"{Request.Scheme}://{Request.Host}/uploads/{fileName}";
        return Ok(new { url });
    }

    [HttpPost("notifications/broadcast")]
    public async Task<IActionResult> BroadcastNotification([FromBody] BroadcastNotificationDto dto)
    {
        if (dto == null)
            return BadRequest(new { message = "البيانات مطلوبة" });
        if (string.IsNullOrWhiteSpace(dto.Title) || string.IsNullOrWhiteSpace(dto.Body))
            return BadRequest(new { message = "العنوان والنص مطلوبان" });

        if (dto.Title.Length > 100)
            return BadRequest(new { message = "العنوان طويل جداً" });

        if (dto.Body.Length > 500)
            return BadRequest(new { message = "نص الإشعار طويل جداً" });

        var subscriptionIds = await db.DeviceSubscriptions
            .Select(d => d.OneSignalPlayerId)
            .ToListAsync();

        var (success, recipientsCount, error) = await oneSignal.SendBroadcastAsync(
            subscriptionIds,
            dto.Title.Trim(),
            dto.Body.Trim(),
            dto.ImageUrl?.Trim());

        if (success)
        {
            try
            {
                db.BroadcastNotificationHistory.Add(new BroadcastNotificationHistory
                {
                    Title = TruncateRequired(dto.Title.Trim(), 100),
                    Body = TruncateRequired(dto.Body.Trim(), 500),
                    ImageUrl = TruncateOptional(dto.ImageUrl?.Trim(), 500),
                    RecipientsCount = recipientsCount
                });
                await db.SaveChangesAsync();
            }
            catch (Exception ex)
            {
                // الإرسال نجح — لا نُرجع 500 بسبب فشل حفظ السجل فقط
                return Ok(new
                {
                    message = "تم إرسال الإشعار بنجاح (تعذر حفظ السجل)",
                    recipientsCount,
                    historyError = ex.Message
                });
            }
            return Ok(new { message = "تم إرسال الإشعار بنجاح", recipientsCount });
        }
        return StatusCode(502, new { message = error ?? "فشل إرسال الإشعار", recipientsCount });
    }

    [HttpGet("notifications/broadcast-history")]
    public async Task<ActionResult<PagedResult<AdminBroadcastNotificationDto>>> GetBroadcastHistory(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null)
    {
        var query = db.BroadcastNotificationHistory.AsQueryable();

        if (!string.IsNullOrEmpty(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(n =>
                n.Title.ToLower().Contains(s) ||
                (n.Body != null && n.Body.ToLower().Contains(s)));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(n => n.SentAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(n => new AdminBroadcastNotificationDto(
                n.Id,
                n.Title,
                n.Body,
                n.ImageUrl,
                n.RecipientsCount,
                n.SentAt
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminBroadcastNotificationDto>(items, total, page, pageSize));
    }

    [HttpPost("notifications/broadcast/{id}/resend")]
    public async Task<IActionResult> ResendBroadcastNotification(Guid id)
    {
        var notification = await db.BroadcastNotificationHistory.AsNoTracking()
            .FirstOrDefaultAsync(n => n.Id == id);
        if (notification == null) return NotFound();

        var subscriptionIds = await db.DeviceSubscriptions
            .Select(d => d.OneSignalPlayerId)
            .Distinct()
            .ToListAsync();

        var (success, recipientsCount, error) = await oneSignal.SendBroadcastAsync(
            subscriptionIds,
            notification.Title,
            notification.Body,
            notification.ImageUrl);

        if (success)
        {
            try
            {
                db.BroadcastNotificationHistory.Add(new BroadcastNotificationHistory
                {
                    Title = TruncateRequired(notification.Title, 100),
                    Body = TruncateRequired(notification.Body, 500),
                    ImageUrl = TruncateOptional(notification.ImageUrl, 500),
                    RecipientsCount = recipientsCount
                });
                await db.SaveChangesAsync();
            }
            catch (Exception ex)
            {
                return Ok(new
                {
                    message = "تم إعادة الإرسال بنجاح (تعذر حفظ السجل)",
                    recipientsCount,
                    historyError = ex.Message
                });
            }
            return Ok(new { message = "تم إعادة الإرسال بنجاح", recipientsCount });
        }
        return StatusCode(502, new { message = error ?? "فشل إرسال الإشعار", recipientsCount });
    }

    private static string TruncateRequired(string? value, int max)
    {
        if (string.IsNullOrEmpty(value)) return "";
        return value.Length <= max ? value : value[..max];
    }

    private static string? TruncateOptional(string? value, int max)
    {
        if (value == null) return null;
        if (value.Length <= max) return value;
        return value[..max];
    }

    [HttpPut("banners/reorder")]
    public async Task<IActionResult> ReorderBanners([FromBody] ReorderBannersDto dto)
    {
        var ids = dto.Ids.ToList();
        var banners = await db.Banners.Where(b => ids.Contains(b.Id)).ToListAsync();
        foreach (var b in banners)
        {
            var idx = ids.IndexOf(b.Id);
            if (idx >= 0) b.Order = idx;
        }
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpGet("stories")]
    public async Task<ActionResult<PagedResult<AdminStorySlideDto>>> GetStories(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] string? status = "all")
    {
        pageSize = Math.Clamp(pageSize, 1, 100);
        page = Math.Max(1, page);
        var now = DateTime.UtcNow;

        var query = db.StorySlides.AsQueryable();
        if (string.Equals(status, "active", StringComparison.OrdinalIgnoreCase))
            query = query.Where(s => s.ExpiresAt > now);
        else if (string.Equals(status, "expired", StringComparison.OrdinalIgnoreCase))
            query = query.Where(s => s.ExpiresAt <= now);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            query = query.Where(s =>
                s.User.Name.Contains(term) ||
                (s.Caption != null && s.Caption.Contains(term)) ||
                s.MediaType.Contains(term));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(s => s.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(s => new AdminStorySlideDto(
                s.Id,
                s.UserId,
                s.User.Name,
                s.User.Avatar,
                s.MediaUrl,
                s.MediaType,
                s.Caption,
                s.BackgroundColor,
                s.FilterId,
                s.VideoDurationSeconds,
                s.SortOrder,
                s.CreatedAt,
                s.ExpiresAt,
                s.ExpiresAt > now,
                s.Views.Count))
            .ToListAsync();

        return Ok(new PagedResult<AdminStorySlideDto>(items, total, page, pageSize));
    }

    [HttpDelete("stories/{id:guid}")]
    public async Task<IActionResult> DeleteStory(Guid id)
    {
        var slide = await db.StorySlides.FirstOrDefaultAsync(s => s.Id == id);
        if (slide == null) return NotFound();

        var userId = slide.UserId;
        db.StorySlides.Remove(slide);
        await db.SaveChangesAsync();

        var audienceIds = await storyAudience.GetAudienceUserIdsAsync(userId);
        if (audienceIds.Count > 0)
        {
            await storyHub.Clients.Users(audienceIds.Select(x => x.ToString()).ToList())
                .SendAsync("StoryDeleted", new { userId, slideId = id });
        }

        return NoContent();
    }
}
