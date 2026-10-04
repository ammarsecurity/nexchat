import 'dart:async';
import 'dart:convert';

import '../../core/json.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/storage/prefs.dart';
import 'conversation_cache.dart';
import 'message_contract.dart';

/// Account-scoped durable text delivery, independent of any mounted chat screen.
class MessageOutbox {
  static final acknowledgments =
      StreamController<({String account, Json message})>.broadcast();
  static final failures =
      StreamController<
        ({String account, String conversation, String clientId})
      >.broadcast();
  static Future<void> _writes = Future.value();
  static final Map<String, Future<void>> _flushes = {};
  static final Set<String> _accepted = {};
  static String _key(String account) => 'nexchat_v2_${account}_outbox';

  static String get currentAccount {
    if ((Prefs.instance.token ?? '').isEmpty) return '';
    try {
      return (jsonDecode(Prefs.instance.getString(Keys.user) ?? '{}') as Map)
          .str('id');
    } catch (_) {
      return '';
    }
  }

  static List<Json> read(String account, [String? conversation]) {
    if (account.isEmpty) return [];
    try {
      final messages = asJsonList(
        jsonDecode(Prefs.instance.getString(_key(account)) ?? '[]'),
      );
      return conversation == null
          ? messages
          : messages
                .where((m) => belongsToConversation(m, conversation))
                .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> enqueue(String account, Json message) {
    if (account.isEmpty ||
        clientMessageId(message).isEmpty ||
        message.str('conversationId').isEmpty) {
      return Future.value();
    }
    final item = Map<String, dynamic>.of(message);
    return _writes = _writes.catchError((_) {}).then((_) async {
      final id = clientMessageId(item);
      if (_accepted.contains('$account:$id') || item.str('id').isNotEmpty) { return; }
      final items = read(account)..removeWhere((m) => clientMessageId(m) == id);
      items.add({...item, 'clientMessageId': id});
      await Prefs.instance.setString(_key(account), jsonEncode(items));
    });
  }

  static Future<void> acknowledge(String account, Json message) async {
    final id = clientMessageId(message);
    if (account.isEmpty ||
        id.isEmpty ||
        message.str('id').isEmpty ||
        message.str('senderId').toLowerCase() != account.toLowerCase()) {
      return;
    }
    _accepted.add('$account:$id');
    await (_writes = _writes.catchError((_) {}).then((_) async {
      final items = read(account)..removeWhere((m) => clientMessageId(m) == id);
      await Prefs.instance.setString(
        _key(account),
        items.isEmpty ? null : jsonEncode(items),
      );
    }));
    await ConversationCache.receive(account, message);
    if (currentAccount == account) {
      acknowledgments.add((account: account, message: message));
    }
  }

  static Future<void> forgetConversation(String account, String conversation) {
    return _writes = _writes.catchError((_) {}).then((_) async {
      final items = read(account)
        ..removeWhere((m) => belongsToConversation(m, conversation));
      await Prefs.instance.setString(
        _key(account),
        items.isEmpty ? null : jsonEncode(items),
      );
    });
  }

  static Future<void> flush(String account) {
    if (account.isEmpty ||
        currentAccount != account ||
        !NetworkStatus.online.value) {
      return Future.value();
    }
    return _flushes.putIfAbsent(
      account,
      () => _flush(account).whenComplete(() { _flushes.remove(account); }),
    );
  }

  static Future<void> _flush(String account) async {
    await _writes;
    for (final item in read(account)) {
      if (currentAccount != account || !NetworkStatus.online.value) return;
      final cid = item.str('conversationId');
      final clientId = clientMessageId(item);
      if (_accepted.contains('$account:$clientId')) continue;
      try {
        final result = await Hubs.conversation.invokeReliable(
          'SendMessageWithClientId',
          [
            cid,
            item.str('content'),
            item.s('type') ?? 'text',
            item.s('replyToMessageId') ?? '',
            item.b('isViewOnce'),
            clientId,
          ],
        );
        if (result is! Map ||
            result.str('id').isEmpty ||
            !belongsToConversation(result, cid) ||
            result.str('clientMessageId') != clientId) {
          throw StateError('Missing durable message acknowledgment');
        }
        await acknowledge(account, {...normalizeMsg(result), 'status': 'sent'});
      } catch (_) {
        if (currentAccount != account) return;
        await enqueue(account, {...item, 'status': 'failed'});
        failures.add((account: account, conversation: cid, clientId: clientId));
      }
    }
  }
}
