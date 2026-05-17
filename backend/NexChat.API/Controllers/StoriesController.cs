using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/stories")]
[Authorize]
[EnableRateLimiting("api")]
public class StoriesController(
    AppDbContext db,
    StoryAudienceService audience,
    IConversationMessageCrypto messageCrypto,
    IProfanityMasker profanity,
    NotificationOutboxService notificationOutbox,
    IHubContext<StoryHub> storyHub,
    IServiceScopeFactory scopeFactory) : ControllerBase
{
    private static readonly string[] AllowedMediaTypes = [StoryMediaType.Image, StoryMediaType.Video, StoryMediaType.Text];

    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("feed")]
    public async Task<ActionResult<IEnumerable<StoryRingDto>>> GetFeed()
    {
        var viewerId = CurrentUserId;
        var now = DateTime.UtcNow;

        var activeByUser = await db.StorySlides
            .Where(s => s.ExpiresAt > now)
            .GroupBy(s => s.UserId)
            .Select(g => new
            {
                UserId = g.Key,
                LatestAt = g.Max(x => x.CreatedAt),
                SlideCount = g.Count(),
                LatestSlide = g.OrderByDescending(x => x.SortOrder).ThenByDescending(x => x.CreatedAt).First()
            })
            .ToListAsync();

        if (activeByUser.Count == 0)
            return Ok(Array.Empty<StoryRingDto>());

        var publisherIds = activeByUser.Select(x => x.UserId).ToList();
        var visibleIds = await GetVisiblePublisherIdsAsync(viewerId, publisherIds);
        var filtered = activeByUser.Where(x => visibleIds.Contains(x.UserId)).ToList();
        if (filtered.Count == 0)
            return Ok(Array.Empty<StoryRingDto>());

        var userIds = filtered.Select(x => x.UserId).ToList();
        var users = await db.Users.Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id);

        var myViewedSlideIds = await db.StoryViews
            .Where(v => v.ViewerUserId == viewerId)
            .Select(v => v.StorySlideId)
            .ToListAsync();
        var viewedSet = myViewedSlideIds.ToHashSet();

        var allSlides = await db.StorySlides
            .Where(s => userIds.Contains(s.UserId) && s.ExpiresAt > now)
            .Select(s => new { s.Id, s.UserId })
            .ToListAsync();

        var rings = filtered
            .OrderByDescending(x => x.UserId == viewerId)
            .ThenByDescending(x => x.LatestAt)
            .Select(x =>
            {
                users.TryGetValue(x.UserId, out var u);
                var userSlideIds = allSlides.Where(s => s.UserId == x.UserId).Select(s => s.Id).ToList();
                var hasUnseen = userSlideIds.Any(id => !viewedSet.Contains(id));
                return new StoryRingDto(
                    x.UserId,
                    u?.Name ?? "—",
                    u?.Avatar,
                    hasUnseen,
                    GetThumbUrl(x.LatestSlide),
                    x.LatestAt,
                    x.SlideCount,
                    x.UserId == viewerId
                );
            })
            .ToList();

        return Ok(rings);
    }

    [HttpGet("mine")]
    public async Task<ActionResult<IEnumerable<StorySlideDto>>> GetMine()
    {
        return Ok(await GetSlidesForUserAsync(CurrentUserId, CurrentUserId));
    }

    [HttpGet("user/{userId:guid}")]
    public async Task<ActionResult<IEnumerable<StorySlideDto>>> GetUserStories(Guid userId)
    {
        if (!await audience.CanViewAsync(CurrentUserId, userId))
            return NotFound();

        return Ok(await GetSlidesForUserAsync(userId, CurrentUserId));
    }

    [HttpPost]
    public async Task<ActionResult<StorySlideDto>> Create([FromBody] CreateStorySlideRequest req)
    {
        var user = await db.Users.FindAsync(CurrentUserId);
        if (user == null) return NotFound();
        if (string.IsNullOrWhiteSpace(user.PhoneNumber))
            return BadRequest(new { message = "يجب إضافة رقم الهاتف من الإعدادات أولاً" });

        var mediaType = (req.MediaType ?? StoryMediaType.Image).ToLowerInvariant();
        if (!AllowedMediaTypes.Contains(mediaType))
            return BadRequest(new { message = "نوع الوسائط غير مدعوم" });

        if (mediaType != StoryMediaType.Text && string.IsNullOrWhiteSpace(req.MediaUrl))
            return BadRequest(new { message = "رابط الوسائط مطلوب" });

        var maxOrder = await db.StorySlides
            .Where(s => s.UserId == CurrentUserId && s.ExpiresAt > DateTime.UtcNow)
            .Select(s => (int?)s.SortOrder)
            .MaxAsync() ?? -1;

        var slide = new StorySlide
        {
            UserId = CurrentUserId,
            MediaUrl = req.MediaUrl,
            MediaType = mediaType,
            Caption = req.Caption?.Trim(),
            OverlayJson = req.OverlayJson,
            BackgroundColor = req.BackgroundColor,
            FilterId = req.FilterId,
            VideoDurationSeconds = req.VideoDurationSeconds,
            SortOrder = req.SortOrder ?? maxOrder + 1,
            ExpiresAt = DateTime.UtcNow.AddHours(24),
            CreatedAt = DateTime.UtcNow
        };

        db.StorySlides.Add(slide);
        await db.SaveChangesAsync();

        var dto = MapSlide(slide, true, 0);

        var publisherId = CurrentUserId;
        var slideId = slide.Id;
        var thumb = GetThumbUrl(slide);
        var publisherName = user.Name ?? "مستخدم";
        _ = BroadcastStoryPublishedAsync(publisherId, slideId, thumb, publisherName);

        return Ok(dto);
    }

    [HttpPut("{slideId:guid}")]
    public async Task<ActionResult<StorySlideDto>> Update(Guid slideId, [FromBody] UpdateStorySlideRequest req)
    {
        var slide = await db.StorySlides.FirstOrDefaultAsync(s =>
            s.Id == slideId && s.UserId == CurrentUserId && s.ExpiresAt > DateTime.UtcNow);
        if (slide == null) return NotFound();

        if (req.MediaUrl != null)
            slide.MediaUrl = req.MediaUrl;
        if (req.Caption != null)
            slide.Caption = string.IsNullOrWhiteSpace(req.Caption) ? null : req.Caption.Trim();
        if (req.OverlayJson != null)
            slide.OverlayJson = req.OverlayJson;
        if (req.BackgroundColor != null)
            slide.BackgroundColor = req.BackgroundColor;
        if (req.FilterId != null)
            slide.FilterId = req.FilterId == "none" ? null : req.FilterId;
        if (req.VideoDurationSeconds.HasValue)
            slide.VideoDurationSeconds = req.VideoDurationSeconds;

        await db.SaveChangesAsync();

        var viewCount = await db.StoryViews.CountAsync(v => v.StorySlideId == slide.Id);
        return Ok(MapSlide(slide, true, viewCount));
    }

    [HttpDelete("{slideId:guid}")]
    public async Task<ActionResult> Delete(Guid slideId)
    {
        var slide = await db.StorySlides.FirstOrDefaultAsync(s => s.Id == slideId && s.UserId == CurrentUserId);
        if (slide == null) return NotFound();

        db.StorySlides.Remove(slide);
        await db.SaveChangesAsync();

        var audienceIds = await audience.GetAudienceUserIdsAsync(CurrentUserId);
        await storyHub.Clients.Users(audienceIds.Select(id => id.ToString()).ToList())
            .SendAsync("StoryDeleted", new { userId = CurrentUserId, slideId });

        return NoContent();
    }

    [HttpPost("{slideId:guid}/view")]
    public async Task<ActionResult> RecordView(Guid slideId)
    {
        var slide = await db.StorySlides
            .Include(s => s.User)
            .FirstOrDefaultAsync(s => s.Id == slideId && s.ExpiresAt > DateTime.UtcNow);
        if (slide == null) return NotFound();
        if (!await audience.CanViewAsync(CurrentUserId, slide.UserId))
            return NotFound();

        if (slide.UserId == CurrentUserId)
            return Ok();

        var exists = await db.StoryViews.AnyAsync(v =>
            v.StorySlideId == slideId && v.ViewerUserId == CurrentUserId);
        if (!exists)
        {
            var viewer = await db.Users.FindAsync(CurrentUserId);
            db.StoryViews.Add(new StoryView
            {
                StorySlideId = slideId,
                ViewerUserId = CurrentUserId,
                ViewedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync();

            await storyHub.Clients.User(slide.UserId.ToString())
                .SendAsync("StoryViewed", new
                {
                    slideId,
                    viewerId = CurrentUserId,
                    viewerName = viewer?.Name ?? "—",
                    viewedAt = DateTime.UtcNow
                });
        }

        return Ok();
    }

    [HttpGet("{slideId:guid}/viewers")]
    public async Task<ActionResult<IEnumerable<StoryViewerDto>>> GetViewers(Guid slideId)
    {
        var slide = await db.StorySlides.FirstOrDefaultAsync(s => s.Id == slideId);
        if (slide == null || slide.UserId != CurrentUserId)
            return NotFound();

        var viewers = await db.StoryViews
            .Where(v => v.StorySlideId == slideId)
            .Include(v => v.Viewer)
            .OrderByDescending(v => v.ViewedAt)
            .Select(v => new StoryViewerDto(
                v.ViewerUserId,
                v.Viewer.Name,
                v.Viewer.Avatar,
                v.ViewedAt))
            .ToListAsync();

        return Ok(viewers);
    }

    [HttpPost("{slideId:guid}/reply")]
    public async Task<ActionResult<StoryReplyResponse>> Reply(Guid slideId, [FromBody] StoryReplyRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Text))
            return BadRequest(new { message = "النص مطلوب" });

        var slide = await db.StorySlides
            .Include(s => s.User)
            .FirstOrDefaultAsync(s => s.Id == slideId && s.ExpiresAt > DateTime.UtcNow);
        if (slide == null) return NotFound();
        if (!await audience.CanViewAsync(CurrentUserId, slide.UserId))
            return NotFound();
        if (slide.UserId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن الرد على ستوريتك" });

        var conv = await FindOrCreatePrivateConversationAsync(CurrentUserId, slide.UserId);
        if (conv == null)
            return BadRequest(new { message = "لا يمكن فتح محادثة مع هذا المستخدم" });

        var replyPrefix = $"↩ ستوري: ";
        var body = profanity.Mask($"{replyPrefix}{req.Text.Trim()}");
        var msg = new ConversationMessage
        {
            ConversationId = conv.Id,
            SenderId = CurrentUserId,
            Content = messageCrypto.EncryptForStorage(body),
            Type = "text"
        };
        db.ConversationMessages.Add(msg);

        var recipientDeletion = await db.UserConversationDeletions
            .FirstOrDefaultAsync(d => d.UserId == slide.UserId && d.ConversationId == conv.Id);
        if (recipientDeletion != null)
            db.UserConversationDeletions.Remove(recipientDeletion);

        await db.SaveChangesAsync();

        return Ok(new StoryReplyResponse(conv.Id, msg.Id));
    }

    private async Task<List<StorySlideDto>> GetSlidesForUserAsync(Guid publisherId, Guid viewerId)
    {
        var now = DateTime.UtcNow;
        var isOwner = publisherId == viewerId;

        return await db.StorySlides
            .AsNoTracking()
            .Where(s => s.UserId == publisherId && s.ExpiresAt > now)
            .OrderBy(s => s.SortOrder)
            .ThenBy(s => s.CreatedAt)
            .Select(s => new StorySlideDto(
                s.Id,
                s.UserId,
                s.MediaUrl,
                s.MediaType,
                s.Caption,
                isOwner ? s.OverlayJson : null,
                s.BackgroundColor,
                s.FilterId,
                s.VideoDurationSeconds,
                s.SortOrder,
                s.CreatedAt,
                s.ExpiresAt,
                db.StoryViews.Any(v => v.ViewerUserId == viewerId && v.StorySlideId == s.Id),
                isOwner ? db.StoryViews.Count(v => v.StorySlideId == s.Id) : 0
            ))
            .ToListAsync();
    }

    private static StorySlideDto MapSlide(StorySlide s, bool viewedByMe, int viewCount) =>
        new(
            s.Id,
            s.UserId,
            s.MediaUrl,
            s.MediaType,
            s.Caption,
            s.OverlayJson,
            s.BackgroundColor,
            s.FilterId,
            s.VideoDurationSeconds,
            s.SortOrder,
            s.CreatedAt,
            s.ExpiresAt,
            viewedByMe,
            viewCount
        );

    private static string? GetThumbUrl(StorySlide s)
    {
        if (!string.IsNullOrEmpty(s.MediaUrl))
            return s.MediaUrl;
        return null;
    }

    private async Task<HashSet<Guid>> GetVisiblePublisherIdsAsync(Guid viewerId, List<Guid> publisherIds)
    {
        var blocked = await db.UserBlocks
            .Where(b => b.BlockerId == viewerId || b.BlockedUserId == viewerId)
            .Select(b => b.BlockerId == viewerId ? b.BlockedUserId : b.BlockerId)
            .ToListAsync();
        var blockedSet = blocked.ToHashSet();

        var eligible = publisherIds
            .Where(id => id == viewerId || !blockedSet.Contains(id))
            .ToList();

        var fromContacts = await db.Contacts
            .Where(c =>
                (c.UserId == viewerId && eligible.Contains(c.ContactUserId)) ||
                (c.ContactUserId == viewerId && eligible.Contains(c.UserId)))
            .Select(c => c.UserId == viewerId ? c.ContactUserId : c.UserId)
            .Distinct()
            .ToListAsync();

        var privatePeers = await db.Conversations
            .Where(c => c.Type == ConversationType.Private &&
                        ((c.User1Id == viewerId && c.User2Id != null && eligible.Contains(c.User2Id.Value)) ||
                         (c.User2Id == viewerId && c.User1Id != null && eligible.Contains(c.User1Id.Value))))
            .Select(c => c.User1Id == viewerId ? c.User2Id!.Value : c.User1Id!.Value)
            .ToListAsync();

        var myConvIds = await db.ConversationMembers
            .Where(m => m.UserId == viewerId)
            .Select(m => m.ConversationId)
            .ToListAsync();

        var groupPeers = await db.ConversationMembers
            .Where(m => myConvIds.Contains(m.ConversationId) &&
                        m.UserId != viewerId &&
                        eligible.Contains(m.UserId))
            .Select(m => m.UserId)
            .Distinct()
            .ToListAsync();

        var visible = new HashSet<Guid> { viewerId };
        foreach (var id in fromContacts.Concat(privatePeers).Concat(groupPeers))
        {
            if (eligible.Contains(id))
                visible.Add(id);
        }

        return visible;
    }

    private async Task<Conversation?> FindOrCreatePrivateConversationAsync(Guid userId, Guid partnerId)
    {
        if (userId == partnerId) return null;

        var blocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == userId && b.BlockedUserId == partnerId) ||
            (b.BlockerId == partnerId && b.BlockedUserId == userId));
        if (blocked) return null;

        var u1 = userId;
        var u2 = partnerId;
        if (u1.CompareTo(u2) > 0) (u1, u2) = (u2, u1);

        var conv = await db.Conversations
            .FirstOrDefaultAsync(c => c.Type == ConversationType.Private && c.User1Id == u1 && c.User2Id == u2);

        if (conv != null)
        {
            var deletion = await db.UserConversationDeletions
                .FirstOrDefaultAsync(d => d.UserId == userId && d.ConversationId == conv.Id);
            if (deletion != null)
                db.UserConversationDeletions.Remove(deletion);
            return conv;
        }

        var isContact = await db.Contacts.AnyAsync(c =>
            c.UserId == userId && c.ContactUserId == partnerId);

        var hasPrivateConv = await db.Conversations.AnyAsync(c =>
            c.Type == ConversationType.Private &&
            ((c.User1Id == userId && c.User2Id == partnerId) ||
             (c.User2Id == userId && c.User1Id == partnerId)));

        if (!isContact && !hasPrivateConv)
        {
            var accepted = await db.MessageRequests.AnyAsync(r =>
                r.Status == MessageRequestStatus.Accepted &&
                ((r.RequesterId == userId && r.TargetId == partnerId) ||
                 (r.RequesterId == partnerId && r.TargetId == userId)));
            if (!accepted) return null;
        }

        conv = new Conversation { Type = ConversationType.Private, User1Id = u1, User2Id = u2 };
        db.Conversations.Add(conv);
        await db.SaveChangesAsync();
        return conv;
    }

    private async Task BroadcastStoryPublishedAsync(
        Guid publisherId,
        Guid slideId,
        string? thumbUrl,
        string publisherName)
    {
        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var scopedAudience = scope.ServiceProvider.GetRequiredService<StoryAudienceService>();
            var scopedOutbox = scope.ServiceProvider.GetRequiredService<NotificationOutboxService>();
            var scopedHub = scope.ServiceProvider.GetRequiredService<IHubContext<StoryHub>>();

            var audienceIds = await scopedAudience.GetAudienceUserIdsAsync(publisherId);
            foreach (var recipientId in audienceIds)
            {
                await scopedOutbox.EnqueueAsync(
                    recipientId,
                    "story_published",
                    publisherName,
                    "نشر ستوري جديد",
                    new Dictionary<string, string>
                    {
                        ["userId"] = publisherId.ToString(),
                        ["slideId"] = slideId.ToString()
                    });
            }

            var userIds = audienceIds.Select(id => id.ToString()).ToList();
            if (userIds.Count > 0)
            {
                await scopedHub.Clients.Users(userIds)
                    .SendAsync("StoryPublished", new
                    {
                        userId = publisherId,
                        slideId,
                        thumbUrl,
                        publisherName
                    });
            }
        }
        catch
        {
            // لا نفشل النشر إذا تأخرت الإشعارات
        }
    }
}
