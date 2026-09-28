import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// Same keys as the Vue app's localStorage so behaviour stays identical.
class Keys {
  static const token = 'nexchat_token';
  static const user = 'nexchat_user';
  static const avatar = 'nexchat_avatar';
  static const needsProfileContact = 'nexchat_needs_profile_contact';
  static const theme = 'nexchat_theme';
  static const locale = 'nexchat_locale';
  static const onboardingSeen = 'nexchat_onboarding_seen';
  static const notifications = 'nexchat_notifications';
  static const pendingInvite = 'nexchat_pending_invite';

  /// Readable from Android native code for call decline without a live Flutter engine.
  static const nativeToken = 'nexchat_native_token';
  static const nativeApi = 'nexchat_native_api';
}

class Prefs {
  Prefs._(this.sp);
  final SharedPreferences sp;
  static const _secure = FlutterSecureStorage();
  static late Prefs instance;
  String? _token;

  static Future<Prefs> init() async {
    final p = Prefs._(await SharedPreferences.getInstance());
    p._token = await _secure.read(key: Keys.token);
    instance = p;
    await p._mirrorNativeAuth();
    return p;
  }

  String? get token => _token;

  Future<void> setToken(String? value) async {
    _token = value;
    if (value == null || value.isEmpty) {
      await _secure.delete(key: Keys.token);
    } else {
      await _secure.write(key: Keys.token, value: value);
    }
    await _mirrorNativeAuth();
  }

  Future<void> _mirrorNativeAuth() async {
    final t = _token;
    if (t == null || t.isEmpty) {
      await sp.remove(Keys.nativeToken);
      await sp.remove(Keys.nativeApi);
    } else {
      await sp.setString(Keys.nativeToken, t);
      await sp.setString(Keys.nativeApi, Env.apiUrl);
    }
  }

  String? getString(String key) => sp.getString(key);
  Future<void> setString(String key, String? value) async {
    if (value == null) {
      await sp.remove(key);
    } else {
      await sp.setString(key, value);
    }
  }
}
