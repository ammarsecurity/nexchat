using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/admin/short-film-comments")]
[Authorize(Policy = "AdminOnly")]
public class AdminShortFilmCommentsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<object>> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30,
        [FromQuery] string? status = "all",
        [FromQuery] Guid? filmId = null)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = db.ShortFilmComments.AsNoTracking()
            .Include(c => c.User)
            .Include(c => c.ShortFilm)
            .Include(c => c.Reports)
            .AsQueryable();

        if (filmId.HasValue)
            query = query.Where(c => c.ShortFilmId == filmId);
        if (string.Equals(status, "hidden", StringComparison.OrdinalIgnoreCase))
            query = query.Where(c => c.IsHidden);
        else if (string.Equals(status, "reported", StringComparison.OrdinalIgnoreCase))
            query = query.Where(c => c.Reports.Any(r => !r.IsReviewed));
        else if (string.Equals(status, "visible", StringComparison.OrdinalIgnoreCase))
            query = query.Where(c => !c.IsHidden);

        var total = await query.CountAsync();
        var rows = await query
            .OrderByDescending(c => c.Reports.Count(r => !r.IsReviewed))
            .ThenByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var items = rows.Select(c => new AdminShortFilmCommentDto(
            c.Id,
            c.ShortFilmId,
            c.ShortFilm?.Title ?? "",
            c.UserId,
            c.User?.Name ?? "",
            c.User?.Avatar,
            c.Body,
            c.IsHidden,
            c.Reports.Count,
            c.CreatedAt)).ToList();

        return Ok(new { items, total, page, pageSize, hasMore = page * pageSize < total });
    }

    [HttpPost("{id:guid}/hide")]
    public async Task<IActionResult> Hide(Guid id)
    {
        var row = await db.ShortFilmComments.Include(c => c.Reports).FirstOrDefaultAsync(c => c.Id == id);
        if (row == null) return NotFound();
        row.IsHidden = true;
        row.UpdatedAt = DateTime.UtcNow;
        foreach (var r in row.Reports.Where(x => !x.IsReviewed))
            r.IsReviewed = true;
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{id:guid}/unhide")]
    public async Task<IActionResult> Unhide(Guid id)
    {
        var row = await db.ShortFilmComments.FirstOrDefaultAsync(c => c.Id == id);
        if (row == null) return NotFound();
        row.IsHidden = false;
        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var row = await db.ShortFilmComments.FirstOrDefaultAsync(c => c.Id == id);
        if (row == null) return NotFound();
        db.ShortFilmComments.Remove(row);
        await db.SaveChangesAsync();
        return NoContent();
    }
}
