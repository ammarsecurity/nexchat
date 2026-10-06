using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/short-films")]
[Authorize]
[EnableRateLimiting("api")]
public class ShortFilmCommentsController(AppDbContext db) : ControllerBase
{
    private const int MaxBodyLength = 300;

    private Guid UserId => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : Guid.Empty;

    private static IQueryable<ShortFilm> Published(IQueryable<ShortFilm> q)
    {
        var now = DateTime.UtcNow;
        return q.Where(f => f.IsActive && (f.ScheduledPublishAt == null || f.ScheduledPublishAt <= now));
    }

    [HttpGet("films/{filmId:guid}/comments")]
    public async Task<ActionResult<ShortFilmCommentsPageDto>> List(
        Guid filmId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        if (!await Published(db.ShortFilms.AsNoTracking()).AnyAsync(f => f.Id == filmId))
            return NotFound();

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 50);

        var query = db.ShortFilmComments.AsNoTracking()
            .Where(c => c.ShortFilmId == filmId && !c.IsHidden);

        var total = await query.CountAsync();
        var rows = await query
            .Include(c => c.User)
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var items = rows.Select(c => Map(c, UserId)).ToList();
        return Ok(new ShortFilmCommentsPageDto(items, total, page, pageSize, page * pageSize < total));
    }

    [HttpGet("films/{filmId:guid}/comments/count")]
    public async Task<ActionResult<object>> Count(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        if (!await Published(db.ShortFilms.AsNoTracking()).AnyAsync(f => f.Id == filmId))
            return NotFound();
        var count = await db.ShortFilmComments.CountAsync(c => c.ShortFilmId == filmId && !c.IsHidden);
        return Ok(new { count });
    }

    [HttpPost("films/{filmId:guid}/comments")]
    public async Task<ActionResult<ShortFilmCommentDto>> Create(Guid filmId, [FromBody] CreateShortFilmCommentDto dto)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        if (!await Published(db.ShortFilms).AnyAsync(f => f.Id == filmId))
            return NotFound();

        var body = (dto.Body ?? "").Trim();
        if (body.Length is 0 or > MaxBodyLength)
            return BadRequest(new { message = $"Comment must be 1–{MaxBodyLength} characters" });

        // Light spam guard: max 5 comments / minute per user on same film.
        var since = DateTime.UtcNow.AddMinutes(-1);
        var recent = await db.ShortFilmComments.CountAsync(c =>
            c.ShortFilmId == filmId && c.UserId == UserId && c.CreatedAt >= since);
        if (recent >= 5)
            return StatusCode(429, new { message = "Too many comments, try again shortly" });

        var row = new ShortFilmComment
        {
            ShortFilmId = filmId,
            UserId = UserId,
            Body = body,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
        };
        db.ShortFilmComments.Add(row);
        await db.SaveChangesAsync();
        await db.Entry(row).Reference(x => x.User).LoadAsync();
        return Ok(Map(row, UserId));
    }

    [HttpDelete("comments/{commentId:guid}")]
    public async Task<IActionResult> DeleteMine(Guid commentId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var row = await db.ShortFilmComments.FirstOrDefaultAsync(c => c.Id == commentId);
        if (row == null) return NotFound();
        if (row.UserId != UserId) return Forbid();
        db.ShortFilmComments.Remove(row);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("comments/{commentId:guid}/report")]
    public async Task<IActionResult> Report(Guid commentId, [FromBody] ReportShortFilmCommentDto? dto)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var comment = await db.ShortFilmComments.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == commentId && !c.IsHidden);
        if (comment == null) return NotFound();
        if (comment.UserId == UserId)
            return BadRequest(new { message = "Cannot report your own comment" });

        var reason = (dto?.Reason ?? "").Trim();
        if (reason.Length > 200) reason = reason[..200];
        if (reason.Length == 0) reason = "inappropriate";

        var exists = await db.ShortFilmCommentReports
            .AnyAsync(r => r.CommentId == commentId && r.ReporterId == UserId);
        if (!exists)
        {
            db.ShortFilmCommentReports.Add(new ShortFilmCommentReport
            {
                CommentId = commentId,
                ReporterId = UserId,
                Reason = reason,
                CreatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync();
        }
        return NoContent();
    }

    private static ShortFilmCommentDto Map(ShortFilmComment c, Guid me) => new(
        c.Id,
        c.ShortFilmId,
        c.UserId,
        c.User?.Name ?? "",
        c.User?.Avatar,
        c.Body,
        c.UserId == me,
        c.CreatedAt);
}
