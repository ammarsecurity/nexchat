using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "AdminOnly")]
public class AdminController(AppDbContext db) : ControllerBase
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
        [FromQuery] int pageSize = 20)
    {
        var total = await db.ChatSessions.CountAsync();
        var sessions = await db.ChatSessions
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
}
