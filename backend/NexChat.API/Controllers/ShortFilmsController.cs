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
public class ShortFilmsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<ShortFilmsPageDto>> GetPage(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 15,
        [FromQuery] Guid? sectionId = null,
        [FromQuery] Guid? seriesId = null,
        [FromQuery] bool excludeFeatured = true,
        [FromQuery] bool standaloneOnly = false,
        [FromQuery] string? search = null)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 50);

        var query = db.ShortFilms.AsNoTracking().Where(f => f.IsActive);
        if (sectionId.HasValue)
            query = query.Where(f => f.SectionId == sectionId);
        if (seriesId.HasValue)
            query = query.Where(f => f.SeriesId == seriesId);
        else if (standaloneOnly)
            query = query.Where(f => f.SeriesId == null);
        if (excludeFeatured)
            query = query.Where(f => !f.IsFeatured);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            query = query.Where(f =>
                f.Title.Contains(term) ||
                (f.Description != null && f.Description.Contains(term)) ||
                (f.Series != null && f.Series.Title.Contains(term)));
        }

        var total = await query.CountAsync();
        var films = await query
            .Include(f => f.Section)
            .Include(f => f.Series)
            .OrderBy(f => f.SeriesId != null ? f.EpisodeNumber ?? int.MaxValue : f.SortOrder)
            .ThenBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var episodeCounts = await LoadEpisodeCountsAsync(films);
        var items = films.Select(f => Map(f, episodeCounts)).ToList();
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
            .Include(f => f.Series)
            .OrderBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .ToListAsync();
        var episodeCounts = await LoadEpisodeCountsAsync(films);
        return Ok(films.Select(f => Map(f, episodeCounts)));
    }

    [HttpGet("series")]
    public async Task<ActionResult<IEnumerable<ShortFilmSeriesDto>>> GetSeries(
        [FromQuery] Guid? sectionId = null,
        [FromQuery] string? search = null)
    {
        var query = db.ShortFilmSeries.AsNoTracking().Where(s => s.IsActive);
        if (sectionId.HasValue)
            query = query.Where(s => s.SectionId == sectionId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            query = query.Where(s =>
                s.Title.Contains(term) ||
                (s.Description != null && s.Description.Contains(term)));
        }

        var series = await query
            .Include(s => s.Section)
            .OrderBy(s => s.SortOrder)
            .ThenByDescending(s => s.CreatedAt)
            .ToListAsync();

        var counts = await db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.SeriesId != null)
            .GroupBy(f => f.SeriesId)
            .Select(g => new { SeriesId = g.Key, Count = g.Count() })
            .ToListAsync();
        var countMap = counts.ToDictionary(x => x.SeriesId!.Value, x => x.Count);

        return Ok(series.Select(s => new ShortFilmSeriesDto(
            s.Id,
            s.Title,
            s.Description,
            s.CoverUrl,
            s.SectionId,
            s.Section?.Name,
            s.SortOrder,
            s.IsFeatured,
            countMap.GetValueOrDefault(s.Id, 0),
            s.CreatedAt)));
    }

    [HttpGet("series/{id:guid}")]
    public async Task<ActionResult<ShortFilmSeriesDetailDto>> GetSeriesById(Guid id)
    {
        var series = await db.ShortFilmSeries.AsNoTracking()
            .Include(s => s.Section)
            .FirstOrDefaultAsync(s => s.Id == id && s.IsActive);
        if (series == null) return NotFound();

        var episodes = await db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.SeriesId == id)
            .Include(f => f.Section)
            .Include(f => f.Series)
            .OrderBy(f => f.EpisodeNumber ?? int.MaxValue)
            .ThenBy(f => f.SortOrder)
            .ThenBy(f => f.CreatedAt)
            .ToListAsync();

        var count = episodes.Count;
        var countMap = new Dictionary<Guid, int> { [id] = count };
        return Ok(new ShortFilmSeriesDetailDto(
            series.Id,
            series.Title,
            series.Description,
            series.CoverUrl,
            series.SectionId,
            series.Section?.Name,
            series.SortOrder,
            series.IsFeatured,
            count,
            series.CreatedAt,
            episodes.Select(f => Map(f, countMap)).ToList()));
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
                .Include(f => f.Series)
                .OrderBy(f => f.SortOrder)
                .ThenByDescending(f => f.CreatedAt)
                .Take(previewSize)
                .ToListAsync();
            if (films.Count == 0) continue;
            var episodeCounts = await LoadEpisodeCountsAsync(films);
            sectionRows.Add(new ShortFilmSectionBrowseDto(
                section.Id,
                section.Name,
                section.SortOrder,
                section.ImageUrl,
                films.Select(f => Map(f, episodeCounts)).ToList()));
        }

        var uncategorized = await db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.SectionId == null && !f.IsFeatured)
            .Include(f => f.Section)
            .Include(f => f.Series)
            .OrderBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .Take(previewSize)
            .ToListAsync();

        var uncCounts = await LoadEpisodeCountsAsync(uncategorized);
        return Ok(new ShortFilmsBrowseDto(
            sectionRows,
            uncategorized.Select(f => Map(f, uncCounts)).ToList()));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<ShortFilmDto>> GetById(Guid id)
    {
        var film = await db.ShortFilms.AsNoTracking()
            .Include(f => f.Section)
            .Include(f => f.Series)
            .FirstOrDefaultAsync(f => f.Id == id && f.IsActive);
        if (film == null) return NotFound();
        var episodeCounts = await LoadEpisodeCountsAsync([film]);
        return Ok(Map(film, episodeCounts));
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

    private async Task<Dictionary<Guid, int>> LoadEpisodeCountsAsync(IReadOnlyList<ShortFilm> films)
    {
        var seriesIds = films.Where(f => f.SeriesId.HasValue).Select(f => f.SeriesId!.Value).Distinct().ToList();
        if (seriesIds.Count == 0) return new Dictionary<Guid, int>();

        var counts = await db.ShortFilms.AsNoTracking()
            .Where(f => f.IsActive && f.SeriesId != null && seriesIds.Contains(f.SeriesId.Value))
            .GroupBy(f => f.SeriesId)
            .Select(g => new { SeriesId = g.Key, Count = g.Count() })
            .ToListAsync();
        return counts.ToDictionary(x => x.SeriesId!.Value, x => x.Count);
    }

    private static ShortFilmDto Map(ShortFilm f, IReadOnlyDictionary<Guid, int> episodeCounts) =>
        new(
            f.Id,
            f.Title,
            f.Description,
            f.VideoUrl,
            f.ThumbnailUrl,
            f.DurationSeconds,
            f.SectionId,
            f.Section?.Name,
            f.SeriesId,
            f.Series?.Title,
            f.EpisodeNumber,
            f.SeriesId is Guid sid ? episodeCounts.GetValueOrDefault(sid) : null,
            f.SortOrder,
            f.IsFeatured,
            f.ViewCount,
            f.CreatedAt);
}
