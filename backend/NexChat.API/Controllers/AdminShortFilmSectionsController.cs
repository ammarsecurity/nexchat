using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/admin/short-film-sections")]
[Authorize(Policy = "AdminOnly")]
public class AdminShortFilmSectionsController(
    AppDbContext db,
    IWebHostEnvironment env,
    IConfiguration config) : ControllerBase
{
    private static readonly string[] AllowedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];

    [HttpGet]
    public async Task<ActionResult<IEnumerable<AdminShortFilmSectionDto>>> GetAll()
    {
        var sections = await db.ShortFilmSections
            .OrderBy(s => s.SortOrder)
            .ThenBy(s => s.Name)
            .ToListAsync();
        var counts = await db.ShortFilms
            .Where(f => f.SectionId != null)
            .GroupBy(f => f.SectionId)
            .Select(g => new { SectionId = g.Key, Count = g.Count() })
            .ToListAsync();
        var countMap = counts.ToDictionary(x => x.SectionId!.Value, x => x.Count);

        return Ok(sections.Select(s => Map(s, countMap.GetValueOrDefault(s.Id, 0))));
    }

    [HttpPost]
    public async Task<ActionResult<AdminShortFilmSectionDto>> Create([FromBody] CreateShortFilmSectionDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Name))
            return BadRequest(new { message = "Name is required" });

        var section = new ShortFilmSection
        {
            Name = dto.Name.Trim(),
            ImageUrl = string.IsNullOrWhiteSpace(dto.ImageUrl) ? null : dto.ImageUrl.Trim(),
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        db.ShortFilmSections.Add(section);
        await db.SaveChangesAsync();
        return Ok(Map(section, 0));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AdminShortFilmSectionDto>> Update(Guid id, [FromBody] UpdateShortFilmSectionDto dto)
    {
        var section = await db.ShortFilmSections.FirstOrDefaultAsync(s => s.Id == id);
        if (section == null) return NotFound();

        if (dto.Name != null)
        {
            if (string.IsNullOrWhiteSpace(dto.Name))
                return BadRequest(new { message = "Name cannot be empty" });
            section.Name = dto.Name.Trim();
        }
        if (dto.SortOrder.HasValue)
            section.SortOrder = dto.SortOrder.Value;
        if (dto.IsActive.HasValue)
            section.IsActive = dto.IsActive.Value;
        if (dto.ClearImageUrl == true)
            section.ImageUrl = null;
        else if (dto.ImageUrl != null)
            section.ImageUrl = string.IsNullOrWhiteSpace(dto.ImageUrl) ? null : dto.ImageUrl.Trim();

        section.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        var count = await db.ShortFilms.CountAsync(f => f.SectionId == id);
        return Ok(Map(section, count));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var section = await db.ShortFilmSections.FirstOrDefaultAsync(s => s.Id == id);
        if (section == null) return NotFound();

        var films = await db.ShortFilms.Where(f => f.SectionId == id).ToListAsync();
        foreach (var film in films)
            film.SectionId = null;

        db.ShortFilmSections.Remove(section);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("upload-image")]
    public async Task<IActionResult> UploadImage(IFormFile file)
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

    private static AdminShortFilmSectionDto Map(ShortFilmSection s, int filmCount) =>
        new(s.Id, s.Name, s.SortOrder, s.IsActive, filmCount, s.ImageUrl, s.CreatedAt, s.UpdatedAt);
}
