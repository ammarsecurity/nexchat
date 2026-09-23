import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';

/// Mirrors stores/conversationsList.js.
class ConversationsListController extends Notifier<List<Json>> {
  @override
  List<Json> build() => [];

  void setList(List<Json> items) => state = List.of(items);

  bool updateConversation(String conversationId, Json updates, {bool incrementUnread = false}) {
    final list = List<Json>.of(state);
    final idx = list.indexWhere((c) => c.str('id') == conversationId);
    if (idx < 0) return false;
    final item = {...list[idx], ...updates};
    if (incrementUnread) {
      final n = item.i('unreadCount') + 1;
      item['unreadCount'] = n;
      item['UnreadCount'] = n;
    }
    final hasNew = updates['lastMessageAt'] != null || updates['LastMessageAt'] != null;
    if (hasNew) {
      list.removeAt(idx);
      list.insert(0, item);
    } else {
      list[idx] = item;
    }
    list.sort((a, b) {
      final ap = a.b('isPinned'), bp = b.b('isPinned');
      if (ap != bp) return bp ? 1 : -1;
      final ta = a.date('lastMessageAt') ?? DateTime(0), tb = b.date('lastMessageAt') ?? DateTime(0);
      return tb.compareTo(ta);
    });
    state = list;
    return true;
  }

  void removeConversation(String id) => state = state.where((c) => c.str('id') != id).toList();

  void updatePartnerAvatarByUserId(String userId, String? avatar) {
    state = state.map((c) {
      if (c.b('isGroup') || c.str('partnerId') != userId) return c;
      return {...c, 'partnerAvatar': avatar, 'PartnerAvatar': avatar};
    }).toList();
  }
}

final conversationsListProvider = NotifierProvider<ConversationsListController, List<Json>>(ConversationsListController.new);

final totalUnreadProvider = Provider<int>((ref) => ref.watch(conversationsListProvider).fold(0, (sum, c) => sum + c.i('unreadCount')));

/// Mirrors stores/messageRequests.js.
class PendingRequestsController extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> fetch() async {
    if (!NetworkStatus.online.value) return;
    try {
      final data = await Api.get('/message-requests/pending-count', skipUnauthorized: true);
      state = data is num ? data.toInt() : int.tryParse('$data') ?? 0;
    } catch (_) {}
  }

  void set(int n) => state = n;
}

final pendingRequestsProvider = NotifierProvider<PendingRequestsController, int>(PendingRequestsController.new);
