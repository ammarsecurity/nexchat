import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../conversations/message_contract.dart';

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
  ChatSession build() { ref.watch(authProvider.select((s) => s.user?.id)); return const ChatSession(); }

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
    if (server.str('sessionId') != state.sessionId || server.str('id').isEmpty) return;
    final id = server.str('id');
    final clientId = clientMessageId(server);
    final existing = state.messages.indexWhere((m) => m.str('id') == id);
    final pending = clientId.isEmpty ? -1 : state.messages.indexWhere((m) =>
        clientMessageId(m) == clientId && m.str('senderId') == server.str('senderId'));
    if (existing < 0 && pending < 0) { addMessage({...server, 'status': 'sent'}); return; }
    final target = existing >= 0 ? existing : pending;
    state = state.copyWith(messages: [
      for (var i = 0; i < state.messages.length; i++)
        if (i == target) {...server, 'status': 'sent', if (state.messages[i]['tempId'] != null) 'tempId': state.messages[i]['tempId']}
        else if (i != pending) state.messages[i],
    ]);
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
