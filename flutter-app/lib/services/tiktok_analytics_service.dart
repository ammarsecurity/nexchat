import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:tiktok_events_sdk/tiktok_events_sdk.dart';

import '../core/config/env.dart';
import '../core/storage/prefs.dart';

/// TikTok App Events SDK wrapper (install / login / registration attribution).
class TikTokAnalyticsService {
  TikTokAnalyticsService._();
  static final instance = TikTokAnalyticsService._();

  bool _ready = false;

  bool get isReady => _ready;

  Future<void> bootstrap() async {
    if (_ready) return;
    final secret = Env.tikTokAppSecret.trim();
    if (secret.isEmpty) {
      developer.log('TikTok SDK skipped: TIKTOK_APP_SECRET not set', name: 'TikTokAnalytics');
      return;
    }
    try {
      await TikTokEventsSdk.initSdk(
        androidAppId: Env.tikTokAndroidAppId,
        tikTokAndroidId: Env.tikTokAppId,
        iosAppId: Env.tikTokIosAppId,
        tiktokIosId: Env.tikTokAppId,
        isDebugMode: kDebugMode,
        logLevel: kDebugMode ? TikTokLogLevel.debug : TikTokLogLevel.info,
        androidOptions: TikTokAndroidOptions(appSecret: secret),
        iosOptions: TikTokIosOptions(accessToken: secret, displayAtt: true),
      );
      _ready = true;
      // Re-bind identity when the user is already logged in (cold start).
      await _identifyFromPrefs();
    } catch (e, st) {
      developer.log('TikTok SDK init failed: $e', name: 'TikTokAnalytics', stackTrace: st);
    }
  }

  Future<void> _identifyFromPrefs() async {
    try {
      final raw = Prefs.instance.getString(Keys.user);
      final token = Prefs.instance.token;
      if (raw == null || raw.isEmpty || token == null || token.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = '${map['id'] ?? ''}';
      if (id.isEmpty) return;
      await identify(userId: id, userName: map['name'] as String?);
    } catch (_) {}
  }

  Future<void> identify({required String userId, String? userName}) async {
    if (!_ready || userId.isEmpty) return;
    try {
      await TikTokEventsSdk.identify(
        identifier: TikTokIdentifier(
          externalId: userId,
          externalUserName: userName,
        ),
      );
    } catch (e, st) {
      developer.log('TikTok identify failed: $e', name: 'TikTokAnalytics', stackTrace: st);
    }
  }

  Future<void> logLogin() => _log(BaseEventName.login.value);

  Future<void> logCompleteRegistration() => _log(BaseEventName.registration.value);

  Future<void> logout() async {
    if (!_ready) return;
    try {
      await TikTokEventsSdk.logout();
    } catch (e, st) {
      developer.log('TikTok logout failed: $e', name: 'TikTokAnalytics', stackTrace: st);
    }
  }

  Future<void> _log(String eventName) async {
    if (!_ready) return;
    try {
      await TikTokEventsSdk.logEvent(event: TikTokEvent(eventName: eventName));
    } catch (e, st) {
      developer.log('TikTok logEvent($eventName) failed: $e', name: 'TikTokAnalytics', stackTrace: st);
    }
  }
}
