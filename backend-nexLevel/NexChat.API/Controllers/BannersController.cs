using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BannersController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IEnumerable<object>>> GetBanners([FromQuery] string placement)
    {
        if (string.IsNullOrEmpty(placement))
            return BadRequest("placement is required (home or matching)");

        var banners = await db.Banners
            .Where(b => b.Placement == placement && b.IsActive)
            .OrderBy(b => b.Order)
            .ThenBy(b => b.CreatedAt)
            .Select(b => new { b.Id, b.ImageUrl, b.Link })
            .ToListAsync();

        return Ok(banners);
    }
}
