using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/short-films")]
[Authorize]
[EnableRateLimiting("api")]
public class ShortFilmsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ShortFilmsPageDto>> GetPage(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 15,
        [FromQuery] Guid? sectionId = null,
        [FromQuery] bool excludeFeatured = true)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 50);

        var query = db.ShortFilms.AsNoTracking().Where(f => f.IsActive);
        if (sectionId.HasValue)
            query = query.Where(f => f.SectionId == sectionId);
        if (excludeFeatured)
            query = query.Where(f => !f.IsFeatured);

        var total = await query.CountAsync();
        var films = await query
            .Include(f => f.Section)
            .OrderBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var items = films.Select(Map).ToList();
        var hasMore = page * pageSize < total;
        return Ok(new ShortFilmsPageDto(items, total, page, pageSize, hasMore));
    }

    [HttpGet("featured")]
    public async Task<ActionResult<IEnumerable<ShortFilmDto>>> GetFeatured(
        [FromQuery] Guid? sectionId = null)
    {
        var query = db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.IsFeatured);
        if (sectionId.HasValue)
            query = query.Where(f => f.SectionId == sectionId);

        var films = await query
            .Include(f => f.Section)
            .OrderBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .ToListAsync();
        return Ok(films.Select(Map));
    }

    [HttpGet("sections")]
    public async Task<ActionResult<IEnumerable<ShortFilmSectionDto>>> GetSections()
    {
        var sections = await db.ShortFilmSections.AsNoTracking()
            .Where(s => s.IsActive)
            .OrderBy(s => s.SortOrder)
            .ThenBy(s => s.Name)
            .ToListAsync();
        var counts = await db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.SectionId != null)
            .GroupBy(f => f.SectionId)
            .Select(g => new { SectionId = g.Key, Count = g.Count() })
            .ToListAsync();
        var countMap = counts.ToDictionary(x => x.SectionId!.Value, x => x.Count);

        return Ok(sections.Select(s => new ShortFilmSectionDto(
            s.Id,
            s.Name,
            s.SortOrder,
            countMap.GetValueOrDefault(s.Id, 0),
            s.ImageUrl)));
    }

    [HttpGet("browse")]
    public async Task<ActionResult<ShortFilmsBrowseDto>> Browse([FromQuery] int previewSize = 8)
    {
        previewSize = Math.Clamp(previewSize, 1, 20);

        var sections = await db.ShortFilmSections.AsNoTracking()
            .Where(s => s.IsActive)
            .OrderBy(s => s.SortOrder)
            .ThenBy(s => s.Name)
            .ToListAsync();

        var sectionRows = new List<ShortFilmSectionBrowseDto>();
        foreach (var section in sections)
        {
            var films = await db.ShortFilms.AsNoTracking()
                .Where(f => f.IsActive && f.SectionId == section.Id && !f.IsFeatured)
                .Include(f => f.Section)
                .OrderBy(f => f.SortOrder)
                .ThenByDescending(f => f.CreatedAt)
                .Take(previewSize)
                .ToListAsync();
            if (films.Count == 0) continue;
            sectionRows.Add(new ShortFilmSectionBrowseDto(
                section.Id,
                section.Name,
                section.SortOrder,
                section.ImageUrl,
                films.Select(Map).ToList()));
        }

        var uncategorized = await db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.SectionId == null && !f.IsFeatured)
            .Include(f => f.Section)
            .OrderBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .Take(previewSize)
            .ToListAsync();

        return Ok(new ShortFilmsBrowseDto(
            sectionRows,
            uncategorized.Select(Map).ToList()));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<ShortFilmDto>> GetById(Guid id)
    {
        var film = await db.ShortFilms.AsNoTracking()
            .Include(f => f.Section)
            .FirstOrDefaultAsync(f => f.Id == id && f.IsActive);
        if (film == null) return NotFound();
        return Ok(Map(film));
    }

    [HttpPost("{id:guid}/view")]
    public async Task<ActionResult<object>> RecordView(Guid id)
    {
        var film = await db.ShortFilms.FirstOrDefaultAsync(f => f.Id == id && f.IsActive);
        if (film == null) return NotFound();

        film.ViewCount++;
        await db.SaveChangesAsync();
        return Ok(new { viewCount = film.ViewCount });
    }

    private static ShortFilmDto Map(Core.Entities.ShortFilm f) =>
        new(
            f.Id,
            f.Title,
            f.Description,
            f.VideoUrl,
            f.ThumbnailUrl,
            f.DurationSeconds,
            f.SectionId,
            f.Section?.Name,
            f.SortOrder,
            f.IsFeatured,
            f.ViewCount,
            f.CreatedAt);
}
