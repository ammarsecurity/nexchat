import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Blocks screenshots / screen recording while sensitive UI is visible.
/// Ref-counted and serialized so chat → call nesting stays correct.
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('nexchat/secure');
  static int _holders = 0;
  static Future<void> _queue = Future.value();
  static void Function()? onScreenshot;
  static bool _handlerReady = false;

  static void ensureHandler() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') onScreenshot?.call();
    });
  }

  static Future<void> acquire() {
    ensureHandler();
    final done = Completer<void>();
    _queue = _queue.then((_) async {
      try {
        _holders++;
        await _set(_holders > 0);
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  static Future<void> release() {
    final done = Completer<void>();
    _queue = _queue.then((_) async {
      try {
        if (_holders > 0) _holders--;
        await _set(_holders > 0);
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  static Future<void> _set(bool enabled) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod('setSecure', {'enabled': enabled});
      }
    } catch (_) {}
  }
}
