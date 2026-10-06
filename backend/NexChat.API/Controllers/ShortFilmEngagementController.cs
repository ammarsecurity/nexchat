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
public class ShortFilmEngagementController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : Guid.Empty;

    public record ReactionBody(string Emoji);
    public record EngagementStateDto(
        bool Liked,
        bool WatchLater,
        string? Reaction,
        bool FollowingSeries,
        int LikeCount,
        int CommentCount = 0);

    private static IQueryable<ShortFilm> Published(IQueryable<ShortFilm> q)
    {
        var now = DateTime.UtcNow;
        return q.Where(f => f.IsActive && (f.ScheduledPublishAt == null || f.ScheduledPublishAt <= now));
    }

    [HttpGet("me/engagement/{filmId:guid}")]
    public async Task<ActionResult<EngagementStateDto>> GetEngagement(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var film = await Published(db.ShortFilms.AsNoTracking()).FirstOrDefaultAsync(f => f.Id == filmId);
        if (film == null) return NotFound();
        var liked = await db.ShortFilmLikes.AnyAsync(x => x.ShortFilmId == filmId && x.UserId == UserId);
        var later = await db.ShortFilmWatchLaters.AnyAsync(x => x.ShortFilmId == filmId && x.UserId == UserId);
        var reaction = await db.ShortFilmReactions.AsNoTracking()
            .Where(x => x.ShortFilmId == filmId && x.UserId == UserId)
            .Select(x => x.Emoji)
            .FirstOrDefaultAsync();
        var following = film.SeriesId.HasValue &&
            await db.ShortFilmSeriesFollows.AnyAsync(x => x.SeriesId == film.SeriesId && x.UserId == UserId);
        var likeCount = await db.ShortFilmLikes.CountAsync(x => x.ShortFilmId == filmId);
        var commentCount = await db.ShortFilmComments.CountAsync(x => x.ShortFilmId == filmId && !x.IsHidden);
        return Ok(new EngagementStateDto(liked, later, reaction, following, likeCount, commentCount));
    }

    [HttpPost("films/{filmId:guid}/like")]
    public async Task<IActionResult> Like(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        if (!await Published(db.ShortFilms).AnyAsync(f => f.Id == filmId)) return NotFound();
        if (!await db.ShortFilmLikes.AnyAsync(x => x.ShortFilmId == filmId && x.UserId == UserId))
        {
            db.ShortFilmLikes.Add(new ShortFilmLike { ShortFilmId = filmId, UserId = UserId });
            await db.SaveChangesAsync();
        }
        return NoContent();
    }

    [HttpDelete("films/{filmId:guid}/like")]
    public async Task<IActionResult> Unlike(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        await db.ShortFilmLikes.Where(x => x.ShortFilmId == filmId && x.UserId == UserId).ExecuteDeleteAsync();
        return NoContent();
    }

    [HttpGet("me/likes")]
    public async Task<ActionResult<IEnumerable<ShortFilmDto>>> MyLikes()
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var ids = await db.ShortFilmLikes.AsNoTracking()
            .Where(x => x.UserId == UserId)
            .OrderByDescending(x => x.CreatedAt)
            .Select(x => x.ShortFilmId)
            .Take(100)
            .ToListAsync();
        var films = await Published(db.ShortFilms.AsNoTracking())
            .Where(f => ids.Contains(f.Id))
            .Include(f => f.Section)
            .Include(f => f.Series)
            .ToListAsync();
        var map = films.ToDictionary(f => f.Id);
        return Ok(ids.Where(map.ContainsKey).Select(id => MapSimple(map[id])));
    }

    [HttpPost("films/{filmId:guid}/watch-later")]
    public async Task<IActionResult> WatchLater(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        if (!await Published(db.ShortFilms).AnyAsync(f => f.Id == filmId)) return NotFound();
        if (!await db.ShortFilmWatchLaters.AnyAsync(x => x.ShortFilmId == filmId && x.UserId == UserId))
        {
            db.ShortFilmWatchLaters.Add(new ShortFilmWatchLater { ShortFilmId = filmId, UserId = UserId });
            await db.SaveChangesAsync();
        }
        return NoContent();
    }

    [HttpDelete("films/{filmId:guid}/watch-later")]
    public async Task<IActionResult> RemoveWatchLater(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        await db.ShortFilmWatchLaters.Where(x => x.ShortFilmId == filmId && x.UserId == UserId).ExecuteDeleteAsync();
        return NoContent();
    }

    [HttpGet("me/watch-later")]
    public async Task<ActionResult<IEnumerable<ShortFilmDto>>> MyWatchLater()
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var ids = await db.ShortFilmWatchLaters.AsNoTracking()
            .Where(x => x.UserId == UserId)
            .OrderByDescending(x => x.CreatedAt)
            .Select(x => x.ShortFilmId)
            .Take(100)
            .ToListAsync();
        var films = await Published(db.ShortFilms.AsNoTracking())
            .Where(f => ids.Contains(f.Id))
            .Include(f => f.Section)
            .Include(f => f.Series)
            .ToListAsync();
        var map = films.ToDictionary(f => f.Id);
        return Ok(ids.Where(map.ContainsKey).Select(id => MapSimple(map[id])));
    }

    [HttpPut("films/{filmId:guid}/reaction")]
    public async Task<IActionResult> SetReaction(Guid filmId, [FromBody] ReactionBody body)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var emoji = (body.Emoji ?? "").Trim();
        if (emoji.Length is 0 or > 8) return BadRequest(new { message = "Invalid reaction" });
        if (!await Published(db.ShortFilms).AnyAsync(f => f.Id == filmId)) return NotFound();
        var row = await db.ShortFilmReactions.FirstOrDefaultAsync(x => x.ShortFilmId == filmId && x.UserId == UserId);
        if (row == null)
            db.ShortFilmReactions.Add(new ShortFilmReaction { ShortFilmId = filmId, UserId = UserId, Emoji = emoji });
        else
            row.Emoji = emoji;
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("films/{filmId:guid}/reaction")]
    public async Task<IActionResult> ClearReaction(Guid filmId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        await db.ShortFilmReactions.Where(x => x.ShortFilmId == filmId && x.UserId == UserId).ExecuteDeleteAsync();
        return NoContent();
    }

    [HttpPost("series/{seriesId:guid}/follow")]
    public async Task<IActionResult> FollowSeries(Guid seriesId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        if (!await db.ShortFilmSeries.AnyAsync(s => s.Id == seriesId && s.IsActive)) return NotFound();
        if (!await db.ShortFilmSeriesFollows.AnyAsync(x => x.SeriesId == seriesId && x.UserId == UserId))
        {
            db.ShortFilmSeriesFollows.Add(new ShortFilmSeriesFollow { SeriesId = seriesId, UserId = UserId });
            await db.SaveChangesAsync();
        }
        return NoContent();
    }

    [HttpDelete("series/{seriesId:guid}/follow")]
    public async Task<IActionResult> UnfollowSeries(Guid seriesId)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        await db.ShortFilmSeriesFollows.Where(x => x.SeriesId == seriesId && x.UserId == UserId).ExecuteDeleteAsync();
        return NoContent();
    }

    [HttpGet("me/following-series")]
    public async Task<ActionResult<object>> MyFollowing()
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var ids = await db.ShortFilmSeriesFollows.AsNoTracking()
            .Where(x => x.UserId == UserId)
            .Select(x => x.SeriesId)
            .ToListAsync();
        return Ok(new { seriesIds = ids });
    }

    [HttpGet("recommended")]
    public async Task<ActionResult<IEnumerable<ShortFilmDto>>> Recommended([FromQuery] Guid? sectionId = null)
    {
        if (UserId == Guid.Empty) return Unauthorized();
        var likedSections = await db.ShortFilmLikes.AsNoTracking()
            .Where(x => x.UserId == UserId)
            .Select(x => x.ShortFilm.SectionId)
            .Where(id => id != null)
            .Distinct()
            .Take(5)
            .ToListAsync();
        var sid = sectionId ?? likedSections.FirstOrDefault();
        var query = Published(db.ShortFilms.AsNoTracking()).Where(f => f.SeriesId == null);
        if (sid.HasValue) query = query.Where(f => f.SectionId == sid);
        var films = await query
            .Include(f => f.Section)
            .Include(f => f.Series)
            .OrderByDescending(f => f.ViewCount)
            .ThenByDescending(f => f.CreatedAt)
            .Take(24)
            .ToListAsync();
        return Ok(films.Select(MapSimple));
    }

    private static ShortFilmDto MapSimple(ShortFilm f) => new(
        f.Id, f.Title, f.Description, f.VideoUrl, f.ThumbnailUrl, f.DurationSeconds,
        f.SectionId, f.Section?.Name, f.SeriesId, f.Series?.Title, f.EpisodeNumber, null,
        f.SortOrder, f.IsFeatured, f.ViewCount, f.CreatedAt);
}
