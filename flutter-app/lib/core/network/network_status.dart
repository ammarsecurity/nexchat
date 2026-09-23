import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

/// Process-wide online flag so Dio/Hubs can fail fast without Riverpod.
class NetworkStatus {
  NetworkStatus._();
  static final online = ValueNotifier<bool>(true);
  static void Function()? onTransportFailure;
  static void Function()? onTransportSuccess;
}

/// stores/network.js + a real reachability probe (Wi‑Fi with no internet counts as offline).
class NetworkNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _reprobe;

  static bool hasLink(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);

  @override
  bool build() {
    NetworkStatus.onTransportFailure = reportTransportFailure;
    NetworkStatus.onTransportSuccess = reportTransportSuccess;
    _sub = Connectivity().onConnectivityChanged.listen(_onLink);
    ref.onDispose(() {
      _sub?.cancel();
      _reprobe?.cancel();
      if (NetworkStatus.onTransportFailure == reportTransportFailure) NetworkStatus.onTransportFailure = null;
      if (NetworkStatus.onTransportSuccess == reportTransportSuccess) NetworkStatus.onTransportSuccess = null;
    });
    Connectivity().checkConnectivity().then(_onLink, onError: (_) {});
    return true;
  }

  void _onLink(List<ConnectivityResult> r) {
    if (!hasLink(r)) {
      _set(false);
      return;
    }
    unawaited(recheck());
  }

  void _set(bool v) {
    if (state == v && NetworkStatus.online.value == v) return;
    state = v;
    NetworkStatus.online.value = v;
  }

  Future<bool> recheck() async {
    try {
      final link = hasLink(await Connectivity().checkConnectivity());
      if (!link) {
        _set(false);
        return false;
      }
    } catch (_) {}
    final ok = await probeInternet();
    _set(ok);
    return ok;
  }

  void reportTransportFailure() {
    _reprobe?.cancel();
    _reprobe = Timer(const Duration(milliseconds: 300), () => unawaited(_confirmAfterFailure()));
  }

  Future<void> _confirmAfterFailure() async {
    final ok = await probeInternet();
    if (ok) {
      _set(true);
      return;
    }
    _set(false);
    _reprobe?.cancel();
    _reprobe = Timer(const Duration(seconds: 4), () => unawaited(recheck()));
  }

  void reportTransportSuccess() {
    if (!state) _set(true);
  }
}

/// Any HTTP response means the API host is reachable (even 401/404).
Future<bool> probeInternet() async {
  try {
    final dio = Dio(BaseOptions(
      baseUrl: '${Env.apiUrl}/',
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
    ));
    await dio.get(
      'SiteContent/app_update',
      options: Options(validateStatus: (_) => true, extra: {'skipUnauthorizedEvent': true, 'skipGlobalLoader': true}),
    );
    return true;
  } catch (_) {
    return false;
  }
}

final networkProvider = NotifierProvider<NetworkNotifier, bool>(NetworkNotifier.new);
