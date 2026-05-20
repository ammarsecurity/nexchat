using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.API.Services.StockVideo;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/admin/short-films")]
[Authorize(Policy = "AdminOnly")]
public class AdminShortFilmsController(
    AppDbContext db,
    IWebHostEnvironment env,
    IConfiguration config,
    StockVideoCatalogService stockCatalog,
    StockVideoImportService stockImport) : ControllerBase
{
    private static readonly string[] AllowedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];
    private static readonly string[] AllowedVideoTypes = ["video/mp4", "video/webm", "video/quicktime"];

    private Guid? AdminUserId
    {
        get
        {
            var id = User.FindFirstValue(ClaimTypes.NameIdentifier);
            return Guid.TryParse(id, out var g) ? g : null;
        }
    }

    [HttpGet]
    public async Task<ActionResult<PagedResult<AdminShortFilmDto>>> GetShortFilms(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] string? status = "all",
        [FromQuery] Guid? sectionId = null)
    {
        pageSize = Math.Clamp(pageSize, 1, 100);
        page = Math.Max(1, page);

        var query = db.ShortFilms.Include(f => f.Section).AsQueryable();
        if (sectionId.HasValue)
            query = query.Where(f => f.SectionId == sectionId);
        if (string.Equals(status, "active", StringComparison.OrdinalIgnoreCase))
            query = query.Where(f => f.IsActive);
        else if (string.Equals(status, "inactive", StringComparison.OrdinalIgnoreCase))
            query = query.Where(f => !f.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            query = query.Where(f =>
                f.Title.Contains(term) ||
                (f.Description != null && f.Description.Contains(term)));
        }

        var total = await query.CountAsync();
        var films = await query
            .OrderBy(f => f.SortOrder)
            .ThenByDescending(f => f.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();
        var items = films.Select(MapAdmin).ToList();

        return Ok(new PagedResult<AdminShortFilmDto>(items, total, page, pageSize));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<AdminShortFilmDto>> GetShortFilm(Guid id)
    {
        var film = await db.ShortFilms.Include(f => f.Section).FirstOrDefaultAsync(f => f.Id == id);
        if (film == null) return NotFound();
        return Ok(MapAdmin(film));
    }

    [HttpPost]
    public async Task<ActionResult<AdminShortFilmDto>> Create([FromBody] CreateShortFilmDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Title))
            return BadRequest(new { message = "Title is required" });
        if (string.IsNullOrWhiteSpace(dto.VideoUrl))
            return BadRequest(new { message = "VideoUrl is required" });

        var film = new ShortFilm
        {
            Title = dto.Title.Trim(),
            Description = string.IsNullOrWhiteSpace(dto.Description) ? null : dto.Description.Trim(),
            VideoUrl = dto.VideoUrl.Trim(),
            ThumbnailUrl = string.IsNullOrWhiteSpace(dto.ThumbnailUrl) ? null : dto.ThumbnailUrl.Trim(),
            DurationSeconds = dto.DurationSeconds,
            SectionId = dto.SectionId,
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            IsFeatured = dto.IsFeatured,
            CreatedByAdminId = AdminUserId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.ShortFilms.Add(film);
        await db.SaveChangesAsync();
        await db.Entry(film).Reference(f => f.Section).LoadAsync();
        return Ok(MapAdmin(film));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AdminShortFilmDto>> Update(Guid id, [FromBody] UpdateShortFilmDto dto)
    {
        var film = await db.ShortFilms.Include(f => f.Section).FirstOrDefaultAsync(f => f.Id == id);
        if (film == null) return NotFound();

        if (dto.Title != null)
        {
            if (string.IsNullOrWhiteSpace(dto.Title))
                return BadRequest(new { message = "Title cannot be empty" });
            film.Title = dto.Title.Trim();
        }
        if (dto.Description != null)
            film.Description = string.IsNullOrWhiteSpace(dto.Description) ? null : dto.Description.Trim();
        if (dto.VideoUrl != null)
        {
            if (string.IsNullOrWhiteSpace(dto.VideoUrl))
                return BadRequest(new { message = "VideoUrl cannot be empty" });
            film.VideoUrl = dto.VideoUrl.Trim();
        }
        if (dto.ThumbnailUrl != null)
            film.ThumbnailUrl = string.IsNullOrWhiteSpace(dto.ThumbnailUrl) ? null : dto.ThumbnailUrl.Trim();
        if (dto.DurationSeconds.HasValue)
            film.DurationSeconds = dto.DurationSeconds;
        if (dto.SetSectionId == true)
            film.SectionId = dto.SectionId;
        if (dto.SortOrder.HasValue)
            film.SortOrder = dto.SortOrder.Value;
        if (dto.IsActive.HasValue)
            film.IsActive = dto.IsActive.Value;
        if (dto.IsFeatured.HasValue)
            film.IsFeatured = dto.IsFeatured.Value;

        film.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(MapAdmin(film));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var film = await db.ShortFilms.FirstOrDefaultAsync(f => f.Id == id);
        if (film == null) return NotFound();

        UploadFileHelper.TryDeleteUploadFile(env, film.VideoUrl);
        UploadFileHelper.TryDeleteUploadFile(env, film.ThumbnailUrl);
        db.ShortFilms.Remove(film);
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("upload-video")]
    public async Task<IActionResult> UploadVideo(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        var contentType = file.ContentType?.ToLower() ?? "";
        if (!AllowedVideoTypes.Contains(contentType) && !contentType.StartsWith("video/"))
            return BadRequest(new { message = "Only video files are allowed (MP4, WebM)" });

        if (file.Length > 50 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 50MB" });

        await using var stream = file.OpenReadStream();
        var url = await UploadFileHelper.SaveUploadAsync(
            env, config, Request, stream, file.FileName,
            [".mp4", ".webm", ".mov"], ".mp4",
            UploadFileHelper.ShortFilmSubfolder);
        return Ok(new { url });
    }

    [HttpGet("stock/providers")]
    public ActionResult<StockVideoProvidersDto> GetStockProviders()
    {
        var providers = stockCatalog.GetConfiguredProviders();
        return Ok(new StockVideoProvidersDto(providers));
    }

    [HttpGet("stock/search")]
    public async Task<ActionResult<StockVideoSearchResultDto>> SearchStockVideos(
        [FromQuery] string provider,
        [FromQuery] string query,
        [FromQuery] int page = 1)
    {
        try
        {
            var result = await stockCatalog.SearchAsync(provider, query, page);
            var items = result.Items.Select(i => new StockVideoSearchItemDto(
                i.Provider,
                i.ExternalId,
                i.Title,
                i.Description,
                i.ThumbnailUrl,
                i.VideoDownloadUrl,
                i.DurationSeconds,
                i.AuthorName,
                i.SourcePageUrl)).ToList();
            return Ok(new StockVideoSearchResultDto(
                items, result.Page, result.PerPage, result.TotalResults, result.HasMore));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (HttpRequestException ex)
        {
            return StatusCode(502, new { message = "Stock provider request failed", detail = ex.Message });
        }
    }

    [HttpPost("stock/import")]
    public async Task<ActionResult<AdminShortFilmDto>> ImportStockVideo([FromBody] ImportStockVideoDto dto)
    {
        try
        {
            var film = await stockImport.ImportAsync(
                Request,
                dto.Provider,
                dto.ExternalId,
                dto.Title,
                dto.Description,
                dto.VideoDownloadUrl,
                dto.ThumbnailUrl,
                dto.DurationSeconds,
                dto.SectionId,
                dto.SortOrder,
                dto.IsActive,
                dto.IsFeatured,
                AdminUserId);
            return Ok(MapAdmin(film));
        }
        catch (InvalidOperationException ex)
        {
            return Conflict(new { message = ex.Message });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (HttpRequestException ex)
        {
            return StatusCode(502, new { message = "Download from stock provider failed", detail = ex.Message });
        }
    }

    [HttpPost("upload-thumbnail")]
    public async Task<IActionResult> UploadThumbnail(IFormFile file)
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

    private static AdminShortFilmDto MapAdmin(ShortFilm f) =>
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
            f.IsActive,
            f.IsFeatured,
            f.ViewCount,
            f.CreatedByAdminId,
            f.CreatedAt,
            f.UpdatedAt);
}
