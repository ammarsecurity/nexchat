import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/env.dart';
import '../core/network/api_client.dart';
import '../core/storage/prefs.dart';
import 'call_native.dart';
import 'push_session.dart';

class PushService {
  PushService._();
  @visibleForTesting
  PushService.testing();
  static final instance = PushService._();
  static const _installationKey = 'nexchat_push_installation';
  static const _enabledKey = 'nexchat_push_enabled';
  static const _pendingCleanupKey = 'nexchat_push_pending_cleanup_user';

  bool _bootstrapped = false;
  bool _observerBound = false;
  final _session = PushSession();
  String? _lastRegisteredSubId;
  String? _voipToken;
  Future<void> _backendQueue = Future<void>.value();
  Future<void> _identityQueue = Future<void>.value();
  static final promptNotifications = ValueNotifier<bool>(false);

  void Function(Map<String, dynamic> data, String? title, String? body)?
  _onOpen;
  void Function(Map<String, dynamic> data, String? title, String? body)?
  _onForeground;
  ({Map<String, dynamic> data, String? title, String? body})? _pendingOpen;

  bool get _wanted => Prefs.instance.getString(_enabledKey) != '0';
  bool get _authenticated =>
      _session.userId != null && (Prefs.instance.token?.isNotEmpty ?? false);
  bool _authMatches(String userId, String? token) {
    if (token == null || token.isEmpty || Prefs.instance.token != token) {
      return false;
    }
    try {
      final user = jsonDecode(Prefs.instance.getString(Keys.user) ?? '{}');
      return user is Map && user['id']?.toString() == userId;
    } catch (_) {
      return false;
    }
  }

  bool _allows(Map<String, dynamic> data) {
    final parsed = parseNotificationData(data);
    final recipient = parsed['recipientUserId'];
    final publicBroadcast =
        parsed['type'] == 'broadcast' && (recipient?.isEmpty ?? true);
    return _authenticated &&
        _wanted &&
        (publicBroadcast || _session.acceptsRecipient(recipient));
  }

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  set onOpen(
    void Function(Map<String, dynamic> data, String? title, String? body)? v,
  ) {
    _onOpen = v;
    final pending = _pendingOpen;
    if (v != null && pending != null) {
      _pendingOpen = null;
      if (_allows(pending.data)) v(pending.data, pending.title, pending.body);
    }
  }

  set onForeground(
    void Function(Map<String, dynamic> data, String? title, String? body)? v,
  ) => _onForeground = v;

  Future<String> _installationId() async {
    final existing = Prefs.instance.getString(_installationKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await Prefs.instance.setString(_installationKey, id);
    return id;
  }

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    // Restore the gate before any native/SDK callback can display old-account content.
    if (Prefs.instance.token?.isNotEmpty == true) {
      try {
        final raw = jsonDecode(Prefs.instance.getString(Keys.user) ?? '{}');
        final uid = raw is Map ? raw['id']?.toString() : null;
        if (uid != null && uid.isNotEmpty) _session.bind(uid);
      } catch (_) {}
    }
    await CallNative.setAuthenticatedUser(_wanted ? _session.userId : null);
    bindVoipTokenUpload();
    if (Env.oneSignalAppId.isEmpty) return;
    try {
      await OneSignal.initialize(Env.oneSignalAppId);
      OneSignal.Notifications.addClickListener((event) {
        final n = event.notification;
        final data = Map<String, dynamic>.from(n.additionalData ?? const {});
        if (!_allows(data)) return;
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
        event.preventDefault();
        if (!_allows(data)) return;
        final type = '${data['type'] ?? ''}';
        _onForeground?.call(data, n.title, n.body);
        if (type != 'video_call' && type != 'call_cancel') {
          try {
            n.display();
          } catch (_) {}
        }
      });
      if (!_observerBound) {
        _observerBound = true;
        OneSignal.User.pushSubscription.addObserver((state) {
          if (state.current.id != null &&
              state.current.id != _lastRegisteredSubId) {
            unawaited(_registerWithBackend());
          }
        });
        OneSignal.Notifications.addPermissionObserver((granted) {
          if (granted) unawaited(refreshRegistration());
        });
      }
      _bootstrapped = true;
      if (!_authenticated || !_wanted) {
        await OneSignal.User.pushSubscription.optOut();
      }
    } catch (_) {}
  }

  Future<bool> init(String userId, {bool promptPermission = true}) async {
    final token = Prefs.instance.token;
    if (userId.isEmpty || !_authMatches(userId, token)) return false;
    final startup = bootstrap();
    final startupGeneration = _session.generation;
    await startup;
    if (!_authMatches(userId, token) ||
        _session.generation != startupGeneration) {
      return false;
    }
    final generation = _session.bind(userId);
    await CallNative.setAuthenticatedUser(_wanted ? userId : null);
    await _replayVoipToken();
    if (!_wanted) return true; // Explicit opt-out must not trigger another permission prompt.
    if (!_bootstrapped) return false;
    try {
      await _linkExternalUser(userId, generation, token);
      if (!_session.isCurrent(userId, generation) ||
          !_authMatches(userId, token)) {
        return false;
      }
      if (Platform.isAndroid && promptPermission) {
        await Permission.notification.request();
      }
      final granted = promptPermission
          ? await OneSignal.Notifications.requestPermission(true)
          : OneSignal.Notifications.permission;
      if (granted &&
          _session.isCurrent(userId, generation) &&
          _authMatches(userId, token) &&
          _wanted) {
        await OneSignal.User.pushSubscription.optIn();
        await _registerWithBackend();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshRegistration() async {
    final uid = _session.userId;
    if (uid == null || !_authenticated) return;
    // init replays cached PushKit state and respects persistent opt-out.
    await init(uid, promptPermission: false);
  }

  Future<void> _enqueueBackend(Future<void> Function() action) {
    final next = _backendQueue.then((_) => action());
    _backendQueue = next.catchError((Object e) {
      if (kDebugMode) {
        debugPrint('[push] backend operation deferred: ${e.runtimeType}');
      }
    });
    return _backendQueue;
  }

  Options _options(String token) => Options(
    headers: {'Authorization': 'Bearer $token'},
    sendTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    extra: {
      'skipUnauthorizedEvent': true,
      'skipGlobalLoader': true,
      'preserveAuthorization': true,
    },
  );

  Future<void> _retryCleanup(
    String userId,
    String token,
    String installationId,
  ) async {
    if (Prefs.instance.getString(_pendingCleanupKey) != userId) return;
    await Api.dio.post(
      'notifications/unregister',
      data: {'installationId': installationId},
      options: _options(token),
    );
    await Prefs.instance.setString(_pendingCleanupKey, null);
  }

  Future<void> _registerWithBackend() async {
    final uid = _session.userId;
    final generation = _session.generation;
    final token = Prefs.instance.token;
    if (uid == null ||
        token == null ||
        !_wanted ||
        !_bootstrapped ||
        !OneSignal.Notifications.permission) {
      return;
    }
    await _enqueueBackend(() async {
      if (!_session.isCurrent(uid, generation) ||
          !_authMatches(uid, token) ||
          !_wanted) {
        return;
      }
      final id =
          OneSignal.User.pushSubscription.id ??
          await _waitForSubscriptionId(uid, generation);
      if (id == null ||
          !_session.isCurrent(uid, generation) ||
          !_authMatches(uid, token) ||
          !_wanted) {
        return;
      }
      final installationId = await _installationId();
      await _retryCleanup(uid, token, installationId);
      if (!_session.isCurrent(uid, generation) ||
          !_authMatches(uid, token) ||
          !_wanted) {
        return;
      }
      await Api.dio.post(
        'notifications/register',
        data: {
          'playerId': id,
          'platform': _platform,
          'installationId': installationId,
        },
        options: _options(token),
      );
      if (_session.isCurrent(uid, generation)) _lastRegisteredSubId = id;
    });
  }

  void bindVoipTokenUpload() {
    CallNative.onVoipToken = (token) {
      _voipToken = token;
      unawaited(_uploadVoipToken());
    };
  }

  Future<void> _replayVoipToken() async {
    if (!Platform.isIOS && _voipToken == null) return;
    _voipToken = await CallNative.getVoipToken() ?? _voipToken;
    await _uploadVoipToken();
  }

  Future<void> _uploadVoipToken() async {
    final uid = _session.userId;
    final generation = _session.generation;
    final authToken = Prefs.instance.token;
    final voipToken = _voipToken;
    if (uid == null || authToken == null || voipToken == null || !_wanted) {
      return;
    }
    await _enqueueBackend(() async {
      if (!_session.isCurrent(uid, generation) ||
          !_authMatches(uid, authToken) ||
          !_wanted) {
        return;
      }
      final installationId = await _installationId();
      await _retryCleanup(uid, authToken, installationId);
      if (!_session.isCurrent(uid, generation) ||
          !_authMatches(uid, authToken) ||
          !_wanted) {
        return;
      }
      await Api.dio.post(
        'notifications/voip-token',
        data: {'token': voipToken, 'installationId': installationId},
        options: _options(authToken),
      );
    });
  }

  Future<void> _linkExternalUser(String userId, int generation, String? token) {
    final next = _identityQueue.then((_) async {
      if (!_session.isCurrent(userId, generation) ||
          !_authMatches(userId, token)) {
        return;
      }
      final current = await OneSignal.User.getExternalId();
      if (!_session.isCurrent(userId, generation) ||
          !_authMatches(userId, token)) {
        return;
      }
      if (current == userId) return;
      await OneSignal.User.pushSubscription.optOut();
      if (current?.isNotEmpty == true) {
        await OneSignal.logout().timeout(const Duration(seconds: 5));
      }
      if (!_session.isCurrent(userId, generation) ||
          !_authMatches(userId, token)) {
        return;
      }
      await OneSignal.login(userId).timeout(const Duration(seconds: 10));
      if (!_session.isCurrent(userId, generation) ||
          !_authMatches(userId, token)) {
        return;
      }
      _lastRegisteredSubId = null;
    });
    _identityQueue = next.catchError((Object _) {});
    return next;
  }

  bool get enabled =>
      _wanted &&
      _authenticated &&
      _bootstrapped &&
      OneSignal.Notifications.permission &&
      (OneSignal.User.pushSubscription.optedIn ?? false);

  Future<void> optIn() async {
    await Prefs.instance.setString(_enabledKey, '1');
    final uid = _session.userId;
    if (uid != null) await init(uid);
  }

  Future<void> optOut() async {
    await Prefs.instance.setString(_enabledKey, '0');
    await CallNative.setAuthenticatedUser(null);
    if (_bootstrapped) {
      try {
        await OneSignal.User.pushSubscription.optOut();
      } catch (_) {}
    }
    await _unregisterCurrent();
  }

  Future<String?> _waitForSubscriptionId(String uid, int generation) async {
    for (
      var attempt = 0;
      attempt < 20 && _session.isCurrent(uid, generation) && _wanted;
      attempt++
    ) {
      final id = OneSignal.User.pushSubscription.id;
      if (id != null && id.isNotEmpty) return id;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<void> _unregisterCurrent({
    String? userId,
    String? token,
    String? playerId,
  }) async {
    final uid = userId ?? _session.userId;
    final auth = token ?? Prefs.instance.token;
    if (uid == null || auth == null) return;
    await Prefs.instance.setString(_pendingCleanupKey, uid);
    await _enqueueBackend(() async {
      await Api.dio.post(
        'notifications/unregister',
        data: {
          'playerId':
              playerId ??
              (_bootstrapped ? OneSignal.User.pushSubscription.id : null),
          'installationId': await _installationId(),
        },
        options: _options(auth),
      );
      if (Prefs.instance.getString(_pendingCleanupKey) == uid) {
        await Prefs.instance.setString(_pendingCleanupKey, null);
      }
    });
  }

  Future<void> clear() async {
    final uid = _session.userId;
    final token = Prefs.instance.token;
    final id = _bootstrapped ? OneSignal.User.pushSubscription.id : null;
    _session.clear(); // Invalidate callbacks before any asynchronous cleanup.
    _lastRegisteredSubId = null;
    _pendingOpen = null;
    promptNotifications.value = false;
    await CallNative.setAuthenticatedUser(null);
    // Local disassociation must run even if unregister is offline/401/timed out.
    if (_bootstrapped) {
      try {
        await OneSignal.User.pushSubscription.optOut().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {}
      final logout = _identityQueue.then(
        (_) => OneSignal.logout().timeout(const Duration(seconds: 5)),
      );
      _identityQueue = logout.catchError((Object _) {});
      await _identityQueue;
    }
    await _unregisterCurrent(userId: uid, token: token, playerId: id);
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
  if (custom is Map && custom['a'] is Map) {
    parsed = {...parsed, ...Map<String, dynamic>.from(custom['a'] as Map)};
  }
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
    'callId': pick(['callId', 'CallId']),
    'recipientUserId': pick(['recipientUserId', 'RecipientUserId']),
    'conversationId': pick(['conversationId', 'ConversationId']),
    'sessionId': pick(['sessionId', 'SessionId']),
    'userId': pick(['userId', 'UserId']),
    'messageRequestId': pick(['messageRequestId', 'MessageRequestId']),
    'slideId': pick(['slideId', 'SlideId']),
    'voiceOnly': pick(['voiceOnly', 'VoiceOnly']),
    'callerName': pick([
      'callerName',
      'CallerName',
      'senderName',
      'publisherName',
    ]),
    'callerAvatar': pick([
      'callerAvatar',
      'CallerAvatar',
      'senderAvatar',
      'publisherAvatar',
      'avatar',
    ]),
    'requesterId': pick(['requesterId', 'RequesterId']),
    'requesterName': pick(['requesterName', 'RequesterName']),
    'requesterGender': pick(['requesterGender', 'RequesterGender']),
    'requesterAvatar': pick(['requesterAvatar', 'RequesterAvatar']),
    'requesterIsFeatured': pick(['requesterIsFeatured', 'RequesterIsFeatured']),
    'notificationId': pick(['notificationId', 'NotificationId']),
    'createdAt': pick(['createdAt', 'CreatedAt']),
  };
}
