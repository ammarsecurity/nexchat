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
    final conn = HubConnectionBuilder()
        .withUrl(
          '${Env.apiHost}$path',
          options: HttpConnectionOptions(accessTokenFactory: () async => Prefs.instance.token ?? ''),
        )
        .withAutomaticReconnect()
        .build();
    conn.onreconnected(({connectionId}) {
      _restartAttempt = 0;
      _reconnected.add(null);
    });
    conn.onclose(({error}) => _scheduleRestart());
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
  Future<void> forceReconnect() async {
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

  Future<void> start() async {
    _wanted = true;
    if (!NetworkStatus.online.value) return;
    if ((Prefs.instance.token ?? '').isEmpty) return;
    _conn ??= _build();
    if (_conn!.state == HubConnectionState.Connected) {
      _restartAttempt = 0;
      _restartTimer?.cancel();
      return;
    }
    if (_conn!.state == HubConnectionState.Disconnected) {
      try {
        await _conn!.start();
        _restartAttempt = 0;
        _restartTimer?.cancel();
      } catch (_) {
        _scheduleRestart();
        rethrow;
      }
      return;
    }
    // Connecting / Reconnecting / Disconnecting — don't leave the socket stuck.
    await forceReconnect();
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

  /// SignalR args can't be null in this client; pass '' for optional strings (the server treats it as absent).
  Future<Object?> invoke(String method, [List<Object> args = const []]) async {
    await ensureConnected();
    return _conn!.invoke(method, args: args);
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
