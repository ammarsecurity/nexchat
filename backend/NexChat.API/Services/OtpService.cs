using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

public class OtpService(
    AppDbContext db,
    EvolutionWhatsAppService evolution,
    IMemoryCache cache,
    IConfiguration config,
    ILogger<OtpService> logger)
{
    public const string PurposeVerifyPhone = "verify_phone";
    public const string PurposeResetPassword = "reset_password";
    public const string PurposeRegister = "register";

    private string OtpPepper =>
        config["Otp:HmacSecret"]
        ?? config["Jwt:Secret"]
        ?? "NexChat-OTP";

    private string HashOtp(string code) => EvolutionWhatsAppService.HashCode(code, OtpPepper);

    public async Task<(bool Ok, SendOtpResponse? Response, string? Error, int StatusCode)> SendAsync(
        string purpose,
        string countryCode,
        string phoneNational,
        string? countryIso,
        Guid? userId,
        CancellationToken ct = default)
    {
        purpose = (purpose ?? "").Trim().ToLowerInvariant();
        if (purpose is not (PurposeVerifyPhone or PurposeResetPassword or PurposeRegister))
            return (false, null, "نوع التحقق غير صالح", 400);

        var status = await evolution.GetStatusAsync(ct);
        if (!status.Enabled || !status.Configured)
            return (false, null, "التحقق عبر واتساب غير مفعّل حالياً", 503);

        if (!PhoneValidationService.TryValidate(countryCode, phoneNational, out var fullPhone, out var phoneError))
            return (false, null, phoneError, 400);

        var cfg = await evolution.GetConfigAsync(ct);

        string? loginName = null;
        string? pendingCountry = null;

        if (purpose == PurposeVerifyPhone)
        {
            if (userId == null || userId == Guid.Empty)
                return (false, null, "يجب تسجيل الدخول", 401);

            var country = (countryIso ?? "").Trim().ToUpperInvariant();
            if (country.Length != 2)
                return (false, null, "كود الدولة يجب أن يكون حرفين (مثل IQ, SA)", 400);

            var duplicate = await db.Users.AnyAsync(u => u.PhoneNumber == fullPhone && u.Id != userId, ct);
            if (duplicate)
                return (false, null, "رقم الهاتف مستخدم من قبل حساب آخر", 409);
            pendingCountry = country;
        }
        else if (purpose == PurposeRegister)
        {
            var country = (countryIso ?? "").Trim().ToUpperInvariant();
            if (country.Length != 2)
                return (false, null, "كود الدولة يجب أن يكون حرفين (مثل IQ, SA)", 400);

            if (await db.Users.AnyAsync(u => u.PhoneNumber == fullPhone, ct))
                return (false, null, "رقم الهاتف مستخدم من قبل حساب آخر", 409);
            pendingCountry = country;
            userId = null;
        }
        else
        {
            var user = await db.Users.AsNoTracking()
                .FirstOrDefaultAsync(u => u.PhoneNumber == fullPhone, ct);
            if (user == null || user.IsBanned)
            {
                // لا نفصح عن وجود الحساب — نفس الرد دائماً
                await Task.Delay(Random.Shared.Next(180, 420), ct);
                return (true, new SendOtpResponse(true, cfg.OtpExpiryMinutes * 60, "إن وُجد حساب مرتبط بهذا الرقم فسيصلك الرمز عبر واتساب"), null, 200);
            }
            userId = user.Id;
            loginName = user.Name;
        }

        var recent = await db.OtpChallenges
            .Where(o => o.PhoneNumber == fullPhone && o.Purpose == purpose && !o.Consumed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (recent != null && recent.CreatedAt > DateTime.UtcNow.AddSeconds(-45))
        {
            var wait = 45 - (int)(DateTime.UtcNow - recent.CreatedAt).TotalSeconds;
            return (false, null, $"انتظر {Math.Max(wait, 1)} ثانية قبل إعادة الإرسال", 429);
        }

        var code = EvolutionWhatsAppService.GenerateCode(cfg.OtpLength);
        var message = evolution.BuildOtpMessage(cfg, code, loginName);

        // احفظ التحدي أولاً ثم أرسل — حتى لا يصل رمز بلا سجل قابل للتحقق
        var old = await db.OtpChallenges
            .Where(o => o.PhoneNumber == fullPhone && o.Purpose == purpose && !o.Consumed)
            .ToListAsync(ct);
        foreach (var o in old) o.Consumed = true;

        var challenge = new OtpChallenge
        {
            PhoneNumber = fullPhone,
            Purpose = purpose,
            CodeHash = HashOtp(code),
            UserId = userId,
            PendingCountry = pendingCountry,
            ExpiresAt = DateTime.UtcNow.AddMinutes(cfg.OtpExpiryMinutes),
        };
        db.OtpChallenges.Add(challenge);
        await db.SaveChangesAsync(ct);

        var (sent, sendError) = await evolution.SendTextAsync(fullPhone, message, ct);
        if (!sent)
        {
            challenge.Consumed = true;
            await db.SaveChangesAsync(ct);
            return (false, null, sendError ?? "فشل إرسال الرمز", 502);
        }

        logger.LogInformation("OTP sent purpose={Purpose} phone=***{Tail}", purpose, fullPhone[^4..]);
        return (true, new SendOtpResponse(true, cfg.OtpExpiryMinutes * 60, "تم إرسال رمز التحقق عبر واتساب"), null, 200);
    }

    /// <summary>التحقق من رمز OTP للتسجيل دون إنشاء المستخدم بعد.</summary>
    public async Task<(bool Ok, string? BoundCountry, string? Error, int StatusCode)> ConsumeRegisterOtpAsync(
        string fullPhone,
        string countryIso,
        string code,
        CancellationToken ct = default)
    {
        var country = (countryIso ?? "").Trim().ToUpperInvariant();
        if (country.Length != 2)
            return (false, null, "كود الدولة يجب أن يكون حرفين (مثل IQ, SA)", 400);

        var challenge = await FindValidChallengeAsync(fullPhone, PurposeRegister, ct);
        if (challenge == null)
            return (false, null, "انتهت صلاحية الرمز أو لم يُرسل بعد", 400);

        if (!string.IsNullOrEmpty(challenge.PendingCountry) &&
            !string.Equals(challenge.PendingCountry, country, StringComparison.OrdinalIgnoreCase))
            return (false, null, "الدولة لا تطابق طلب التحقق", 400);

        if (!TryMatchCode(challenge, code, out var err, out var status))
        {
            await db.SaveChangesAsync(ct);
            return (false, null, err, status);
        }

        challenge.Consumed = true;
        await db.SaveChangesAsync(ct);
        var bound = string.IsNullOrEmpty(challenge.PendingCountry) ? country : challenge.PendingCountry;
        return (true, bound, null, 200);
    }

    public async Task<(bool Ok, string? Error, int StatusCode)> VerifyPhoneAndSaveAsync(
        Guid userId,
        string countryCode,
        string phoneNational,
        string countryIso,
        string code,
        CancellationToken ct = default)
    {
        if (!PhoneValidationService.TryValidate(countryCode, phoneNational, out var fullPhone, out var phoneError))
            return (false, phoneError, 400);

        var country = (countryIso ?? "").Trim().ToUpperInvariant();
        if (country.Length != 2)
            return (false, "كود الدولة يجب أن يكون حرفين (مثل IQ, SA)", 400);

        var challenge = await FindValidChallengeAsync(fullPhone, PurposeVerifyPhone, ct);
        if (challenge == null)
            return (false, "انتهت صلاحية الرمز أو لم يُرسل بعد", 400);

        if (challenge.UserId != null && challenge.UserId != userId)
            return (false, "الرمز غير صالح لهذا الحساب", 403);

        if (!string.IsNullOrEmpty(challenge.PendingCountry) &&
            !string.Equals(challenge.PendingCountry, country, StringComparison.OrdinalIgnoreCase))
            return (false, "الدولة لا تطابق طلب التحقق", 400);

        if (!TryMatchCode(challenge, code, out var err, out var status))
        {
            await db.SaveChangesAsync(ct);
            return (false, err, status);
        }

        var duplicate = await db.Users.AnyAsync(u => u.PhoneNumber == fullPhone && u.Id != userId, ct);
        if (duplicate)
            return (false, "رقم الهاتف مستخدم من قبل حساب آخر", 409);

        var boundCountry = string.IsNullOrEmpty(challenge.PendingCountry) ? country : challenge.PendingCountry;
        challenge.Consumed = true;
        await db.Users.Where(u => u.Id == userId).ExecuteUpdateAsync(s => s
            .SetProperty(u => u.Country, boundCountry)
            .SetProperty(u => u.PhoneNumber, fullPhone)
            .SetProperty(u => u.IsPhoneVerified, true), ct);
        await db.SaveChangesAsync(ct);
        return (true, null, 200);
    }

    public async Task<(bool Ok, string? Error, int StatusCode)> ResetPasswordAsync(
        string countryCode,
        string phoneNational,
        string code,
        string newPassword,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(newPassword) || newPassword.Length < 4)
            return (false, "كلمة المرور يجب أن تكون 4 أحرف على الأقل", 400);

        if (!PhoneValidationService.TryValidate(countryCode, phoneNational, out var fullPhone, out var phoneError))
            return (false, phoneError, 400);

        var challenge = await FindValidChallengeAsync(fullPhone, PurposeResetPassword, ct);
        if (challenge == null)
            return (false, "انتهت صلاحية الرمز أو لم يُرسل بعد", 400);

        if (!TryMatchCode(challenge, code, out var err, out var status))
        {
            await db.SaveChangesAsync(ct);
            return (false, err, status);
        }

        var user = await db.Users.FirstOrDefaultAsync(u => u.PhoneNumber == fullPhone, ct);
        if (user == null)
            return (false, "انتهت صلاحية الرمز أو لم يُرسل بعد", 400);
        if (user.IsBanned)
            return (false, "هذا الحساب محظور", 403);

        challenge.Consumed = true;
        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(newPassword);
        user.IsPhoneVerified = true;
        await db.DeviceSubscriptions.Where(d => d.UserId == user.Id).ExecuteDeleteAsync();
        await db.SaveChangesAsync(ct);
        cache.Remove($"avs:{user.Id}");
        return (true, null, 200);
    }

    private async Task<OtpChallenge?> FindValidChallengeAsync(string fullPhone, string purpose, CancellationToken ct)
    {
        return await db.OtpChallenges
            .Where(o => o.PhoneNumber == fullPhone
                        && o.Purpose == purpose
                        && !o.Consumed
                        && o.ExpiresAt > DateTime.UtcNow)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);
    }

    private bool TryMatchCode(OtpChallenge challenge, string code, out string? error, out int status)
    {
        error = null;
        status = 200;
        if (challenge.Attempts >= 5)
        {
            challenge.Consumed = true;
            error = "تم تجاوز عدد المحاولات. أعد إرسال رمز جديد";
            status = 429;
            return false;
        }

        challenge.Attempts++;
        var hash = HashOtp(code ?? "");
        if (!string.Equals(hash, challenge.CodeHash, StringComparison.OrdinalIgnoreCase))
        {
            error = "رمز التحقق غير صحيح";
            status = 400;
            return false;
        }
        return true;
    }
}
