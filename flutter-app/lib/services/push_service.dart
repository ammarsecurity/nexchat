import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';

/// Mirrors the native part of mobile-app/src/services/notifications.js.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _initialized = false;
  String? _userId;

  /// auth.shouldPromptNotifications — set after login when permission wasn't granted.
  static final promptNotifications = ValueNotifier<bool>(false);

  /// Set by the app shell: routes a tapped notification (same payload fields as the Vue app).
  void Function(Map<String, dynamic> data, String? title, String? body)? onOpen;

  /// Set by the app shell: records a notification received while the app is in the foreground.
  void Function(Map<String, dynamic> data, String? title, String? body)? onForeground;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<bool> init(String userId, {bool promptPermission = true}) async {
    if (Env.oneSignalAppId.isEmpty) return false;
    try {
      if (!_initialized) {
        OneSignal.initialize(Env.oneSignalAppId);
        OneSignal.Notifications.addClickListener((event) {
          final n = event.notification;
          onOpen?.call(Map<String, dynamic>.from(n.additionalData ?? const {}), n.title, n.body);
        });
        OneSignal.Notifications.addForegroundWillDisplayListener((event) {
          final n = event.notification;
          onForeground?.call(Map<String, dynamic>.from(n.additionalData ?? const {}), n.title, n.body);
          event.preventDefault();
        });
        _initialized = true;
      }
      if (_userId != userId) {
        OneSignal.login(userId);
        _userId = userId;
      }
      final granted = promptPermission ? await OneSignal.Notifications.requestPermission(true) : OneSignal.Notifications.permission;
      if (granted) {
        OneSignal.User.pushSubscription.optIn();
        unawaited(_registerWithBackend());
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  bool get enabled => _initialized && OneSignal.Notifications.permission && (OneSignal.User.pushSubscription.optedIn ?? false);

  Future<void> optIn() async {
    await OneSignal.Notifications.requestPermission(true);
    OneSignal.User.pushSubscription.optIn();
    unawaited(_registerWithBackend());
  }

  void optOut() => OneSignal.User.pushSubscription.optOut();

  Future<String?> _waitForSubscriptionId() async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < const Duration(seconds: 15)) {
      final id = OneSignal.User.pushSubscription.id;
      if (id != null && id.isNotEmpty) return id;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  Future<void> _registerWithBackend() async {
    final id = await _waitForSubscriptionId();
    if (id == null) return;
    try {
      await Api.dio.post('notifications/register',
          data: {'playerId': id, 'platform': _platform},
          options: Options(extra: {'skipUnauthorizedEvent': true, 'skipGlobalLoader': true}));
    } catch (_) {}
  }

  Future<void> clear() async {
    if (!_initialized) return;
    try {
      final id = OneSignal.User.pushSubscription.id;
      if (id != null) {
        await Api.dio.post('notifications/unregister',
            data: {'playerId': id, 'platform': _platform},
            options: Options(extra: {'skipUnauthorizedEvent': true, 'skipGlobalLoader': true}));
      }
      OneSignal.logout();
    } catch (_) {}
    _userId = null;
  }
}

/// Same field extraction as parseNotificationData() in the Vue app.
Map<String, String?> parseNotificationData(Map<String, dynamic> raw) {
  Map<String, dynamic> parsed = {};
  final dataJson = raw['dataJson'] ?? raw['DataJson'];
  if (dataJson is String && dataJson.isNotEmpty) {
    try {
      final decoded = jsonDecode(dataJson);
      if (decoded is Map) parsed = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  } else if (dataJson is Map) {
    parsed = Map<String, dynamic>.from(dataJson);
  }
  final custom = raw['custom'];
  if (custom is Map && custom['a'] is Map) parsed = {...parsed, ...Map<String, dynamic>.from(custom['a'] as Map)};
  final src = {...parsed, ...raw};

  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = src[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return null;
  }

  return {
    'type': pick(['type', 'Type']) ?? 'message',
    'conversationId': pick(['conversationId', 'ConversationId']),
    'sessionId': pick(['sessionId', 'SessionId']),
    'userId': pick(['userId', 'UserId']),
    'messageRequestId': pick(['messageRequestId', 'MessageRequestId']),
    'slideId': pick(['slideId', 'SlideId']),
    'voiceOnly': pick(['voiceOnly', 'VoiceOnly']),
    'callerName': pick(['callerName', 'CallerName']),
    'callerAvatar': pick(['callerAvatar', 'CallerAvatar']),
    'requesterId': pick(['requesterId', 'RequesterId']),
    'requesterName': pick(['requesterName', 'RequesterName']),
    'requesterGender': pick(['requesterGender', 'RequesterGender']),
    'requesterAvatar': pick(['requesterAvatar', 'RequesterAvatar']),
    'requesterIsFeatured': pick(['requesterIsFeatured', 'RequesterIsFeatured']),
  };
}
