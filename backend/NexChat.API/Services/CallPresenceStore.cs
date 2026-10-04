using System.Text.Json;
using StackExchange.Redis;

namespace NexChat.API.Services;

/// <summary>Atomic call attempts and renewable liveness leases. Redis is authoritative when configured.</summary>
public static class CallPresenceStore
{
    public static readonly TimeSpan RingingStaleAfter = TimeSpan.FromSeconds(65);
    public static readonly TimeSpan InCallStaleAfter = TimeSpan.FromMinutes(5);
    public sealed record PendingCall(Guid CallerId, bool VoiceOnly, bool Accepted, DateTime StartedUtc,
        Guid CallId = default, Guid RecipientId = default, DateTime LastSeenUtc = default);
    public sealed record BusyCall(Guid ConversationId, DateTime SinceUtc, Guid CallId = default);
    private static readonly Dictionary<Guid, PendingCall> MemPending = new();
    private static readonly Dictionary<Guid, BusyCall> MemBusy = new();
    private static readonly Dictionary<Guid, DateTime> Completed = new();
    private const string DoneKey = "nexchat:{calls}:completed";
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static readonly object Gate = new();
    // The common hash tag makes every transition a single Redis Cluster slot operation.
    private const string PendingKey = "nexchat:{calls}:pending";
    private const string BusyKey = "nexchat:{calls}:busy";
    private static IDatabase? _db;
    private static TimeProvider _clock = TimeProvider.System;
    private static DateTime Now => _clock.GetUtcNow().UtcDateTime;
    private static string Key(Guid id) => id.ToString();
    private static string Json<T>(T value) => JsonSerializer.Serialize(value, JsonOpts);

    public static void Configure(IConnectionMultiplexer? mux, TimeProvider? clock = null)
    {
        lock (Gate) { _db = mux?.GetDatabase(); _clock = clock ?? TimeProvider.System; MemPending.Clear(); MemBusy.Clear(); Completed.Clear(); }
    }
    public static bool UsesRedis => _db != null;
    public static PendingBag Pending { get; } = new();
    public static BusyBag Busy { get; } = new();
    public static bool IsStale(PendingCall p) => Now - (p.LastSeenUtc == default ? p.StartedUtc : p.LastSeenUtc) >
        (p.Accepted ? InCallStaleAfter : RingingStaleAfter);
    public static int Duration(PendingCall p) => p.Accepted ? Math.Max(0, (int)(Now - p.StartedUtc).TotalSeconds) : 0;

    public static bool TryStart(Guid roomId, Guid callerId, Guid recipientId, bool voiceOnly, Guid callId, out PendingCall pending)
    {
        var now = Now;
        pending = new(callerId, voiceOnly, false, now, callId, recipientId, now);
        if (callId == Guid.Empty || callerId == recipientId) return false;
        var busy = new BusyCall(roomId, now, callId);
        lock (Gate)
        {
            if (_db != null)
                return (int)_db.ScriptEvaluate("""
                    if redis.call('ZSCORE', KEYS[3], ARGV[6]) or redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 or
                       redis.call('HEXISTS', KEYS[2], ARGV[2]) == 1 or
                       redis.call('HEXISTS', KEYS[2], ARGV[3]) == 1 then return 0 end
                    redis.call('HSET', KEYS[1], ARGV[1], ARGV[4])
                    redis.call('HSET', KEYS[2], ARGV[2], ARGV[5], ARGV[3], ARGV[5])
                    return 1
                    """, [PendingKey, BusyKey, DoneKey], [Key(roomId), Key(callerId), Key(recipientId), Json(pending), Json(busy), Key(callId)]) == 1;
            foreach (var old in Completed.Where(kv => now - kv.Value > TimeSpan.FromDays(7)).Select(kv => kv.Key).ToArray()) Completed.Remove(old);
            if (Completed.ContainsKey(callId) || MemPending.ContainsKey(roomId) || MemBusy.ContainsKey(callerId) || MemBusy.ContainsKey(recipientId)) return false;
            MemPending[roomId] = pending; MemBusy[callerId] = busy; MemBusy[recipientId] = busy;
            return true;
        }
    }

    public static bool TryAccept(Guid roomId, Guid callId, Guid userId, out PendingCall? accepted)
    {
        accepted = null;
        if (!TryGetPending(roomId, out var p) || p == null || p.CallId != callId || p.RecipientId != userId || IsStale(p)) return false;
        if (p.Accepted) { accepted = p; return true; } // duplicate accept of the same attempt
        var now = Now;
        var updated = p with { Accepted = true, StartedUtc = now, LastSeenUtc = now };
        if (!TryUpdatePending(roomId, updated, p)) return false;
        accepted = updated; return true;
    }

    public static bool Heartbeat(Guid roomId, Guid callId, Guid userId)
    {
        // Retry a concurrent peer heartbeat; never recreate a consumed attempt.
        for (var i = 0; i < 3; i++)
        {
            if (!TryGetPending(roomId, out var p) || p == null || !p.Accepted || p.CallId != callId ||
                (p.CallerId != userId && p.RecipientId != userId) || IsStale(p)) return false;
            if (TryUpdatePending(roomId, p with { LastSeenUtc = Now }, p)) return true;
        }
        return false;
    }

    public static bool TryEnd(Guid roomId, Guid callId, Guid userId, out PendingCall? pending)
    {
        pending = null;
        if (!TryGetPending(roomId, out var p) || p == null || p.CallId != callId ||
            (p.CallerId != userId && p.RecipientId != userId)) return false;
        // Heartbeats can race terminal events. Re-read, but always match this attempt.
        while (p != null && p.CallId == callId)
        {
            if (TryRemoveExact(roomId, p)) { pending = p; return true; }
            if (!TryGetPending(roomId, out p)) return false;
        }
        return false;
    }

    public static bool TryGetPending(Guid roomId, out PendingCall? pending)
    {
        lock (Gate)
        {
            if (_db != null)
            {
                var value = _db.HashGet(PendingKey, Key(roomId));
                pending = value.IsNullOrEmpty ? null : JsonSerializer.Deserialize<PendingCall>((string)value!, JsonOpts);
                return pending != null;
            }
            return MemPending.TryGetValue(roomId, out pending);
        }
    }

    public static bool TryUpdatePending(Guid roomId, PendingCall updated, PendingCall expected)
    {
        if (updated.CallId != expected.CallId || updated.CallerId != expected.CallerId || updated.RecipientId != expected.RecipientId) return false;
        var busy = new BusyCall(roomId, updated.LastSeenUtc, updated.CallId);
        lock (Gate)
        {
            if (_db != null)
                return (int)_db.ScriptEvaluate("""
                    if redis.call('HGET', KEYS[1], ARGV[1]) ~= ARGV[2] then return 0 end
                    redis.call('HSET', KEYS[1], ARGV[1], ARGV[3])
                    redis.call('HSET', KEYS[2], ARGV[4], ARGV[6], ARGV[5], ARGV[6])
                    return 1
                    """, [PendingKey, BusyKey], [Key(roomId), Json(expected), Json(updated), Key(updated.CallerId), Key(updated.RecipientId), Json(busy)]) == 1;
            if (!MemPending.TryGetValue(roomId, out var current) || current != expected) return false;
            MemPending[roomId] = updated;
            MemBusy[updated.CallerId] = busy; MemBusy[updated.RecipientId] = busy;
            return true;
        }
    }

    private static bool TryRemoveExact(Guid roomId, PendingCall expected)
    {
        lock (Gate)
        {
            if (_db != null)
                return (int)_db.ScriptEvaluate("""
                    if redis.call('HGET', KEYS[1], ARGV[1]) ~= ARGV[2] then return 0 end
                    redis.call('HDEL', KEYS[1], ARGV[1])
                    redis.call('ZADD', KEYS[3], ARGV[6], ARGV[5])
                    redis.call('ZREMRANGEBYSCORE', KEYS[3], '-inf', tonumber(ARGV[6]) - 604800)
                    for i = 3, 4 do
                        local b = redis.call('HGET', KEYS[2], ARGV[i])
                        if b and cjson.decode(b).callId == ARGV[5] then redis.call('HDEL', KEYS[2], ARGV[i]) end
                    end
                    return 1
                    """, [PendingKey, BusyKey, DoneKey], [Key(roomId), Json(expected), Key(expected.CallerId), Key(expected.RecipientId), Key(expected.CallId), new DateTimeOffset(Now).ToUnixTimeSeconds()]) == 1;
            if (!MemPending.TryGetValue(roomId, out var current) || current != expected) return false;
            MemPending.Remove(roomId);
            Completed[expected.CallId] = Now;
            foreach (var user in new[] { expected.CallerId, expected.RecipientId })
                if (MemBusy.TryGetValue(user, out var b) && b.CallId == expected.CallId) MemBusy.Remove(user);
            return true;
        }
    }

    public static void PurgeStale(Action<Guid, PendingCall>? onPurged = null)
    {
        foreach (var (roomId, p) in SnapshotPending())
            if (IsStale(p) && TryRemoveExact(roomId, p)) onPurged?.Invoke(roomId, p);
    }
    public static bool TryRemovePending(Guid roomId, out PendingCall? pending)
    {
        pending = null;
        while (TryGetPending(roomId, out var p) && p != null)
            if (TryRemoveExact(roomId, p)) { pending = p; return true; }
        return false;
    }
    public static void ClearRoom(Guid roomId) => TryRemovePending(roomId, out _);
    public static bool TryGetBusy(Guid userId, out BusyCall? busy)
    {
        lock (Gate)
        {
            if (_db != null)
            {
                var value = _db.HashGet(BusyKey, Key(userId));
                busy = value.IsNullOrEmpty ? null : JsonSerializer.Deserialize<BusyCall>((string)value!, JsonOpts);
                return busy != null;
            }
            return MemBusy.TryGetValue(userId, out busy);
        }
    }
    public static bool IsBusy(Guid userId) => TryGetBusy(userId, out _);
    public static bool IsBusyElsewhere(Guid userId, Guid roomId) => TryGetBusy(userId, out var b) && b!.ConversationId != roomId;
    public static bool AnyBusyForRoom(Guid roomId) => SnapshotBusy().Any(kv => kv.Value.ConversationId == roomId);
    public static void ClearBusyForRoom(Guid roomId, Guid a, Guid b)
    {
        // A busy reservation is owned by its pending attempt. Never release it independently.
        if (!HasPending(roomId)) { RemoveOrphanBusy(a, roomId); RemoveOrphanBusy(b, roomId); }
    }
    private static void RemoveOrphanBusy(Guid userId, Guid roomId)
    {
        lock (Gate)
        {
            if (_db != null)
            {
                _db.ScriptEvaluate("""
                    local b = redis.call('HGET', KEYS[2], ARGV[1])
                    if b and cjson.decode(b).conversationId == ARGV[2] and redis.call('HEXISTS', KEYS[1], ARGV[2]) == 0 then
                        return redis.call('HDEL', KEYS[2], ARGV[1]) end
                    return 0
                    """, [PendingKey, BusyKey], [Key(userId), Key(roomId)]);
            }
            else if (!MemPending.ContainsKey(roomId) && MemBusy.TryGetValue(userId, out var b) && b.ConversationId == roomId) MemBusy.Remove(userId);
        }
    }
    public static bool TryRemoveBusy(Guid userId)
    {
        if (!TryGetBusy(userId, out var b) || b == null) return false;
        RemoveOrphanBusy(userId, b.ConversationId); return true;
    }
    public static KeyValuePair<Guid, PendingCall>[] SnapshotPending()
    {
        lock (Gate) return _db == null ? MemPending.ToArray() : _db.HashGetAll(PendingKey)
            .Select(e => new KeyValuePair<Guid, PendingCall>(Guid.Parse((string)e.Name!), JsonSerializer.Deserialize<PendingCall>((string)e.Value!, JsonOpts)!)).ToArray();
    }
    public static KeyValuePair<Guid, BusyCall>[] SnapshotBusy()
    {
        lock (Gate) return _db == null ? MemBusy.ToArray() : _db.HashGetAll(BusyKey)
            .Select(e => new KeyValuePair<Guid, BusyCall>(Guid.Parse((string)e.Name!), JsonSerializer.Deserialize<BusyCall>((string)e.Value!, JsonOpts)!)).ToArray();
    }
    public static bool HasPending(Guid roomId) => TryGetPending(roomId, out _);
    public sealed class PendingBag
    {
        public bool TryGetValue(Guid roomId, out PendingCall pending) { var ok = TryGetPending(roomId, out var p); pending = p!; return ok; }
        public bool TryRemove(Guid roomId, out PendingCall pending) { var ok = TryRemovePending(roomId, out var p); pending = p!; return ok; }
        public bool TryUpdate(Guid roomId, PendingCall updated, PendingCall expected) => TryUpdatePending(roomId, updated, expected);
        public bool ContainsKey(Guid roomId) => HasPending(roomId);
        public KeyValuePair<Guid, PendingCall>[] ToArray() => SnapshotPending();
    }
    public sealed class BusyBag
    {
        public bool TryGetValue(Guid userId, out BusyCall busy) { var ok = TryGetBusy(userId, out var b); busy = b!; return ok; }
        public bool TryRemove(Guid userId, out BusyCall busy) { var had = TryGetBusy(userId, out var b); busy = b!; TryRemoveBusy(userId); return had; }
        public bool Any(Func<KeyValuePair<Guid, BusyCall>, bool> pred) => SnapshotBusy().Any(pred);
        public KeyValuePair<Guid, BusyCall>[] ToArray() => SnapshotBusy();
    }
}
