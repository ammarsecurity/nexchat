import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/storage/prefs.dart';

/// Local PIN vault for WhatsApp-style hidden chats.
/// PIN never leaves the device; server only stores [IsHidden] per conversation.
class HiddenChatsVault {
  HiddenChatsVault._();
  static final instance = HiddenChatsVault._();

  String get _account {
    try { return '${(jsonDecode(Prefs.instance.getString(Keys.user) ?? '{}') as Map)['id'] ?? ''}'; } catch (_) { return ''; }
  }
  String get _hashKey => 'nexchat_hidden_pin_hash_$_account';
  String get _saltKey => 'nexchat_hidden_pin_salt_$_account';
  static const minPinLength = 4;
  static const maxPinLength = 12;

  final _secure = const FlutterSecureStorage();

  Future<bool> get hasPin async => (await _secure.read(key: _hashKey))?.isNotEmpty == true;

  Future<bool> setPin(String pin) async {
    final cleaned = pin.trim();
    if (cleaned.length < minPinLength || cleaned.length > maxPinLength) return false;
    if (_account.isEmpty) return false;
    final hashKey = _hashKey, saltKey = _saltKey;
    final salt = _randomSalt();
    final hash = _hash(cleaned, salt);
    await _secure.write(key: saltKey, value: salt);
    await _secure.write(key: hashKey, value: hash);
    return true;
  }

  Future<bool> verify(String pin) async {
    final account = _account;
    final hashKey = _hashKey, saltKey = _saltKey;
    if (account.isEmpty) return false;
    final hash = await _secure.read(key: hashKey);
    final salt = await _secure.read(key: saltKey);
    if (_account != account) return false;
    if (hash == null || salt == null || hash.isEmpty || salt.isEmpty) return false;
    return _hash(pin.trim(), salt) == hash;
  }

  Future<void> clearPin() async {
    final hashKey = _hashKey, saltKey = _saltKey;
    await _secure.delete(key: hashKey);
    await _secure.delete(key: saltKey);
  }

  String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
