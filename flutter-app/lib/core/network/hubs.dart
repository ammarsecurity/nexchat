import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import '../config/env.dart';
import '../i18n/i18n.dart';
import '../storage/prefs.dart';
import 'network_status.dart';

typedef HubHandler = void Function(List<Object?> args);

/// Mirrors mobile-app/src/services/signalr.js: one shared connection per hub.
class Hub {
  Hub(this.path);

  final String path;
  HubConnection? _conn;
  final Map<String, List<HubHandler>> _handlers = {};
  final _reconnected = StreamController<void>.broadcast();

  Stream<void> get onReconnected => _reconnected.stream;

  HubConnection _build() {
    final token = Prefs.instance.token;
    _connectionToken = token;
    final conn = HubConnectionBuilder()
        .withUrl(
          '${Env.apiHost}$path',
          options: HttpConnectionOptions(accessTokenFactory: () async => token ?? ''),
        )
        .withAutomaticReconnect()
        .build();
    conn.onreconnected(({connectionId}) {
      if (!identical(_conn, conn) || token != Prefs.instance.token) return;
      _restartAttempt = 0;
      _reconnected.add(null);
    });
    conn.onclose(({error}) {
      if (identical(_conn, conn) && token == Prefs.instance.token) _scheduleRestart();
    });
    _bound.clear();
    for (final name in _handlers.keys) {
      _bind(conn, name);
    }
    return conn;
  }

  final Set<String> _bound = {};

  void _bind(HubConnection conn, String name) {
    if (!_bound.add(name)) return;
    conn.on(name, (args) {
      if (!identical(_conn, conn) || _connectionToken != Prefs.instance.token) return;
      for (final h in List.of(_handlers[name] ?? const <HubHandler>[])) {
        h(args ?? const []);
      }
    });
  }

  HubConnectionState get state => _conn?.state ?? HubConnectionState.Disconnected;

  /// True between start() and stop(): the connection should be kept alive.
  bool _wanted = false;
  Timer? _restartTimer;
  int _restartAttempt = 0;
  int _generation = 0;
  Future<void>? _starting;
  Future<void>? _reconnecting;
  String? _connectionToken;

  Future<void> _disposeConn() async {
    _restartTimer?.cancel();
    final c = _conn;
    _conn = null;
    _bound.clear();
    if (c == null) return;
    try {
      await c.stop();
    } catch (_) {}
  }

  /// Tear down any half-dead socket and open a fresh one (needed after network loss).
  Future<void> forceReconnect() => _reconnecting ??= _forceReconnect().whenComplete(() => _reconnecting = null);

  Future<void> _forceReconnect() async {
    if (!_wanted) return;
    _restartAttempt = 0;
    await _disposeConn();
    if (!NetworkStatus.online.value || (Prefs.instance.token ?? '').isEmpty) return;
    try {
      await start();
      _reconnected.add(null);
    } catch (_) {
      _scheduleRestart();
    }
  }

  /// withAutomaticReconnect gives up after ~40 s; keep retrying with backoff while the hub is wanted.
  void _scheduleRestart() {
    if (!_wanted || !NetworkStatus.online.value || (Prefs.instance.token ?? '').isEmpty) return;
    _restartTimer?.cancel();
    final delay = Duration(seconds: [2, 5, 10, 20, 30][_restartAttempt.clamp(0, 4)]);
    _restartAttempt++;
    _restartTimer = Timer(delay, () async {
      if (!_wanted || !NetworkStatus.online.value) return;
      try {
        await forceReconnect();
      } catch (_) {
        _scheduleRestart();
      }
    });
  }

  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    _wanted = true;
    if (!NetworkStatus.online.value || (Prefs.instance.token ?? '').isEmpty) return;
    final generation = _generation;
    if (_conn != null && _connectionToken != Prefs.instance.token) await _disposeConn();
    if (generation != _generation || !_wanted) return;
    _conn ??= _build();
    final connection = _conn!;
    if (connection.state == HubConnectionState.Connected) {
      _restartAttempt = 0;
      _restartTimer?.cancel();
      return;
    }
    // Let an in-flight start or automatic reconnect finish instead of tearing it down.
    if (connection.state != HubConnectionState.Disconnected) return;
    try {
      await connection.start();
      if (generation != _generation || !_wanted) { await connection.stop(); return; }
      _restartAttempt = 0;
      _restartTimer?.cancel();
    } catch (_) {
      _scheduleRestart();
      rethrow;
    }
  }

  /// App resumed / network back: reconnect now instead of waiting for the backoff timer.
  Future<void> resume() async {
    if (!_wanted || !NetworkStatus.online.value) return;
    if (state == HubConnectionState.Connected) {
      // Still notify listeners so chat can re-join / flush outbox.
      _reconnected.add(null);
      return;
    }
    await forceReconnect();
  }

  Future<void> ensureConnected({Duration timeout = const Duration(seconds: 15)}) async {
    if (!NetworkStatus.online.value) throw TimeoutException(I18n.t('noConnection.title'));
    _wanted = true;
    if ((Prefs.instance.token ?? '').isEmpty) throw TimeoutException(I18n.t('noConnection.title'));

    if (_conn == null || state == HubConnectionState.Disconnected) {
      await start();
      if (state == HubConnectionState.Connected) return;
    }
    if (state == HubConnectionState.Connected) return;

    final started = DateTime.now();
    while (state != HubConnectionState.Connected) {
      if (DateTime.now().difference(started) > timeout) {
        await forceReconnect();
        if (state == HubConnectionState.Connected) return;
        throw TimeoutException('انتهت مهلة الاتصال');
      }
      if (state == HubConnectionState.Disconnected) {
        try {
          await start();
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> stop() async {
    _generation++;
    _wanted = false;
    await _disposeConn();
  }

  /// Drop the socket but keep the hub wanted so resume() can bring it back.
  Future<void> pause() async {
    await _disposeConn();
  }

  /// Registers a listener; returns a disposer. Listeners survive reconnects and restarts.
  void Function() on(String name, HubHandler handler) {
    final list = _handlers.putIfAbsent(name, () => []);
    list.add(handler);
    if (_conn != null) _bind(_conn!, name);
    return () => list.remove(handler);
  }

  /// Serialize invokes — concurrent SignalR invokes on the same connection often fail on mobile.
  Future<void> _invokeChain = Future.value();

  /// SignalR args can't be null in this client; pass '' for optional strings (the server treats it as absent).
  Future<Object?> invoke(String method, [List<Object> args = const []]) {
    final done = Completer<Object?>();
    final token = Prefs.instance.token;
    final generation = _generation;
    _invokeChain = _invokeChain.catchError((_) {}).then((_) async {
      try {
        if (token != Prefs.instance.token || generation != _generation) throw StateError('Account changed');
        await ensureConnected();
        if (token != Prefs.instance.token || generation != _generation) throw StateError('Account changed');
        final result = await _conn!.invoke(method, args: args);
        done.complete(result);
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Invoke with one reconnect+retry — used for critical sends.
  Future<Object?> invokeReliable(String method, [List<Object> args = const []]) async {
    final token = Prefs.instance.token;
    final generation = _generation;
    try {
      return await invoke(method, args);
    } catch (_) {
      if (token != Prefs.instance.token || generation != _generation) rethrow;
      // Only idempotent sends can be retried after an uncertain transport outcome.
      if (method != 'SendMessageWithClientId') rethrow;
      if (state == HubConnectionState.Connected) rethrow;
      await forceReconnect();
      await ensureConnected(timeout: const Duration(seconds: 20));
      return await invoke(method, args);
    }
  }
}

class Hubs {
  static final matching = Hub('/hubs/matching');
  static final chat = Hub('/hubs/chat');
  static final conversation = Hub('/hubs/conversation');
  static final story = Hub('/hubs/story');

  static Future<void> stopAll() async {
    await Future.wait([matching.stop(), chat.stop(), conversation.stop(), story.stop()]);
  }

  static Future<void> pauseAll() async {
    await Future.wait([matching.pause(), chat.pause(), conversation.pause(), story.pause()]);
  }

  static Future<void> resumeAll() async {
    await Future.wait([matching.resume(), chat.resume(), conversation.resume(), story.resume()]);
  }

  /// Hard reconnect after network restore / retry tap.
  static Future<void> forceReconnectAll() async {
    await Future.wait([
      matching.forceReconnect(),
      chat.forceReconnect(),
      conversation.forceReconnect(),
      story.forceReconnect(),
    ]);
  }
}
