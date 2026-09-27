using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.Infrastructure.Data;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/support")]
[Authorize]
[Microsoft.AspNetCore.RateLimiting.EnableRateLimiting("api")]
public class SupportController(
    AppDbContext db,
    SupportConversationService supportConversations) : ControllerBase
{
    /// <summary>
    /// يضمن محادثة الدعم في صندوق المحادثات ويعيد معرفها (متاحة دائماً).
    /// </summary>
    [HttpGet("conversation")]
    public async Task<ActionResult<object>> GetOrCreateConversation(CancellationToken ct)
    {
        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdStr) || !Guid.TryParse(userIdStr, out var userId))
            return Unauthorized();

        var ensured = await supportConversations.EnsureForUserAsync(userId, ct);
        if (ensured == null)
            return StatusCode(500, new { message = "خدمة الدعم غير متاحة" });

        var (conv, support) = ensured.Value;
        return Ok(new
        {
            conversationId = conv.Id,
            isSupport = true,
            partner = new
            {
                support.Id,
                support.Name,
                support.Gender,
                support.UniqueCode,
                support.Avatar,
                IsFeatured = support.IsFeatured
            }
        });
    }

    /// <summary>توافق قديم: يفتح جلسة ChatSession (للعملاء القديمين).</summary>
    [HttpGet("session")]
    public async Task<ActionResult<object>> GetOrCreateSession(CancellationToken ct)
    {
        // Prefer conversation-based support; still create/open legacy session for old clients.
        var userIdStr = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdStr) || !Guid.TryParse(userIdStr, out var userId))
            return Unauthorized();

        var ensured = await supportConversations.EnsureForUserAsync(userId, ct);
        if (ensured == null)
            return StatusCode(500, new { message = "خدمة الدعم غير متاحة" });

        var (conv, supportUser) = ensured.Value;

        var session = await db.ChatSessions
            .Include(s => s.User1)
            .Include(s => s.User2)
            .FirstOrDefaultAsync(s =>
                s.Type == "support" &&
                s.User1Id == supportUser.Id &&
                s.User2Id == userId, ct);

        if (session != null && session.EndedAt != null)
        {
            session.EndedAt = null;
            await db.SaveChangesAsync(ct);
        }

        if (session == null)
        {
            session = new NexChat.Core.Entities.ChatSession
            {
                User1Id = supportUser.Id,
                User2Id = userId,
                Type = "support"
            };
            db.ChatSessions.Add(session);
            await db.SaveChangesAsync(ct);
            session = await db.ChatSessions
                .Include(s => s.User1)
                .Include(s => s.User2)
                .FirstAsync(s => s.Id == session.Id, ct);
        }

        return Ok(new
        {
            sessionId = session.Id.ToString(),
            conversationId = conv.Id.ToString(),
            isSupport = true,
            partner = new
            {
                session.User1.Name,
                session.User1.Gender,
                session.User1.UniqueCode,
                session.User1.Avatar,
                IsFeatured = session.User1.IsFeatured
            }
        });
    }
}
