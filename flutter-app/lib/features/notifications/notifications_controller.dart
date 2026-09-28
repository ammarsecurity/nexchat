import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/storage/prefs.dart';
import '../../core/time.dart';
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
    return parseApiDate(raw);
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

  static String? _fingerprint(Json x) {
    final sid = x['serverId'] ?? x['notificationId'];
    if (sid != null && '$sid'.isNotEmpty) return 'srv:$sid';
    final type = '${x['type'] ?? ''}';
    final reqId = '${x['messageRequestId'] ?? ''}';
    if (reqId.isNotEmpty && (type == 'message_request' || type == 'friend_request' || type == 'contact_request')) {
      return 'req:$type|$reqId';
    }
    final conv = '${x['conversationId'] ?? ''}';
    final body = '${x['body'] ?? ''}';
    final title = '${x['title'] ?? ''}';
    final ts = _ts(x);
    // Bucket to the minute so FG receive + tap don't create near-duplicates.
    final bucket = ts == null ? '' : '${ts.toUtc().year}-${ts.toUtc().month}-${ts.toUtc().day}T${ts.toUtc().hour}:${ts.toUtc().minute}';
    if (type.isEmpty && body.isEmpty && title.isEmpty) return null;
    return 'fp:$type|$conv|$title|$body|$bucket';
  }

  /// Stable logical key for upserting (ignores receive-time bucket).
  static String? _logicalKey(Json x) {
    final sid = x['serverId'] ?? x['notificationId'];
    if (sid != null && '$sid'.isNotEmpty) return 'srv:$sid';
    final type = '${x['type'] ?? ''}';
    final reqId = '${x['messageRequestId'] ?? ''}';
    if (reqId.isNotEmpty) return 'req:$type|$reqId';
    final conv = '${x['conversationId'] ?? ''}';
    if (conv.isNotEmpty && (type == 'conversation_message' || type == 'message' || type == 'video_call')) {
      return 'conv:$type|$conv|${x['body'] ?? ''}';
    }
    return null;
  }

  int get unreadCount => state.where((x) => x['isRead'] != true).length;

  void load() {
    state = _sorted(_read());
  }

  void add(Json n) {
    final serverId = n['serverId'] ?? n['notificationId'];
    // Prefer event time from the server. Never invent "now" when we have a
    // server id — delayed OneSignal delivery would otherwise jump to the top.
    final incomingTs = n['timestamp'] ?? n['createdAt'];
    final logical = _logicalKey({...n, 'serverId': ?serverId});
    final existingIdx = logical == null
        ? -1
        : state.indexWhere((x) => _logicalKey(x) == logical);

    if (existingIdx >= 0) {
      final prev = state[existingIdx];
      final prevTs = prev['timestamp'] ?? prev['createdAt'];
      final merged = {
        ...prev,
        ...n,
        'id': prev['id'] ?? (serverId != null ? 'srv-$serverId' : prev['id']),
        'serverId': serverId ?? prev['serverId'],
        // Keep the older/known event time; don't replace with receive-time.
        'timestamp': incomingTs ?? prevTs,
        'isRead': n['isRead'] == true || prev['isRead'] == true,
      };
      final next = [...state];
      next[existingIdx] = merged;
      state = _sorted(next);
      _save();
      return;
    }

    final item = {
      ...n,
      'id': '${n['id'] ?? (serverId != null ? 'srv-$serverId' : DateTime.now().millisecondsSinceEpoch)}',
      'serverId': ?serverId,
      if (incomingTs != null) 'timestamp': incomingTs,
      'isRead': n['isRead'] == true,
    };
    if (state.any((x) => '${x['id']}' == item['id'])) return;
    if (serverId != null && state.any((x) => '${x['serverId']}' == '$serverId')) return;
    final fp = _fingerprint(item);
    if (fp != null && state.any((x) => _fingerprint(x) == fp)) return;
    state = _sorted([item, ...state]).take(100).toList();
    _save();
  }

  /// دمج إشعارات السيرفر مع المحلي. القائمة الفارغة من السيرفر تُسقط المحلي المطابق فقط.
  void mergeServer(List<Json> serverItems) {
    final serverIds = <String>{};
    final merged = <Json>[];
    final prevByServer = <String, Json>{
      for (final x in state)
        if (x['serverId'] != null) '${x['serverId']}': x,
    };

    for (final n in serverItems) {
      final sid = '${n['serverId'] ?? n['id']}';
      serverIds.add(sid);
      final prev = prevByServer[sid];
      // Server timestamps win — they are event time, not push delivery time.
      merged.add(prev == null
          ? n
          : {
              ...prev,
              ...n,
              'id': prev['id'] ?? n['id'],
              'serverId': sid,
              'timestamp': n['timestamp'] ?? n['createdAt'] ?? prev['timestamp'],
            });
    }

    final serverLogical = merged.map(_logicalKey).whereType<String>().toSet();
    final serverFps = merged.map(_fingerprint).whereType<String>().toSet();
    final localOnly = state.where((x) {
      if (x['serverId'] != null) return false;
      final logical = _logicalKey(x);
      if (logical != null && serverLogical.contains(logical)) return false;
      final fp = _fingerprint(x);
      if (fp != null && serverFps.contains(fp)) return false;
      return true;
    });

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
    'timestamp': x['createdAt'] ?? extra['createdAt'],
    'isRead': x['isRead'] == true,
    'avatar': nav['callerAvatar'] ?? nav['requesterAvatar'] ?? extra['avatar'] ?? extra['senderAvatar'] ?? extra['publisherAvatar'],
    'actorName': nav['callerName'] ?? nav['requesterName'] ?? extra['senderName'] ?? extra['publisherName'] ?? x['title'],
  };
}
