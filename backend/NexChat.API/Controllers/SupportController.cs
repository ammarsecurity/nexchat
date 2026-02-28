using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/support")]
[Authorize]
[Microsoft.AspNetCore.RateLimiting.EnableRateLimiting("api")]
public class SupportController(AppDbContext db) : ControllerBase
{
    [HttpGet("session")]
    public async Task<ActionResult<object>> GetOrCreateSession()
    {
        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdStr) || !Guid.TryParse(userIdStr, out var userId))
            return Unauthorized();

        var supportUser = await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == "NX-SUPPORT");
        if (supportUser == null)
            return StatusCode(500, new { message = "خدمة الدعم غير متاحة" });

        var session = await db.ChatSessions
            .Include(s => s.User1)
            .Include(s => s.User2)
            .FirstOrDefaultAsync(s =>
                s.Type == "support" &&
                s.User1Id == supportUser.Id &&
                s.User2Id == userId);

        if (session == null)
        {
            session = new NexChat.Core.Entities.ChatSession
            {
                User1Id = supportUser.Id,
                User2Id = userId,
                Type = "support"
            };
            db.ChatSessions.Add(session);
            await db.SaveChangesAsync();
            session = await db.ChatSessions
                .Include(s => s.User1)
                .Include(s => s.User2)
                .FirstAsync(s => s.Id == session.Id);
        }

        return Ok(new
        {
            sessionId = session.Id.ToString(),
            isSupport = true,
            partner = new
            {
                session.User1.Name,
                session.User1.Gender,
                session.User1.UniqueCode,
                session.User1.Avatar
            }
        });
    }
}
