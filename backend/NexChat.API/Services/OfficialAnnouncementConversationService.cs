using Microsoft.EntityFrameworkCore;
using NexChat.Core;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

/// <summary>
/// محادثة إعلانات رسمية باتجاه واحد (مثل قنوات واتساب).
/// يعيد استخدام حساب الستوري الرسمي (NX-STORY / اسم NexChat) لتجنب تعارض IX_Users_Name.
/// </summary>
public class OfficialAnnouncementConversationService(
    AppDbContext db,
    IConversationMessageCrypto messageCrypto,
    ILogger<OfficialAnnouncementConversationService> logger)
{
    public const string OfficialUniqueCode = "NX-NEWS";
    public const string StoryUniqueCode = OfficialStoryPublisherService.UniqueCode; // NX-STORY
    public const string DisplayName = "NexChat";
    public const string WelcomeText =
        "مرحباً بك في NexChat 👋\nهنا تصلك الإعلانات والرسائل الرسمية. هذه المحادثة للقراءة فقط.";

    public static bool IsOfficialAccount(User? u) =>
        u != null && (
            u.UniqueCode == OfficialUniqueCode
            || u.UniqueCode == StoryUniqueCode
            || u.IsOfficialStoryPublisher);

    public static bool IsOfficialUniqueCode(string? code) =>
        code == OfficialUniqueCode || code == StoryUniqueCode;

    public async Task<User?> GetOfficialUserAsync(CancellationToken ct = default) =>
        await db.Users.FirstOrDefaultAsync(u =>
            u.UniqueCode == OfficialUniqueCode
            || u.UniqueCode == StoryUniqueCode
            || u.IsOfficialStoryPublisher, ct);

    public async Task<User> EnsureOfficialUserAsync(CancellationToken ct = default)
    {
        var existing = await GetOfficialUserAsync(ct);
        if (existing != null)
        {
            var dirty = false;
            // Keep the unique display name "NexChat" (already taken by story publisher).
            if (string.IsNullOrWhiteSpace(existing.Name))
            {
                existing.Name = DisplayName;
                dirty = true;
            }
            if (!existing.IsFeatured)
            {
                existing.IsFeatured = true;
                dirty = true;
            }
            if (dirty) await db.SaveChangesAsync(ct);
            return existing;
        }

        // No official account yet — create NX-NEWS. Name must be unique (IX_Users_Name).
        var name = DisplayName;
        if (await db.Users.AnyAsync(u => u.Name == name, ct))
            name = "NexChat News";

        var user = new User
        {
            Name = name,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString("N")),
            Gender = "other",
            UniqueCode = OfficialUniqueCode,
            IsFeatured = true,
            IsAdmin = false,
            ShowOnlineStatusToOthers = false,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Created official announcement user {UserId} code={Code}", user.Id, OfficialUniqueCode);
        return user;
    }

    public async Task<bool> IsOfficialConversationAsync(Guid conversationId, CancellationToken ct = default)
    {
        var official = await GetOfficialUserAsync(ct);
        if (official == null) return false;
        return await db.Conversations.AnyAsync(c =>
            c.Id == conversationId &&
            c.Type == ConversationType.Private &&
            (c.User1Id == official.Id || c.User2Id == official.Id), ct);
    }

    public async Task<(Conversation Conversation, User OfficialUser)?> EnsureForUserAsync(
        Guid userId,
        CancellationToken ct = default)
    {
        if (userId == Guid.Empty) return null;

        var official = await EnsureOfficialUserAsync(ct);
        if (official.Id == userId) return null;

        var u1 = official.Id;
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

        var deletion = await db.UserConversationDeletions
            .FirstOrDefaultAsync(d => d.UserId == userId && d.ConversationId == conv.Id, ct);
        if (deletion != null)
            db.UserConversationDeletions.Remove(deletion);

        var state = await db.UserConversationStates
            .FirstOrDefaultAsync(s => s.UserId == userId && s.ConversationId == conv.Id, ct);
        if (state == null)
        {
            db.UserConversationStates.Add(new UserConversationState
            {
                UserId = userId,
                ConversationId = conv.Id,
                IsPinned = true,
                IsArchived = false,
                IsHidden = false,
                UpdatedAt = DateTime.UtcNow
            });
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
                SenderId = official.Id,
                Content = messageCrypto.EncryptForStorage(WelcomeText),
                Type = "text",
                SentAt = DateTime.UtcNow,
                DisappearMode = DisappearMode.Off,
                IsRead = false
            });
        }

        await db.SaveChangesAsync(ct);
        if (created)
            logger.LogInformation("Created official announcement conversation {ConvId} for user {UserId}", conv.Id, userId);
        return (conv, official);
    }
}
