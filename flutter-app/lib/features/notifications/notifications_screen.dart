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

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final ctrl = ref.read(notificationsProvider.notifier);
    ctrl.load();
    try {
      final data = await Api.get('/user-notifications', query: {'take': 60});
      if (!mounted) return;
      final normalized = asJsonList(data).map(normalizeServerNotification).toList();
      ctrl.mergeServer(normalized);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(Object? ts) {
    final d = parseApiDate(ts);
    return formatRelative(d);
  }

  String _typeLabel(Object? type) => switch (type) {
        'video_call' => t('notifications.typeVideoCall'),
        'code_connected' => t('notifications.typeCode'),
        'conversation_message' || 'message' => t('notifications.typeMessage'),
        'story_published' || 'story_like' || 'story_liked' => t('notifications.typeStory'),
        'message_request' => t('notifications.typeMessageRequest'),
        'friend_request' || 'contact_request' => t('notifications.typeFriendRequest'),
        'broadcast' || 'system' => t('notifications.typeSystem'),
        _ => t('notifications.typeDefault'),
      };

  _NotifStyle _styleFor(Object? type) {
    switch (type) {
      case 'message_request':
      case 'friend_request':
      case 'contact_request':
      case 'code_connected':
        return const _NotifStyle(
          accent: Color(0xFF3B82F6),
          soft: Color(0xFFE8F1FF),
          typeIcon: LucideIcons.users,
          badgeIcon: LucideIcons.userPlus,
          badgeBg: Color(0xFF3B82F6),
        );
      case 'conversation_message':
      case 'message':
        return const _NotifStyle(
          accent: Color(0xFF22C55E),
          soft: Color(0xFFE8F8EF),
          typeIcon: LucideIcons.messageCircle,
          badgeIcon: LucideIcons.messageCircle,
          badgeBg: Color(0xFF22C55E),
        );
      case 'story_published':
      case 'story_like':
      case 'story_liked':
        return const _NotifStyle(
          accent: Color(0xFFEF4444),
          soft: Color(0xFFFDE8EC),
          typeIcon: LucideIcons.heart,
          badgeIcon: LucideIcons.heart,
          badgeBg: Color(0xFFEC4899),
          storyRing: true,
        );
      case 'video_call':
        return const _NotifStyle(
          accent: Color(0xFF3B82F6),
          soft: Color(0xFFE8F1FF),
          typeIcon: LucideIcons.video,
          badgeIcon: LucideIcons.phone,
          badgeBg: Color(0xFF3B82F6),
        );
      default:
        return const _NotifStyle(
          accent: Color(0xFF3B82F6),
          soft: Color(0xFFE8F1FF),
          typeIcon: LucideIcons.bell,
          badgeIcon: LucideIcons.rocket,
          badgeBg: Color(0xFF3B82F6),
          systemLeading: true,
        );
    }
  }

  Future<void> _open(Json n) async {
    ref.read(notificationsProvider.notifier).markRead('${n['id']}');
    final sid = n['serverId'];
    if (sid != null) Api.put('/user-notifications/$sid/read').catchError((_) {});
    await navigateFromNotification(ref, n);
  }

  Future<void> _markAllRead() async {
    final list = ref.read(notificationsProvider);
    if (list.isEmpty || list.every((n) => n['isRead'] == true)) return;
    try {
      await Api.put('/user-notifications/read-all');
      ref.read(notificationsProvider.notifier).markAllRead();
      if (mounted) showToast(context, t('notifications.markedAllRead'), success: true);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  Future<void> _deleteOne(Json n) async {
    final ok = await confirmDialog(
      context,
      title: t('notifications.deleteOneTitle'),
      message: t('notifications.deleteOneText'),
      confirm: t('common.delete'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok || !mounted) return;
    final sid = n['serverId'];
    try {
      if (sid != null) await Api.delete('/user-notifications/$sid');
      ref.read(notificationsProvider.notifier).remove('${n['id']}');
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  Future<void> _deleteAll() async {
    final list = ref.read(notificationsProvider);
    if (list.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: t('notifications.deleteAllTitle'),
      message: t('notifications.deleteAllText'),
      confirm: t('notifications.deletePermanently'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await Api.delete('/user-notifications');
      ref.read(notificationsProvider.notifier).clear();
      if (mounted) showToast(context, t('notifications.deletedAll'), success: true);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  String? _avatarOf(Json n) =>
      n.s('avatar') ?? n.s('callerAvatar') ?? n.s('requesterAvatar') ?? n.s('senderAvatar') ?? n.s('publisherAvatar');

  String _nameOf(Json n) {
    final actor = n.s('actorName') ?? n.s('callerName') ?? n.s('requesterName') ?? n.s('senderName');
    if (actor != null && actor.isNotEmpty) return actor;
    final title = n.s('title');
    if (title != null && title.isNotEmpty) return title;
    return _typeLabel(n['type']);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = ref.watch(notificationsProvider);
    final unread = list.where((n) => n['isRead'] != true).length;

    return ModernPage(
      title: t('notifications.title'),
      backTo: null,
      actions: [
        if (list.isNotEmpty) ...[
          if (unread > 0) ...[
            GlassIconButton(icon: LucideIcons.checkCheck, color: c.primary, onTap: _markAllRead),
            const SizedBox(width: 8),
          ],
          GlassIconButton(icon: LucideIcons.trash2, color: c.danger, onTap: _deleteAll),
        ],
      ],
      scroll: false,
      padding: EdgeInsets.zero,
      body: _loading && list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? EmptyState(icon: LucideIcons.bell, text: t('notifications.empty'))
              : RefreshIndicator(
                  color: c.primary,
                  onRefresh: _refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final n = list[i];
                      final style = _styleFor(n['type']);
                      final unreadItem = n['isRead'] != true;
                      return Dismissible(
                        key: ValueKey('notif-${n['id']}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await _deleteOne(n);
                          return false;
                        },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsetsDirectional.only(end: 20),
                          decoration: BoxDecoration(
                            color: c.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(LucideIcons.trash2, color: c.danger, size: 22),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _NotificationCard(
                            title: (n.s('title')?.isNotEmpty ?? false) ? n.s('title')! : _typeLabel(n['type']),
                            body: n.s('body') ?? '',
                            time: _formatTime(n['timestamp']),
                            unread: unreadItem,
                            style: style,
                            avatarUrl: _avatarOf(n),
                            avatarName: _nameOf(n),
                            onTap: () => _open(n),
                            onLongPress: () => _deleteOne(n),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotifStyle {
  const _NotifStyle({
    required this.accent,
    required this.soft,
    required this.typeIcon,
    required this.badgeIcon,
    required this.badgeBg,
    this.storyRing = false,
    this.systemLeading = false,
  });

  final Color accent;
  final Color soft;
  final IconData typeIcon;
  final IconData badgeIcon;
  final Color badgeBg;
  final bool storyRing;
  final bool systemLeading;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
    required this.style,
    required this.avatarName,
    required this.onTap,
    required this.onLongPress,
    this.avatarUrl,
  });

  final String title;
  final String body;
  final String time;
  final bool unread;
  final _NotifStyle style;
  final String avatarName;
  final String? avatarUrl;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget leading;
    if (style.systemLeading) {
      leading = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [style.accent, style.accent.withValues(alpha: 0.75)]),
          boxShadow: [BoxShadow(color: style.accent.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: const Icon(LucideIcons.rocket, color: Colors.white, size: 24),
      );
    } else {
      Widget avatar = UserAvatar(url: avatarUrl, name: avatarName, size: 56);
      if (style.storyRing) {
        avatar = Container(
          padding: const EdgeInsets.all(2.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFFF472B6), Color(0xFFEC4899), Color(0xFFEF4444)],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.bgCard),
            child: avatar,
          ),
        );
      }
      leading = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          PositionedDirectional(
            bottom: -1,
            end: -1,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: style.badgeBg,
                shape: BoxShape.circle,
                border: Border.all(color: c.bgCard, width: 2),
                boxShadow: [BoxShadow(color: style.badgeBg.withValues(alpha: 0.35), blurRadius: 6)],
              ),
              child: Icon(style.badgeIcon, size: 11, color: Colors.white),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: unread ? Color.alphaBlend(style.soft.withValues(alpha: 0.55), c.bgCard) : c.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: unread ? style.accent.withValues(alpha: 0.16) : c.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0F0F172A), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: style.soft, shape: BoxShape.circle),
                  child: Icon(style.typeIcon, size: 20, color: style.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsetsDirectional.only(start: 8),
                              decoration: BoxDecoration(color: style.accent, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.45),
                        ),
                      ],
                      if (time.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(time, style: TextStyle(fontSize: 11, color: c.textMuted, fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                leading,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
