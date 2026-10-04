import 'dart:async';
import 'dart:convert';

import '../../core/json.dart';
import '../../core/storage/prefs.dart';
import 'message_contract.dart';

/// Private cache keys are always bound to the account that started the operation.
class ConversationCache {
  static String inboxKey(String account, [String filter = 'all']) =>
      'nexchat_v2_${account}_inbox_$filter';
  static String historyKey(String account, String conversation) =>
      'nexchat_v2_${account}_messages_$conversation';
  static String _deletedKey(String account, String conversation) =>
      'nexchat_v2_${account}_deleted_$conversation';
  static Future<void> _writes = Future.value();

  static Set<String> _deleted(String account, String conversation) {
    try {
      return (jsonDecode(
        Prefs.instance.getString(_deletedKey(account, conversation)) ?? '[]',
      ) as List).map((id) => '$id').toSet();
    } catch (_) {
      return {};
    }
  }

  static List<Json> read(String account, String conversation) {
    if (account.isEmpty) return [];
    try {
      return _filter(
        account,
        conversation,
        asJsonList(
          jsonDecode(
            Prefs.instance.getString(historyKey(account, conversation)) ?? '[]',
          ),
        ),
      );
    } catch (_) {
      return [];
    }
  }

  static List<Json> _filter(
    String account,
    String conversation,
    List<Json> messages,
  ) {
    final unavailable = _deleted(account, conversation);
    return withoutExpiredMessages([
      for (final m in messages)
        if (!unavailable.contains(m.str('id'))) redactReply(m, unavailable),
    ]);
  }

  static Future<void> _write(
    String account,
    String conversation,
    List<Json> messages,
  ) async {
    final list = _filter(
      account,
      conversation,
      messages.where((m) => m.str('id').isNotEmpty).toList(),
    );
    await Prefs.instance.setString(
      historyKey(account, conversation),
      jsonEncode(list.length > 150 ? list.sublist(list.length - 150) : list),
    );
  }

  static Future<void> save(
    String account,
    String conversation,
    List<Json> messages,
  ) {
    if (account.isEmpty) return Future.value();
    final snapshot = [for (final m in messages) Map<String, dynamic>.of(m)];
    return _writes = _writes
        .catchError((_) {})
        .then((_) => _write(account, conversation, snapshot));
  }

  static Future<void> receive(String account, Json message) {
    final cid = message.str('conversationId');
    if (account.isEmpty || cid.isEmpty || message.str('id').isEmpty) {
      return Future.value();
    }
    return _writes = _writes.catchError((_) {}).then((_) async {
      final messages = read(account, cid);
      final index = messages.indexWhere(
        (m) => m.str('id') == message.str('id'),
      );
      if (index < 0) {
        messages.add(message);
      } else {
        messages[index] = message;
      }
      await _write(account, cid, messages);
    });
  }

  static Future<void> redact(
    String account,
    String conversation,
    Iterable<String> ids,
  ) {
    if (account.isEmpty || conversation.isEmpty) return Future.value();
    return _writes = _writes.catchError((_) {}).then((_) async {
      final deleted = {..._deleted(account, conversation), ...ids};
      await Prefs.instance.setString(
        _deletedKey(account, conversation),
        jsonEncode(deleted.toList()),
      );
      await _write(account, conversation, read(account, conversation));
    });
  }

  static Future<void> setExpiry(String account, String conversation, Set<String> ids, String? at) {
    return _writes = _writes.catchError((_) {}).then((_) async {
      final messages = read(account, conversation);
      await _write(account, conversation, [for (final m in messages) {
        ...m,
        if (ids.contains(m.str('id'))) 'expiresAt': at,
        if (ids.contains(m.str('replyToMessageId'))) 'replyToExpiresAt': at,
      }]);
    });
  }

  static Future<void> forget(String account, String conversation) {
    return _writes = _writes
        .catchError((_) {})
        .then(
          (_) =>
              Prefs.instance.setString(historyKey(account, conversation), null),
        );
  }

  /// Unscoped legacy bytes have no trustworthy owner; never migrate them to a login.
  static Future<void> removeLegacy() async {
    for (final key in Prefs.instance.sp.getKeys().toList()) {
      if (key == 'nexchat_conversations_cache' ||
          key.startsWith('nexchat_msgs_') ||
          key.startsWith('nexchat_outbox_')) {
        await Prefs.instance.setString(key, null);
      }
    }
  }
}
