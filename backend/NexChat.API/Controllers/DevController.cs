using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

/// <summary>
/// واجهات للمطورين - استرجاع حساب الدعم عند الحذف.
/// </summary>
[ApiController]
[Route("api/dev")]
public class DevController(AppDbContext db, IConfiguration config) : ControllerBase
{
    /// <summary>
    /// استرجاع حساب الدعم. ينشئ الحساب إذا كان محذوفاً.
    /// </summary>
    [HttpPost("restore-support")]
    public async Task<ActionResult<object>> RestoreSupportAccount()
    {
        var supportUser = await db.Users.FirstOrDefaultAsync(u => u.UniqueCode == "NX-SUPPORT");
        if (supportUser != null)
            return Ok(new
            {
                created = false,
                message = "حساب الدعم موجود مسبقاً",
                user = new
                {
                    supportUser.Id,
                    supportUser.Name,
                    supportUser.UniqueCode,
                    supportUser.Avatar
                }
            });

        var password = config["Support:Password"]
            ?? Environment.GetEnvironmentVariable("NEXCHAT_SUPPORT_PASSWORD")
            ?? "Support2025!";

        supportUser = new NexChat.Core.Entities.User
        {
            Name = "دعم",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
            Gender = "other",
            UniqueCode = "NX-SUPPORT",
            IsAdmin = false
        };
        db.Users.Add(supportUser);
        await db.SaveChangesAsync();

        return Ok(new
        {
            created = true,
            message = "تم استرجاع حساب الدعم بنجاح",
            user = new
            {
                supportUser.Id,
                supportUser.Name,
                supportUser.UniqueCode,
                supportUser.Avatar
            }
        });
    }
}
