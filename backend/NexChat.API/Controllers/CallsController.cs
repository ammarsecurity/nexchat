using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/calls")]
[Authorize]
[EnableRateLimiting("api")]
public class CallsController(AppDbContext db, IConversationMessageCrypto messageCrypto) : ControllerBase
{
    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<ActionResult<IEnumerable<CallHistoryItemDto>>> List([FromQuery] int take = 100)
    {
        take = Math.Clamp(take, 1, 300);
        var uid = CurrentUserId;

        var myConvIds = await db.Conversations
            .Where(c => c.Type == ConversationType.Private &&
                        (c.User1Id == uid || c.User2Id == uid))
            .Select(c => c.Id)
            .ToListAsync();

        var deletedMsgIds = await db.UserMessageDeletions
            .Where(d => d.UserId == uid)
            .Select(d => d.MessageId)
            .ToListAsync();

        var rows = await db.ConversationMessages
            .AsNoTracking()
            .Where(m => myConvIds.Contains(m.ConversationId) &&
                        m.Type == "call" &&
                        !m.DeletedForEveryone &&
                        !deletedMsgIds.Contains(m.Id))
            .OrderByDescending(m => m.SentAt)
            .Take(take)
            .Select(m => new
            {
                m.Id,
                m.ConversationId,
                m.SenderId,
                m.Content,
                m.SentAt,
                User1Id = m.Conversation.User1Id,
                User2Id = m.Conversation.User2Id,
                User1Name = m.Conversation.User1 != null ? m.Conversation.User1.Name : null,
                User1Avatar = m.Conversation.User1 != null ? m.Conversation.User1.Avatar : null,
                User2Name = m.Conversation.User2 != null ? m.Conversation.User2.Name : null,
                User2Avatar = m.Conversation.User2 != null ? m.Conversation.User2.Avatar : null,
            })
            .ToListAsync();

        var list = new List<CallHistoryItemDto>(rows.Count);
        foreach (var r in rows)
        {
            var partnerId = r.User1Id == uid ? r.User2Id : r.User1Id;
            if (partnerId == null) continue;
            var partnerName = r.User1Id == uid ? (r.User2Name ?? "—") : (r.User1Name ?? "—");
            var partnerAvatar = r.User1Id == uid ? r.User2Avatar : r.User1Avatar;

            var plain = messageCrypto.DecryptFromStorage(r.Content ?? "");
            var (status, voiceOnly, durationSec) = ParseCallPayload(plain);

            list.Add(new CallHistoryItemDto(
                r.Id,
                r.ConversationId,
                partnerId.Value,
                partnerName,
                partnerAvatar,
                r.SenderId,
                r.SenderId == uid,
                voiceOnly,
                status,
                durationSec,
                r.SentAt));
        }

        return Ok(list);
    }

    [HttpDelete("{messageId:guid}")]
    public async Task<ActionResult> DeleteOne(Guid messageId)
    {
        var uid = CurrentUserId;
        var msg = await db.ConversationMessages
            .AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == messageId && m.Type == "call");
        if (msg == null) return NotFound();

        var isParticipant = await db.Conversations.AnyAsync(c =>
            c.Id == msg.ConversationId &&
            c.Type == ConversationType.Private &&
            (c.User1Id == uid || c.User2Id == uid));
        if (!isParticipant) return Forbid();

        if (!await db.UserMessageDeletions.AnyAsync(d => d.UserId == uid && d.MessageId == messageId))
        {
            db.UserMessageDeletions.Add(new UserMessageDeletion { UserId = uid, MessageId = messageId });
            await db.SaveChangesAsync();
        }

        return NoContent();
    }

    [HttpDelete]
    public async Task<ActionResult<object>> ClearAll()
    {
        var uid = CurrentUserId;
        var myConvIds = await db.Conversations
            .Where(c => c.Type == ConversationType.Private &&
                        (c.User1Id == uid || c.User2Id == uid))
            .Select(c => c.Id)
            .ToListAsync();

        var already = await db.UserMessageDeletions
            .Where(d => d.UserId == uid)
            .Select(d => d.MessageId)
            .ToListAsync();
        var alreadySet = already.ToHashSet();

        var callIds = await db.ConversationMessages
            .Where(m => myConvIds.Contains(m.ConversationId) &&
                        m.Type == "call" &&
                        !m.DeletedForEveryone &&
                        !alreadySet.Contains(m.Id))
            .Select(m => m.Id)
            .ToListAsync();

        foreach (var id in callIds)
            db.UserMessageDeletions.Add(new UserMessageDeletion { UserId = uid, MessageId = id });

        await db.SaveChangesAsync();
        return Ok(new { deleted = callIds.Count });
    }

    private static (string Status, bool VoiceOnly, int DurationSec) ParseCallPayload(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var status = root.TryGetProperty("status", out var s) ? s.GetString() ?? "missed" : "missed";
            var voiceOnly = root.TryGetProperty("voiceOnly", out var v) && v.ValueKind == JsonValueKind.True;
            var durationSec = root.TryGetProperty("durationSec", out var d) && d.TryGetInt32(out var n) ? Math.Max(0, n) : 0;
            return (status, voiceOnly, durationSec);
        }
        catch
        {
            return ("missed", false, 0);
        }
    }
}
