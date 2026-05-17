using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

public class StoryAudienceService(AppDbContext db)
{
    /// <summary>Users who may view the publisher's stories (contacts + conversation partners, minus blocks).</summary>
    public async Task<HashSet<Guid>> GetAudienceUserIdsAsync(Guid publisherId)
    {
        var blockedByPublisher = await db.UserBlocks
            .Where(b => b.BlockerId == publisherId)
            .Select(b => b.BlockedUserId)
            .ToListAsync();
        var blockedPublisher = await db.UserBlocks
            .Where(b => b.BlockedUserId == publisherId)
            .Select(b => b.BlockerId)
            .ToListAsync();
        var blocked = blockedByPublisher.Union(blockedPublisher).ToHashSet();

        var contactIds = await db.Contacts
            .Where(c => c.UserId == publisherId)
            .Select(c => c.ContactUserId)
            .ToListAsync();

        var privatePeerIds = await db.Conversations
            .Where(c => c.Type == ConversationType.Private &&
                        (c.User1Id == publisherId || c.User2Id == publisherId))
            .Select(c => c.User1Id == publisherId ? c.User2Id!.Value : c.User1Id!.Value)
            .ToListAsync();

        var groupPeerIds = await db.ConversationMembers
            .Where(m => m.UserId != publisherId &&
                        db.ConversationMembers.Any(x => x.ConversationId == m.ConversationId && x.UserId == publisherId))
            .Select(m => m.UserId)
            .Distinct()
            .ToListAsync();

        var audience = new HashSet<Guid>();
        foreach (var id in contactIds.Concat(privatePeerIds).Concat(groupPeerIds))
        {
            if (id != publisherId && !blocked.Contains(id))
                audience.Add(id);
        }

        return audience;
    }

    /// <summary>True if viewer may see publisher's stories (fast path — no full audience scan).</summary>
    public async Task<bool> CanViewAsync(Guid viewerId, Guid publisherId)
    {
        if (viewerId == publisherId)
            return true;

        var blocked = await db.UserBlocks.AnyAsync(b =>
            (b.BlockerId == viewerId && b.BlockedUserId == publisherId) ||
            (b.BlockerId == publisherId && b.BlockedUserId == viewerId));
        if (blocked)
            return false;

        var isContact = await db.Contacts.AnyAsync(c =>
            (c.UserId == viewerId && c.ContactUserId == publisherId) ||
            (c.UserId == publisherId && c.ContactUserId == viewerId));
        if (isContact)
            return true;

        var hasPrivateChat = await db.Conversations.AnyAsync(c =>
            c.Type == ConversationType.Private &&
            ((c.User1Id == viewerId && c.User2Id == publisherId) ||
             (c.User2Id == viewerId && c.User1Id == publisherId)));
        if (hasPrivateChat)
            return true;

        return await db.ConversationMembers
            .Where(m => m.UserId == viewerId)
            .AnyAsync(m => db.ConversationMembers.Any(x =>
                x.ConversationId == m.ConversationId && x.UserId == publisherId));
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

        var result = new HashSet<Guid>();
        foreach (var pubId in activePublishers)
        {
            if (pubId == viewerId || await CanViewAsync(viewerId, pubId))
                result.Add(pubId);
        }

        return result;
    }
}
