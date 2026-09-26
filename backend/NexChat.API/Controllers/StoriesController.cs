using System.Text.Json;
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
    IHubContext<ConversationHub> conversationHub,
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

        // Audience first — avoid scanning every active story on the platform.
        var publisherIds = await audience.GetFeedPublisherIdsAsync(viewerId);
        if (publisherIds.Count == 0)
            return Ok(Array.Empty<StoryRingDto>());

        var slides = await db.StorySlides.AsNoTracking()
            .Where(s => s.ExpiresAt > now && publisherIds.Contains(s.UserId))
            .Select(s => new { s.Id, s.UserId, s.CreatedAt, s.SortOrder, s.MediaUrl })
            .ToListAsync();

        if (slides.Count == 0)
            return Ok(Array.Empty<StoryRingDto>());

        var byUser = slides
            .GroupBy(s => s.UserId)
            .Select(g =>
            {
                var latest = g.OrderByDescending(x => x.SortOrder).ThenByDescending(x => x.CreatedAt).First();
                return new
                {
                    UserId = g.Key,
                    LatestAt = g.Max(x => x.CreatedAt),
                    SlideCount = g.Count(),
                    LatestMediaUrl = latest.MediaUrl,
                    SlideIds = g.Select(x => x.Id).ToList()
                };
            })
            .ToList();

        var userIds = byUser.Select(x => x.UserId).ToList();
        var users = await db.Users.AsNoTracking()
            .Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id);

        var slideIdSet = slides.Select(s => s.Id).ToHashSet();
        var viewedSet = (await db.StoryViews.AsNoTracking()
                .Where(v => v.ViewerUserId == viewerId && slideIdSet.Contains(v.StorySlideId))
                .Select(v => v.StorySlideId)
                .ToListAsync())
            .ToHashSet();

        var rings = byUser
            .OrderByDescending(x => x.UserId == viewerId)
            .ThenByDescending(x => x.LatestAt)
            .Select(x =>
            {
                users.TryGetValue(x.UserId, out var u);
                var hasUnseen = x.SlideIds.Any(id => !viewedSet.Contains(id));
                return new StoryRingDto(
                    x.UserId,
                    u?.Name ?? "—",
                    u?.Avatar,
                    hasUnseen,
                    string.IsNullOrEmpty(x.LatestMediaUrl) ? null : x.LatestMediaUrl,
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

        var dto = MapSlide(slide, viewedByMe: true, viewCount: 0, likedByMe: false, likeCount: 0);

        var publisherId = CurrentUserId;
        var slideId = slide.Id;
        var thumb = GetThumbUrl(slide);
        var publisherName = user.Name ?? "مستخدم";
        _ = BroadcastStoryPublishedAsync(publisherId, slideId, thumb, publisherName, user.Avatar);

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
        var likeCount = await db.StoryLikes.CountAsync(l => l.StorySlideId == slide.Id);
        return Ok(MapSlide(slide, viewedByMe: true, viewCount, likedByMe: false, likeCount));
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

        var views = await db.StoryViews
            .AsNoTracking()
            .Where(v => v.StorySlideId == slideId)
            .Include(v => v.Viewer)
            .ToListAsync();

        var likes = await db.StoryLikes
            .AsNoTracking()
            .Where(l => l.StorySlideId == slideId)
            .Include(l => l.User)
            .ToListAsync();

        var likedIds = likes.Select(l => l.UserId).ToHashSet();
        var byUser = new Dictionary<Guid, StoryViewerDto>();

        foreach (var v in views)
        {
            byUser[v.ViewerUserId] = new StoryViewerDto(
                v.ViewerUserId,
                v.Viewer?.Name ?? "—",
                v.Viewer?.Avatar,
                v.ViewedAt,
                likedIds.Contains(v.ViewerUserId));
        }

        // Include likers who somehow have no view row yet.
        foreach (var l in likes)
        {
            if (byUser.ContainsKey(l.UserId)) continue;
            byUser[l.UserId] = new StoryViewerDto(
                l.UserId,
                l.User?.Name ?? "—",
                l.User?.Avatar,
                null,
                true);
        }

        var viewers = byUser.Values
            .OrderByDescending(v => v.Liked)
            .ThenByDescending(v => v.ViewedAt ?? DateTime.MinValue)
            .ToList();

        return Ok(viewers);
    }

    [HttpPost("{slideId:guid}/like")]
    public async Task<ActionResult<StoryLikeResponse>> ToggleLike(Guid slideId)
    {
        var slide = await db.StorySlides
            .FirstOrDefaultAsync(s => s.Id == slideId && s.ExpiresAt > DateTime.UtcNow);
        if (slide == null) return NotFound();
        if (!await audience.CanViewAsync(CurrentUserId, slide.UserId))
            return NotFound();
        if (slide.UserId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن الإعجاب بستوريته" });

        var existing = await db.StoryLikes
            .FirstOrDefaultAsync(l => l.StorySlideId == slideId && l.UserId == CurrentUserId);
        bool liked;
        if (existing != null)
        {
            db.StoryLikes.Remove(existing);
            liked = false;
        }
        else
        {
            db.StoryLikes.Add(new StoryLike
            {
                StorySlideId = slideId,
                UserId = CurrentUserId,
                CreatedAt = DateTime.UtcNow
            });
            liked = true;
        }

        await db.SaveChangesAsync();
        var likeCount = await db.StoryLikes.CountAsync(l => l.StorySlideId == slideId);

        if (liked)
        {
            var liker = await db.Users.FindAsync(CurrentUserId);
            await storyHub.Clients.User(slide.UserId.ToString())
                .SendAsync("StoryLiked", new
                {
                    slideId,
                    userId = CurrentUserId,
                    userName = liker?.Name ?? "—",
                    likeCount
                });
        }

        return Ok(new StoryLikeResponse(liked, likeCount));
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

        var text = profanity.Mask(req.Text.Trim());
        var payload = JsonSerializer.Serialize(new
        {
            text,
            slideId = slide.Id,
            mediaUrl = slide.MediaUrl,
            mediaType = slide.MediaType,
            backgroundColor = slide.BackgroundColor,
            caption = slide.Caption
        });

        var msg = new ConversationMessage
        {
            ConversationId = conv.Id,
            SenderId = CurrentUserId,
            Content = messageCrypto.EncryptForStorage(payload),
            Type = "story_reply"
        };
        db.ConversationMessages.Add(msg);

        var recipientDeletion = await db.UserConversationDeletions
            .FirstOrDefaultAsync(d => d.UserId == slide.UserId && d.ConversationId == conv.Id);
        if (recipientDeletion != null)
            db.UserConversationDeletions.Remove(recipientDeletion);

        await db.SaveChangesAsync();

        var preview = ConversationPreviewHelper.BuildStoryReplyPreview(payload);
        var sender = await db.Users.FindAsync(CurrentUserId);
        var receivePayload = new
        {
            msg.Id,
            msg.SenderId,
            Content = payload,
            msg.Type,
            msg.SentAt,
            msg.DeletedForEveryone,
            ReplyToMessageId = (Guid?)null,
            ReplyToContent = (string?)null,
            ReplyToSenderName = (string?)null,
            IsRead = false,
            Reactions = Array.Empty<object>(),
            MyReaction = (string?)null
        };

        await conversationHub.Clients.User(CurrentUserId.ToString()).SendAsync("ReceiveMessage", receivePayload);
        await conversationHub.Clients.User(slide.UserId.ToString()).SendAsync("ReceiveMessage", receivePayload);

        var listUpdate = new
        {
            ConversationId = conv.Id,
            LastMessagePreview = preview,
            LastMessageType = "story_reply",
            LastMessageAt = msg.SentAt,
            SenderId = CurrentUserId
        };
        await conversationHub.Clients.User(CurrentUserId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
        await conversationHub.Clients.User(slide.UserId.ToString()).SendAsync("ConversationListUpdated", listUpdate);

        await notificationOutbox.EnqueueAsync(
            slide.UserId,
            "conversation_message",
            sender?.Name ?? "شخص",
            preview,
            new Dictionary<string, string>
            {
                ["conversationId"] = conv.Id.ToString(),
                ["userId"] = CurrentUserId.ToString(),
                ["senderName"] = sender?.Name ?? "",
                ["senderAvatar"] = sender?.Avatar ?? ""
            });

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
                s.OverlayJson,
                s.BackgroundColor,
                s.FilterId,
                s.VideoDurationSeconds,
                s.SortOrder,
                s.CreatedAt,
                s.ExpiresAt,
                db.StoryViews.Any(v => v.ViewerUserId == viewerId && v.StorySlideId == s.Id),
                isOwner ? db.StoryViews.Count(v => v.StorySlideId == s.Id) : 0,
                db.StoryLikes.Any(l => l.UserId == viewerId && l.StorySlideId == s.Id),
                db.StoryLikes.Count(l => l.StorySlideId == s.Id)
            ))
            .ToListAsync();
    }

    private static StorySlideDto MapSlide(
        StorySlide s,
        bool viewedByMe,
        int viewCount,
        bool likedByMe,
        int likeCount) =>
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
            viewCount,
            likedByMe,
            likeCount
        );

    private static string? GetThumbUrl(StorySlide s)
    {
        if (!string.IsNullOrEmpty(s.MediaUrl))
            return s.MediaUrl;
        return null;
    }

    private async Task<Conversation?> FindOrCreatePrivateConversationAsync(Guid userId, Guid partnerId)
    {
        if (userId == partnerId) return null;

        var blocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == userId && b.BlockedUserId == partnerId) ||
            (b.BlockerId == partnerId && b.BlockedUserId == userId));
        if (blocked) return null;

        // Stories are friends-only: require mutual contacts (accepted friendship).
        if (!await audience.AreMutualFriendsAsync(userId, partnerId))
            return null;

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

        conv = new Conversation { Type = ConversationType.Private, User1Id = u1, User2Id = u2 };
        db.Conversations.Add(conv);
        await db.SaveChangesAsync();
        return conv;
    }

    private async Task BroadcastStoryPublishedAsync(
        Guid publisherId,
        Guid slideId,
        string? thumbUrl,
        string publisherName,
        string? publisherAvatar)
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
                        ["slideId"] = slideId.ToString(),
                        ["publisherName"] = publisherName,
                        ["publisherAvatar"] = publisherAvatar ?? "",
                        ["avatar"] = publisherAvatar ?? ""
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
                        publisherName,
                        publisherAvatar
                    });
            }
        }
        catch
        {
            // لا نفشل النشر إذا تأخرت الإشعارات
        }
    }
}
