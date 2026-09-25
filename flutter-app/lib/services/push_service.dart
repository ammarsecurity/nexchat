import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';

/// Mirrors the native part of mobile-app/src/services/notifications.js.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _bootstrapped = false;
  bool _initialized = false;
  String? _userId;
  bool _observerBound = false;
  String? _lastRegisteredSubId;

  /// auth.shouldPromptNotifications — set after login when permission wasn't granted.
  static final promptNotifications = ValueNotifier<bool>(false);

  void Function(Map<String, dynamic> data, String? title, String? body)? _onOpen;
  void Function(Map<String, dynamic> data, String? title, String? body)? _onForeground;
  ({Map<String, dynamic> data, String? title, String? body})? _pendingOpen;

  /// Set by the app shell: routes a tapped notification (same payload fields as the Vue app).
  set onOpen(void Function(Map<String, dynamic> data, String? title, String? body)? v) {
    _onOpen = v;
    final pending = _pendingOpen;
    if (v != null && pending != null) {
      _pendingOpen = null;
      v(pending.data, pending.title, pending.body);
    }
  }

  /// Set by the app shell: records a notification received while the app is in the foreground.
  set onForeground(void Function(Map<String, dynamic> data, String? title, String? body)? v) => _onForeground = v;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// Must run before [runApp] so the native SDK can attach the FCM token and click queue.
  Future<void> bootstrap() async {
    if (_bootstrapped || Env.oneSignalAppId.isEmpty) return;
    try {
      await OneSignal.initialize(Env.oneSignalAppId);
      OneSignal.Notifications.addClickListener((event) {
        final n = event.notification;
        final data = Map<String, dynamic>.from(n.additionalData ?? const {});
        final handler = _onOpen;
        if (handler != null) {
          handler(data, n.title, n.body);
        } else {
          _pendingOpen = (data: data, title: n.title, body: n.body);
        }
      });
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        final n = event.notification;
        final data = Map<String, dynamic>.from(n.additionalData ?? const {});
        final type = '${data['type'] ?? ''}';
        _onForeground?.call(data, n.title, n.body);
        // Video calls use the custom incoming-call UI — suppress the system banner.
        // Text/message pushes must still show in the tray (explicit display for OneSignal 5).
        if (type == 'video_call') {
          event.preventDefault();
        } else {
          try {
            event.notification.display();
          } catch (_) {}
        }
      });
      if (!_observerBound) {
        _observerBound = true;
        OneSignal.User.pushSubscription.addObserver((state) {
          final id = state.current.id;
          if (id != null && id.isNotEmpty && id != _lastRegisteredSubId) {
            unawaited(_registerWithBackend(force: true));
          }
        });
        OneSignal.Notifications.addPermissionObserver((granted) {
          if (granted) unawaited(_registerWithBackend(force: true));
        });
      }
      _bootstrapped = true;
      _initialized = true;
    } catch (_) {}
  }

  Future<bool> init(String userId, {bool promptPermission = true}) async {
    if (Env.oneSignalAppId.isEmpty || userId.isEmpty) return false;
    try {
      await bootstrap();
      if (!_bootstrapped) return false;

      await _linkExternalUser(userId);

      if (Platform.isAndroid) {
        await Permission.notification.request();
      }
      final granted = promptPermission
          ? await OneSignal.Notifications.requestPermission(true)
          : OneSignal.Notifications.permission;
      if (granted) {
        await OneSignal.User.pushSubscription.optIn();
        await _registerWithBackend(force: true);
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Re-bind alias + refresh backend registration (call on app resume while logged in).
  Future<void> refreshRegistration() async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    try {
      await bootstrap();
      await _linkExternalUser(uid);
      if (OneSignal.Notifications.permission) {
        await OneSignal.User.pushSubscription.optIn();
        await _registerWithBackend(force: true);
      }
    } catch (_) {}
  }

  Future<void> _registerWithBackend({bool force = false}) async {
    final id = OneSignal.User.pushSubscription.id ?? await _waitForSubscriptionId();
    if (id == null) return;
    if (!force && id == _lastRegisteredSubId) return;
    try {
      await Api.dio.post(
        'notifications/register',
        data: {'playerId': id, 'platform': _platform},
        options: Options(extra: {'skipUnauthorizedEvent': true, 'skipGlobalLoader': true}),
      );
      _lastRegisteredSubId = id;
      if (kDebugMode) debugPrint('[push] registered subscription=$id user=$_userId');
    } catch (e) {
      if (kDebugMode) debugPrint('[push] register failed: $e');
    }
  }

  Future<void> _linkExternalUser(String userId) async {
    try {
      final current = await OneSignal.User.getExternalId();
      if (current == userId) {
        _userId = userId;
        return;
      }
      if (current != null && current.isNotEmpty && current != userId) {
        try {
          await OneSignal.logout().timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      try {
        await OneSignal.login(userId).timeout(const Duration(seconds: 10));
      } catch (_) {}
      _userId = userId;

      final started = DateTime.now();
      while (DateTime.now().difference(started) < const Duration(seconds: 8)) {
        final linked = await OneSignal.User.getExternalId();
        if (linked == userId) return;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } catch (_) {
      _userId = userId;
    }
  }

  bool get enabled => _initialized && OneSignal.Notifications.permission && (OneSignal.User.pushSubscription.optedIn ?? false);

  Future<void> optIn() async {
    await bootstrap();
    if (Platform.isAndroid) await Permission.notification.request();
    await OneSignal.Notifications.requestPermission(true);
    await OneSignal.User.pushSubscription.optIn();
    await _registerWithBackend(force: true);
  }

  void optOut() => OneSignal.User.pushSubscription.optOut();

  Future<String?> _waitForSubscriptionId() async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < const Duration(seconds: 20)) {
      final id = OneSignal.User.pushSubscription.id;
      if (id != null && id.isNotEmpty) return id;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  Future<void> clear() async {
    if (!_initialized) return;
    try {
      final id = OneSignal.User.pushSubscription.id;
      if (id != null) {
        await Api.dio.post(
          'notifications/unregister',
          data: {'playerId': id, 'platform': _platform},
          options: Options(extra: {'skipUnauthorizedEvent': true, 'skipGlobalLoader': true}),
        );
      }
      await OneSignal.logout();
    } catch (_) {}
    _userId = null;
    _lastRegisteredSubId = null;
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
    'callerName': pick(['callerName', 'CallerName', 'senderName', 'publisherName']),
    'callerAvatar': pick(['callerAvatar', 'CallerAvatar', 'senderAvatar', 'publisherAvatar', 'avatar']),
    'requesterId': pick(['requesterId', 'RequesterId']),
    'requesterName': pick(['requesterName', 'RequesterName']),
    'requesterGender': pick(['requesterGender', 'RequesterGender']),
    'requesterAvatar': pick(['requesterAvatar', 'RequesterAvatar']),
    'requesterIsFeatured': pick(['requesterIsFeatured', 'RequesterIsFeatured']),
  };
}
