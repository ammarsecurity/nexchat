import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/storage/prefs.dart';
import '../../services/push_service.dart';

/// stores/notifications.js — local notification centre persisted under `nexchat_notifications`.
class NotificationsController extends Notifier<List<Json>> {
  @override
  List<Json> build() => _read();

  List<Json> _read() {
    try {
      return asJsonList(jsonDecode(Prefs.instance.getString(Keys.notifications) ?? '[]'));
    } catch (_) {
      return [];
    }
  }

  void _save() => Prefs.instance.setString(Keys.notifications, jsonEncode(state));

  int get unreadCount => state.where((x) => x['isRead'] != true).length;

  void load() {
    final next = _read();
    if (next.length == state.length &&
        (next.isEmpty || identical(next, state) || '${next.first['id']}' == '${state.first['id']}')) {
      return;
    }
    state = next;
  }

  void add(Json n) {
    final item = {...n, 'id': '${n['id'] ?? DateTime.now().millisecondsSinceEpoch}', 'isRead': n['isRead'] == true};
    if (state.any((x) => '${x['id']}' == item['id'])) return;
    state = [item, ...state].take(100).toList();
    _save();
  }

  void markRead(String id) {
    state = [for (final x in state) '${x['id']}' == id ? {...x, 'isRead': true} : x];
    _save();
  }

  void markAllRead() {
    state = [for (final x in state) {...x, 'isRead': true}];
    _save();
  }

  void clear() {
    state = [];
    Prefs.instance.setString(Keys.notifications, null);
  }
}

final notificationsProvider = NotifierProvider<NotificationsController, List<Json>>(NotificationsController.new);
final unreadNotificationsProvider = Provider<int>((ref) => ref.watch(notificationsProvider).where((x) => x['isRead'] != true).length);

/// normalizeServerNotification()
Json normalizeServerNotification(Json x) {
  Map<String, dynamic> extra = {};
  final dj = x['dataJson'];
  if (dj is String) {
    try {
      extra = Map<String, dynamic>.from(jsonDecode(dj) as Map);
    } catch (_) {}
  } else if (dj is Map) {
    extra = Map<String, dynamic>.from(dj);
  }
  final nav = parseNotificationData({...extra, ...x});
  return {
    ...nav,
    'id': 'srv-${x['id']}',
    'serverId': x['id'],
    'type': x['type'] ?? nav['type'],
    'title': x['title'],
    'body': x['body'],
    'timestamp': x['createdAt'],
    'isRead': x['isRead'] == true,
  };
}
