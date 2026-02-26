using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using NexChat.Core.Entities;

namespace NexChat.Infrastructure.Services;

public class JwtService(IConfiguration config)
{
    private readonly string _secret = config["Jwt:Secret"] ?? throw new InvalidOperationException("JWT Secret not configured");
    private readonly string _issuer = config["Jwt:Issuer"] ?? "NexChat";
    private readonly string _audience = config["Jwt:Audience"] ?? "NexChatApp";

    public string GenerateToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.Name),
            new("gender", user.Gender),
            new("code", user.UniqueCode)
        };
        if (user.IsAdmin)
            claims.Add(new Claim("role", "admin"));

        var token = new JwtSecurityToken(
            issuer: _issuer,
            audience: _audience,
            claims: claims,
            expires: DateTime.UtcNow.AddDays(30),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
