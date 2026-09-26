using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>
/// Stories are visible only to mutual friends (both sides have a Contact row),
/// which is created when a message/friend request is accepted — WhatsApp-like.
/// </summary>
public class StoryAudienceService(AppDbContext db)
{
    /// <summary>Mutual friends of the publisher (minus blocks).</summary>
    public async Task<HashSet<Guid>> GetAudienceUserIdsAsync(Guid publisherId)
    {
        var blocked = await GetBlockedSetAsync(publisherId);
        var mutual = await GetMutualFriendIdsAsync(publisherId);
        mutual.RemoveWhere(id => id == publisherId || blocked.Contains(id));
        return mutual;
    }

    /// <summary>True if viewer may see publisher's stories.</summary>
    public async Task<bool> CanViewAsync(Guid viewerId, Guid publisherId)
    {
        if (viewerId == publisherId)
            return true;

        if (await IsBlockedEitherWayAsync(viewerId, publisherId))
            return false;

        return await AreMutualFriendsAsync(viewerId, publisherId);
    }

    /// <summary>Publisher user ids whose stories the viewer may see in feed.</summary>
    public async Task<HashSet<Guid>> GetVisiblePublisherIdsAsync(Guid viewerId)
    {
        var now = DateTime.UtcNow;
        var activePublishers = await db.StorySlides
            .Where(s => s.ExpiresAt > now)
            .Select(s => s.UserId)
            .Distinct()
            .ToListAsync();

        return await FilterVisiblePublishersAsync(viewerId, activePublishers);
    }

    /// <summary>Keep only self + mutual friends (minus blocks) from a candidate publisher list.</summary>
    public async Task<HashSet<Guid>> FilterVisiblePublishersAsync(Guid viewerId, IReadOnlyList<Guid> publisherIds)
    {
        var result = new HashSet<Guid>();
        if (publisherIds.Count == 0)
            return result;

        var blocked = await GetBlockedSetAsync(viewerId);
        var candidates = publisherIds.Where(id => id == viewerId || !blocked.Contains(id)).Distinct().ToList();
        if (candidates.Count == 0)
            return result;

        var iAdded = await db.Contacts
            .Where(c => c.UserId == viewerId && candidates.Contains(c.ContactUserId))
            .Select(c => c.ContactUserId)
            .ToListAsync();
        List<Guid> theyAddedMe;
        if (iAdded.Count == 0)
            theyAddedMe = [];
        else
            theyAddedMe = await db.Contacts
                .Where(c => c.ContactUserId == viewerId && iAdded.Contains(c.UserId))
                .Select(c => c.UserId)
                .ToListAsync();
        var mutual = theyAddedMe.ToHashSet();

        foreach (var id in candidates)
        {
            if (id == viewerId || mutual.Contains(id))
                result.Add(id);
        }

        return result;
    }

    /// Mutual friends + self (minus blocks) — publishers the viewer may see in the story feed.
    public async Task<HashSet<Guid>> GetFeedPublisherIdsAsync(Guid viewerId)
    {
        var blocked = await GetBlockedSetAsync(viewerId);
        var mutual = await GetMutualFriendIdsAsync(viewerId);
        mutual.Add(viewerId);
        mutual.RemoveWhere(id => id != viewerId && blocked.Contains(id));
        return mutual;
    }

    public async Task<bool> AreMutualFriendsAsync(Guid a, Guid b)
    {
        var ab = await db.Contacts.AnyAsync(c => c.UserId == a && c.ContactUserId == b);
        if (!ab) return false;
        return await db.Contacts.AnyAsync(c => c.UserId == b && c.ContactUserId == a);
    }

    async Task<HashSet<Guid>> GetMutualFriendIdsAsync(Guid userId)
    {
        var iAdded = await db.Contacts
            .Where(c => c.UserId == userId)
            .Select(c => c.ContactUserId)
            .ToListAsync();
        if (iAdded.Count == 0)
            return [];

        var theyAddedMe = await db.Contacts
            .Where(c => c.ContactUserId == userId && iAdded.Contains(c.UserId))
            .Select(c => c.UserId)
            .ToListAsync();

        return theyAddedMe.ToHashSet();
    }

    async Task<HashSet<Guid>> GetBlockedSetAsync(Guid userId)
    {
        var blockedByMe = await db.UserBlocks
            .Where(b => b.BlockerId == userId)
            .Select(b => b.BlockedUserId)
            .ToListAsync();
        var blockedMe = await db.UserBlocks
            .Where(b => b.BlockedUserId == userId)
            .Select(b => b.BlockerId)
            .ToListAsync();
        return blockedByMe.Union(blockedMe).ToHashSet();
    }

    async Task<bool> IsBlockedEitherWayAsync(Guid a, Guid b) =>
        await db.UserBlocks.AnyAsync(x =>
            (x.BlockerId == a && x.BlockedUserId == b) ||
            (x.BlockerId == b && x.BlockedUserId == a));
}
