import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';

class ActiveConversation {
  const ActiveConversation({
    this.conversationId,
    this.partner,
    this.isGroup = false,
    this.messages = const [],
    this.partnerTyping = false,
    this.partnerLastReadAt,
  });

  final String? conversationId;
  final Json? partner;
  final bool isGroup;
  final List<Json> messages;
  final bool partnerTyping;
  final DateTime? partnerLastReadAt;

  ActiveConversation copyWith({
    Json? partner,
    List<Json>? messages,
    bool? partnerTyping,
    DateTime? partnerLastReadAt,
  }) =>
      ActiveConversation(
        conversationId: conversationId,
        partner: partner ?? this.partner,
        isGroup: isGroup,
        messages: messages ?? this.messages,
        partnerTyping: partnerTyping ?? this.partnerTyping,
        partnerLastReadAt: partnerLastReadAt ?? this.partnerLastReadAt,
      );
}

String msgId(Json m) => m.str('id');

/// stores/conversation.js
class ActiveConversationController extends Notifier<ActiveConversation> {
  @override
  ActiveConversation build() => const ActiveConversation();

  void setConversation(String id, Json? partner, {bool isGroup = false}) =>
      state = ActiveConversation(conversationId: id, partner: partner, isGroup: isGroup);

  void setConversationAndMessages(String id, Json? partner, {bool isGroup = false, required List<Json> messages}) =>
      state = ActiveConversation(conversationId: id, partner: partner, isGroup: isGroup, messages: List.of(messages));

  void clear() => state = const ActiveConversation();

  void setPartner(Json? partner) => state = state.copyWith(partner: partner);

  void setMessages(List<Json> msgs) => state = state.copyWith(messages: List.of(msgs));

  void prependMessages(List<Json> older) => state = state.copyWith(messages: [...older, ...state.messages]);

  void addMessage(Json m) => state = state.copyWith(messages: [...state.messages, m]);

  void setTyping(bool v) => state = state.copyWith(partnerTyping: v);

  void setPartnerLastReadAt(DateTime? at) => state = state.copyWith(partnerLastReadAt: at);

  void setMessagesRead(Iterable<String> ids) {
    final set = ids.toSet();
    state = state.copyWith(messages: [for (final m in state.messages) set.contains(msgId(m)) ? {...m, 'isRead': true} : m]);
  }

  void updateByTempId(String tempId, Json updates) {
    state = state.copyWith(messages: [for (final m in state.messages) m['tempId'] == tempId ? {...m, ...updates} : m]);
  }

  void updateById(String id, Json updates) {
    state = state.copyWith(messages: [for (final m in state.messages) msgId(m) == id ? {...m, ...updates} : m]);
  }

  void removeMessage(String id) => state = state.copyWith(messages: state.messages.where((m) => msgId(m) != id).toList());

  void removeByTempId(String tempId) => state = state.copyWith(messages: state.messages.where((m) => m['tempId'] != tempId).toList());

  void setDeletedForEveryone(String id) => updateById(id, {'deletedForEveryone': true});

  void updateReactions(String id, List<dynamic> reactions) => updateById(id, {'reactions': reactions});

  void applyOptimisticReaction(String messageId, String userId, String emoji) {
    final idx = state.messages.indexWhere((m) => msgId(m) == messageId);
    if (idx < 0) return;
    final m = state.messages[idx];
    final list = [
      for (final r in (m['reactions'] as List? ?? const []))
        if (r is Map)
          {
            'emoji': r.str('emoji'),
            'count': r.i('count'),
            'userIds': [for (final u in (r.v('userIds') as List? ?? const [])) '$u'],
          },
    ];
    final wasMine = list.any((r) => r['emoji'] == emoji && (r['userIds'] as List).contains(userId));
    final withoutMe = <Map<String, dynamic>>[];
    for (final r in list) {
      final ids = List<String>.from(r['userIds'] as List);
      if (ids.remove(userId)) {
        final n = (r['count'] as int) - 1;
        if (n > 0) withoutMe.add({...r, 'count': n, 'userIds': ids});
      } else {
        withoutMe.add(r);
      }
    }
    List<Map<String, dynamic>> next = withoutMe;
    if (!wasMine) {
      var found = false;
      next = [
        for (final r in withoutMe)
          if (r['emoji'] == emoji)
            (() {
              found = true;
              return {...r, 'count': (r['count'] as int) + 1, 'userIds': [...r['userIds'] as List, userId]};
            })()
          else
            r,
      ];
      if (!found) next.add({'emoji': emoji, 'count': 1, 'userIds': [userId]});
    }
    updateById(messageId, {'reactions': next});
  }

  /// Replace a pending optimistic message with the server echo.
  bool updatePendingMessage(Json server) {
    final type = server.s('type') ?? 'text';
    final sender = server.str('senderId');
    final reply = server.s('replyToMessageId') ?? '';
    final media = type == 'audio' || type == 'image' || type == 'video' || type == 'album';
    final idx = state.messages.indexWhere((m) {
      if (m['status'] != 'pending' || m.str('senderId') != sender || (m.s('type') ?? 'text') != type) return false;
      if (media) return true;
      if (m.s('content') == server.s('content')) return true;
      return (m.s('replyToMessageId') ?? '') == reply;
    });
    if (idx < 0) return false;
    final list = List<Json>.of(state.messages);
    list[idx] = {...server, 'status': 'sent', if (list[idx]['tempId'] != null) 'tempId': list[idx]['tempId']};
    state = state.copyWith(messages: list);
    return true;
  }

  void patchPartnerAvatar(String userId, String? avatar, [String? uniqueCode]) {
    final p = state.partner;
    if (p == null || state.isGroup) return;
    final byCode = uniqueCode != null && uniqueCode.isNotEmpty && p.s('uniqueCode') == uniqueCode;
    if ((p.s('id') ?? p.s('userId')) == userId || byCode) state = state.copyWith(partner: {...p, 'avatar': avatar});
  }
}

final activeConversationProvider = NotifierProvider<ActiveConversationController, ActiveConversation>(ActiveConversationController.new);
