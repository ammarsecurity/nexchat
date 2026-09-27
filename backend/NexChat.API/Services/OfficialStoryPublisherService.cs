using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Services;

/// <summary>
/// يضمن وجود حساب نظام NexChat لنشر الستوري الرسمي لكل المستخدمين.
/// </summary>
public class OfficialStoryPublisherService(AppDbContext db, ILogger<OfficialStoryPublisherService> logger)
{
    /// <summary>Max 10 chars (Users.UniqueCode varchar(10)).</summary>
    public const string UniqueCode = "NX-STORY";
    public const string DisplayName = "NexChat";

    public async Task<User> GetOrCreateAsync(CancellationToken ct = default)
    {
        var existing = await db.Users.FirstOrDefaultAsync(u => u.IsOfficialStoryPublisher, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == UniqueCode, ct);

        if (existing != null)
        {
            var dirty = false;
            if (!existing.IsOfficialStoryPublisher)
            {
                existing.IsOfficialStoryPublisher = true;
                dirty = true;
            }
            if (string.IsNullOrWhiteSpace(existing.Name))
            {
                existing.Name = DisplayName;
                dirty = true;
            }
            if (dirty)
                await db.SaveChangesAsync(ct);
            return existing;
        }

        var user = new User
        {
            Name = DisplayName,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString("N")),
            Gender = "other",
            UniqueCode = UniqueCode,
            IsAdmin = false,
            IsFeatured = true,
            IsOfficialStoryPublisher = true,
            PhoneNumber = null,
            IsPhoneVerified = false,
            CreatedAt = DateTime.UtcNow
        };
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Created official story publisher user {UserId}", user.Id);
        return user;
    }

    public Task<Guid?> GetPublisherIdAsync(CancellationToken ct = default) =>
        db.Users.AsNoTracking()
            .Where(u => u.IsOfficialStoryPublisher)
            .Select(u => (Guid?)u.Id)
            .FirstOrDefaultAsync(ct);

    public Task<bool> IsOfficialPublisherAsync(Guid userId, CancellationToken ct = default) =>
        db.Users.AsNoTracking().AnyAsync(u => u.Id == userId && u.IsOfficialStoryPublisher, ct);
}
