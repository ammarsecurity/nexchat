import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
