using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using NexChat.API.Hubs;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);

// Database
builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Services (In-Memory Matching - no Redis needed)
builder.Services.AddScoped<JwtService>();
builder.Services.AddScoped<MatchingService>();

// JWT Auth
var jwtSecret = builder.Configuration["Jwt:Secret"] ?? "NexChatSuperSecretKeyForJWT2025!";
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opt =>
    {
        opt.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateIssuer = false,
            ValidateAudience = false,
            ClockSkew = TimeSpan.Zero
        };

        // Allow JWT in SignalR WebSocket query string
        opt.Events = new JwtBearerEvents
        {
            OnMessageReceived = ctx =>
            {
                var accessToken = ctx.Request.Query["access_token"];
                var path = ctx.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
                    ctx.Token = accessToken;
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization(opt =>
{
    opt.AddPolicy("AdminOnly", policy =>
        policy.RequireRole("admin"));
});

builder.Services.AddControllers();
builder.Services.AddSignalR();
builder.Services.AddOpenApi();

// CORS
builder.Services.AddCors(opt =>
    opt.AddPolicy("NexChatPolicy", policy =>
        policy.WithOrigins(
            "http://localhost:5173",
            "http://localhost:5174",
            "capacitor://localhost",
            "ionic://localhost"
        )
        .AllowAnyMethod()
        .AllowAnyHeader()
        .AllowCredentials()
    )
);

var app = builder.Build();

// Auto migrate + seed admin
using (var scope = app.Services.CreateScope())
{
    var dbCtx = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await dbCtx.Database.MigrateAsync();

    if (!dbCtx.Users.Any(u => u.IsAdmin))
    {
        dbCtx.Users.Add(new NexChat.Core.Entities.User
        {
            Name = "admin",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("admin123"),
            Gender = "other",
            UniqueCode = "NX-ADMIN",
            IsAdmin = true
        });
        await dbCtx.SaveChangesAsync();
    }
}

if (app.Environment.IsDevelopment())
    app.MapOpenApi();

app.UseStaticFiles();
app.UseCors("NexChatPolicy");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.MapHub<MatchingHub>("/hubs/matching");
app.MapHub<ChatHub>("/hubs/chat");
app.MapHub<WebRtcHub>("/hubs/webrtc");

app.Run();
