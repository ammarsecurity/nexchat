using NexChat.API.Services;
using StackExchange.Redis;

var redis = args.Contains("--redis") ? ConnectionMultiplexer.Connect("127.0.0.1:16379,defaultDatabase=15,abortConnect=true") : null;
var clock = new ManualClock();
CallPresenceStore.Configure(redis, clock);
int passed = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception(name); }
void Test(string name, Action test) { test(); passed++; Console.WriteLine("PASS " + name); }
(Guid Room, Guid A, Guid B, Guid Call) Create()
{
    var ids = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
    Check(CallPresenceStore.TryStart(ids.Item1, ids.Item2, ids.Item3, true, ids.Item4, out _), "start");
    return ids;
}
Test("cancel wins before stale acceptance CAS; no resurrection", () => {
    var x = Create(); CallPresenceStore.TryGetPending(x.Room, out var pending);
    Check(CallPresenceStore.TryEnd(x.Room, x.Call, x.A, out _), "cancel");
    Check(!CallPresenceStore.TryUpdatePending(x.Room, pending! with { Accepted = true }, pending!), "stale CAS succeeded");
    Check(!CallPresenceStore.HasPending(x.Room) && !CallPresenceStore.IsBusy(x.A) && !CallPresenceStore.IsBusy(x.B), "resurrected");
});
Test("both users and room reserved atomically under concurrent requests", () => {
    var sharedUser = Guid.NewGuid(); int wins = 0; Guid room = default; Guid attempt = default;
    Parallel.For(0, 64, index => { var r = Guid.NewGuid(); var id = Guid.NewGuid();
        if (CallPresenceStore.TryStart(r, sharedUser, Guid.NewGuid(), false, id, out _)) { Interlocked.Increment(ref wins); room = r; attempt = id; } });
    Check(wins == 1, $"reservation winners={wins}"); CallPresenceStore.TryEnd(room, attempt, sharedUser, out _);
});
Test("REST/hub simultaneous decline consumes only one terminal snapshot", () => {
    var x = Create(); int wins = 0;
    Parallel.For(0, 64, i => { if (CallPresenceStore.TryEnd(x.Room, x.Call, i % 2 == 0 ? x.A : x.B, out var p)) {
        Check(p!.CallerId == x.A && p.RecipientId == x.B && p.VoiceOnly, "direction/type changed"); Interlocked.Increment(ref wins); } });
    Check(wins == 1, $"terminal winners={wins}");
});
Test("callee accept is idempotent, caller cannot accept own attempt", () => {
    var x = Create(); Check(!CallPresenceStore.TryAccept(x.Room, x.Call, x.A, out _), "caller accepted");
    Check(CallPresenceStore.TryAccept(x.Room, x.Call, x.B, out var first), "accept"); clock.Advance(TimeSpan.FromSeconds(1));
    Check(CallPresenceStore.TryAccept(x.Room, x.Call, x.B, out var second) && first!.StartedUtc == second!.StartedUtc, "duplicate reset duration");
    CallPresenceStore.TryEnd(x.Room, x.Call, x.B, out _);
});
Test("healthy call survives more than five minutes and retains accepted time", () => {
    var x = Create(); CallPresenceStore.TryAccept(x.Room, x.Call, x.B, out var accepted);
    for (var i = 0; i < 40; i++) { clock.Advance(TimeSpan.FromSeconds(30));
        Check(CallPresenceStore.Heartbeat(x.Room, x.Call, i % 2 == 0 ? x.A : x.B), "heartbeat"); CallPresenceStore.PurgeStale(); }
    Check(CallPresenceStore.TryGetPending(x.Room, out var p) && p!.StartedUtc == accepted!.StartedUtc && CallPresenceStore.Duration(p) == 1200, "healthy expired/duration reset");
    Check(CallPresenceStore.IsBusy(x.A) && CallPresenceStore.IsBusy(x.B), "lost reservation"); CallPresenceStore.TryEnd(x.Room, x.Call, x.B, out _);
});
Test("orphan expires by missing liveness exactly once", () => {
    var x = Create(); CallPresenceStore.TryAccept(x.Room, x.Call, x.B, out _); clock.Advance(TimeSpan.FromMinutes(6)); int purged = 0;
    CallPresenceStore.PurgeStale((r, p) => { if (r == x.Room) purged++; }); CallPresenceStore.PurgeStale((r, p) => { if (r == x.Room) purged++; });
    Check(purged == 1 && !CallPresenceStore.IsBusy(x.A) && !CallPresenceStore.IsBusy(x.B), "orphan cleanup");
});
Test("late old attempt cannot end or heartbeat replacement in same room", () => {
    var x = Create(); CallPresenceStore.TryEnd(x.Room, x.Call, x.A, out _); var next = Guid.NewGuid();
    Check(CallPresenceStore.TryStart(x.Room, x.A, x.B, false, next, out _), "replacement");
    Check(!CallPresenceStore.TryEnd(x.Room, x.Call, x.B, out _) && !CallPresenceStore.Heartbeat(x.Room, x.Call, x.A), "old event affected replacement");
    Check(CallPresenceStore.TryGetPending(x.Room, out var p) && p!.CallId == next, "replacement missing"); CallPresenceStore.TryEnd(x.Room, next, x.B, out _);
});
Test("completed request replay cannot recreate call", () => {
    var x = Create(); CallPresenceStore.TryEnd(x.Room, x.Call, x.A, out _);
    Check(!CallPresenceStore.TryStart(x.Room, x.A, x.B, false, x.Call, out _), "replay recreated completed call");
});
Test("unrelated user cannot heartbeat or terminate attempt", () => {
    var x = Create(); var stranger = Guid.NewGuid(); CallPresenceStore.TryAccept(x.Room, x.Call, x.B, out _);
    Check(!CallPresenceStore.TryEnd(x.Room, x.Call, stranger, out _) && !CallPresenceStore.Heartbeat(x.Room, x.Call, stranger), "unauthorized transition");
    CallPresenceStore.TryEnd(x.Room, x.Call, x.A, out _);
});
HubContractTests.Run(); passed++;
passed += await CallApiTests.Run();
if (redis != null) Test("configured Redis outage cannot fall back to stale memory", () => {
    var x = Create(); redis.Dispose(); var threw = false;
    try { CallPresenceStore.TryEnd(x.Room, x.Call, x.A, out _); } catch (ObjectDisposedException) { threw = true; }
    Check(threw, "failed open");
});
Console.WriteLine($"{passed} actual call regressions passed ({(redis == null ? "memory" : "Redis")}).");
sealed class ManualClock : TimeProvider
{
    private DateTimeOffset now = new(2026, 10, 4, 0, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset GetUtcNow() => now;
    public void Advance(TimeSpan duration) => now += duration;
}
