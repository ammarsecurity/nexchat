import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../services/notification_nav.dart';
import '../../shared/widgets.dart';
import 'notifications_controller.dart';

/// views/NotificationsView.vue
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = ref.read(notificationsProvider.notifier);
      ctrl.load();
      Api.get('/user-notifications', query: {'take': 40}).then((data) {
        if (!mounted) return;
        final normalized = asJsonList(data).map(normalizeServerNotification).toList();
        if (normalized.isEmpty) return;
        final seen = ref.read(notificationsProvider).map((x) => '${x['serverId'] ?? x['id']}').toSet();
        for (final n in normalized) {
          if (!seen.contains('${n['serverId']}')) ctrl.add(n);
        }
      }).catchError((_) {});
    });
  }

  String _formatTime(Object? ts) {
    final d = ts == null ? null : DateTime.tryParse('$ts')?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMilliseconds < 60000) return t('connectionHistory.now');
    if (diff.inMilliseconds < 3600000) return t('connectionHistory.minutesAgo', {'n': diff.inMinutes});
    if (diff.inMilliseconds < 86400000) return t('connectionHistory.hoursAgo', {'n': diff.inHours});
    return formatGregorianDateTime(d);
  }

  String _typeLabel(Object? type) => switch (type) {
        'video_call' => t('notifications.typeVideoCall'),
        'code_connected' => t('notifications.typeCode'),
        'conversation_message' || 'message' => t('notifications.typeMessage'),
        'story_published' => t('notifications.typeStory'),
        'message_request' => t('notifications.typeMessageRequest'),
        _ => t('notifications.typeDefault'),
      };

  void _open(Json n) {
    ref.read(notificationsProvider.notifier).markRead('${n['id']}');
    if (n['serverId'] != null) Api.put('/user-notifications/${n['serverId']}/read').catchError((_) {});
    navigateFromNotification(ref, n);
  }

  void _clearAll() {
    ref.read(notificationsProvider.notifier).clear();
    Api.put('/user-notifications/read-all').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = ref.watch(notificationsProvider);
    return ModernPage(
      title: t('settings.notifications'),
      backTo: null,
      actions: [if (list.isNotEmpty) GlassIconButton(icon: LucideIcons.trash2, onTap: _clearAll)],
      scroll: list.isNotEmpty,
      body: list.isEmpty
          ? EmptyState(icon: LucideIcons.bell, text: t('notifications.empty'))
          : Column(children: [
              for (final n in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: n['isRead'] == true ? c.bgCard : c.primarySoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(color: n['isRead'] == true ? c.border : c.primaryMuted),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(n),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                            child: Icon(LucideIcons.bell, size: 22, color: c.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                (n.s('title')?.isNotEmpty ?? false) ? n.s('title')! : _typeLabel(n['type']),
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary),
                              ),
                              if (n.s('body')?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 2),
                                Text(n.s('body')!, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                              ],
                              const SizedBox(height: 4),
                              Text(_formatTime(n['timestamp']), style: TextStyle(fontSize: 11, color: c.textMuted)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
    );
  }
}
