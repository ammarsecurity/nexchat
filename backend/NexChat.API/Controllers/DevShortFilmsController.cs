using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NexChat.API.Services;
using NexChat.Core.DTOs;

namespace NexChat.API.Controllers;

/// <summary>
/// إضافة فيلم قصير بدون JWT — يحمّل الفيديو والصورة إلى السيرفر.
/// مسموح في Development، أو مع هيدر X-Api-Key = ShortFilmIngest:ApiKey.
/// </summary>
[ApiController]
[Route("api/dev/short-films")]
[AllowAnonymous]
public class DevShortFilmsController(
    ShortFilmIngestService ingest,
    IHostEnvironment env,
    IConfiguration config) : ControllerBase
{
    [HttpPost]
    [RequestSizeLimit(100 * 1024 * 1024)]
    public async Task<ActionResult<AdminShortFilmDto>> Create(
        [FromBody] JsonElement body,
        CancellationToken ct)
    {
        if (!IsIngestAllowed())
            return Unauthorized(new { message = "Invalid or missing X-Api-Key" });

        var title = ReadString(body, "title", "Title");
        var videoUrl = ReadString(body, "video_url", "videoUrl", "VideoUrl");
        if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(videoUrl))
            return BadRequest(new { message = "title and video_url (or videoUrl) are required" });

        // Prefer explicit series_title; fall back to filtered_title as series slug/name for episode batches.
        var seriesTitle = ReadString(body, "series_title", "seriesTitle", "SeriesTitle")
            ?? ReadString(body, "filtered_title", "filteredTitle");
        var episodeNumber = ReadInt(body, "episode_num", "episode_number", "episodeNumber", "EpisodeNumber");

        try
        {
            var film = await ingest.IngestAsync(
                Request,
                title,
                ReadString(body, "description", "Description"),
                videoUrl,
                ReadString(body, "thumbnail_url", "thumbnailUrl", "ThumbnailUrl"),
                ReadInt(body, "duration_seconds", "durationSeconds", "DurationSeconds"),
                ReadGuid(body, "section_id", "sectionId", "SectionId"),
                ReadInt(body, "sort_order", "sortOrder", "SortOrder") ?? episodeNumber ?? 0,
                ReadBool(body, "is_active", "isActive", "IsActive") ?? true,
                ReadBool(body, "is_featured", "isFeatured", "IsFeatured") ?? false,
                seriesTitle,
                ReadGuid(body, "series_id", "seriesId", "SeriesId"),
                episodeNumber,
                ct);

            return Ok(new AdminShortFilmDto(
                film.Id,
                film.Title,
                film.Description,
                film.VideoUrl,
                film.ThumbnailUrl,
                film.DurationSeconds,
                film.SectionId,
                film.Section?.Name,
                film.SeriesId,
                film.Series?.Title,
                film.EpisodeNumber,
                film.SortOrder,
                film.IsActive,
                film.IsFeatured,
                film.ViewCount,
                film.CreatedByAdminId,
                film.CreatedAt,
                film.UpdatedAt));
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (DuplicateShortFilmTitleException ex)
        {
            return Conflict(new { message = ex.Message, skipped = true, title = ex.Title });
        }
        catch (DuplicateShortFilmEpisodeException ex)
        {
            return Conflict(new
            {
                message = ex.Message,
                skipped = true,
                seriesTitle = ex.SeriesTitle,
                episodeNumber = ex.EpisodeNumber
            });
        }
        catch (InvalidOperationException ex)
        {
            return StatusCode(502, new { message = "Download failed", detail = ex.Message });
        }
    }

    private static string? ReadString(JsonElement body, params string[] names)
    {
        foreach (var name in names)
        {
            if (TryGetPropertyIgnoreCase(body, name, out var el) && el.ValueKind == JsonValueKind.String)
            {
                var s = el.GetString();
                if (!string.IsNullOrWhiteSpace(s)) return s;
            }
        }
        return null;
    }

    private static int? ReadInt(JsonElement body, params string[] names)
    {
        foreach (var name in names)
        {
            if (!TryGetPropertyIgnoreCase(body, name, out var el)) continue;
            if (el.ValueKind == JsonValueKind.Number && el.TryGetInt32(out var n)) return n;
            if (el.ValueKind == JsonValueKind.String && int.TryParse(el.GetString(), out var p)) return p;
        }
        return null;
    }

    private static bool? ReadBool(JsonElement body, params string[] names)
    {
        foreach (var name in names)
        {
            if (!TryGetPropertyIgnoreCase(body, name, out var el)) continue;
            if (el.ValueKind is JsonValueKind.True or JsonValueKind.False) return el.GetBoolean();
            if (el.ValueKind == JsonValueKind.String && bool.TryParse(el.GetString(), out var p)) return p;
        }
        return null;
    }

    private static Guid? ReadGuid(JsonElement body, params string[] names)
    {
        foreach (var name in names)
        {
            if (!TryGetPropertyIgnoreCase(body, name, out var el)) continue;
            if (el.ValueKind == JsonValueKind.String && Guid.TryParse(el.GetString(), out var g)) return g;
        }
        return null;
    }

    private static bool TryGetPropertyIgnoreCase(JsonElement body, string name, out JsonElement value)
    {
        if (body.ValueKind != JsonValueKind.Object)
        {
            value = default;
            return false;
        }
        foreach (var prop in body.EnumerateObject())
        {
            if (string.Equals(prop.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                value = prop.Value;
                return true;
            }
        }
        value = default;
        return false;
    }

    private bool IsIngestAllowed()
    {
        if (env.IsDevelopment())
            return true;

        var expected = config["ShortFilmIngest:ApiKey"];
        if (string.IsNullOrWhiteSpace(expected))
            return false;

        var provided = Request.Headers["X-Api-Key"].FirstOrDefault()
            ?? Request.Query["apiKey"].FirstOrDefault();
        if (string.IsNullOrEmpty(provided))
            return false;

        var a = Encoding.UTF8.GetBytes(provided);
        var b = Encoding.UTF8.GetBytes(expected);
        return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
    }
}
