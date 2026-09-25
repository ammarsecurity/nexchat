import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/widgets.dart';
import 'conversations_list_controller.dart';

/// طلبات الصداقة: واردة (للموافقة) وصادرة (بانتظار الرد).
class MessageRequestsPanel extends ConsumerStatefulWidget {
  const MessageRequestsPanel({super.key, this.notice});
  final String? notice;

  @override
  ConsumerState<MessageRequestsPanel> createState() => _MessageRequestsPanelState();
}

class _MessageRequestsPanelState extends ConsumerState<MessageRequestsPanel> {
  bool _loading = true;
  String _tab = 'incoming';
  List<Json> _incoming = [];
  List<Json> _outgoing = [];
  String? _actionId;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _applyNotice(widget.notice);
    _fetch();
  }

  @override
  void didUpdateWidget(MessageRequestsPanel old) {
    super.didUpdateWidget(old);
    if (widget.notice != old.notice) setState(() => _applyNotice(widget.notice));
  }

  void _applyNotice(String? n) {
    if (n == 'outgoing-wait') {
      _banner = 'wait';
      _tab = 'outgoing';
    }
    if (n == 'outgoing-share-wait') {
      _banner = 'share';
      _tab = 'outgoing';
    }
  }

  Future<void> _fetch() async {
    if (!NetworkStatus.online.value) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final pending = ref.read(pendingRequestsProvider.notifier);
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.get('/message-requests'),
        Api.get('/message-requests/outgoing'),
      ]);
      _incoming = asJsonList(results[0]);
      _outgoing = asJsonList(results[1]);
    } catch (_) {
      _incoming = [];
      _outgoing = [];
    }
    if (!mounted) return;
    setState(() => _loading = false);
    await pending.fetch();
  }

  Future<void> _act(String id, String action, {required bool incoming}) async {
    if (_actionId != null) return;
    if (!NetworkStatus.online.value) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    final pending = ref.read(pendingRequestsProvider.notifier);
    setState(() => _actionId = id);
    try {
      await Api.post('/message-requests/$id/$action', {});
      if (!mounted) return;
      setState(() {
        if (incoming) {
          _incoming.removeWhere((x) => x.str('id') == id);
        } else {
          _outgoing.removeWhere((x) => x.str('id') == id);
        }
      });
      await pending.fetch();
      if (!mounted) return;
      final msg = switch (action) {
        'accept' => t('messageRequests.acceptedToast'),
        'decline' => t('messageRequests.declinedToast'),
        'cancel' => t('messageRequests.cancelledToast'),
        _ => null,
      };
      if (msg != null) showToast(context, msg);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _tab == 'incoming' ? _incoming : _outgoing;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, tabScrollPadding(context, extra: 16)),
        children: [
          _IntroCard(c: c),
          if (_banner != null) ...[
            const SizedBox(height: 10),
            _Banner(
              text: _banner == 'share'
                  ? t('messageRequests.waitingForAcceptCannotShare')
                  : t('messageRequests.waitingForAcceptFromOther'),
              onDismiss: () => setState(() => _banner = null),
            ),
          ],
          const SizedBox(height: 14),
          _SegmentTabs(
            tab: _tab,
            incomingCount: _incoming.length,
            outgoingCount: _outgoing.length,
            onChanged: (v) => setState(() => _tab = v),
          ),
          const SizedBox(height: 8),
          Text(
            _tab == 'incoming' ? t('messageRequests.incomingHint') : t('messageRequests.outgoingHint'),
            style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary),
          ),
          const SizedBox(height: 14),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted, fontSize: 15))),
            )
          else if (list.isEmpty)
            _Empty(
              icon: _tab == 'incoming' ? LucideIcons.userPlus : LucideIcons.send,
              title: _tab == 'incoming' ? t('messageRequests.emptyIncoming') : t('messageRequests.emptyOutgoing'),
              subtitle: _tab == 'incoming' ? t('messageRequests.emptyIncomingHint') : t('messageRequests.emptyOutgoingHint'),
            )
          else if (_tab == 'incoming')
            for (final r in _incoming)
              _IncomingCard(
                item: r,
                busy: _actionId == r.str('id'),
                onAccept: () => _act(r.str('id'), 'accept', incoming: true),
                onDecline: () => _act(r.str('id'), 'decline', incoming: true),
                onOpenProfile: () {
                  final uid = r.s('requesterId');
                  if (uid != null && uid.isNotEmpty) context.push('/profile/$uid');
                },
              )
          else
            for (final r in _outgoing)
              _OutgoingCard(
                item: r,
                busy: _actionId == r.str('id'),
                onCancel: () => _act(r.str('id'), 'cancel', incoming: false),
                onOpenProfile: () {
                  final uid = r.s('targetId');
                  if (uid != null && uid.isNotEmpty) context.push('/profile/$uid');
                },
              ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.primary.withValues(alpha: 0.18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(LucideIcons.users, size: 20, color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('messageRequests.title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
            const SizedBox(height: 4),
            Text(t('messageRequests.intro'), style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onDismiss});
  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(LucideIcons.info, size: 18, color: c.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textPrimary))),
        GestureDetector(
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(LucideIcons.x, size: 16, color: c.textMuted),
          ),
        ),
      ]),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.tab,
    required this.incomingCount,
    required this.outgoingCount,
    required this.onChanged,
  });

  final String tab;
  final int incomingCount;
  final int outgoingCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget chip(String id, String label, int count, IconData icon) {
      final active = tab == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? c.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 15, color: active ? Colors.white : c.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : c.textSecondary),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Colors.white.withValues(alpha: 0.22) : c.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: active ? Colors.white : c.danger),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        chip('incoming', t('messageRequests.incomingTab'), incomingCount, LucideIcons.inbox),
        const SizedBox(width: 4),
        chip('outgoing', t('messageRequests.outgoingTab'), outgoingCount, LucideIcons.send),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: c.bgElevated, shape: BoxShape.circle, border: Border.all(color: c.border)),
          child: Icon(icon, size: 28, color: c.textMuted),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.5, color: c.textSecondary)),
      ]),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.item,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenProfile,
  });

  final Json item;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = item.str('requesterName');
    final code = item.s('requesterUniqueCode');
    final when = formatRelative(item.date('createdAt'));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenProfile,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                UserAvatar(url: item.s('requesterAvatar'), name: name, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    if (code != null && code.isNotEmpty)
                      Text(code, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    const SizedBox(height: 2),
                    Text(t('messageRequests.wantsToBeFriend'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primary)),
                    if (when.isNotEmpty)
                      Text(when, style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _ActionBtn(
                    label: t('messageRequests.accept'),
                    icon: LucideIcons.check,
                    filled: true,
                    color: c.success,
                    enabled: !busy,
                    onTap: onAccept,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionBtn(
                    label: t('messageRequests.decline'),
                    icon: LucideIcons.x,
                    filled: false,
                    color: c.danger,
                    enabled: !busy,
                    onTap: onDecline,
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OutgoingCard extends StatelessWidget {
  const _OutgoingCard({
    required this.item,
    required this.busy,
    required this.onCancel,
    required this.onOpenProfile,
  });

  final Json item;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = item.str('targetName');
    final code = item.s('targetUniqueCode');
    final when = formatRelative(item.date('createdAt'));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenProfile,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                UserAvatar(url: item.s('targetAvatar'), name: name, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    if (code != null && code.isNotEmpty)
                      Text(code, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    const SizedBox(height: 2),
                    Text(t('messageRequests.waitingStatus'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFD97706))),
                    if (when.isNotEmpty)
                      Text(when, style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              _ActionBtn(
                label: t('messageRequests.cancelRequest'),
                icon: LucideIcons.ban,
                filled: false,
                color: c.textSecondary,
                enabled: !busy,
                onTap: onCancel,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: filled ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: filled ? Colors.white : color),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
