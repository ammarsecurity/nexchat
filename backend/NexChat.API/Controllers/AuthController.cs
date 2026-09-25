using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[EnableRateLimiting("auth")]
public class AuthController(AppDbContext db, JwtService jwt, OtpService otp, EvolutionWhatsAppService evolution) : ControllerBase
{
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length < 2 || req.Name.Length > 50)
            return BadRequest(new { message = "اسم غير صالح (2-50 حرف)" });

        if (string.IsNullOrWhiteSpace(req.Password) || req.Password.Length < 4)
            return BadRequest(new { message = "كلمة المرور يجب أن تكون 4 أحرف على الأقل" });

        if (!new[] { "male", "female", "other" }.Contains(req.Gender.ToLower()))
            return BadRequest(new { message = "الجنس غير صالح" });

        if (string.IsNullOrWhiteSpace(req.BirthDate))
            return BadRequest(new { message = "تاريخ الميلاد مطلوب" });

        if (!DateOnly.TryParse(req.BirthDate, out var birthDate))
            return BadRequest(new { message = "تاريخ الميلاد غير صالح" });

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var age = today.Year - birthDate.Year;
        if (birthDate > today.AddYears(-age)) age--;
        if (age < 18)
            return BadRequest(new { message = "يجب أن يكون عمرك 18 عاماً أو أكثر للتسجيل" });

        var country = (req.Country ?? "").Trim().ToUpperInvariant();
        var countryCode = (req.CountryCode ?? "").Trim().TrimStart('+');
        var phoneNational = (req.PhoneNumber ?? "").Trim().Replace(" ", "").Replace("-", "");

        if (country.Length != 2)
            return BadRequest(new { message = "اختر الدولة ورقم الهاتف" });

        if (!PhoneValidationService.TryValidate(countryCode, phoneNational, out var fullPhone, out var phoneError))
            return BadRequest(new { message = phoneError });

        var nameExists = await db.Users.AnyAsync(u => u.Name.ToLower() == req.Name.ToLower(), ct);
        if (nameExists)
            return Conflict(new { message = "هذا الاسم مستخدم بالفعل" });

        var phoneExists = await db.Users.AnyAsync(u => u.PhoneNumber == fullPhone, ct);
        if (phoneExists)
            return Conflict(new { message = "رقم الهاتف مستخدم من قبل حساب آخر" });

        var otpStatus = await evolution.GetStatusAsync(ct);
        var otpRequired = otpStatus.Enabled && otpStatus.Configured;
        var phoneVerified = false;

        if (otpRequired)
        {
            if (string.IsNullOrWhiteSpace(req.OtpCode))
                return BadRequest(new { message = "أدخل رمز التحقق من واتساب", requireOtp = true });

            var (otpOk, boundCountry, otpErr, otpCode) = await otp.ConsumeRegisterOtpAsync(fullPhone, country, req.OtpCode!, ct);
            if (!otpOk)
                return StatusCode(otpCode, new { message = otpErr });
            country = boundCountry ?? country;
            phoneVerified = true;
        }

        var user = new User
        {
            Name = req.Name.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password),
            Gender = req.Gender.ToLower(),
            BirthDate = birthDate,
            UniqueCode = await GenerateUniqueCode(),
            Country = country,
            PhoneNumber = fullPhone,
            IsPhoneVerified = phoneVerified,
        };

        db.Users.Add(user);
        await db.SaveChangesAsync(ct);

        var token = jwt.GenerateToken(user);
        return Ok(new AuthResponse(token, user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar, user.IsFeatured, NeedsProfileContact: false));
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest req)
    {
        var login = (req.Name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(login) || string.IsNullOrWhiteSpace(req.Password))
            return Unauthorized(new { message = "اسم أو كلمة مرور غير صحيحة" });

        User? user = null;

        // دخول برقم الهاتف إن بدا الإدخال كرقم
        var phoneCandidates = LoginPhoneCandidates(login);
        if (phoneCandidates.Count > 0)
        {
            user = await db.Users.FirstOrDefaultAsync(u =>
                u.PhoneNumber != null && phoneCandidates.Contains(u.PhoneNumber));
        }

        // وإلا (أو إن لم يُوجد) ابحث باسم الدخول
        if (user == null)
        {
            var lower = login.ToLowerInvariant();
            user = await db.Users.FirstOrDefaultAsync(u => u.Name.ToLower() == lower);
        }

        if (user == null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
            return Unauthorized(new { message = "اسم أو كلمة مرور غير صحيحة" });

        if (user.IsBanned)
            return Forbid();

        var token = jwt.GenerateToken(user);
        var needsProfileContact = string.IsNullOrWhiteSpace(user.Country) || string.IsNullOrWhiteSpace(user.PhoneNumber);
        return Ok(new AuthResponse(token, user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar, user.IsFeatured, needsProfileContact));
    }

    /// <summary>صيغ رقم محتملة للمطابقة مع Users.PhoneNumber عند تسجيل الدخول.</summary>
    private static HashSet<string> LoginPhoneCandidates(string raw)
    {
        var outSet = new HashSet<string>(StringComparer.Ordinal);
        var digits = new string((raw ?? "").Where(char.IsDigit).ToArray());
        if (digits.Length < 8 || digits.Length > 15)
            return outSet;

        // يجب أن يكون الإدخال أرقاماً/رموز هاتف غالباً وليس اسماً يحتوي أرقاماً قليلة
        var stripped = (raw ?? "").Trim().Replace(" ", "").Replace("-", "").Replace("+", "").Replace("(", "").Replace(")", "");
        if (stripped.Length == 0 || stripped.Any(c => !char.IsDigit(c)))
        {
            // اسمح بـ + فقط في البداية؛ غير ذلك اعتبره اسم دخول
            var tmp = (raw ?? "").Trim();
            if (!(tmp.StartsWith('+') && tmp[1..].All(c => char.IsDigit(c) || c == ' ' || c == '-')))
                return outSet;
        }

        while (digits.Length > 11 && digits.StartsWith("00"))
            digits = digits[2..];

        outSet.Add(digits);
        if (digits.StartsWith('0') && digits.Length > 1)
            outSet.Add(digits.TrimStart('0'));

        // أرقام عراقية شائعة: 07xxxxxxxx → 9647xxxxxxxx
        if (digits.StartsWith("07") && digits.Length == 11)
            outSet.Add("964" + digits[1..]);
        if (digits.StartsWith("7") && digits.Length == 10)
            outSet.Add("964" + digits);

        return outSet.Where(p => p.Length >= 8 && p.Length <= 15).ToHashSet(StringComparer.Ordinal);
    }

    private async Task<string> GenerateUniqueCode()
    {
        string code;
        do
        {
            code = "NX-" + Guid.NewGuid().ToString("N")[..4].ToUpper();
        } while (await db.Users.AnyAsync(u => u.UniqueCode == code));
        return code;
    }
}
