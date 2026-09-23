import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Native call helpers: Android foreground service, proximity screen-off, keep-screen-on.
class CallNative {
  CallNative._();

  static const _channel = MethodChannel('nexchat/call');

  static Future<void> start({required bool video, required String title, required String text}) async {
    try {
      if (video) await WakelockPlus.enable();
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod('start', {'video': video, 'title': title, 'text': text});
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await WakelockPlus.disable();
      if (Platform.isAndroid || Platform.isIOS) await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<void> proximity(bool enabled) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) await _channel.invokeMethod('proximity', {'enabled': enabled});
    } catch (_) {}
  }
}
