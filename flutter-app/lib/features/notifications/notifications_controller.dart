import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/storage/prefs.dart';
import '../../services/push_service.dart';

/// stores/notifications.js — local notification centre persisted under `nexchat_notifications`.
class NotificationsController extends Notifier<List<Json>> {
  @override
  List<Json> build() => _sorted(_read());

  List<Json> _read() {
    try {
      return asJsonList(jsonDecode(Prefs.instance.getString(Keys.notifications) ?? '[]'));
    } catch (_) {
      return [];
    }
  }

  void _save() => Prefs.instance.setString(Keys.notifications, jsonEncode(state));

  static DateTime? _ts(Json x) {
    final raw = x['timestamp'] ?? x['createdAt'];
    if (raw == null) return null;
    return DateTime.tryParse('$raw');
  }

  static List<Json> _sorted(List<Json> list) {
    final copy = [...list];
    copy.sort((a, b) {
      final at = _ts(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = _ts(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return copy;
  }

  int get unreadCount => state.where((x) => x['isRead'] != true).length;

  void load() {
    state = _sorted(_read());
  }

  void add(Json n) {
    final item = {...n, 'id': '${n['id'] ?? DateTime.now().millisecondsSinceEpoch}', 'isRead': n['isRead'] == true};
    if (state.any((x) => '${x['id']}' == item['id'])) return;
    final serverId = item['serverId'];
    if (serverId != null && state.any((x) => '${x['serverId']}' == '$serverId')) return;
    state = _sorted([item, ...state]).take(100).toList();
    _save();
  }

  /// دمج إشعارات السيرفر مع المحلي، مع حذف ما لم يعد موجوداً على السيرفر.
  void mergeServer(List<Json> serverItems) {
    final localOnly = state.where((x) => x['serverId'] == null).toList();
    final prevByServer = <String, Json>{
      for (final x in state)
        if (x['serverId'] != null) '${x['serverId']}': x,
    };

    final merged = <Json>[];
    for (final n in serverItems) {
      final sid = '${n['serverId'] ?? n['id']}';
      final prev = prevByServer[sid];
      merged.add(prev == null ? n : {...prev, ...n, 'id': prev['id'] ?? n['id']});
    }

    state = _sorted([...merged, ...localOnly]).take(100).toList();
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

  void remove(String id) {
    state = state.where((x) => '${x['id']}' != id).toList();
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
    'avatar': nav['callerAvatar'] ?? nav['requesterAvatar'] ?? extra['avatar'] ?? extra['senderAvatar'] ?? extra['publisherAvatar'],
    'actorName': nav['callerName'] ?? nav['requesterName'] ?? extra['senderName'] ?? extra['publisherName'] ?? x['title'],
  };
}
