using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using NexChat.API.Controllers;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NexChat.API.Hubs;
using NexChat.API.Services;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

static class CallApiTests
{
    public static async Task<int> Run()
    {
        var services = new ServiceCollection().AddLogging().AddOptions();
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        connection.CreateCollation("utf8mb4_bin", string.CompareOrdinal);
        services.AddDbContext<AppDbContext>(o => o.UseSqlite(connection));
        services.AddSingleton<IConversationMessageCrypto>(new ConversationMessageCrypto(null));
        services.AddScoped<NotificationOutboxService>();
        services.AddSingleton<IHubContext<ConversationHub>>(new NullHubContext<ConversationHub>());
        services.AddSingleton<IHubContext<ChatHub>>(new NullHubContext<ChatHub>());
        await using var provider = services.BuildServiceProvider();
        await using (var schema = provider.CreateAsyncScope()) await schema.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreatedAsync();
        int count = 0;
        foreach (var httpFirst in new[] { false, true })
        {
            await using var scope = provider.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var a = Guid.NewGuid(); var b = Guid.NewGuid(); var room = Guid.NewGuid(); var attempt = Guid.NewGuid();
            db.Users.AddRange(new User { Id = a, Name = a.ToString(), UniqueCode = a.ToString() }, new User { Id = b, Name = b.ToString(), UniqueCode = b.ToString() });
            db.Conversations.Add(new Conversation { Id = room, User1Id = a, User2Id = b }); await db.SaveChangesAsync();
            CallPresenceStore.TryStart(room, a, b, true, attempt, out _);
            var hub = new ConversationHub(db, scope.ServiceProvider.GetRequiredService<NotificationOutboxService>(), null!,
                scope.ServiceProvider.GetRequiredService<ILogger<ConversationHub>>(), null!,
                scope.ServiceProvider.GetRequiredService<IConversationMessageCrypto>(), null!, null!, null!, null!, null!)
                { Context = new UserContext(b), Clients = new NullClients() };
            async Task Http() => _ = await ConversationHub.DeclineFromHttpAsync(provider.GetRequiredService<IServiceScopeFactory>(), b, room, false, "declined", attempt);
            async Task SignalR() => await hub.DeclineVideoCallV2(room.ToString(), false, "declined", attempt.ToString());
            if (httpFirst) { await Http(); await SignalR(); } else { await SignalR(); await Http(); }
            await Http(); await SignalR(); // retries must remain idempotent
            var rows = await db.ConversationMessages.Where(m => m.ConversationId == room).ToListAsync();
            Assert(rows.Count == 1 && rows[0].Id == attempt && rows[0].SenderId == a, "REST/SignalR duplicate or reversed history");
            using var content = JsonDocument.Parse(rows[0].Content!);
            Assert(content.RootElement.GetProperty("voiceOnly").GetBoolean() && content.RootElement.GetProperty("status").GetString() == "declined", "type/outcome changed");
            Console.WriteLine($"PASS real REST + SignalR decline ({(httpFirst ? "REST" : "hub")} first), repeated delivery, one original-caller voice row"); count++;
        }
        foreach (var ending in new[] { false, true })
        {
            await using var scope = provider.CreateAsyncScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var a = Guid.NewGuid(); var b = Guid.NewGuid(); var room = Guid.NewGuid(); var attempt = Guid.NewGuid();
            db.Users.AddRange(new User { Id = a, Name = a.ToString(), UniqueCode = a.ToString() }, new User { Id = b, Name = b.ToString(), UniqueCode = b.ToString() });
            db.ChatSessions.Add(new ChatSession { Id = room, User1Id = a, User2Id = b }); await db.SaveChangesAsync();
            CallPresenceStore.TryStart(room, a, b, true, attempt, out _);
            if (ending) CallPresenceStore.TryAccept(room, attempt, b, out _);
            var hub = new ChatHub(db, scope.ServiceProvider.GetRequiredService<NotificationOutboxService>(), null!)
                { Context = new UserContext(b), Clients = new NullClients() };
            if (ending) await hub.EndVideoCallV2(room.ToString(), 12, attempt.ToString());
            else await hub.DeclineVideoCallV2(room.ToString(), "declined", attempt.ToString());
            var rows = await db.Messages.Where(m => m.SessionId == room).ToListAsync();
            Assert(rows.Count == 1 && rows[0].SenderId == a && rows[0].Id == attempt, "callee history omitted");
            Console.WriteLine($"PASS random callee {(ending ? "hangup" : "decline")} writes original-caller history"); count++;
        }
        await using (var scope = provider.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var a = Guid.NewGuid(); var b = Guid.NewGuid(); var room = Guid.NewGuid(); var attempt = Guid.NewGuid();
            db.Users.AddRange(new User { Id = a, Name = a.ToString(), UniqueCode = a.ToString() }, new User { Id = b, Name = b.ToString(), UniqueCode = b.ToString() });
            db.ChatSessions.Add(new ChatSession { Id = room, User1Id = a, User2Id = b }); await db.SaveChangesAsync();
            CallPresenceStore.TryStart(room, a, b, true, attempt, out _);
            var controller = new CallsController(db, scope.ServiceProvider.GetRequiredService<IConversationMessageCrypto>()) {
                ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext { User = new UserContext(b).User } } };
            var dto = new CallsController.CallSignalingDeclineDto(CallId: attempt, SessionId: room, Outcome: "declined");
            await controller.SignalingDecline(dto, provider.GetRequiredService<IServiceScopeFactory>());
            await controller.SignalingDecline(dto, provider.GetRequiredService<IServiceScopeFactory>());
            var rows = await db.Messages.Where(m => m.SessionId == room).ToListAsync();
            Assert(rows.Count == 1 && rows[0].SenderId == a && rows[0].Id == attempt, "random native REST failed/idempotency");
            Console.WriteLine("PASS native random-session REST decline and replay produce one original-caller row"); count++;
        }
        await using (var scope = provider.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var a = Guid.NewGuid(); var b = Guid.NewGuid(); var room = Guid.NewGuid(); var attempt = Guid.NewGuid();
            db.Users.AddRange(new User { Id = a, Name = a.ToString(), UniqueCode = a.ToString() }, new User { Id = b, Name = b.ToString(), UniqueCode = b.ToString() });
            db.ChatSessions.Add(new ChatSession { Id = room, User1Id = a, User2Id = b }); await db.SaveChangesAsync();
            CallPresenceStore.TryStart(room, a, b, true, attempt, out _);
            var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> {
                ["LiveKit:ApiKey"] = "local-test", ["LiveKit:ApiSecret"] = "local-regression-test-secret-not-production", ["LiveKit:Url"] = "wss://localhost" }).Build();
            var controller = new LiveKitController(db, config, null!, null!) {
                ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext { User = new UserContext(a).User } } };
            Assert(await controller.GetToken(new LiveKitTokenRequest(room.ToString(), attempt)) is ConflictObjectResult, "ringing received media token");
            CallPresenceStore.TryAccept(room, attempt, b, out _);
            var tokenResult = await controller.GetToken(new LiveKitTokenRequest(room.ToString(), attempt)) as OkObjectResult;
            Assert(tokenResult != null, "accepted call token denied");
            using var response = JsonDocument.Parse(JsonSerializer.Serialize(tokenResult!.Value));
            var jwt = response.RootElement.GetProperty("token").GetString()!;
            var segment = jwt.Split('.')[1].Replace('-', '+').Replace('_', '/');
            using var payload = JsonDocument.Parse(Convert.FromBase64String(segment.PadRight((segment.Length + 3) / 4 * 4, '=')));
            Assert(payload.RootElement.GetProperty("video").GetProperty("room").GetString() == $"{room:N}:{attempt:N}", "media room missing attempt isolation");
            CallPresenceStore.TryEnd(room, attempt, a, out _);
            var next = Guid.NewGuid(); CallPresenceStore.TryStart(room, a, b, true, next, out _); CallPresenceStore.TryAccept(room, next, b, out _);
            Assert(await controller.GetToken(new LiveKitTokenRequest(room.ToString(), attempt)) is ConflictObjectResult, "old token request joined replacement");
            CallPresenceStore.TryEnd(room, next, a, out _);
            Console.WriteLine("PASS actual LiveKit token controller rejects ringing/stale attempts and isolates accepted room JWT"); count++;
        }
        return count;
    }
    private static void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
}
sealed class UserContext(Guid user) : HubCallerContext
{
    public override string ConnectionId => "test-" + user;
    public override string? UserIdentifier => user.ToString();
    public override ClaimsPrincipal User => new(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, user.ToString())]));
    public override IDictionary<object, object?> Items { get; } = new Dictionary<object, object?>();
    public override IFeatureCollection Features { get; } = new FeatureCollection();
    public override CancellationToken ConnectionAborted => CancellationToken.None;
    public override void Abort() { }
}
sealed class NullProxy : IClientProxy
{
    public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default) => Task.CompletedTask;
}
sealed class NullClients : IHubCallerClients, IHubClients
{
    private readonly IClientProxy proxy = new NullProxy();
    public IClientProxy All => proxy; public IClientProxy Caller => proxy; public IClientProxy Others => proxy;
    public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => proxy;
    public IClientProxy Client(string connectionId) => proxy;
    public IClientProxy Clients(IReadOnlyList<string> connectionIds) => proxy;
    public IClientProxy Group(string groupName) => proxy;
    public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => proxy;
    public IClientProxy Groups(IReadOnlyList<string> groupNames) => proxy;
    public IClientProxy OthersInGroup(string groupName) => proxy;
    public IClientProxy User(string userId) => proxy;
    public IClientProxy Users(IReadOnlyList<string> userIds) => proxy;
}
sealed class NullHubContext<T> : IHubContext<T> where T : Hub
{
    public IHubClients Clients { get; } = new NullClients();
    public IGroupManager Groups => null!;
}
