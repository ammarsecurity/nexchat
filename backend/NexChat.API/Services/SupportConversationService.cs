using Microsoft.EntityFrameworkCore;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

/// <summary>
/// يضمن محادثة خاصة دائمة بين كل مستخدم وحساب الدعم (NX-SUPPORT).
/// </summary>
public class SupportConversationService(
    AppDbContext db,
    IConversationMessageCrypto messageCrypto,
    ILogger<SupportConversationService> logger)
{
    public const string SupportUniqueCode = "NX-SUPPORT";
    public const string WelcomeText = "مرحباً بك في دعم NexChat 👋\nكيف يمكننا مساعدتك؟";

    public async Task<User?> GetSupportUserAsync(CancellationToken ct = default) =>
        await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == SupportUniqueCode, ct);

    public async Task<bool> IsSupportConversationAsync(Guid conversationId, CancellationToken ct = default)
    {
        var support = await GetSupportUserAsync(ct);
        if (support == null) return false;
        return await db.Conversations.AnyAsync(c =>
            c.Id == conversationId &&
            c.Type == ConversationType.Private &&
            (c.User1Id == support.Id || c.User2Id == support.Id), ct);
    }

    public async Task<(Conversation Conversation, User SupportUser)?> EnsureForUserAsync(
        Guid userId,
        CancellationToken ct = default)
    {
        if (userId == Guid.Empty) return null;

        var support = await GetSupportUserAsync(ct);
        if (support == null)
        {
            logger.LogWarning("NX-SUPPORT user missing — cannot ensure support conversation");
            return null;
        }
        if (support.Id == userId) return null;

        var u1 = support.Id;
        var u2 = userId;
        if (u1.CompareTo(u2) > 0) (u1, u2) = (u2, u1);

        var conv = await db.Conversations
            .Include(c => c.User1)
            .Include(c => c.User2)
            .FirstOrDefaultAsync(c =>
                c.Type == ConversationType.Private && c.User1Id == u1 && c.User2Id == u2, ct);

        var created = false;
        if (conv == null)
        {
            conv = new Conversation
            {
                Type = ConversationType.Private,
                User1Id = u1,
                User2Id = u2,
                CreatedAt = DateTime.UtcNow
            };
            db.Conversations.Add(conv);
            created = true;
            await db.SaveChangesAsync(ct);
            await db.Entry(conv).Reference(c => c.User1).LoadAsync(ct);
            await db.Entry(conv).Reference(c => c.User2).LoadAsync(ct);
        }

        // Always restore for the end-user: pinned, visible, not deleted.
        var deletion = await db.UserConversationDeletions
            .FirstOrDefaultAsync(d => d.UserId == userId && d.ConversationId == conv.Id, ct);
        if (deletion != null)
            db.UserConversationDeletions.Remove(deletion);

        var state = await db.UserConversationStates
            .FirstOrDefaultAsync(s => s.UserId == userId && s.ConversationId == conv.Id, ct);
        if (state == null)
        {
            state = new UserConversationState
            {
                UserId = userId,
                ConversationId = conv.Id,
                IsPinned = true,
                IsArchived = false,
                IsHidden = false,
                UpdatedAt = DateTime.UtcNow
            };
            db.UserConversationStates.Add(state);
        }
        else
        {
            state.IsPinned = true;
            state.IsArchived = false;
            state.IsHidden = false;
            state.UpdatedAt = DateTime.UtcNow;
        }

        var hasMessages = await db.ConversationMessages
            .AnyAsync(m => m.ConversationId == conv.Id, ct);
        if (!hasMessages)
        {
            db.ConversationMessages.Add(new ConversationMessage
            {
                ConversationId = conv.Id,
                SenderId = support.Id,
                Content = messageCrypto.EncryptForStorage(WelcomeText),
                Type = "text",
                SentAt = DateTime.UtcNow,
                DisappearMode = DisappearMode.Off,
                IsRead = false
            });
        }

        await db.SaveChangesAsync(ct);
        if (created)
            logger.LogInformation("Created support conversation {ConvId} for user {UserId}", conv.Id, userId);

        return (conv, support);
    }
}
