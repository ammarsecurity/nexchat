import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'conversations_list_controller.dart';

/// views/ConversationOptionsView.vue
class ConversationOptionsScreen extends ConsumerWidget {
  const ConversationOptionsScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(conversationsListProvider);
    final conv = list.where((x) => x.str('id') == conversationId).firstOrNull;
    void back() => context.go('/conversations');

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        if (context.mounted) back();
      } catch (e) {
        if (context.mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
      }
    }

    final ctrl = ref.read(conversationsListProvider.notifier);
    final isGroup = conv?.b('isGroup') ?? false;

    return ModernPage(
      title: t('conversations.optionsTitle'),
      backTo: '/conversations',
      body: conv == null
          ? EmptyState(
              icon: LucideIcons.messageCircle,
              text: t('conversations.notFound'),
              action: SizedBox(width: 240, child: PillButton(label: t('common.back'), onPressed: back)),
            )
          : Column(children: [
              const SizedBox(height: 16),
              UserAvatar(url: conv.s('partnerAvatar'), name: conv.s('partnerName') ?? '?', size: 96),
              const SizedBox(height: 12),
              Text(conv.s('partnerName') ?? '—', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const SizedBox(height: 24),
              _OptionBtn(
                icon: isGroup ? LucideIcons.users : LucideIcons.user,
                label: isGroup ? t('groups.infoTitle') : t('profile.viewProfile'),
                onTap: () {
                  if (isGroup) {
                    context.push('/conversation/$conversationId/group-info');
                    return;
                  }
                  final pid = conv.s('partnerId');
                  if (pid == null) return;
                  context.push('/profile/$pid', extra: {'conversationId': conversationId});
                },
              ),
              _OptionBtn(
                icon: LucideIcons.pin,
                label: conv.b('isPinned') ? t('conversations.unpin') : t('conversations.pin'),
                onTap: () => run(() async {
                  await Api.put('/conversations/$conversationId/pin');
                  ctrl.updateConversation(conversationId, {'isPinned': !conv.b('isPinned')});
                }),
              ),
              _OptionBtn(
                icon: LucideIcons.archive,
                label: conv.b('isArchived') ? t('conversations.unarchive') : t('conversations.archive'),
                onTap: () => run(() async {
                  await Api.put('/conversations/$conversationId/archive');
                  ctrl.updateConversation(conversationId, {'isArchived': !conv.b('isArchived')});
                }),
              ),
              if (conv.i('unreadCount') > 0)
                _OptionBtn(
                  icon: LucideIcons.check,
                  label: t('conversations.markRead'),
                  onTap: () => run(() async {
                    await Api.put('/conversations/$conversationId/read');
                    ctrl.updateConversation(conversationId, {'unreadCount': 0});
                  }),
                ),
              _OptionBtn(
                icon: LucideIcons.trash2,
                label: t('conversations.delete'),
                danger: true,
                onTap: () => run(() async {
                  await Api.delete('/conversations/$conversationId');
                  ctrl.removeConversation(conversationId);
                }),
              ),
            ]),
    );
  }
}

/// `.modern-option-btn`
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
