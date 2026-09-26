import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';

/// Mirrors stores/conversationsList.js.
class ConversationsListController extends Notifier<List<Json>> {
  @override
  List<Json> build() => [];

  void setList(List<Json> items) => state = List.of(items);

  void appendList(List<Json> items) {
    if (items.isEmpty) return;
    final seen = {for (final c in state) c.str('id')};
    final added = [for (final c in items) if (seen.add(c.str('id'))) c];
    if (added.isEmpty) return;
    state = [...state, ...added];
  }

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

  void updatePartnerOnlineByUserId(String userId, bool isOnline) {
    state = state.map((c) {
      if (c.b('isGroup') || c.str('partnerId') != userId) return c;
      return {...c, 'partnerIsOnline': isOnline, 'PartnerIsOnline': isOnline};
    }).toList();
  }

  /// Soft refresh after network restore (keeps current list on failure).
  /// Omits `page` so API returns the full list (legacy shape) and does not drop loaded pages.
  Future<void> refreshSilently() async {
    if (!NetworkStatus.online.value) return;
    try {
      final data = await Api.get('/conversations', query: {'filter': 'all'}, skipUnauthorized: true);
      state = asJsonList(data);
    } catch (_) {}
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
