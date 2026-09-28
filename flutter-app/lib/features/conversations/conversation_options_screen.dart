import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'active_conversation.dart';
import 'conversations_list_controller.dart';
import 'hidden_chats_pin_dialog.dart';

/// views/ConversationOptionsView.vue
class ConversationOptionsScreen extends ConsumerStatefulWidget {
  const ConversationOptionsScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ConversationOptionsScreen> createState() => _ConversationOptionsScreenState();
}

class _ConversationOptionsScreenState extends ConsumerState<ConversationOptionsScreen> {
  bool _busy = false;
  late Json? _conv;
  int _disappearMode = 0;

  @override
  void initState() {
    super.initState();
    _conv = ref.read(conversationsListProvider).where((x) => x.str('id') == widget.conversationId).firstOrNull;
    Future.microtask(_loadDisappearMode);
  }

  Future<void> _loadDisappearMode() async {
    try {
      final data = await Api.get('/conversations/${widget.conversationId}');
      if (data is Map && mounted) {
        setState(() {
          _disappearMode = data.i('disappearMode');
          if (_conv != null) {
            _conv = {
              ..._conv!,
              'isSupport': data.b('isSupport'),
              'IsSupport': data.b('isSupport'),
              'isOfficial': data.b('isOfficial') || data.b('isReadOnly'),
              'IsOfficial': data.b('isOfficial') || data.b('isReadOnly'),
              'partnerUniqueCode': data.s('partnerUniqueCode') ?? _conv!.s('partnerUniqueCode'),
            };
          }
        });
      }
    } catch (_) {}
  }

  String _disappearLabel(int mode) => switch (mode) {
        1 => t('conversations.disappearAfterRead'),
        2 => t('conversations.disappear1h'),
        3 => t('conversations.disappear24h'),
        4 => t('conversations.disappear1w'),
        _ => t('conversations.disappearOff'),
      };

  Future<void> _pickDisappearMode() async {
    if (_busy) return;
    final c = context.colors;
    final isGroup = _conv?.b('isGroup') ?? false;
    final modes = isGroup ? const [0, 2, 3, 4] : const [0, 1, 2, 3, 4];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('conversations.disappearTitle'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const SizedBox(height: 6),
              Text(
                isGroup ? t('conversations.disappearHintGroup') : t('conversations.disappearHint'),
                style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              for (final mode in modes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_disappearLabel(mode), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                  trailing: mode == _disappearMode ? Icon(LucideIcons.check, color: c.primary, size: 20) : null,
                  onTap: () => Navigator.pop(ctx, mode),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _disappearMode || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.put('/conversations/${widget.conversationId}/disappear', {'mode': picked});
      if (!mounted) return;
      setState(() {
        _disappearMode = picked;
        _busy = false;
      });
      showToast(context, t('conversations.disappearSaved'), success: true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, Api.errorMessage(e, t('common.error')), error: true);
      }
    }
  }

  void _back() {
    if (!mounted) return;
    context.go('/conversations');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _back();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, Api.errorMessage(e, t('common.error')), error: true);
      }
    }
  }

  Future<void> _toggleHide() async {
    if (_busy) return;
    final conv = _conv;
    if (conv == null) return;
    final wasHidden = conv.b('isHidden');
    final ctrl = ref.read(conversationsListProvider.notifier);

    setState(() => _busy = true);
    try {
      if (!wasHidden) {
        final ok = await ensureHiddenChatsPin(context);
        if (!ok || !mounted) {
          setState(() => _busy = false);
          return;
        }
        final proceed = await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: Text(t('conversations.hide')),
            content: Text(t('conversations.hideConfirm')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('common.ok'))),
            ],
          ),
        );
        if (proceed != true || !mounted) {
          setState(() => _busy = false);
          return;
        }
      }

      await Api.put('/conversations/${widget.conversationId}/hide');
      if (!mounted) return;

      // Leave this screen before mutating the watched list — avoids InheritedWidget dispose crash.
      _back();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Always remove from the current list (vault or inbox), then user refreshes the other view.
        ctrl.removeConversation(widget.conversationId);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, Api.errorMessage(e, t('common.error')), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final latest = ref.watch(conversationsListProvider).where((x) => x.str('id') == widget.conversationId).firstOrNull;
    if (!_busy && latest != null) _conv = latest;
    final conv = _conv;
    final isGroup = conv?.b('isGroup') ?? false;
    final isSupport = conv?.b('isSupport') ?? false;
    final isOfficial = isOfficialConversation(conv);
    final locked = isSupport || isOfficial;
    final isHidden = conv?.b('isHidden') ?? false;
    final ctrl = ref.read(conversationsListProvider.notifier);
    final displayName = isOfficial ? t('conversations.officialName') : (conv?.s('partnerName') ?? '—');

    return ModernPage(
      title: t('conversations.optionsTitle'),
      backTo: '/conversations',
      body: conv == null
          ? EmptyState(
              icon: LucideIcons.messageCircle,
              text: t('conversations.notFound'),
              action: SizedBox(width: 240, child: PillButton(label: t('common.back'), onPressed: _back)),
            )
          : AbsorbPointer(
              absorbing: _busy,
              child: Column(children: [
                const SizedBox(height: 16),
                UserAvatar(url: conv.s('partnerAvatar'), name: displayName, size: 96),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(displayName, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    ),
                    if (isSupport || isOfficial) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified, size: 20, color: c.primary),
                    ],
                  ],
                ),
                if (isOfficial) ...[
                  const SizedBox(height: 6),
                  Text(t('conversations.officialDesc'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ] else if (isSupport) ...[
                  const SizedBox(height: 6),
                  Text(t('settings.supportDesc'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ],
                const SizedBox(height: 24),
                if (!locked)
                  _OptionBtn(
                    icon: isGroup ? LucideIcons.users : LucideIcons.user,
                    label: isGroup ? t('groups.infoTitle') : t('profile.viewProfile'),
                    onTap: () {
                      if (isGroup) {
                        context.push('/conversation/${widget.conversationId}/group-info');
                        return;
                      }
                      final pid = conv.s('partnerId');
                      if (pid == null) return;
                      context.push('/profile/$pid', extra: {'conversationId': widget.conversationId});
                    },
                  ),
                if (!locked)
                  _OptionBtn(
                    icon: LucideIcons.pin,
                    label: conv.b('isPinned') ? t('conversations.unpin') : t('conversations.pin'),
                    onTap: () => _run(() async {
                      await Api.put('/conversations/${widget.conversationId}/pin');
                      ctrl.updateConversation(widget.conversationId, {'isPinned': !conv.b('isPinned')});
                    }),
                  ),
                if (!locked && !isHidden)
                  _OptionBtn(
                    icon: LucideIcons.archive,
                    label: conv.b('isArchived') ? t('conversations.unarchive') : t('conversations.archive'),
                    onTap: () => _run(() async {
                      await Api.put('/conversations/${widget.conversationId}/archive');
                      ctrl.updateConversation(widget.conversationId, {'isArchived': !conv.b('isArchived')});
                    }),
                  ),
                if (!locked)
                  _OptionBtn(
                    icon: LucideIcons.timer,
                    label: '${t('conversations.disappearTitle')}: ${_disappearLabel(_disappearMode)}',
                    onTap: _pickDisappearMode,
                  ),
                if (!locked)
                  _OptionBtn(
                    icon: isHidden ? LucideIcons.eye : LucideIcons.lock,
                    label: isHidden ? t('conversations.unhide') : t('conversations.hide'),
                    onTap: _toggleHide,
                  ),
                if (conv.i('unreadCount') > 0)
                  _OptionBtn(
                    icon: LucideIcons.check,
                    label: t('conversations.markRead'),
                    onTap: () => _run(() async {
                      await Api.put('/conversations/${widget.conversationId}/read');
                      ctrl.updateConversation(widget.conversationId, {'unreadCount': 0});
                    }),
                  ),
                if (!locked)
                  _OptionBtn(
                    icon: LucideIcons.trash2,
                    label: t('conversations.delete'),
                    danger: true,
                    onTap: () => _run(() async {
                      await Api.delete('/conversations/${widget.conversationId}');
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ctrl.removeConversation(widget.conversationId);
                      });
                    }),
                  ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                ],
              ]),
            ),
    );
  }
}

class _OptionBtn extends StatelessWidget {
  const _OptionBtn({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = danger ? c.danger : c.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: danger ? c.danger.withValues(alpha: 0.08) : c.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: danger ? c.danger.withValues(alpha: 0.25) : c.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg))),
            ]),
          ),
        ),
      ),
    );
  }
}
