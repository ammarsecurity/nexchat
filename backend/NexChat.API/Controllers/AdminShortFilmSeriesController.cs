using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/admin/short-film-series")]
[Authorize(Policy = "AdminOnly")]
public class AdminShortFilmSeriesController(
    AppDbContext db,
    IWebHostEnvironment env,
    IConfiguration config) : ControllerBase
{
    private static readonly string[] AllowedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];

    [HttpGet]
    public async Task<ActionResult<IEnumerable<AdminShortFilmSeriesDto>>> GetAll()
    {
        var series = await db.ShortFilmSeries
            .Include(s => s.Section)
            .OrderBy(s => s.SortOrder)
            .ThenBy(s => s.Title)
            .ToListAsync();
        var counts = await db.ShortFilms
            .Where(f => f.SeriesId != null)
            .GroupBy(f => f.SeriesId)
            .Select(g => new { SeriesId = g.Key, Count = g.Count() })
            .ToListAsync();
        var countMap = counts.ToDictionary(x => x.SeriesId!.Value, x => x.Count);
        return Ok(series.Select(s => Map(s, countMap.GetValueOrDefault(s.Id, 0))));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<AdminShortFilmSeriesDto>> GetById(Guid id)
    {
        var series = await db.ShortFilmSeries.Include(s => s.Section).FirstOrDefaultAsync(s => s.Id == id);
        if (series == null) return NotFound();
        var count = await db.ShortFilms.CountAsync(f => f.SeriesId == id);
        return Ok(Map(series, count));
    }

    [HttpPost]
    public async Task<ActionResult<AdminShortFilmSeriesDto>> Create([FromBody] CreateShortFilmSeriesDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Title))
            return BadRequest(new { message = "Title is required" });

        if (dto.SectionId is Guid sid)
        {
            var ok = await db.ShortFilmSections.AnyAsync(s => s.Id == sid);
            if (!ok) return BadRequest(new { message = "SectionId not found" });
        }

        var series = new ShortFilmSeries
        {
            Title = dto.Title.Trim(),
            Description = string.IsNullOrWhiteSpace(dto.Description) ? null : dto.Description.Trim(),
            CoverUrl = string.IsNullOrWhiteSpace(dto.CoverUrl) ? null : dto.CoverUrl.Trim(),
            SectionId = dto.SectionId,
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            IsFeatured = dto.IsFeatured,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        db.ShortFilmSeries.Add(series);
        await db.SaveChangesAsync();
        await db.Entry(series).Reference(s => s.Section).LoadAsync();
        return Ok(Map(series, 0));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AdminShortFilmSeriesDto>> Update(Guid id, [FromBody] UpdateShortFilmSeriesDto dto)
    {
        var series = await db.ShortFilmSeries.Include(s => s.Section).FirstOrDefaultAsync(s => s.Id == id);
        if (series == null) return NotFound();

        if (dto.Title != null)
        {
            if (string.IsNullOrWhiteSpace(dto.Title))
                return BadRequest(new { message = "Title cannot be empty" });
            series.Title = dto.Title.Trim();
        }
        if (dto.Description != null)
            series.Description = string.IsNullOrWhiteSpace(dto.Description) ? null : dto.Description.Trim();
        if (dto.ClearCoverUrl == true)
            series.CoverUrl = null;
        else if (dto.CoverUrl != null)
            series.CoverUrl = string.IsNullOrWhiteSpace(dto.CoverUrl) ? null : dto.CoverUrl.Trim();
        if (dto.SetSectionId == true)
            series.SectionId = dto.SectionId;
        if (dto.SortOrder.HasValue)
            series.SortOrder = dto.SortOrder.Value;
        if (dto.IsActive.HasValue)
            series.IsActive = dto.IsActive.Value;
        if (dto.IsFeatured.HasValue)
            series.IsFeatured = dto.IsFeatured.Value;

        series.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        var count = await db.ShortFilms.CountAsync(f => f.SeriesId == id);
        return Ok(Map(series, count));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var series = await db.ShortFilmSeries.FirstOrDefaultAsync(s => s.Id == id);
        if (series == null) return NotFound();

        var films = await db.ShortFilms.Where(f => f.SeriesId == id).ToListAsync();
        foreach (var film in films)
        {
            film.SeriesId = null;
            film.EpisodeNumber = null;
        }

        UploadFileHelper.TryDeleteUploadFile(env, series.CoverUrl);
        db.ShortFilmSeries.Remove(series);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("upload-cover")]
    public async Task<IActionResult> UploadCover(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        if (!AllowedImageTypes.Contains(file.ContentType.ToLower()))
            return BadRequest(new { message = "Only images are allowed (JPEG, PNG, GIF, WebP)" });

        if (file.Length > 10 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 10MB" });

        await using var stream = file.OpenReadStream();
        var url = await UploadFileHelper.SaveUploadAsync(
            env, config, Request, stream, file.FileName,
            [".jpg", ".jpeg", ".png", ".gif", ".webp"], ".jpg",
            UploadFileHelper.ShortFilmSubfolder);
        return Ok(new { url });
    }

    private static AdminShortFilmSeriesDto Map(ShortFilmSeries s, int episodesCount) =>
        new(
            s.Id,
            s.Title,
            s.Description,
            s.CoverUrl,
            s.SectionId,
            s.Section?.Name,
            s.SortOrder,
            s.IsActive,
            s.IsFeatured,
            episodesCount,
            s.CreatedAt,
            s.UpdatedAt);
}
