using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NexChat.API.Controllers;
using NexChat.API.Services;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Xunit;

namespace NexChat.Media.Tests;

public sealed class TestClock : TimeProvider
{
    public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
    public override DateTimeOffset GetUtcNow() => Now;
}

// Disposable in-process identities only. No real bearer tokens or outbound requests.
public sealed class TestAuthentication(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync() => Task.FromResult(
        Guid.TryParse(Request.Headers["X-Test-User"], out var id)
            ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, id.ToString())], "Test")), "Test"))
            : AuthenticateResult.NoResult());
}

public sealed class MediaSecurityTests : IAsyncLifetime
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "nexchat-media-tests-" + Guid.NewGuid());
    private readonly SqliteConnection connection = new("DataSource=:memory:");
    private IHost host = null!;
    private HttpClient client = null!;
    private readonly TestClock clock = new();
    private readonly Guid sender = Guid.NewGuid(), recipient = Guid.NewGuid(), other = Guid.NewGuid();

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(Path.Combine(root, "wwwroot"));
        await connection.OpenAsync();
        connection.CreateCollation("utf8mb4_bin", string.CompareOrdinal);
        host = await new HostBuilder().ConfigureWebHost(web => web.UseTestServer().UseContentRoot(root).UseWebRoot(Path.Combine(root, "wwwroot"))
            .ConfigureServices(services =>
            {
                services.AddControllers().AddApplicationPart(typeof(MediaController).Assembly);
                services.AddAuthentication("Test").AddScheme<AuthenticationSchemeOptions, TestAuthentication>("Test", _ => { });
                services.AddAuthorization();
                services.AddRateLimiter(options => options.AddFixedWindowLimiter("api", limiter => { limiter.PermitLimit = 1000; limiter.Window = TimeSpan.FromMinutes(1); }));
                services.AddDbContext<AppDbContext>(options => options.UseSqlite(connection));
                services.AddScoped<MediaStorageService>();
                services.AddScoped<ViewOnceMediaService>();
                services.AddSingleton<IConversationMessageCrypto>(new ConversationMessageCrypto(null));
                services.AddSingleton<TimeProvider>(clock);
            }).Configure(app =>
            {
                app.UseStaticFiles();
                app.UseRouting();
                app.UseRateLimiter();
                app.UseAuthentication();
                app.UseAuthorization();
                app.UseEndpoints(endpoints => endpoints.MapControllers());
            })).StartAsync();
        client = host.GetTestClient();
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();
        db.Users.AddRange(new[] { sender, recipient, other }.Select((id, i) => new User { Id = id, Name = "test-" + i, UniqueCode = "TEST-" + i }));
        await db.SaveChangesAsync();
    }

    public async Task DisposeAsync()
    {
        client.Dispose();
        await host.StopAsync();
        host.Dispose();
        await connection.DisposeAsync();
        Directory.Delete(root, recursive: true);
    }

    private HttpRequestMessage Request(HttpMethod method, string url, Guid? user = null)
    {
        var request = new HttpRequestMessage(method, url);
        if (user.HasValue) request.Headers.Add("X-Test-User", user.Value.ToString());
        return request;
    }

    private async Task<byte[]> Jpeg()
    {
        using var image = new Image<Rgb24>(2, 2);
        using var buffer = new MemoryStream();
        await image.SaveAsJpegAsync(buffer);
        return buffer.ToArray();
    }

    private async Task<HttpResponseMessage> Upload(string endpoint, string name, string mime, byte[] bytes, bool viewOnce = false)
    {
        var file = new ByteArrayContent(bytes);
        file.Headers.ContentType = new MediaTypeHeaderValue(mime);
        var multipart = new MultipartFormDataContent();
        multipart.Add(file, "file", name);
        using var request = Request(HttpMethod.Post, "/api/media/" + endpoint + (viewOnce ? "?viewOnce=true" : ""), sender);
        request.Content = multipart;
        return await client.SendAsync(request);
    }

    private async Task<(Guid MessageId, string Reference)> SeedMessage(bool group = false, string type = "image")
    {
        var response = await Upload(type == "video" ? "upload-chat-video" : "upload", type == "video" ? "test.mp4" : "test.jpg", type == "video" ? "video/mp4" : "image/jpeg", type == "video" ? Enumerable.Range(0, 128).Select(x => (byte)x).ToArray() : await Jpeg(), viewOnce: true);
        response.EnsureSuccessStatusCode();
        var reference = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("url").GetString()!;
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var conversation = new Conversation { Type = group ? ConversationType.Group : ConversationType.Private, User1Id = group ? null : sender, User2Id = group ? null : recipient };
        db.Conversations.Add(conversation);
        if (group) db.ConversationMembers.AddRange(new[] { sender, recipient, other }.Select(id => new ConversationMember { ConversationId = conversation.Id, UserId = id }));
        var msg = new ConversationMessage { ConversationId = conversation.Id, SenderId = sender, Content = reference, Type = type, IsViewOnce = true };
        db.ConversationMessages.Add(msg);
        await db.SaveChangesAsync();
        return (msg.Id, reference);
    }

    private async Task<ViewOnceOpenResult?> Open(Guid message, Guid user)
    {
        using var scope = host.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<ViewOnceMediaService>().OpenAsync(message, user);
    }

    [Fact]
    public async Task UploadMimeTypesAndAlbumImagesMatchApiAllowlist()
    {
        var jpeg = await Jpeg();
        for (var i = 0; i < 2; i++) Assert.Equal(HttpStatusCode.OK, (await Upload("upload", $"album-{i}.jpg", "image/jpeg", jpeg)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Upload("upload-chat-video", "video.mp4", "video/mp4", new byte[64])).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Upload("upload-chat-video", "video.mov", "video/quicktime", new byte[64])).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Upload("upload-audio", "voice.m4a", "audio/mp4", new byte[64])).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Upload("upload", "image.jpg", "application/octet-stream", jpeg)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Upload("upload", "image.jpg", "image/jpeg", new byte[64])).StatusCode);
    }

    [Fact]
    public async Task PrivateUploadIsNotPublicAndRecipientCannotReopenAfterClose()
    {
        var (message, reference) = await SeedMessage();
        Assert.StartsWith(MediaStorageService.PrivatePrefix, reference);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync(reference)).StatusCode);
        var filename = reference.Split('/').Last();
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/uploads/" + filename)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, "/api/media/avatar/" + filename, sender))).StatusCode);
        var opened = Assert.IsType<ViewOnceOpenResult>(await Open(message, recipient));
        Assert.False(opened.Opened);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(opened.Content)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, opened.Content!, other))).StatusCode);
        var delivered = await client.SendAsync(Request(HttpMethod.Get, opened.Content!, recipient));
        Assert.Equal(HttpStatusCode.OK, delivered.StatusCode);
        Assert.True(delivered.Headers.CacheControl!.NoStore);
        Assert.True(delivered.Headers.CacheControl.Private);
        Assert.Null(delivered.Headers.ETag);
        Assert.True((await Open(message, recipient))!.Opened);
        Assert.Null((await Open(message, recipient))!.Content);
        // A different account cannot revoke this viewing session.
        await client.SendAsync(Request(HttpMethod.Delete, opened.Content!, other));
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(Request(HttpMethod.Get, opened.Content!, recipient))).StatusCode);
        await client.SendAsync(Request(HttpMethod.Delete, opened.Content!, recipient));
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, opened.Content!, recipient))).StatusCode);
        Assert.True((await Open(message, recipient))!.Opened);
    }

    [Fact]
    public async Task GroupRecipientsHaveIndependentSessionsAndVideoSupportsRepeatedRanges()
    {
        var (message, _) = await SeedMessage(group: true, type: "video");
        var first = (await Open(message, recipient))!;
        var second = (await Open(message, other))!;
        Assert.NotEqual(first.SessionId, second.SessionId);
        for (var start = 0; start < 32; start += 16)
        {
            using var request = Request(HttpMethod.Get, first.Content!, recipient);
            request.Headers.Range = new RangeHeaderValue(start, start + 15);
            var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.PartialContent, response.StatusCode);
            Assert.Equal(Enumerable.Range(start, 16).Select(x => (byte)x), await response.Content.ReadAsByteArrayAsync());
            Assert.True(response.Headers.CacheControl!.NoStore);
        }
        await client.SendAsync(Request(HttpMethod.Delete, first.Content!, recipient));
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(Request(HttpMethod.Get, second.Content!, other))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, second.Content!, recipient))).StatusCode);
    }

    [Fact]
    public async Task DeadlineDeletionAndMembershipAreRecheckedOnEveryMediaRead()
    {
        var (message, _) = await SeedMessage(group: true);
        var first = (await Open(message, recipient))!;
        clock.Now += ViewOnceMediaService.SessionLifetime;
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, first.Content!, recipient))).StatusCode);
        Assert.True((await Open(message, recipient))!.Opened);
        var second = (await Open(message, other))!;
        using (var scope = host.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.ConversationMembers.Remove(await db.ConversationMembers.SingleAsync(m => m.UserId == other));
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, second.Content!, other))).StatusCode);
        Assert.Null(await Open(message, other));
        var own = (await Open(message, sender))!;
        using (var scope = host.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            (await db.ConversationMessages.SingleAsync(m => m.Id == message)).DeletedForEveryone = true;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.NotFound, (await client.SendAsync(Request(HttpMethod.Get, own.Content!, sender))).StatusCode);
    }

    [Fact]
    public async Task SenderMayReopenButPublicOrForeignUploadsCannotBeSentAsViewOnce()
    {
        var (message, reference) = await SeedMessage();
        Assert.False((await Open(message, sender))!.Opened);
        Assert.False((await Open(message, sender))!.Opened);
        Assert.Null(await Open(message, other));
        using var scope = host.Services.CreateScope();
        var storage = scope.ServiceProvider.GetRequiredService<MediaStorageService>();
        Assert.True(storage.ValidateMessageMedia(reference, "image", true, sender, null));
        Assert.False(storage.ValidateMessageMedia(reference, "image", true, other, null));
        Assert.False(storage.ValidateMessageMedia(reference, "image", false, sender, null));
        var response = await Upload("upload", "image.jpg", "image/jpeg", await Jpeg());
        var url = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("url").GetString()!;
        var request = new DefaultHttpContext().Request;
        request.Scheme = "http";
        request.Host = new HostString("localhost");
        Assert.True(storage.ValidateMessageMedia(url, "image", false, sender, request));
        Assert.True(storage.ValidateMessageMedia(new Uri(url).AbsolutePath, "image", false, sender, request));
        Assert.False(storage.ValidateMessageMedia("//external.invalid" + new Uri(url).AbsolutePath, "image", false, sender, request));
        Assert.False(storage.ValidateMessageMedia(url + "?redirect=external", "image", false, sender, request));
        Assert.False(storage.ValidateMessageMedia("/uploads/../image.jpg", "image", false, sender, request));
        Assert.False(storage.ValidateMessageMedia(url, "image", true, sender, request));
        Assert.False(storage.ValidateMessageMedia(url.Replace("localhost", "localhost.evil.test"), "image", false, sender, request));
        Assert.False(storage.ValidateMessageMedia(JsonSerializer.Serialize(new { urls = new[] { url, "https://external.invalid/image.jpg" } }), "album", false, sender, request));
        Assert.True(storage.ValidateMessageMedia(JsonSerializer.Serialize(new { urls = new[] { url, url } }), "album", false, sender, request));
        Assert.False(storage.ValidateMessageMedia("[]", "album", false, sender, request));
        Assert.False(storage.ValidateMessageMedia("null", "album", false, sender, request));
    }

    [Fact]
    public async Task LegacyPreflightIsReadOnlyAndQuarantineRefusesSharedPublicReferences()
    {
        var (message, reference) = await SeedMessage();
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var storage = scope.ServiceProvider.GetRequiredService<MediaStorageService>();
        var crypto = scope.ServiceProvider.GetRequiredService<IConversationMessageCrypto>();
        Assert.True(storage.TryPrivatePath(reference, out var path));
        var filename = Path.GetFileName(path);
        Directory.CreateDirectory(storage.PublicRoot);
        var publicPath = Path.Combine(storage.PublicRoot, filename);
        File.Move(path, publicPath);
        var oldUrl = "http://localhost/uploads/" + filename;
        var old = await db.ConversationMessages.SingleAsync(m => m.Id == message);
        old.Content = oldUrl;
        db.ConversationMessages.Add(new ConversationMessage { ConversationId = old.ConversationId, SenderId = sender, Type = "album", Content = JsonSerializer.Serialize(new { urls = new[] { oldUrl } }) });
        (await db.Users.SingleAsync(u => u.Id == sender)).Avatar = oldUrl;
        await db.SaveChangesAsync();
        var report = Assert.Single(await storage.PreflightLegacyViewOnceAsync(db, crypto));
        Assert.Equal(filename, report.FileName);
        Assert.Contains(report.SharedReferences, r => r.Kind == "message");
        Assert.Contains(report.SharedReferences, r => r.Kind == "avatar");
        Assert.True(File.Exists(publicPath));
        Assert.Equal(oldUrl, (await db.ConversationMessages.AsNoTracking().SingleAsync(m => m.Id == message)).Content);
        Assert.Null(await Open(message, recipient)); // Legacy view-once fails closed.
        await Assert.ThrowsAsync<InvalidOperationException>(() => storage.QuarantineLegacyViewOnceAsync(db, crypto));
        Assert.True(File.Exists(publicPath));
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(oldUrl)).StatusCode); // Ordinary sharing is preserved.
    }

    [Fact]
    public async Task LegacyQuarantineRemovesPublicOriginalAndThumbnailBeforeServing()
    {
        var (message, reference) = await SeedMessage();
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var storage = scope.ServiceProvider.GetRequiredService<MediaStorageService>();
        Assert.True(storage.TryPrivatePath(reference, out var path));
        var filename = Path.GetFileName(path);
        Directory.CreateDirectory(storage.PublicRoot);
        File.Move(path, Path.Combine(storage.PublicRoot, filename));
        var thumb = Path.GetFileNameWithoutExtension(filename) + "_thumb.jpg";
        await File.WriteAllBytesAsync(Path.Combine(storage.PublicRoot, thumb), [1, 2, 3]);
        (await db.ConversationMessages.SingleAsync(m => m.Id == message)).Content = "https://old-origin.invalid/uploads/" + filename;
        await db.SaveChangesAsync();
        await storage.QuarantineLegacyViewOnceAsync(db, scope.ServiceProvider.GetRequiredService<IConversationMessageCrypto>());
        Assert.False(File.Exists(Path.Combine(storage.PublicRoot, filename)));
        Assert.False(File.Exists(Path.Combine(storage.PublicRoot, thumb)));
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync("/uploads/" + filename)).StatusCode);
        Assert.False((await Open(message, recipient))!.Opened);
        // Restart/retry is idempotent.
        await storage.QuarantineLegacyViewOnceAsync(db, scope.ServiceProvider.GetRequiredService<IConversationMessageCrypto>());
    }
}
