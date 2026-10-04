import 'dart:convert';
import 'dart:math';

import '../../core/json.dart';

/// Persist this identity with the optimistic row and reuse it for every retry.
String newClientMessageId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String clientMessageId(Json message) =>
    message.s('clientMessageId') ?? message.s('tempId') ?? '';

bool belongsToConversation(Map payload, String conversationId) =>
    payload.str('conversationId').toLowerCase() == conversationId.toLowerCase();

Json normalizeMsg(Map<dynamic, dynamic> m) => {
  'id': m.s('id'),
  'conversationId': m.s('conversationId'),
  'clientMessageId': m.s('clientMessageId'),
  'senderId': m.s('senderId'),
  'content': m.s('content'),
  'type': m.s('type') ?? 'text',
  'sentAt': m.s('sentAt'),
  'deletedForEveryone': m.b('deletedForEveryone'),
  'isRead': m.b('isRead'),
  'replyToMessageId': m.s('replyToMessageId'),
  'replyToContent': (m.b('replyToUnavailable') || (m.date('replyToExpiresAt') != null && !m.date('replyToExpiresAt')!.isAfter(DateTime.now().toUtc()))) ? 'الرسالة غير متاحة' : m.s('replyToContent'),
  'replyToSenderName': m.s('replyToSenderName'),
  'replyToType': m.s('replyToType'),
      'replyToExpiresAt': m.s('replyToExpiresAt'),
  'senderName': m.s('senderName'),
  'senderAvatar': m.s('senderAvatar'),
  'reactions': m.v('reactions') ?? const [],
  'myReaction': m.s('myReaction'),
  'disappearMode': m.i('disappearMode'),
  'expiresAt': m.s('expiresAt'),
  'isViewOnce': m.b('isViewOnce'),
  'viewOnceOpened': m.b('viewOnceOpened'),
};

bool messageIsExpired(Json m, [DateTime? now]) {
  final at = m.date('expiresAt');
  return at != null && !at.isAfter(now ?? DateTime.now().toUtc());
}

Json redactReply(Json message, Set<String> unavailable) =>
    unavailable.contains(message.str('replyToMessageId'))
    ? {
        ...message,
        'replyToContent': 'الرسالة غير متاحة',
        'replyToSenderName': null,
        'replyToType': 'unavailable',
      }
    : message;

List<Json> withoutExpiredMessages(List<Json> messages) {
  final now = DateTime.now().toUtc();
  final expired = {
    for (final m in messages) if (messageIsExpired(m, now)) m.str('id'),
    for (final m in messages)
      if (m.date('replyToExpiresAt') != null && !m.date('replyToExpiresAt')!.isAfter(now)) m.str('replyToMessageId'),
  };
  return [for (final m in messages) if (!messageIsExpired(m, now)) redactReply(m, expired)];
}

/// Copy only the text that is rendered, never a media URL or serialized payload.
String? copyableMessageText(Json message) {
  if (message.b('deletedForEveryone') ||
      message.b('isViewOnce') ||
      message.b('restricted') ||
      messageIsExpired(message)) {
    return null;
  }
  final type = message.s('type') ?? 'text';
  final content = message.s('content') ?? '';
  if (type == 'text') return content.trim().isEmpty ? null : content;
  if (type == 'story_share' || type == 'story_reply') {
    try {
      final payload = jsonDecode(content);
      if (payload is! Map) return null;
      final text = payload.s(type == 'story_reply' ? 'text' : 'caption');
      return text == null || text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// SignalR binds exact arity, including optional values: all six arguments matter.
List<Object> conversationSendArguments(String conversation, String content, String type,
        String replyId, bool viewOnce, String clientId) =>
    [conversation, content, type, replyId, viewOnce, clientId];
