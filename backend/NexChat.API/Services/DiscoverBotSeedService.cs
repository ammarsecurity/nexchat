using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using NexChat.Core;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

public class DiscoverBotSeedService(
    AppDbContext db,
    IWebHostEnvironment env,
    IConfiguration config,
    IMediaFileCrypto mediaCrypto,
    DiscoverBotsSettingsService settings)
{
    private static readonly string[] FemaleNames =
    [
        "نور", "سارة", "مريم", "لين", "ياسمين", "هدى", "ريم", "دانية", "علا", "شهد",
        "تالا", "ليندا", "سلمى", "جنى", "رند", "مايا", "لارا", "تولين", "ميس", "فرح",
        "آية", "بتول", "خلود", "داليا", "رغد", "زهراء", "سنا", "شذى", "عُلا", "غادة",
        "إيناس", "قمر", "كندا", "لمى", "منى", "ندى", "هبة", "ورد", "يسرى", "أمل"
    ];

    private static readonly string[] MaleNames =
    [
        "أحمد", "علي", "حسن", "حسين", "محمد", "عمر", "يوسف", "كريم", "مصطفى", "زيد",
        "أوس", "باسم", "تامر", "جعفر", "خالد", "رائد", "سامر", "صلاح", "طارق", "عباس",
        "فارس", "قاسم", "لؤي", "ماجد", "نبيل", "هاني", "وسام", "ياسر", "إياد", "بدر",
        "جهاد", "حازم", "رعد", "سعد", "عادل", "غازي", "فهد", "قصي", "مروان", "نزار"
    ];

    /// <summary>Shared unusable password hash — bots never log in; hashing once keeps sync fast.</summary>
    private static readonly Lazy<string> SharedBotPasswordHash = new(() =>
        BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString("N") + "|discover-bot"));

    public string PhotoRoot
    {
        get
        {
            var configured = config["DiscoverBots:PhotoRoot"];
            if (!string.IsNullOrWhiteSpace(configured))
                return Path.GetFullPath(configured);
            return Path.GetFullPath(Path.Combine(env.ContentRootPath, "data", "discover-bots"));
        }
    }

    public (int available, int used) CountPhotos(string gender)
    {
        var folder = Path.Combine(PhotoRoot, gender == "female" ? "female" : "male");
        if (!Directory.Exists(folder)) return (0, 0);
        var files = Directory.GetFiles(folder, "*.jpg")
            .Concat(Directory.GetFiles(folder, "*.jpeg"))
            .Concat(Directory.GetFiles(folder, "*.png"))
            .Select(f => RelPath(gender, f))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        // Load usages in memory — avoid EF translating HashSet.Contains to SQL incorrectly.
        var usedPaths = db.DiscoverBotPhotoUsages.AsNoTracking()
            .Where(u => u.Gender == gender)
            .Select(u => u.RelativePath)
            .ToList()
            .Count(p => files.Contains(p));
        return (files.Count, usedPaths);
    }

    public async Task<DiscoverBotsStatusDto> GetStatusAsync(CancellationToken ct = default)
    {
        var cfg = await settings.GetConfigAsync(ct);
        var femaleBots = await db.Users.AsNoTracking().CountAsync(u => u.IsDiscoverBot && u.Gender == "female", ct);
        var maleBots = await db.Users.AsNoTracking().CountAsync(u => u.IsDiscoverBot && u.Gender == "male", ct);
        var (fAvail, fUsed) = CountPhotos("female");
        var (mAvail, mUsed) = CountPhotos("male");
        return new DiscoverBotsStatusDto(cfg, femaleBots, maleBots, Math.Max(0, fAvail - fUsed), Math.Max(0, mAvail - mUsed), fUsed, mUsed);
    }

    public async Task<DiscoverBotsSyncResultDto> SyncAsync(CancellationToken ct = default)
    {
        var cfg = await settings.GetConfigAsync(ct);
        var createdF = await EnsureGenderAsync("female", cfg.FemaleTarget, cfg, ct);
        var createdM = await EnsureGenderAsync("male", cfg.MaleTarget, cfg, ct);
        var (fAvail, fUsed) = CountPhotos("female");
        var (mAvail, mUsed) = CountPhotos("male");
        string? msg = null;
        if (createdF + createdM == 0)
            msg = "لا يوجد نقص، أو نفدت الصور غير المستخدمة في الحزمة.";
        else
            msg = $"أُنشئ {createdF} أنثى و {createdM} ذكر.";
        return new DiscoverBotsSyncResultDto(createdF, createdM, Math.Max(0, fAvail - fUsed), Math.Max(0, mAvail - mUsed), msg);
    }

    /// <summary>Re-encode bundled photos onto existing bots (keeps accounts; replaces blurry old uploads).</summary>
    public async Task<object> RefreshPhotosAsync(CancellationToken ct = default)
    {
        var usages = await db.DiscoverBotPhotoUsages.AsNoTracking().ToListAsync(ct);
        var userIds = usages.Select(u => u.UserId).ToList();
        var users = await db.Users.Where(u => u.IsDiscoverBot && userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, ct);
        var uploads = Path.GetFullPath(Path.Combine(env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot"), "uploads"));
        Directory.CreateDirectory(uploads);
        var baseUrl = (config["Media:BaseUrl"] ?? "").TrimEnd('/');
        var updated = 0;
        var missing = 0;

        foreach (var usage in usages)
        {
            ct.ThrowIfCancellationRequested();
            if (!users.TryGetValue(usage.UserId, out var user)) continue;
            var file = Path.Combine(PhotoRoot, usage.RelativePath.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(file)) { missing++; continue; }

            await using var fs = File.OpenRead(file);
            var optimized = await ImageOptimizeService.TryOptimizeAsync(fs, Path.GetExtension(file), ct);
            byte[] bytes;
            string ext;
            if (optimized != null)
            {
                bytes = optimized.Bytes;
                ext = optimized.Extension;
            }
            else
            {
                fs.Position = 0;
                using var ms = new MemoryStream();
                await fs.CopyToAsync(ms, ct);
                bytes = ms.ToArray();
                ext = Path.GetExtension(file).ToLowerInvariant();
                if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp")) ext = ".jpg";
            }
            if (bytes.Length < 500) { missing++; continue; }

            var fileName = $"{Guid.NewGuid():D}{ext}";
            var dest = Path.Combine(uploads, fileName);
            await mediaCrypto.WriteAllEncryptedAsync(dest, bytes, ct);
            var url = string.IsNullOrEmpty(baseUrl) ? $"/uploads/{fileName}" : $"{baseUrl}/uploads/{fileName}";
            var (json, avatar) = ProfilePhotos.Normalize([url]);
            if (avatar == null) { missing++; continue; }
            user.Avatar = avatar;
            user.ProfilePhotosJson = json;
            updated++;
        }

        await db.SaveChangesAsync(ct);
        return new { updated, missing, status = await GetStatusAsync(ct) };
    }

    public async Task<int> DeleteAllBotsAsync(CancellationToken ct = default)
    {
        var ids = await db.Users.Where(u => u.IsDiscoverBot).Select(u => u.Id).ToListAsync(ct);
        if (ids.Count == 0) return 0;

        await db.UserSwipes.Where(s => ids.Contains(s.FromUserId) || ids.Contains(s.ToUserId)).ExecuteDeleteAsync(ct);

        var matchConvIds = await db.UserMatches.AsNoTracking()
            .Where(m => ids.Contains(m.UserAId) || ids.Contains(m.UserBId))
            .Select(m => m.ConversationId)
            .Distinct()
            .ToListAsync(ct);
        await db.UserMatches.Where(m => ids.Contains(m.UserAId) || ids.Contains(m.UserBId)).ExecuteDeleteAsync(ct);

        if (matchConvIds.Count > 0)
        {
            var msgIds = await db.ConversationMessages.AsNoTracking()
                .Where(m => matchConvIds.Contains(m.ConversationId))
                .Select(m => m.Id)
                .ToListAsync(ct);
            if (msgIds.Count > 0)
            {
                await db.MessageReactions.Where(r => msgIds.Contains(r.MessageId)).ExecuteDeleteAsync(ct);
                await db.UserMessageDeletions.Where(d => msgIds.Contains(d.MessageId)).ExecuteDeleteAsync(ct);
                await db.ViewOnceReceipts.Where(r => msgIds.Contains(r.MessageId)).ExecuteDeleteAsync(ct);
            }
            await db.UserConversationDeletions.Where(d => matchConvIds.Contains(d.ConversationId)).ExecuteDeleteAsync(ct);
            await db.UserConversationStates.Where(s => matchConvIds.Contains(s.ConversationId)).ExecuteDeleteAsync(ct);
            await db.ConversationMessages.Where(m => matchConvIds.Contains(m.ConversationId)).ExecuteDeleteAsync(ct);
            await db.ConversationMembers.Where(m => matchConvIds.Contains(m.ConversationId)).ExecuteDeleteAsync(ct);
            await db.Conversations.Where(c => matchConvIds.Contains(c.Id)).ExecuteDeleteAsync(ct);
        }

        await db.Contacts.Where(c => ids.Contains(c.UserId) || ids.Contains(c.ContactUserId)).ExecuteDeleteAsync(ct);
        await db.UserBlocks.Where(b => ids.Contains(b.BlockerId) || ids.Contains(b.BlockedUserId)).ExecuteDeleteAsync(ct);
        await db.MessageRequests.Where(r => ids.Contains(r.RequesterId) || ids.Contains(r.TargetId)).ExecuteDeleteAsync(ct);
        await db.Reports.Where(r => ids.Contains(r.ReporterId) || ids.Contains(r.ReportedId)).ExecuteDeleteAsync(ct);
        await db.UserNotifications.Where(n => ids.Contains(n.UserId)).ExecuteDeleteAsync(ct);
        await db.NotificationOutboxItems.Where(n => ids.Contains(n.RecipientUserId)).ExecuteDeleteAsync(ct);
        await db.DeviceSubscriptions.Where(d => ids.Contains(d.UserId)).ExecuteDeleteAsync(ct);
        await db.DiscoverBotPhotoUsages.Where(p => ids.Contains(p.UserId)).ExecuteDeleteAsync(ct);
        await db.Users.Where(u => u.IsDiscoverBot).ExecuteDeleteAsync(ct);
        return ids.Count;
    }

    private async Task<int> EnsureGenderAsync(string gender, int target, DiscoverBotsConfigDto cfg, CancellationToken ct)
    {
        var current = await db.Users.CountAsync(u => u.IsDiscoverBot && u.Gender == gender, ct);
        var need = Math.Max(0, target - current);
        if (need == 0) return 0;

        var folder = Path.Combine(PhotoRoot, gender == "female" ? "female" : "male");
        if (!Directory.Exists(folder)) return 0;

        var usedSet = (await db.DiscoverBotPhotoUsages.AsNoTracking()
                .Where(u => u.Gender == gender)
                .Select(u => u.RelativePath)
                .ToListAsync(ct))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var freeFiles = Directory.GetFiles(folder, "*.*")
            .Where(f => f.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
                        || f.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase)
                        || f.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
            .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
            .Where(f => !usedSet.Contains(RelPath(gender, f)))
            .Take(need)
            .ToList();

        if (freeFiles.Count == 0) return 0;

        var created = 0;
        var uploads = Path.GetFullPath(Path.Combine(env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot"), "uploads"));
        Directory.CreateDirectory(uploads);
        var baseUrl = (config["Media:BaseUrl"] ?? "").TrimEnd('/');
        var passwordHash = SharedBotPasswordHash.Value;
        var existingNames = await db.Users.AsNoTracking().Select(u => u.Name).ToListAsync(ct);
        var nameSet = existingNames.ToHashSet(StringComparer.Ordinal);
        var existingPhones = await db.Users.AsNoTracking()
            .Where(u => u.PhoneNumber != null)
            .Select(u => u.PhoneNumber!)
            .ToListAsync(ct);
        var phoneSet = existingPhones.ToHashSet(StringComparer.Ordinal);
        var existingCodes = await db.Users.AsNoTracking().Select(u => u.UniqueCode).ToListAsync(ct);
        var codeSet = existingCodes.ToHashSet(StringComparer.OrdinalIgnoreCase);

        const int batchSize = 25;
        var pending = 0;

        foreach (var file in freeFiles)
        {
            ct.ThrowIfCancellationRequested();
            byte[] bytes;
            string ext;
            try
            {
                await using var fs = File.OpenRead(file);
                var optimized = await ImageOptimizeService.TryOptimizeAsync(fs, Path.GetExtension(file), ct);
                if (optimized != null)
                {
                    bytes = optimized.Bytes;
                    ext = optimized.Extension;
                }
                else
                {
                    fs.Position = 0;
                    using var ms = new MemoryStream();
                    await fs.CopyToAsync(ms, ct);
                    bytes = ms.ToArray();
                    ext = Path.GetExtension(file).ToLowerInvariant();
                    if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp")) ext = ".jpg";
                }
            }
            catch { continue; }
            if (bytes.Length < 500) continue;

            var fileName = $"{Guid.NewGuid():D}{ext}";
            var dest = Path.Combine(uploads, fileName);
            await mediaCrypto.WriteAllEncryptedAsync(dest, bytes, ct);

            var url = string.IsNullOrEmpty(baseUrl)
                ? $"/uploads/{fileName}"
                : $"{baseUrl}/uploads/{fileName}";
            var (json, avatar) = ProfilePhotos.Normalize([url]);
            if (avatar == null)
            {
                try { File.Delete(dest); } catch { /* ignore */ }
                continue;
            }

            var name = NextUniqueNameLocal(gender, nameSet);
            var phone = NextUniquePhoneLocal(phoneSet);
            var code = NextUniqueCodeLocal(codeSet);
            var birth = RandomBirthDate(cfg.AgeMin, cfg.AgeMax);
            var userId = Guid.NewGuid();

            db.Users.Add(new User
            {
                Id = userId,
                Name = name,
                PasswordHash = passwordHash,
                Gender = gender,
                BirthDate = birth,
                UniqueCode = code,
                PhoneNumber = phone,
                Country = cfg.Country,
                IsPhoneVerified = false,
                DiscoverEnabled = true,
                IsDiscoverBot = true,
                IsAdmin = false,
                IsBanned = false,
                Avatar = avatar,
                ProfilePhotosJson = json,
                DiscoverPreferGender = "all",
                DiscoverAgeMin = 18,
                DiscoverAgeMax = 60,
                Bio = null,
                IsOnline = Random.Shared.Next(100) < 35
            });
            db.DiscoverBotPhotoUsages.Add(new DiscoverBotPhotoUsage
            {
                RelativePath = RelPath(gender, file),
                Gender = gender,
                UserId = userId
            });
            created++;
            pending++;

            if (pending >= batchSize)
            {
                await db.SaveChangesAsync(ct);
                pending = 0;
            }
        }

        if (pending > 0)
            await db.SaveChangesAsync(ct);

        return created;
    }

    private static string RelPath(string gender, string absolutePath)
    {
        var folder = gender == "female" ? "female" : "male";
        return $"{folder}/{Path.GetFileName(absolutePath)}".Replace('\\', '/');
    }

    private static string NextUniqueNameLocal(string gender, HashSet<string> nameSet)
    {
        var pool = gender == "female" ? FemaleNames : MaleNames;
        for (var attempt = 0; attempt < 200; attempt++)
        {
            var baseName = pool[Random.Shared.Next(pool.Length)];
            var suffix = Random.Shared.Next(10, 9999);
            var name = $"{baseName} {suffix}";
            if (name.Length > 50) name = name[..50];
            if (nameSet.Add(name)) return name;
        }
        var fallback = $"Bot {Guid.NewGuid():N}"[..16];
        nameSet.Add(fallback);
        return fallback;
    }

    private static string NextUniquePhoneLocal(HashSet<string> phoneSet)
    {
        for (var i = 0; i < 80; i++)
        {
            var mid = Random.Shared.Next(3) switch { 0 => "75", 1 => "77", _ => "78" };
            var rest = RandomNumberGenerator.GetInt32(10_000_000, 99_999_999);
            var phone = $"964{mid}{rest}";
            if (phoneSet.Add(phone)) return phone;
        }
        var fb = $"96479{RandomNumberGenerator.GetInt32(10000000, 99999999)}";
        phoneSet.Add(fb);
        return fb;
    }

    private static string NextUniqueCodeLocal(HashSet<string> codeSet)
    {
        string code;
        do
        {
            code = "NX-" + Guid.NewGuid().ToString("N")[..4].ToUpperInvariant();
        } while (!codeSet.Add(code));
        return code;
    }

    private static DateOnly RandomBirthDate(int ageMin, int ageMax)
    {
        var age = Random.Shared.Next(ageMin, ageMax + 1);
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        // Keep within the chosen age year (avoid drifting past ageMax).
        return today.AddYears(-age).AddDays(-Random.Shared.Next(0, 30));
    }
}
