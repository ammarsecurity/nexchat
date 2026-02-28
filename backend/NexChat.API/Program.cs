using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using NexChat.API.Hubs;
using NexChat.API.Middleware;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
var builder = WebApplication.CreateBuilder(args);

// Database - MySQL
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseMySql(connectionString, ServerVersion.AutoDetect(connectionString)));

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
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Rate Limiting
builder.Services.AddRateLimiter(opt =>
{
    opt.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    opt.AddFixedWindowLimiter("api", config =>
    {
        config.PermitLimit = 100;
        config.Window = TimeSpan.FromMinutes(1);
        config.QueueLimit = 5;
    });
    opt.AddFixedWindowLimiter("auth", config =>
    {
        config.PermitLimit = 10;
        config.Window = TimeSpan.FromMinutes(1);
    });
});

// CORS - مسموح لجميع المصادر
builder.Services.AddCors(opt =>
    opt.AddPolicy("NexChatPolicy", policy =>
    {
        policy.SetIsOriginAllowed(origin => !string.IsNullOrEmpty(origin))
            .AllowAnyMethod()
            .AllowAnyHeader()
            .AllowCredentials();
    })
);

var app = builder.Build();

app.UseMiddleware<ExceptionHandlingMiddleware>();

// Forwarded headers (عند تشغيل خلف nginx/aaPanel)
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost
});

// Auto migrate + seed admin
using (var scope = app.Services.CreateScope())
{
    var dbCtx = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await dbCtx.Database.MigrateAsync();

    if (!dbCtx.Users.Any(u => u.IsAdmin))
    {
        var adminPassword = builder.Configuration["Admin:Password"]
            ?? Environment.GetEnvironmentVariable("NEXCHAT_ADMIN_PASSWORD");
        if (string.IsNullOrEmpty(adminPassword))
        {
            if (app.Environment.IsDevelopment())
                adminPassword = "DevAdmin2025!"; // فقط للتطوير - غيّره في الإنتاج
            else
                throw new InvalidOperationException("Admin password must be set via Admin:Password or NEXCHAT_ADMIN_PASSWORD");
        }
        dbCtx.Users.Add(new NexChat.Core.Entities.User
        {
            Name = "admin",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(adminPassword),
            Gender = "other",
            UniqueCode = "NX-ADMIN",
            IsAdmin = true
        });
        await dbCtx.SaveChangesAsync();
    }

    if (!dbCtx.Users.Any(u => u.UniqueCode == "NX-SUPPORT"))
    {
        var supportPassword = builder.Configuration["Support:Password"]
            ?? Environment.GetEnvironmentVariable("NEXCHAT_SUPPORT_PASSWORD")
            ?? "Support2025!";
        dbCtx.Users.Add(new NexChat.Core.Entities.User
        {
            Name = "دعم",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(supportPassword),
            Gender = "other",
            UniqueCode = "NX-SUPPORT",
            IsAdmin = false
        });
        await dbCtx.SaveChangesAsync();
    }
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "NexChat API v1"));
}

app.UseStaticFiles();
app.UseCors("NexChatPolicy");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.MapHub<MatchingHub>("/hubs/matching");
app.MapHub<ChatHub>("/hubs/chat");

app.Run();
