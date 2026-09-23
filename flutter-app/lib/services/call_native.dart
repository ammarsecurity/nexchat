import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Native call helpers: Android foreground service, proximity, incoming-call UI.
class CallNative {
  CallNative._();

  static const _channel = MethodChannel('nexchat/call');
  static bool _listening = false;

  static void Function(Map<String, dynamic> event)? onIncomingEvent;

  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingEvent' && call.arguments is Map) {
        onIncomingEvent?.call(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  static Future<void> ready() async {
    try {
      if (Platform.isAndroid) await _channel.invokeMethod('ready');
    } catch (_) {}
  }

  static Future<void> setForeground(bool value) async {
    try {
      if (Platform.isAndroid) await _channel.invokeMethod('setForeground', {'value': value});
    } catch (_) {}
  }

  static Future<void> showIncoming({
    String? conversationId,
    String? sessionId,
    required bool voiceOnly,
    required String callerName,
    String? callerAvatar,
  }) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('showIncoming', {
          'conversationId': conversationId,
          'sessionId': sessionId,
          'voiceOnly': voiceOnly,
          'callerName': callerName,
          'callerAvatar': callerAvatar,
        });
      }
    } catch (_) {}
  }

  static Future<void> dismissIncoming() async {
    try {
      if (Platform.isAndroid) await _channel.invokeMethod('dismissIncoming');
    } catch (_) {}
  }

  static Future<void> start({required bool video, required String title, required String text}) async {
    try {
      await WakelockPlus.enable();
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

  static Future<bool> isEmulator() async {
    try {
      if (!Platform.isAndroid) return false;
      return await _channel.invokeMethod<bool>('isEmulator') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> proximity(bool enabled) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) await _channel.invokeMethod('proximity', {'enabled': enabled});
    } catch (_) {}
  }
}
