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
    conn.onreconnected(({connectionId}) => _reconnected.add(null));
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

  /// withAutomaticReconnect gives up after ~40 s; keep retrying with backoff while the hub is wanted.
  void _scheduleRestart() {
    if (!_wanted || !NetworkStatus.online.value || (Prefs.instance.token ?? '').isEmpty) return;
    _restartTimer?.cancel();
    final delay = Duration(seconds: [2, 5, 10, 20, 30][_restartAttempt.clamp(0, 4)]);
    _restartAttempt++;
    _restartTimer = Timer(delay, () async {
      if (!_wanted) return;
      try {
        await start();
        _reconnected.add(null);
      } catch (_) {
        _scheduleRestart();
      }
    });
  }

  Future<void> start() async {
    _wanted = true;
    if (!NetworkStatus.online.value) return;
    _conn ??= _build();
    if (_conn!.state == HubConnectionState.Disconnected) {
      try {
        await _conn!.start();
        _restartAttempt = 0;
        _restartTimer?.cancel();
      } catch (_) {
        _scheduleRestart();
        rethrow;
      }
    }
  }

  /// App resumed / network back: reconnect now instead of waiting for the backoff timer.
  Future<void> resume() async {
    if (!_wanted || !NetworkStatus.online.value || state != HubConnectionState.Disconnected) return;
    _restartAttempt = 0;
    try {
      await start();
      _reconnected.add(null);
    } catch (_) {
      _scheduleRestart();
    }
  }

  Future<void> ensureConnected({Duration timeout = const Duration(seconds: 15)}) async {
    if (!NetworkStatus.online.value) throw TimeoutException(I18n.t('noConnection.title'));
    _wanted = true;
    _conn ??= _build();
    if (_conn!.state == HubConnectionState.Connected) return;
    if (_conn!.state == HubConnectionState.Disconnected) {
      await _conn!.start();
      return;
    }
    final started = DateTime.now();
    while (_conn!.state != HubConnectionState.Connected) {
      if (DateTime.now().difference(started) > timeout) throw TimeoutException('انتهت مهلة الاتصال');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> stop() async {
    _wanted = false;
    _restartTimer?.cancel();
    final c = _conn;
    if (c != null && c.state != HubConnectionState.Disconnected) await c.stop();
  }

  /// Drop the socket but keep the hub wanted so resume() can bring it back.
  Future<void> pause() async {
    _restartTimer?.cancel();
    final c = _conn;
    if (c != null && c.state != HubConnectionState.Disconnected) {
      try {
        await c.stop();
      } catch (_) {}
    }
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
}
