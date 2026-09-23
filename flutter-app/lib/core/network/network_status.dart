import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// stores/network.js
class NetworkNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  static bool _online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  @override
  bool build() {
    _sub = Connectivity().onConnectivityChanged.listen((r) => state = _online(r));
    ref.onDispose(() => _sub?.cancel());
    Connectivity().checkConnectivity().then((r) => state = _online(r), onError: (_) {});
    return true;
  }

  Future<bool> recheck() async {
    try {
      state = _online(await Connectivity().checkConnectivity());
    } catch (_) {}
    return state;
  }
}

final networkProvider = NotifierProvider<NetworkNotifier, bool>(NetworkNotifier.new);
