using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "AdminOnly")]
public class AdminController(AppDbContext db, IHubContext<ChatHub> hubContext) : ControllerBase
{
    [HttpGet("stats")]
    public async Task<ActionResult<AdminStatsDto>> GetStats()
    {
        var today = DateTime.UtcNow.Date;

        var stats = new AdminStatsDto(
            TotalUsers: await db.Users.CountAsync(),
            OnlineUsers: await db.Users.CountAsync(u => u.IsOnline),
            ActiveSessions: await db.ChatSessions.CountAsync(s => s.EndedAt == null),
            TotalSessionsToday: await db.ChatSessions.CountAsync(s => s.StartedAt >= today),
            TotalMessagesToday: await db.Messages.CountAsync(m => m.SentAt >= today),
            PendingReports: await db.Reports.CountAsync(r => !r.IsReviewed)
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
            .Select(u => new AdminUserDto(u.Id, u.Name, u.Gender, u.UniqueCode, u.IsOnline, u.IsBanned, u.CreatedAt))
            .ToListAsync();

        return Ok(new PagedResult<AdminUserDto>(users, total, page, pageSize));
    }

    [HttpPut("users/{id}/ban")]
    public async Task<IActionResult> BanUser(Guid id, [FromBody] bool ban)
    {
        var rows = await db.Users
            .Where(u => u.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsBanned, ban));

        return rows > 0 ? Ok() : NotFound();
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
                s.Messages.Count
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminSessionDto>(sessions, total, page, pageSize));
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
                r.Reason, r.IsReviewed, r.CreatedAt
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
        var days = Enumerable.Range(0, 7)
            .Select(i => DateTime.UtcNow.Date.AddDays(-6 + i))
            .ToList();

        var sessionCounts = await db.ChatSessions
            .Where(s => s.StartedAt >= days[0])
            .GroupBy(s => s.StartedAt.Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        var userCounts = await db.Users
            .Where(u => u.CreatedAt >= days[0])
            .GroupBy(u => u.CreatedAt.Date)
            .Select(g => new { Date = g.Key, Count = g.Count() })
            .ToListAsync();

        var result = days.Select(day => new ChartPointDto(
            day.ToString("MM/dd"),
            sessionCounts.FirstOrDefault(x => x.Date == day)?.Count ?? 0,
            userCounts.FirstOrDefault(x => x.Date == day)?.Count ?? 0
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
                s.Messages.Count
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
                m.SentAt
            ))
            .ToListAsync();

        return Ok(new PagedResult<AdminMessageDto>(messages, total, page, pageSize));
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
}
