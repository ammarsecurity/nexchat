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
    StockVideoImportService stockImport,
    NotificationOutboxService notificationOutbox) : ControllerBase
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

    [HttpGet("stats")]
    public async Task<ActionResult<ShortFilmStatsDto>> GetStats()
    {
        var totalFilms = await db.ShortFilms.CountAsync();
        var activeFilms = await db.ShortFilms.CountAsync(f => f.IsActive);
        var featuredFilms = await db.ShortFilms.CountAsync(f => f.IsActive && f.IsFeatured);
        var totalSeries = await db.ShortFilmSeries.CountAsync(s => s.IsActive);
        var totalLikes = await db.ShortFilmLikes.CountAsync();
        var totalWatchLater = await db.ShortFilmWatchLaters.CountAsync();
        var totalFollows = await db.ShortFilmSeriesFollows.CountAsync();

        var topViews = await db.ShortFilms.AsNoTracking()
            .OrderByDescending(f => f.ViewCount)
            .Take(8)
            .Select(f => new ShortFilmStatsTopDto(f.Id, f.Title, f.ViewCount))
            .ToListAsync();

        var topLikes = await db.ShortFilmLikes.AsNoTracking()
            .GroupBy(x => new { x.ShortFilmId, x.ShortFilm.Title })
            .Select(g => new ShortFilmStatsTopDto(g.Key.ShortFilmId, g.Key.Title, g.Count()))
            .OrderByDescending(x => x.Count)
            .Take(8)
            .ToListAsync();

        return Ok(new ShortFilmStatsDto(
            totalFilms, activeFilms, featuredFilms, totalSeries,
            totalLikes, totalWatchLater, totalFollows, topViews, topLikes));
    }

    [HttpPut("reorder")]
    public async Task<IActionResult> ReorderFilms([FromBody] List<ShortFilmReorderItemDto> items)
    {
        if (items == null || items.Count == 0) return BadRequest(new { message = "Empty reorder list" });
        var ids = items.Select(i => i.Id).ToList();
        var films = await db.ShortFilms.Where(f => ids.Contains(f.Id)).ToListAsync();
        var map = items.ToDictionary(i => i.Id, i => i.SortOrder);
        foreach (var film in films)
        {
            if (map.TryGetValue(film.Id, out var order))
            {
                film.SortOrder = order;
                film.UpdatedAt = DateTime.UtcNow;
            }
        }
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet]
    public async Task<ActionResult<PagedResult<AdminShortFilmDto>>> GetShortFilms(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] string? status = "all",
        [FromQuery] Guid? sectionId = null,
        [FromQuery] Guid? seriesId = null)
    {
        pageSize = Math.Clamp(pageSize, 1, 100);
        page = Math.Max(1, page);

        var query = db.ShortFilms.Include(f => f.Section).Include(f => f.Series).AsQueryable();
        if (sectionId.HasValue)
            query = query.Where(f => f.SectionId == sectionId);
        if (seriesId.HasValue)
            query = query.Where(f => f.SeriesId == seriesId);
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
        var film = await db.ShortFilms.Include(f => f.Section).Include(f => f.Series).FirstOrDefaultAsync(f => f.Id == id);
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

        if (dto.SeriesId is Guid seriesId)
        {
            var seriesOk = await db.ShortFilmSeries.AnyAsync(s => s.Id == seriesId);
            if (!seriesOk) return BadRequest(new { message = "SeriesId not found" });
            if (dto.EpisodeNumber is null or < 1)
                return BadRequest(new { message = "EpisodeNumber is required when SeriesId is set" });
            var dup = await db.ShortFilms.AnyAsync(f => f.SeriesId == seriesId && f.EpisodeNumber == dto.EpisodeNumber);
            if (dup) return Conflict(new { message = "Episode number already exists in this series" });
        }

        var film = new ShortFilm
        {
            Title = dto.Title.Trim(),
            Description = string.IsNullOrWhiteSpace(dto.Description) ? null : dto.Description.Trim(),
            VideoUrl = dto.VideoUrl.Trim(),
            ThumbnailUrl = string.IsNullOrWhiteSpace(dto.ThumbnailUrl) ? null : dto.ThumbnailUrl.Trim(),
            DurationSeconds = dto.DurationSeconds,
            SectionId = dto.SectionId,
            SeriesId = dto.SeriesId,
            EpisodeNumber = dto.SeriesId.HasValue ? dto.EpisodeNumber : null,
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            IsFeatured = dto.IsFeatured,
            ScheduledPublishAt = dto.ScheduledPublishAt,
            CreatedByAdminId = AdminUserId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.ShortFilms.Add(film);
        await db.SaveChangesAsync();
        await db.Entry(film).Reference(f => f.Section).LoadAsync();
        await db.Entry(film).Reference(f => f.Series).LoadAsync();
        if (film.IsActive && film.SeriesId.HasValue &&
            (film.ScheduledPublishAt == null || film.ScheduledPublishAt <= DateTime.UtcNow))
            await NotifySeriesFollowersAsync(film);
        return Ok(MapAdmin(film));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AdminShortFilmDto>> Update(Guid id, [FromBody] UpdateShortFilmDto dto)
    {
        var film = await db.ShortFilms.Include(f => f.Section).Include(f => f.Series).FirstOrDefaultAsync(f => f.Id == id);
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
        if (dto.SetSeriesId == true)
        {
            if (dto.SeriesId is Guid seriesId)
            {
                var seriesOk = await db.ShortFilmSeries.AnyAsync(s => s.Id == seriesId);
                if (!seriesOk) return BadRequest(new { message = "SeriesId not found" });
                var episodeNumber = dto.EpisodeNumber ?? film.EpisodeNumber;
                if (episodeNumber is null or < 1)
                    return BadRequest(new { message = "EpisodeNumber is required when SeriesId is set" });
                var dup = await db.ShortFilms.AnyAsync(f =>
                    f.Id != id && f.SeriesId == seriesId && f.EpisodeNumber == episodeNumber);
                if (dup) return Conflict(new { message = "Episode number already exists in this series" });
                film.SeriesId = seriesId;
                film.EpisodeNumber = episodeNumber;
            }
            else
            {
                film.SeriesId = null;
                film.EpisodeNumber = null;
            }
        }
        else if (dto.EpisodeNumber.HasValue && film.SeriesId.HasValue)
        {
            var dup = await db.ShortFilms.AnyAsync(f =>
                f.Id != id && f.SeriesId == film.SeriesId && f.EpisodeNumber == dto.EpisodeNumber);
            if (dup) return Conflict(new { message = "Episode number already exists in this series" });
            film.EpisodeNumber = dto.EpisodeNumber;
        }
        if (dto.SortOrder.HasValue)
            film.SortOrder = dto.SortOrder.Value;
        if (dto.IsActive.HasValue)
            film.IsActive = dto.IsActive.Value;
        if (dto.IsFeatured.HasValue)
            film.IsFeatured = dto.IsFeatured.Value;
        if (dto.ClearScheduledPublishAt == true)
            film.ScheduledPublishAt = null;
        else if (dto.ScheduledPublishAt.HasValue)
            film.ScheduledPublishAt = dto.ScheduledPublishAt;

        film.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(MapAdmin(film));
    }

    private async Task NotifySeriesFollowersAsync(ShortFilm film)
    {
        try
        {
            if (!film.SeriesId.HasValue) return;
            var seriesTitle = film.Series?.Title
                ?? await db.ShortFilmSeries.AsNoTracking()
                    .Where(s => s.Id == film.SeriesId)
                    .Select(s => s.Title)
                    .FirstOrDefaultAsync()
                ?? "مسلسل";
            var followerIds = await db.ShortFilmSeriesFollows.AsNoTracking()
                .Where(x => x.SeriesId == film.SeriesId)
                .Select(x => x.UserId)
                .Distinct()
                .Take(2000)
                .ToListAsync();
            var ep = film.EpisodeNumber?.ToString() ?? "";
            var title = $"حلقة جديدة · {seriesTitle}";
            var body = string.IsNullOrEmpty(ep) ? film.Title : $"الحلقة {ep}: {film.Title}";
            foreach (var uid in followerIds)
            {
                await notificationOutbox.EnqueueAsync(
                    uid,
                    "short_film_episode",
                    title,
                    body,
                    new Dictionary<string, string>
                    {
                        ["filmId"] = film.Id.ToString(),
                        ["seriesId"] = film.SeriesId.Value.ToString(),
                        ["episodeNumber"] = ep,
                    });
            }
        }
        catch
        {
            // best-effort
        }
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
    [RequestSizeLimit(100 * 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = 100 * 1024 * 1024)]
    public async Task<IActionResult> UploadVideo(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file provided" });

        var contentType = file.ContentType?.ToLower() ?? "";
        if (!AllowedVideoTypes.Contains(contentType) && !contentType.StartsWith("video/"))
            return BadRequest(new { message = "Only video files are allowed (MP4, WebM)" });

        if (file.Length > 100 * 1024 * 1024)
            return BadRequest(new { message = "Max file size is 100MB" });

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
                dto.SeriesId,
                dto.EpisodeNumber,
                dto.SortOrder,
                dto.IsActive,
                dto.IsFeatured,
                AdminUserId);
            if (film.IsActive && film.SeriesId.HasValue &&
                (film.ScheduledPublishAt == null || film.ScheduledPublishAt <= DateTime.UtcNow))
                await NotifySeriesFollowersAsync(film);
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

    private static AdminShortFilmDto MapAdmin(ShortFilm f, int likeCount = 0) =>
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
            f.SortOrder,
            f.IsActive,
            f.IsFeatured,
            f.ViewCount,
            f.ScheduledPublishAt,
            f.CreatedByAdminId,
            f.CreatedAt,
            f.UpdatedAt,
            likeCount);
}
