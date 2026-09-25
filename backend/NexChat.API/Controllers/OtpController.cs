using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/otp")]
[EnableRateLimiting("auth")]
public class OtpController(OtpService otp, EvolutionWhatsAppService evolution) : ControllerBase
{
    /// <summary>حالة تفعيل واتساب OTP للتطبيق.</summary>
    [HttpGet("status")]
    [AllowAnonymous]
    public async Task<ActionResult<EvolutionWhatsAppStatusDto>> GetStatus(CancellationToken ct)
        => Ok(await evolution.GetStatusAsync(ct));

    /// <summary>
    /// إرسال رمز OTP عبر واتساب.
    /// purpose: verify_phone (يتطلب JWT) | reset_password | register (عام)
    /// </summary>
    [HttpPost("send")]
    [AllowAnonymous]
    public async Task<IActionResult> Send([FromBody] SendOtpRequest req, CancellationToken ct)
    {
        var purpose = (req.Purpose ?? "").Trim().ToLowerInvariant();
        Guid? userId = null;

        if (purpose == OtpService.PurposeVerifyPhone)
        {
            // AllowAnonymous لا يملأ User دائماً إن فشل الـ JWT — نتحقق صراحة من الـ claim
            var idClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (User.Identity?.IsAuthenticated != true || string.IsNullOrEmpty(idClaim) || !Guid.TryParse(idClaim, out var uid))
                return Unauthorized(new { message = "يجب تسجيل الدخول" });
            userId = uid;
        }

        var (ok, response, error, status) = await otp.SendAsync(
            purpose,
            req.CountryCode,
            req.PhoneNumber,
            req.Country,
            userId,
            ct);

        if (!ok)
            return StatusCode(status, new { message = error });
        return Ok(response);
    }

    /// <summary>تأكيد رقم الهاتف عبر OTP وحفظه في الملف الشخصي.</summary>
    [HttpPost("verify-phone")]
    [Authorize]
    public async Task<IActionResult> VerifyPhone([FromBody] VerifyPhoneOtpRequest req, CancellationToken ct)
    {
        var userId = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        var (ok, error, status) = await otp.VerifyPhoneAndSaveAsync(
            userId,
            req.CountryCode,
            req.PhoneNumber,
            req.Country,
            req.Code,
            ct);
        if (!ok)
            return StatusCode(status, new { message = error });
        return Ok(new { message = "تم التحقق من الرقم بنجاح" });
    }

    /// <summary>إعادة تعيين كلمة المرور عبر OTP واتساب.</summary>
    [HttpPost("reset-password")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordOtpRequest req, CancellationToken ct)
    {
        var (ok, error, status) = await otp.ResetPasswordAsync(
            req.CountryCode,
            req.PhoneNumber,
            req.Code,
            req.NewPassword,
            ct);
        if (!ok)
            return StatusCode(status, new { message = error });
        return Ok(new { message = "تم تغيير كلمة المرور بنجاح" });
    }
}
