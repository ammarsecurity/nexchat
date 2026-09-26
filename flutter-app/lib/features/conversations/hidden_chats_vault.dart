import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local PIN vault for WhatsApp-style hidden chats.
/// PIN never leaves the device; server only stores [IsHidden] per conversation.
class HiddenChatsVault {
  HiddenChatsVault._();
  static final instance = HiddenChatsVault._();

  static const _hashKey = 'nexchat_hidden_pin_hash';
  static const _saltKey = 'nexchat_hidden_pin_salt';
  static const minPinLength = 4;
  static const maxPinLength = 12;

  final _secure = const FlutterSecureStorage();

  Future<bool> get hasPin async => (await _secure.read(key: _hashKey))?.isNotEmpty == true;

  Future<bool> setPin(String pin) async {
    final cleaned = pin.trim();
    if (cleaned.length < minPinLength || cleaned.length > maxPinLength) return false;
    final salt = _randomSalt();
    final hash = _hash(cleaned, salt);
    await _secure.write(key: _saltKey, value: salt);
    await _secure.write(key: _hashKey, value: hash);
    return true;
  }

  Future<bool> verify(String pin) async {
    final hash = await _secure.read(key: _hashKey);
    final salt = await _secure.read(key: _saltKey);
    if (hash == null || salt == null || hash.isEmpty || salt.isEmpty) return false;
    return _hash(pin.trim(), salt) == hash;
  }

  Future<void> clearPin() async {
    await _secure.delete(key: _hashKey);
    await _secure.delete(key: _saltKey);
  }

  String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
