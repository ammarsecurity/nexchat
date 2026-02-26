using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.DTOs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController(AppDbContext db, JwtService jwt) : ControllerBase
{
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Length < 2 || req.Name.Length > 50)
            return BadRequest(new { message = "اسم غير صالح (2-50 حرف)" });

        if (string.IsNullOrWhiteSpace(req.Password) || req.Password.Length < 4)
            return BadRequest(new { message = "كلمة المرور يجب أن تكون 4 أحرف على الأقل" });

        if (!new[] { "male", "female", "other" }.Contains(req.Gender.ToLower()))
            return BadRequest(new { message = "الجنس غير صالح" });

        var nameExists = await db.Users.AnyAsync(u => u.Name.ToLower() == req.Name.ToLower());
        if (nameExists)
            return Conflict(new { message = "هذا الاسم مستخدم بالفعل" });

        var user = new User
        {
            Name = req.Name.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password),
            Gender = req.Gender.ToLower(),
            UniqueCode = await GenerateUniqueCode()
        };

        db.Users.Add(user);
        await db.SaveChangesAsync();

        var token = jwt.GenerateToken(user);
        return Ok(new AuthResponse(token, user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar));
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest req)
    {
        var user = await db.Users.FirstOrDefaultAsync(u =>
            u.Name.ToLower() == req.Name.ToLower());

        if (user == null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
            return Unauthorized(new { message = "اسم أو كلمة مرور غير صحيحة" });

        if (user.IsBanned)
            return Forbid();

        var token = jwt.GenerateToken(user);
        return Ok(new AuthResponse(token, user.Id, user.Name, user.Gender, user.UniqueCode, user.Avatar));
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
