using System.Collections.Concurrent;
using System.Text.Json;
using StackExchange.Redis;

namespace NexChat.API.Services;

/// <summary>
/// حالة busy/pending للمكالمات. الذاكرة كافية لـ API واحد؛
/// Redis اختياري فقط عند تشغيل عدة instances.
/// </summary>
public static class CallPresenceStore
{
    public static readonly TimeSpan RingingStaleAfter = TimeSpan.FromSeconds(65);
    public static readonly TimeSpan InCallStaleAfter = TimeSpan.FromMinutes(45);

    public sealed record PendingCall(Guid CallerId, bool VoiceOnly, bool Accepted, DateTime StartedUtc);
    public sealed record BusyCall(Guid ConversationId, DateTime SinceUtc);

    private static readonly ConcurrentDictionary<Guid, PendingCall> MemPending = new();
    private static readonly ConcurrentDictionary<Guid, BusyCall> MemBusy = new();
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static IDatabase? _db;
    private static readonly object Gate = new();

    /// <summary>يُستدعى من Program عند الإقلاع. null = ذاكرة فقط.</summary>
    public static void Configure(IConnectionMultiplexer? mux)
    {
        lock (Gate)
        {
            _db = mux?.GetDatabase();
        }
    }

    public static bool UsesRedis
    {
        get { lock (Gate) return _db != null; }
    }

    // --- Compatibility surface used by hubs (dictionary-like) ---
    public static PendingBag Pending { get; } = new();
    public static BusyBag Busy { get; } = new();

    public static bool IsBusy(Guid userId) => TryGetBusy(userId, out _);

    public static bool IsBusyElsewhere(Guid userId, Guid roomId) =>
        TryGetBusy(userId, out var b) && b!.ConversationId != roomId;

    public static void ClearBusyForRoom(Guid roomId, Guid a, Guid b)
    {
        if (TryGetBusy(a, out var ca) && ca!.ConversationId == roomId)
            TryRemoveBusy(a);
        if (TryGetBusy(b, out var cb) && cb!.ConversationId == roomId)
            TryRemoveBusy(b);
    }

    public static void ClearRoom(Guid roomId)
    {
        TryRemovePending(roomId, out _);
        foreach (var kv in SnapshotBusy())
        {
            if (kv.Value.ConversationId == roomId)
                TryRemoveBusy(kv.Key);
        }
    }

    public static void PurgeStale(Action<Guid, PendingCall>? onPurged = null)
    {
        var now = DateTime.UtcNow;
        foreach (var kv in SnapshotPending())
        {
            var limit = kv.Value.Accepted ? InCallStaleAfter : RingingStaleAfter;
            if (now - kv.Value.StartedUtc <= limit) continue;
            var snapshot = kv.Value;
            ClearRoom(kv.Key);
            onPurged?.Invoke(kv.Key, snapshot);
        }

        foreach (var kv in SnapshotBusy())
        {
            var hasPending = TryGetPending(kv.Value.ConversationId, out var p);
            var limit = hasPending && p!.Accepted ? InCallStaleAfter : RingingStaleAfter;
            if (now - kv.Value.SinceUtc <= limit) continue;
            TryRemoveBusy(kv.Key);
        }
    }

    public static bool TryGetPending(Guid roomId, out PendingCall? pending)
    {
        if (TryRedisGetPending(roomId, out pending))
        {
            if (pending != null) MemPending[roomId] = pending;
            else MemPending.TryRemove(roomId, out _);
            return pending != null;
        }
        return MemPending.TryGetValue(roomId, out pending!);
    }

    public static void SetPending(Guid roomId, PendingCall pending)
    {
        MemPending[roomId] = pending;
        var ttl = pending.Accepted ? InCallStaleAfter : RingingStaleAfter;
        TryRedisSet($"nexchat:call:pending:{roomId:N}", pending, ttl);
    }

    public static bool TryRemovePending(Guid roomId, out PendingCall? pending)
    {
        MemPending.TryRemove(roomId, out var mem);
        TryRedisGetPending(roomId, out var redis);
        pending = redis ?? mem;
        TryRedisDel($"nexchat:call:pending:{roomId:N}");
        return pending != null;
    }

    public static bool TryUpdatePending(Guid roomId, PendingCall updated, PendingCall expected)
    {
        // Optimistic: compare current then set.
        if (!TryGetPending(roomId, out var cur) || cur is null) return false;
        if (cur.CallerId != expected.CallerId || cur.Accepted != expected.Accepted ||
            cur.VoiceOnly != expected.VoiceOnly || cur.StartedUtc != expected.StartedUtc)
            return false;
        SetPending(roomId, updated);
        return true;
    }

    public static bool TryGetBusy(Guid userId, out BusyCall? busy)
    {
        if (TryRedisGetBusy(userId, out busy))
        {
            if (busy != null) MemBusy[userId] = busy;
            else MemBusy.TryRemove(userId, out _);
            return busy != null;
        }
        return MemBusy.TryGetValue(userId, out busy!);
    }

    public static void SetBusy(Guid userId, BusyCall busy)
    {
        MemBusy[userId] = busy;
        var ttl = InCallStaleAfter;
        if (TryGetPending(busy.ConversationId, out var p) && p is { Accepted: false })
            ttl = RingingStaleAfter;
        TryRedisSet($"nexchat:call:busy:{userId:N}", busy, ttl);
    }

    public static bool TryRemoveBusy(Guid userId)
    {
        MemBusy.TryRemove(userId, out _);
        TryRedisDel($"nexchat:call:busy:{userId:N}");
        return true;
    }

    public static bool AnyBusyForRoom(Guid roomId) =>
        SnapshotBusy().Any(kv => kv.Value.ConversationId == roomId);

    public static KeyValuePair<Guid, PendingCall>[] SnapshotPending()
    {
        if (_db != null)
        {
            try
            {
                var server = _db.Multiplexer.GetServers().FirstOrDefault(s => s.IsConnected);
                if (server != null)
                {
                    var list = new List<KeyValuePair<Guid, PendingCall>>();
                    foreach (var key in server.Keys(pattern: "nexchat:call:pending:*"))
                    {
                        var idPart = key.ToString().Split(':').LastOrDefault();
                        if (!Guid.TryParseExact(idPart, "N", out var roomId)) continue;
                        if (TryRedisGetPending(roomId, out var p) && p != null)
                            list.Add(new(roomId, p));
                    }
                    if (list.Count > 0) return list.ToArray();
                }
            }
            catch { /* fall through */ }
        }
        return MemPending.ToArray();
    }

    public static KeyValuePair<Guid, BusyCall>[] SnapshotBusy()
    {
        if (_db != null)
        {
            try
            {
                var server = _db.Multiplexer.GetServers().FirstOrDefault(s => s.IsConnected);
                if (server != null)
                {
                    var list = new List<KeyValuePair<Guid, BusyCall>>();
                    foreach (var key in server.Keys(pattern: "nexchat:call:busy:*"))
                    {
                        var idPart = key.ToString().Split(':').LastOrDefault();
                        if (!Guid.TryParseExact(idPart, "N", out var userId)) continue;
                        if (TryRedisGetBusy(userId, out var b) && b != null)
                            list.Add(new(userId, b));
                    }
                    if (list.Count > 0) return list.ToArray();
                }
            }
            catch { /* fall through */ }
        }
        return MemBusy.ToArray();
    }

    public static bool HasPending(Guid roomId) => TryGetPending(roomId, out _);

    // --- Compatibility wrappers so hubs can keep dictionary-style calls ---
    public sealed class PendingBag
    {
        public PendingCall this[Guid roomId]
        {
            set => SetPending(roomId, value);
        }

        public bool TryGetValue(Guid roomId, out PendingCall pending)
        {
            var ok = TryGetPending(roomId, out var p);
            pending = p!;
            return ok;
        }

        public bool TryRemove(Guid roomId, out PendingCall pending)
        {
            var ok = TryRemovePending(roomId, out var p);
            pending = p!;
            return ok;
        }

        public bool TryUpdate(Guid roomId, PendingCall updated, PendingCall expected) =>
            TryUpdatePending(roomId, updated, expected);

        public bool ContainsKey(Guid roomId) => HasPending(roomId);

        public KeyValuePair<Guid, PendingCall>[] ToArray() => SnapshotPending();
    }

    public sealed class BusyBag
    {
        public BusyCall this[Guid userId]
        {
            set => SetBusy(userId, value);
        }

        public bool TryGetValue(Guid userId, out BusyCall busy)
        {
            var ok = TryGetBusy(userId, out var b);
            busy = b!;
            return ok;
        }

        public bool TryRemove(Guid userId, out BusyCall busy)
        {
            var had = TryGetBusy(userId, out var b);
            busy = b!;
            TryRemoveBusy(userId);
            return had;
        }

        public bool Any(Func<KeyValuePair<Guid, BusyCall>, bool> pred) =>
            SnapshotBusy().Any(pred);

        public KeyValuePair<Guid, BusyCall>[] ToArray() => SnapshotBusy();
    }

    private static bool TryRedisGetPending(Guid roomId, out PendingCall? pending)
    {
        pending = null;
        var db = _db;
        if (db == null) return false;
        try
        {
            var val = db.StringGet($"nexchat:call:pending:{roomId:N}");
            if (val.IsNullOrEmpty) { pending = null; return true; }
            pending = JsonSerializer.Deserialize<PendingCall>((string)val!, JsonOpts);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryRedisGetBusy(Guid userId, out BusyCall? busy)
    {
        busy = null;
        var db = _db;
        if (db == null) return false;
        try
        {
            var val = db.StringGet($"nexchat:call:busy:{userId:N}");
            if (val.IsNullOrEmpty) { busy = null; return true; }
            busy = JsonSerializer.Deserialize<BusyCall>((string)val!, JsonOpts);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void TryRedisSet<T>(string key, T value, TimeSpan ttl)
    {
        var db = _db;
        if (db == null) return;
        try
        {
            var json = JsonSerializer.Serialize(value, JsonOpts);
            db.StringSet(key, json, ttl);
        }
        catch { /* memory remains source for this process */ }
    }

    private static void TryRedisDel(string key)
    {
        var db = _db;
        if (db == null) return;
        try { db.KeyDelete(key); } catch { }
    }
}
