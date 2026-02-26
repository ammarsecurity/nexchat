using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SiteContentController(AppDbContext db) : ControllerBase
{
    [HttpGet("{key}")]
    public async Task<ActionResult<object>> Get(string key)
    {
        var content = await db.SiteContents
            .Where(c => c.Key == key)
            .Select(c => new { c.Content, c.UpdatedAt })
            .FirstOrDefaultAsync();

        if (content == null)
            return Ok(new { content = "", updatedAt = (DateTime?)null });

        return Ok(content);
    }
}
