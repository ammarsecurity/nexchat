import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';

/// stores/chat.js — the random / code-connect chat session.
class ChatSession {
  const ChatSession({this.sessionId, this.partner, this.messages = const [], this.partnerTyping = false});
  final String? sessionId;
  final Json? partner;
  final List<Json> messages;
  final bool partnerTyping;

  ChatSession copyWith({String? sessionId, Json? partner, List<Json>? messages, bool? partnerTyping}) => ChatSession(
        sessionId: sessionId ?? this.sessionId,
        partner: partner ?? this.partner,
        messages: messages ?? this.messages,
        partnerTyping: partnerTyping ?? this.partnerTyping,
      );
}

class ChatSessionController extends Notifier<ChatSession> {
  @override
  ChatSession build() => const ChatSession();

  ChatSession get current => state;

  void setSession(String? sessionId, Json? partner) => state = ChatSession(sessionId: sessionId, partner: partner);

  void setSessionId(String sessionId) => state = state.copyWith(sessionId: sessionId);

  void setPartner(Json? partner) => state = state.copyWith(partner: partner);

  void addMessage(Json msg) {
    final id = msg['id'];
    if (id != null && state.messages.any((m) => m['id'] != null && '${m['id']}' == '$id')) return;
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  void setMessages(List<Json> list) => state = state.copyWith(messages: list);

  void setTyping(bool v) => state = state.copyWith(partnerTyping: v);

  void updateMessage(String tempId, Json updates) => state = state.copyWith(
        messages: [for (final m in state.messages) m['tempId'] == tempId ? {...m, ...updates} : m],
      );

  void updatePendingMessage(Json server) {
    final type = server.s('type') ?? 'text';
    final sender = server.str('senderId');
    final media = type == 'audio' || type == 'image' || type == 'video' || type == 'album';
    final list = [...state.messages];
    var idx = list.indexWhere((m) {
      if (m['status'] != 'pending' || (m['type'] ?? 'text') != type) return false;
      if ('${m['senderId'] ?? ''}' != sender) return false;
      if (media) return true;
      return m['content'] == server.v('content');
    });
    if (idx < 0) {
      idx = list.indexWhere((m) => m['status'] == 'pending' && (m['type'] ?? 'text') == type && '${m['senderId'] ?? ''}' == sender);
    }
    if (idx < 0) return;
    list[idx] = {...server, 'status': 'sent'};
    state = state.copyWith(messages: list);
  }

  void clear() => state = const ChatSession();

  void patchPartnerFromBroadcast(String userId, String? avatar, String? uniqueCode) {
    final p = state.partner;
    if (p == null) return;
    final pid = p.s('id') ?? p.s('userId') ?? '';
    if (pid == userId || (uniqueCode != null && uniqueCode.isNotEmpty && p.s('uniqueCode') == uniqueCode)) {
      state = state.copyWith(partner: {...p, 'avatar': avatar});
    }
  }
}

final chatSessionProvider = NotifierProvider<ChatSessionController, ChatSession>(ChatSessionController.new);
