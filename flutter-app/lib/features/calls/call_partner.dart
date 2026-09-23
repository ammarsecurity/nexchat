import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../chat/chat_session.dart';
import '../conversations/active_conversation.dart';
import 'call_state.dart';

class CallPartner {
  const CallPartner({this.name = '', this.avatar, this.userId});
  final String name;
  final String? avatar;
  final String? userId;
}

/// `partner` / `partnerUserIdForCall` in VideoCallView.vue: open conversation, then call meta, then random-chat partner.
CallPartner resolveCallPartner(WidgetRef ref, String sessionId) {
  final conv = ref.read(activeConversationProvider);
  if (conv.conversationId == sessionId && conv.partner != null) {
    final p = conv.partner!;
    return CallPartner(name: p.str('name'), avatar: p.s('avatar'), userId: p.s('id') ?? p.s('userId'));
  }
  final ac = ref.read(activeCallProvider);
  if (ac.sessionId == sessionId && (ac.partnerName.isNotEmpty || ac.partnerAvatar != null)) {
    return CallPartner(name: ac.partnerName.isNotEmpty ? ac.partnerName : '…', avatar: ac.partnerAvatar, userId: ac.partnerUserId);
  }
  final chat = ref.read(chatSessionProvider);
  final p = chat.partner;
  if (p == null) return CallPartner(userId: ac.partnerUserId);
  return CallPartner(
    name: p.str('name'),
    avatar: p.s('avatar'),
    userId: chat.sessionId == sessionId ? (p.s('id') ?? p.s('userId')) : ac.partnerUserId,
  );
}
