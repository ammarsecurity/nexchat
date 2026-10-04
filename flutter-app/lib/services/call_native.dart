import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Native call helpers: Android FGS / FSI, iOS CallKit, proximity, pending store.
class CallNative {
  CallNative._();

  static const _channel = MethodChannel('nexchat/call');
  static bool _listening = false;
  static String? _ongoingCallId;

  static void Function(Map<String, dynamic> event)? onIncomingEvent;

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incomingEvent' && call.arguments is Map) {
        onIncomingEvent?.call(Map<String, dynamic>.from(call.arguments as Map));
      } else if (call.method == 'voipToken' && call.arguments is Map) {
        final token = (call.arguments as Map)['token']?.toString();
        if (token != null) onVoipToken?.call(token);
      }
    });
  }

  static void Function(String token)? onVoipToken;

  static Future<String?> getVoipToken() async {
    try {
      if (Platform.isIOS) {
        return await _channel.invokeMethod<String>('getVoipToken');
      }
    } catch (_) {}
    return null;
  }

  static Future<void> setAuthenticatedUser(String? userId) async {
    try {
      if (_mobile) {
        await _channel.invokeMethod('setAuthenticatedUser', {'userId': userId});
      }
    } catch (_) {}
  }

  static Future<void> ready() async {
    try {
      if (_mobile) await _channel.invokeMethod('ready');
    } catch (_) {}
  }

  static Future<void> setForeground(bool value) async {
    try {
      if (_mobile) {
        await _channel.invokeMethod('setForeground', {'value': value});
      }
    } catch (_) {}
  }

  static Future<void> showIncoming({
    String? callId,
    String? conversationId,
    String? sessionId,
    required bool voiceOnly,
    required String callerName,
    String? callerAvatar,
  }) async {
    try {
      if (_mobile) {
        await _channel.invokeMethod('showIncoming', {
          'callId': callId,
          'conversationId': conversationId,
          'sessionId': sessionId,
          'voiceOnly': voiceOnly,
          'callerName': callerName,
          'callerAvatar': callerAvatar,
        });
      }
    } catch (_) {}
  }

  static Future<void> acceptIncoming({required String callId}) async {
    try {
      if (_mobile) {
        await _channel.invokeMethod('acceptIncoming', {'callId': callId});
      }
    } catch (_) {}
  }

  static Future<void> dismissIncoming({String? callId}) async {
    try {
      if (_mobile) {
        await _channel.invokeMethod('dismissIncoming', {'callId': callId});
      }
    } catch (_) {}
  }

  static Future<void> start({
    String? callId,
    required bool video,
    required String title,
    required String text,
  }) async {
    try {
      _ongoingCallId = callId;
      await WakelockPlus.enable();
      if (_mobile) {
        await _channel.invokeMethod('start', {
          'callId': callId,
          'video': video,
          'title': title,
          'text': text,
        });
      }
    } catch (_) {}
  }

  static Future<void> stop({String? callId}) async {
    if (callId != null && _ongoingCallId != null && _ongoingCallId != callId) {
      return;
    }
    _ongoingCallId = null;
    try {
      await WakelockPlus.disable();
      if (_mobile) await _channel.invokeMethod('stop', {'callId': callId});
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
      if (_mobile) {
        await _channel.invokeMethod('proximity', {'enabled': enabled});
      }
    } catch (_) {}
  }

  static Future<void> clearLockScreen() async {
    try {
      if (Platform.isAndroid) await _channel.invokeMethod('clearLockScreen');
    } catch (_) {}
  }

  /// Returns a pending incoming-call payload (if any) and clears native storage.
  static Future<Map<String, dynamic>?> consumePending() async {
    try {
      if (!_mobile) return null;
      final raw = await _channel.invokeMethod<dynamic>('consumePending');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }
}
