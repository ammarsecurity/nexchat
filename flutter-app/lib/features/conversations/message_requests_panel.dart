import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/widgets.dart';
import 'conversations_list_controller.dart';

/// components/MessageRequestsPanel.vue
class MessageRequestsPanel extends ConsumerStatefulWidget {
  const MessageRequestsPanel({super.key, this.notice});
  final String? notice;

  @override
  ConsumerState<MessageRequestsPanel> createState() => _MessageRequestsPanelState();
}

class _MessageRequestsPanelState extends ConsumerState<MessageRequestsPanel> {
  bool _loading = true;
  List<Json> _list = [];
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
    if (n == 'outgoing-wait') _banner = 'wait';
    if (n == 'outgoing-share-wait') _banner = 'share';
  }

  Future<void> _fetch() async {
    if (!NetworkStatus.online.value) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final pending = ref.read(pendingRequestsProvider.notifier);
    setState(() => _loading = true);
    try {
      _list = asJsonList(await Api.get('/message-requests'));
    } catch (_) {
      _list = [];
    }
    if (!mounted) return;
    setState(() => _loading = false);
    await pending.fetch();
  }

  Future<void> _act(String id, String action) async {
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
      setState(() => _list.removeWhere((x) => x.str('id') == id));
      await pending.fetch();
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget circleBtn(IconData icon, Color bg, Color fg, VoidCallback? onTap) => Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 16, color: fg)),
            ),
          ),
        );

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, tabScrollPadding(context, extra: 16)),
        children: [
          if (_banner != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    _banner == 'share' ? t('messageRequests.waitingForAcceptCannotShare') : t('messageRequests.waitingForAcceptFromOther'),
                    style: TextStyle(fontSize: 14, color: c.textPrimary),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _banner = null),
                  child: Text('×', style: TextStyle(fontSize: 22, height: 1, color: c.textMuted)),
                ),
              ]),
            ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted, fontSize: 15))),
            )
          else if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text(t('messageRequests.empty'), style: TextStyle(color: c.textMuted, fontSize: 15))),
            )
          else
            for (final r in _list)
              ModernListRow(
                leading: UserAvatar(url: r.s('requesterAvatar'), name: r.str('requesterName'), size: 52),
                title: r.str('requesterName'),
                subtitle: r.s('requesterUniqueCode'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  circleBtn(LucideIcons.check, const Color(0x2622C55E), c.success,
                      _actionId == r.str('id') ? null : () => _act(r.str('id'), 'accept')),
                  const SizedBox(width: 8),
                  circleBtn(LucideIcons.x, const Color(0x1FEF4444), c.danger,
                      _actionId == r.str('id') ? null : () => _act(r.str('id'), 'decline')),
                ]),
              ),
        ],
      ),
    );
  }
}
