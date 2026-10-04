using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Controllers;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Xunit;

namespace NexChat.Push.Tests;

public class PushRegistrationTests : IAsyncLifetime
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private AppDbContext _db = null!;
    private readonly Guid _a = Guid.NewGuid();
    private readonly Guid _b = Guid.NewGuid();
    private readonly string _phoneA = Guid.NewGuid().ToString();
    private readonly string _phoneB = Guid.NewGuid().ToString();

    public async Task InitializeAsync()
    {
        await _connection.OpenAsync();
        _connection.CreateCollation("utf8mb4_bin", string.CompareOrdinal);
        _db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseSqlite(_connection).Options);
        // Exercise the real controller/model against relational constraints, without unrelated
        // MySQL-specific schema types or any external database/provider request.
        await _db.Database.ExecuteSqlRawAsync("""
            CREATE TABLE DeviceSubscriptions (
                Id TEXT NOT NULL PRIMARY KEY, UserId TEXT NOT NULL,
                InstallationId TEXT NULL UNIQUE, OneSignalPlayerId TEXT NOT NULL UNIQUE,
                VoipDeviceToken TEXT NULL UNIQUE, Platform TEXT NULL, CreatedAt TEXT NOT NULL
            );
            """);
    }
    public async Task DisposeAsync() { await _db.DisposeAsync(); await _connection.DisposeAsync(); }
    private NotificationsController As(Guid user) => new(_db)
    {
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, user.ToString()) }, "test"))
        }}
    };

    [Fact]
    public async Task PUSH01_AccountSwitchTransfersBothChannelsToSingleOwner()
    {
        Assert.IsType<OkResult>(await As(_a).Register(new("player", "ios", _phoneA)));
        Assert.IsType<OkResult>(await As(_a).RegisterVoip(new("aabb", _phoneA)));
        Assert.IsType<OkResult>(await As(_b).Register(new("player", "ios", _phoneA)));
        var row = await _db.DeviceSubscriptions.SingleAsync();
        Assert.Equal(_b, row.UserId);
        Assert.Equal("aabb", row.VoipDeviceToken);
        Assert.IsType<OkObjectResult>(await As(_a).Unregister(new("player", "ios", _phoneA)));
        Assert.Equal(_b, (await _db.DeviceSubscriptions.SingleAsync()).UserId);
    }

    [Fact]
    public async Task PUSH03_FirstLoginVoipBeforeOneSignalMergesAndLogoutRevokesBoth()
    {
        Assert.IsType<OkResult>(await As(_a).RegisterVoip(new("abcd", _phoneA)));
        Assert.IsType<OkResult>(await As(_a).Register(new("player", "ios", _phoneA)));
        var row = await _db.DeviceSubscriptions.SingleAsync();
        Assert.Equal("player", row.OneSignalPlayerId);
        Assert.Equal("abcd", row.VoipDeviceToken);
        await As(_a).Unregister(new(null, "ios", _phoneA));
        Assert.Empty(await _db.DeviceSubscriptions.AsNoTracking().ToListAsync());
    }

    [Fact]
    public async Task PUSH03_TwoPhonesRefreshingTokensNeverOverwriteEachOther()
    {
        await As(_a).Register(new("phone-a", "ios", _phoneA));
        await As(_a).Register(new("phone-b", "ios", _phoneB));
        await As(_a).RegisterVoip(new("aaaa", _phoneA));
        await As(_a).RegisterVoip(new("bbbb", _phoneB));
        await As(_a).RegisterVoip(new("cccc", _phoneA));
        Assert.Equal("cccc", (await _db.DeviceSubscriptions.SingleAsync(x => x.InstallationId == _phoneA)).VoipDeviceToken);
        Assert.Equal("bbbb", (await _db.DeviceSubscriptions.SingleAsync(x => x.InstallationId == _phoneB)).VoipDeviceToken);
    }

    [Fact]
    public async Task PUSH03_InvalidatedTokenCannotRevokeOtherDeviceOrNewOwner()
    {
        await As(_a).RegisterVoip(new("aaaa", _phoneA));
        await As(_a).RegisterVoip(new("bbbb", _phoneB));
        await As(_b).Register(new("player", "ios", _phoneA));
        await As(_a).RegisterVoip(new("", _phoneA));
        Assert.Equal("aaaa", (await _db.DeviceSubscriptions.AsNoTracking().SingleAsync(x => x.InstallationId == _phoneA)).VoipDeviceToken);
        await As(_a).RegisterVoip(new("", _phoneB));
        Assert.Null((await _db.DeviceSubscriptions.AsNoTracking().SingleAsync(x => x.InstallationId == _phoneB)).VoipDeviceToken);
    }

    [Fact]
    public async Task PUSH01_LegacySubscriptionRegistrationAlsoTransfersOwnership()
    {
        await As(_a).Register(new("legacy-player", "android"));
        await As(_b).Register(new("legacy-player", "android"));
        Assert.Equal(_b, (await _db.DeviceSubscriptions.SingleAsync()).UserId);
    }

    [Fact]
    public async Task PUSH03_RejectsUnscopedAndMalformedVoipTokens()
    {
        Assert.IsType<BadRequestObjectResult>(await As(_a).RegisterVoip(new("aaaa")));
        Assert.IsType<BadRequestObjectResult>(await As(_a).RegisterVoip(new("not-hex", _phoneA)));
        Assert.IsType<BadRequestObjectResult>(await As(_a).RegisterVoip(new("aaaa", "not-a-uuid")));
        Assert.Empty(await _db.DeviceSubscriptions.ToListAsync());
    }

    [Fact]
    public async Task PUSH01_UniqueModelIndexesPreventCrossAccountDuplicates()
    {
        var indexes = _db.Model.FindEntityType(typeof(DeviceSubscription))!.GetIndexes();
        foreach (var property in new[] { "InstallationId", "OneSignalPlayerId", "VoipDeviceToken" })
            Assert.Contains(indexes, index => index.IsUnique && index.Properties.Single().Name == property);
        await As(_a).Register(new("same", "android", _phoneA));
        _db.DeviceSubscriptions.Add(new() { UserId = _b, InstallationId = _phoneB, OneSignalPlayerId = "same" });
        await Assert.ThrowsAsync<DbUpdateException>(() => _db.SaveChangesAsync());
    }
    private sealed class NoLogScope : Microsoft.Extensions.DependencyInjection.IServiceScopeFactory
    {
        public Microsoft.Extensions.DependencyInjection.IServiceScope CreateScope() =>
            throw new InvalidOperationException("No external log database in this test");
    }
    private sealed class CapturePush : HttpMessageHandler
    {
        public string Payload = "";
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken ct)
        {
            Payload = await req.Content!.ReadAsStringAsync(ct);
            return new(System.Net.HttpStatusCode.OK) { Content = new StringContent("{\"id\":\"test-message\"}") };
        }
    }

    [Fact]
    public async Task PUSH04_CancellationUsesNormalPriorityDataPushWithoutAlertOrSound()
    {
        await As(_a).Register(new("player", "ios", _phoneA));
        var capture = new CapturePush();
        var service = new NexChat.Infrastructure.Services.OneSignalService(new HttpClient(capture),
            Microsoft.Extensions.Options.Options.Create(new NexChat.Infrastructure.Services.OneSignalOptions {
                AppId = "test-app", RestApiKey = "test-key"
            }), _db, new NoLogScope(), Microsoft.Extensions.Logging.Abstractions.NullLogger<NexChat.Infrastructure.Services.OneSignalService>.Instance);
        var callId = Guid.NewGuid().ToString();
        Assert.True(await service.SendToUserAsync(_a, " ", " ", new Dictionary<string, string> {
            ["type"] = "call_cancel", ["callId"] = callId,
        }));
        using var document = System.Text.Json.JsonDocument.Parse(capture.Payload);
        var push = document.RootElement;
        Assert.True(push.GetProperty("content_available").GetBoolean());
        Assert.Equal(5, push.GetProperty("priority").GetInt32());
        Assert.False(push.TryGetProperty("contents", out _));
        Assert.False(push.TryGetProperty("headings", out _));
        Assert.False(push.TryGetProperty("ios_sound", out _));
        Assert.Equal($"call_{callId}", push.GetProperty("collapse_id").GetString());
        Assert.Equal(_a.ToString(), push.GetProperty("data").GetProperty("recipientUserId").GetString());
    }

}
