using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.API.Services;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using System.Security.Claims;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/discover")]
[Authorize]
[EnableRateLimiting("api")]
public class DiscoverController(
    AppDbContext db,
    IHubContext<ConversationHub> conversationHub,
    SiteContentFeatureService features,
    NotificationOutboxService notificationOutbox) : ControllerBase
{
    private const int FeedLimit = 20;
    /// <summary>Passed/liked (unmatched) profiles re-enter the feed after this window so it does not stay empty.</summary>
    private const int SwipeCooldownHours = 24;

    private static DateTime SwipeCooldownCutoffUtc() => DateTime.UtcNow.AddHours(-SwipeCooldownHours);

    private static DateOnly AdultBirthCutoff() =>
        DateOnly.FromDateTime(IraqTime.Now.Date.AddYears(-18));

    private static DateOnly TodayIraq() => DateOnly.FromDateTime(IraqTime.Now);

    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    private static bool HasDiscoverPhoto(User u) =>
        ProfilePhotos.Resolve(u.ProfilePhotosJson, u.Avatar, u.CoverImageUrl).Count > 0;

    private async Task<ActionResult?> RequireDiscoverEnabledAsync()
    {
        if (!await features.IsDiscoverSwipeEnabledAsync())
            return NotFound(new { message = "التعارف غير متاح حالياً", code = "DISCOVER_DISABLED" });
        return null;
    }

    [HttpGet("feed")]
    public async Task<ActionResult<object>> GetFeed([FromQuery] int limit = FeedLimit)
    {
        if (await RequireDiscoverEnabledAsync() is { } disabled) return disabled;

        var me = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == CurrentUserId);
        if (me == null) return Unauthorized();

        var gate = ProfileGate(me);
        if (gate != null) return BadRequest(gate);

        limit = Math.Clamp(limit, 1, 50);

        var meId = CurrentUserId;
        var today = TodayIraq();
        var adultCutoff = AdultBirthCutoff();

        var preferGender = (me.DiscoverPreferGender ?? "all").Trim().ToLowerInvariant();
        if (preferGender is not ("male" or "female")) preferGender = "all";
        var ageMin = Math.Clamp(me.DiscoverAgeMin <= 0 ? 18 : me.DiscoverAgeMin, 18, 60);
        var ageMax = Math.Clamp(me.DiscoverAgeMax <= 0 ? 60 : me.DiscoverAgeMax, 18, 60);
        if (ageMin > ageMax) (ageMin, ageMax) = (ageMax, ageMin);
        // BirthDate windows for age range (Iraq calendar day).
        var youngestBirth = today.AddYears(-ageMin);       // age >= ageMin → BirthDate <= youngestBirth
        var oldestBirthExclusive = today.AddYears(-(ageMax + 1)); // age <= ageMax → BirthDate > oldestBirthExclusive

        // Hide only recent swipes (24h). Older pass/like (without a match) can reappear.
        var swipeFreshAfter = SwipeCooldownCutoffUtc();

        // Subqueries avoid huge NOT IN parameter lists for heavy swipers.
        var query = db.Users.AsNoTracking()
            .Where(u =>
                u.Id != meId &&
                !u.IsBanned &&
                !u.IsAdmin &&
                u.Avatar != null &&
                (u.Avatar.StartsWith("http://") || u.Avatar.StartsWith("https://") || u.Avatar.StartsWith("/")) &&
                u.BirthDate != null &&
                u.BirthDate <= adultCutoff &&
                u.BirthDate <= youngestBirth &&
                u.BirthDate > oldestBirthExclusive &&
                (preferGender == "all" || u.Gender == preferGender) &&
                !db.UserBlocks.Any(b =>
                    (b.BlockerId == meId && b.BlockedUserId == u.Id) ||
                    (b.BlockerId == u.Id && b.BlockedUserId == meId)) &&
                !db.UserSwipes.Any(s =>
                    s.FromUserId == meId &&
                    s.ToUserId == u.Id &&
                    s.CreatedAt >= swipeFreshAfter) &&
                !db.UserMatches.Any(m =>
                    (m.UserAId == meId && m.UserBId == u.Id) ||
                    (m.UserAId == u.Id && m.UserBId == meId)));

        var candidates = await query
            .OrderByDescending(u => u.IsOnline)
            .ThenByDescending(u => u.CreatedAt)
            .Take(limit)
            .ToListAsync();

        var cards = candidates.Select(u => ToCard(u, today)).ToList();
        return Ok(new
        {
            items = cards,
            canSwipe = true,
            prefs = new { preferGender, ageMin, ageMax }
        });
    }

    [HttpGet("eligibility")]
    public async Task<ActionResult<object>> GetEligibility()
    {
        if (await RequireDiscoverEnabledAsync() is { } disabled) return disabled;

        var me = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == CurrentUserId);
        if (me == null) return Unauthorized();

        var hasAvatar = HasDiscoverPhoto(me);
        var hasBirthDate = me.BirthDate != null;
        var ageOk = hasBirthDate && me.BirthDate <= AdultBirthCutoff();
        return Ok(new
        {
            canSwipe = hasAvatar && ageOk,
            hasAvatar,
            hasBirthDate,
            ageOk,
            message = ProfileGateMessage(hasAvatar, hasBirthDate, ageOk)
        });
    }

    public record SwipeRequest(Guid TargetUserId, string Direction);

    [HttpPost("swipe")]
    public async Task<ActionResult<object>> Swipe([FromBody] SwipeRequest req)
    {
        if (await RequireDiscoverEnabledAsync() is { } disabled) return disabled;

        var me = await db.Users.FirstOrDefaultAsync(u => u.Id == CurrentUserId);
        if (me == null) return Unauthorized();

        var gate = ProfileGate(me);
        if (gate != null) return BadRequest(gate);

        var direction = (req.Direction ?? "").Trim().ToLowerInvariant();
        if (direction is not (SwipeDirection.Like or SwipeDirection.Pass))
            return BadRequest(new { message = "الاتجاه غير صالح", code = "INVALID_DIRECTION" });

        if (req.TargetUserId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن التفاعل مع نفسك" });

        var adultCutoff = AdultBirthCutoff();
        var target = await db.Users
            .FirstOrDefaultAsync(u => u.Id == req.TargetUserId && !u.IsBanned);
        if (target == null)
            return NotFound(new { message = "المستخدم غير موجود" });

        // Same gates as feed: never match minors / incomplete profiles via direct id.
        if (!HasDiscoverPhoto(target) ||
            target.BirthDate == null ||
            target.BirthDate > adultCutoff)
            return BadRequest(new { message = "هذا الملف غير مؤهل للتعارف", code = "TARGET_INELIGIBLE" });

        var blocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == CurrentUserId && b.BlockedUserId == req.TargetUserId) ||
            (b.BlockerId == req.TargetUserId && b.BlockedUserId == CurrentUserId));
        if (blocked)
            return BadRequest(new { message = "لا يمكن التفاعل مع هذا المستخدم", code = "BLOCKED" });

        var (userA, userB) = CanonicalPair(CurrentUserId, req.TargetUserId);
        var existingMatch = await db.UserMatches
            .AsNoTracking()
            .FirstOrDefaultAsync(m => m.UserAId == userA && m.UserBId == userB);
        if (existingMatch != null)
        {
            return Ok(new
            {
                matched = true,
                alreadySwiped = true,
                conversationId = existingMatch.ConversationId,
                matchId = existingMatch.Id,
                partner = ToCard(target, TodayIraq())
            });
        }

        var swipeFreshAfter = SwipeCooldownCutoffUtc();
        var existing = await db.UserSwipes
            .FirstOrDefaultAsync(s => s.FromUserId == CurrentUserId && s.ToUserId == req.TargetUserId);
        if (existing != null)
        {
            // Still within cooldown — ignore duplicate swipe.
            if (existing.CreatedAt >= swipeFreshAfter)
                return Ok(new { matched = false, alreadySwiped = true, conversationId = (Guid?)null });

            // Cooldown expired: refresh direction + timestamp (unique From/To row).
            existing.Direction = direction;
            existing.CreatedAt = DateTime.UtcNow;
        }
        else
        {
            db.UserSwipes.Add(new UserSwipe
            {
                FromUserId = CurrentUserId,
                ToUserId = req.TargetUserId,
                Direction = direction
            });
        }

        // Commit swipe first so a concurrent mutual like can see this row (avoids permanent no-match).
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Unique (From,To): concurrent duplicate swipe.
            db.ChangeTracker.Clear();
            existingMatch = await db.UserMatches.AsNoTracking()
                .FirstOrDefaultAsync(m => m.UserAId == userA && m.UserBId == userB);
            if (existingMatch != null)
            {
                return Ok(new
                {
                    matched = true,
                    alreadySwiped = true,
                    conversationId = existingMatch.ConversationId,
                    matchId = existingMatch.Id,
                    partner = ToCard(target, TodayIraq())
                });
            }
            return Ok(new { matched = false, alreadySwiped = true, conversationId = (Guid?)null });
        }

        if (direction != SwipeDirection.Like)
            return Ok(new { matched = false, conversationId = (Guid?)null });

        var reciprocal = await db.UserSwipes.AnyAsync(s =>
            s.FromUserId == req.TargetUserId &&
            s.ToUserId == CurrentUserId &&
            s.Direction == SwipeDirection.Like);

        if (!reciprocal)
            return Ok(new { matched = false, conversationId = (Guid?)null });

        return await CreateOrGetMatchAsync(me, target, userA, userB);
    }

    private async Task<ActionResult<object>> CreateOrGetMatchAsync(User me, User target, Guid userA, Guid userB)
    {
        var today = TodayIraq();
        var existingMatch = await db.UserMatches
            .FirstOrDefaultAsync(m => m.UserAId == userA && m.UserBId == userB);
        if (existingMatch != null)
        {
            return Ok(new
            {
                matched = true,
                conversationId = existingMatch.ConversationId,
                matchId = existingMatch.Id,
                partner = ToCard(target, today)
            });
        }

        await EnsureMutualContactsAsync(CurrentUserId, target.Id);
        // Stage conversation without early SaveChanges so match+contacts+conv commit together.
        var conv = await FindOrCreatePrivateConversationAsync(CurrentUserId, target.Id, saveNew: false);
        if (conv == null)
            return BadRequest(new { message = "تعذر إنشاء المحادثة" });

        var match = new UserMatch
        {
            UserAId = userA,
            UserBId = userB,
            ConversationId = conv.Id
        };
        db.UserMatches.Add(match);

        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Concurrent match insert: return the winner's row.
            db.ChangeTracker.Clear();
            existingMatch = await db.UserMatches.AsNoTracking()
                .FirstOrDefaultAsync(m => m.UserAId == userA && m.UserBId == userB);
            if (existingMatch == null)
                return BadRequest(new { message = "تعذر إنشاء التطابق" });

            return Ok(new
            {
                matched = true,
                conversationId = existingMatch.ConversationId,
                matchId = existingMatch.Id,
                partner = ToCard(target, today)
            });
        }

        var meCard = ToCard(me, today);
        var partnerCard = ToCard(target, today);
        var payloadForMe = new
        {
            matchId = match.Id,
            conversationId = conv.Id,
            partner = partnerCard
        };
        var payloadForThem = new
        {
            matchId = match.Id,
            conversationId = conv.Id,
            partner = meCard
        };

        // ConversationHub is always connected while logged in; avoid dual-hub duplicate dialogs.
        await conversationHub.Clients.User(CurrentUserId.ToString()).SendAsync("MatchCreated", payloadForMe);
        await conversationHub.Clients.User(target.Id.ToString()).SendAsync("MatchCreated", payloadForThem);

        var listUpdate = new
        {
            ConversationId = conv.Id,
            LastMessagePreview = "تم التطابق — ابدأ المحادثة",
            LastMessageType = "system",
            LastMessageAt = match.CreatedAt,
            SenderId = (Guid?)null
        };
        await conversationHub.Clients.User(CurrentUserId.ToString()).SendAsync("ConversationListUpdated", listUpdate);
        await conversationHub.Clients.User(target.Id.ToString()).SendAsync("ConversationListUpdated", listUpdate);

        // Push the *other* user (swiper already gets MatchCreated dialog on this device).
        await notificationOutbox.EnqueueAsync(
            target.Id,
            "discover_match",
            "تم التطابق!",
            $"تطابق جديد مع {me.Name} — ابدأ المحادثة",
            new Dictionary<string, string>
            {
                ["conversationId"] = conv.Id.ToString(),
                ["matchId"] = match.Id.ToString(),
                ["partnerId"] = me.Id.ToString(),
                ["partnerName"] = me.Name
            });

        return Ok(new
        {
            matched = true,
            conversationId = conv.Id,
            matchId = match.Id,
            partner = partnerCard
        });
    }

    /// <summary>تراجع عن آخر سوايپ إن لم ينتج تطابقاً.</summary>
    [HttpPost("undo")]
    public async Task<ActionResult<object>> UndoLastSwipe()
    {
        if (await RequireDiscoverEnabledAsync() is { } disabled) return disabled;

        var me = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == CurrentUserId);
        if (me == null) return Unauthorized();
        var gate = ProfileGate(me);
        if (gate != null) return BadRequest(gate);

        var last = await db.UserSwipes
            .Where(s => s.FromUserId == CurrentUserId)
            .OrderByDescending(s => s.CreatedAt)
            .FirstOrDefaultAsync();
        if (last == null)
            return BadRequest(new { message = "لا يوجد سوايپ للتراجع عنه", code = "NOTHING_TO_UNDO" });

        var (userA, userB) = CanonicalPair(CurrentUserId, last.ToUserId);
        var matched = await db.UserMatches.AsNoTracking()
            .AnyAsync(m => m.UserAId == userA && m.UserBId == userB);
        if (matched)
            return BadRequest(new { message = "لا يمكن التراجع بعد حدوث تطابق", code = "ALREADY_MATCHED" });

        var target = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == last.ToUserId);
        db.UserSwipes.Remove(last);
        await db.SaveChangesAsync();

        return Ok(new
        {
            undone = true,
            direction = last.Direction,
            card = target == null ? null : ToCard(target, TodayIraq())
        });
    }

    public record ReportRequest(Guid TargetUserId, string? Reason);

    [HttpPost("report")]
    public async Task<IActionResult> Report([FromBody] ReportRequest req)
    {
        if (await RequireDiscoverEnabledAsync() is { } disabled) return disabled;

        if (req.TargetUserId == CurrentUserId)
            return BadRequest(new { message = "لا يمكن الإبلاغ عن نفسك" });

        var target = await db.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == req.TargetUserId);
        if (target == null)
            return NotFound(new { message = "المستخدم غير موجود" });

        var reason = (req.Reason ?? "").Trim();
        if (reason.Length > 500) reason = reason[..500];
        if (string.IsNullOrEmpty(reason)) reason = "Discover report";

        var recent = DateTime.UtcNow.AddHours(-24);
        var already = await db.Reports.AnyAsync(r =>
            r.ReporterId == CurrentUserId &&
            r.ReportedId == req.TargetUserId &&
            r.CreatedAt >= recent);
        if (already)
            return Ok(new { alreadyReported = true });

        db.Reports.Add(new Report
        {
            ReporterId = CurrentUserId,
            ReportedId = req.TargetUserId,
            Reason = reason
        });
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpGet("matches")]
    public async Task<ActionResult<object>> GetMatches()
    {
        if (await RequireDiscoverEnabledAsync() is { } disabled) return disabled;

        var today = TodayIraq();
        var meId = CurrentUserId;
        var rows = await db.UserMatches.AsNoTracking()
            .Where(m => m.UserAId == meId || m.UserBId == meId)
            .OrderByDescending(m => m.CreatedAt)
            .Take(100)
            .ToListAsync();

        var partnerIds = rows
            .Select(m => m.UserAId == meId ? m.UserBId : m.UserAId)
            .Distinct()
            .ToList();
        var partners = await db.Users.AsNoTracking()
            .Where(u => partnerIds.Contains(u.Id) && !u.IsBanned)
            .ToDictionaryAsync(u => u.Id);
        var blockedIds = await db.UserBlocks.AsNoTracking()
            .Where(b =>
                (b.BlockerId == meId && partnerIds.Contains(b.BlockedUserId)) ||
                (b.BlockedUserId == meId && partnerIds.Contains(b.BlockerId)))
            .Select(b => b.BlockerId == meId ? b.BlockedUserId : b.BlockerId)
            .ToListAsync();
        var blocked = blockedIds.ToHashSet();

        var items = rows
            .Select(m =>
            {
                var pid = m.UserAId == meId ? m.UserBId : m.UserAId;
                return (m, pid);
            })
            .Where(x => partners.ContainsKey(x.pid) && !blocked.Contains(x.pid))
            .Select(x => new
            {
                matchId = x.m.Id,
                conversationId = x.m.ConversationId,
                createdAt = x.m.CreatedAt,
                partner = ToCard(partners[x.pid], today)
            })
            .ToList();

        return Ok(new { items });
    }

    private static object? ProfileGate(User me)
    {
        var hasAvatar = HasDiscoverPhoto(me);
        var hasBirthDate = me.BirthDate != null;
        var ageOk = hasBirthDate && me.BirthDate <= AdultBirthCutoff();
        if (hasAvatar && ageOk) return null;
        return new
        {
            message = ProfileGateMessage(hasAvatar, hasBirthDate, ageOk),
            code = "PROFILE_INCOMPLETE",
            hasAvatar,
            hasBirthDate,
            ageOk
        };
    }

    private static string ProfileGateMessage(bool hasAvatar, bool hasBirthDate, bool ageOk)
    {
        if (!hasAvatar) return "أضف صورة شخصية (ليست رمزًا تعبيريًا) قبل البدء";
        if (!hasBirthDate) return "أضف تاريخ ميلادك قبل البدء";
        if (!ageOk) return "يجب أن يكون عمرك 18 عاماً أو أكثر";
        return "";
    }

    private static (Guid a, Guid b) CanonicalPair(Guid x, Guid y) =>
        x.CompareTo(y) <= 0 ? (x, y) : (y, x);

    private async Task EnsureMutualContactsAsync(Guid a, Guid b)
    {
        var existing = await db.Contacts
            .Where(c =>
                (c.UserId == a && c.ContactUserId == b) ||
                (c.UserId == b && c.ContactUserId == a))
            .Select(c => new { c.UserId, c.ContactUserId })
            .ToListAsync();

        if (!existing.Any(c => c.UserId == a && c.ContactUserId == b))
            db.Contacts.Add(new Contact { UserId = a, ContactUserId = b });
        if (!existing.Any(c => c.UserId == b && c.ContactUserId == a))
            db.Contacts.Add(new Contact { UserId = b, ContactUserId = a });
    }

    private async Task<Conversation?> FindOrCreatePrivateConversationAsync(Guid userId, Guid partnerId, bool saveNew = true)
    {
        if (userId == partnerId) return null;

        var (u1, u2) = CanonicalPair(userId, partnerId);
        var conv = await db.Conversations
            .FirstOrDefaultAsync(c => c.Type == ConversationType.Private && c.User1Id == u1 && c.User2Id == u2);

        if (conv != null)
        {
            var deletions = await db.UserConversationDeletions
                .Where(d => d.ConversationId == conv.Id && (d.UserId == userId || d.UserId == partnerId))
                .ToListAsync();
            if (deletions.Count > 0)
                db.UserConversationDeletions.RemoveRange(deletions);
            return conv;
        }

        conv = new Conversation { Type = ConversationType.Private, User1Id = u1, User2Id = u2 };
        db.Conversations.Add(conv);
        if (saveNew)
            await db.SaveChangesAsync();
        return conv;
    }

    private static object ToCard(User u, DateOnly today)
    {
        int? age = null;
        if (u.BirthDate is { } bd)
        {
            age = today.Year - bd.Year;
            if (bd > today.AddYears(-age.Value)) age--;
        }

        var photos = ProfilePhotos.Resolve(u.ProfilePhotosJson, u.Avatar, u.CoverImageUrl);
        return new
        {
            id = u.Id,
            name = u.Name,
            gender = u.Gender,
            avatar = photos.FirstOrDefault() ?? u.Avatar,
            coverImageUrl = u.CoverImageUrl,
            photos,
            age,
            country = u.Country,
            isFeatured = u.IsFeatured,
            bio = u.Bio
        };
    }
}
