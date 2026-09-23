import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'conversations_list_controller.dart';
import 'open_private.dart';

/// views/ShareMessageView.vue — forward a message (or a short film share) to a conversation or contact.
class ShareMessageScreen extends ConsumerStatefulWidget {
  const ShareMessageScreen({super.key, this.shareMessage, this.sourceConversationId, this.returnPath});
  final Json? shareMessage;
  final String? sourceConversationId;
  final String? returnPath;

  @override
  ConsumerState<ShareMessageScreen> createState() => _ShareMessageScreenState();
}

class _ShareMessageScreenState extends ConsumerState<ShareMessageScreen> {
  final _search = TextEditingController();
  List<Json> _conversations = [];
  List<Json> _contacts = [];
  bool _loading = true;
  bool _sending = false;

  String get _backTo =>
      widget.returnPath ?? (widget.sourceConversationId != null ? '/conversation/${widget.sourceConversationId}' : '/conversations');

  @override
  void initState() {
    super.initState();
    if (widget.shareMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(_backTo);
      });
      return;
    }
    _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final cachedList = ref.read(conversationsListProvider);
    if (cachedList.isNotEmpty) _conversations = cachedList;
    if (!NetworkStatus.online.value) {
      if (_conversations.isEmpty) {
        final cached = Prefs.instance.getString('nexchat_conversations_cache');
        if (cached != null) {
          try {
            _conversations = asJsonList(jsonDecode(cached));
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final r = await Future.wait([
        Api.get('/conversations', query: {'filter': 'all'}),
        Api.get('/contacts').catchError((_) => <dynamic>[]),
      ]);
      _conversations = asJsonList(r[0]);
      _contacts = asJsonList(r[1]);
    } catch (_) {
      if (_conversations.isEmpty) _conversations = [];
      if (_contacts.isEmpty) _contacts = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send(String cid) async {
    final msg = widget.shareMessage!;
    await Hubs.conversation.ensureConnected();
    await Hubs.conversation.invoke('SendMessage', [cid, msg.str('content'), msg.s('type') ?? 'text', '']);
  }

  bool _requireOnline() {
    if (NetworkStatus.online.value) return true;
    if (mounted) showToast(context, t('noConnection.sendFailed'), error: true);
    return false;
  }

  Future<void> _toConversation(String cid) async {
    if (_sending) return;
    if (!_requireOnline()) return;
    setState(() => _sending = true);
    try {
      await _send(cid);
      if (mounted) context.go('/conversation/$cid');
    } catch (e) {
      if (!mounted) return;
      showToast(context, Api.errorMessage(e, t('noConnection.sendFailed')), error: true);
      setState(() => _sending = false);
    }
  }

  Future<void> _toContact(Json contact) async {
    if (!_requireOnline()) return;
    final uid = contact.s('contactUserId');
    if (uid == null || _sending) return;
    setState(() => _sending = true);
    try {
      final cid = await createPrivateConversationOrRequest(uid);
      if (cid == null) {
        await ref.read(pendingRequestsProvider.notifier).fetch();
        if (mounted) goToMessageRequestsOutgoingNotice(context, share: true);
        if (mounted) setState(() => _sending = false);
        return;
      }
      await _send(cid);
      if (mounted) context.go('/conversation/$cid');
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorText(e), error: true);
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _search.text.trim();
    final lower = q.toLowerCase();
    final convs = _conversations.where((x) => x.str('id') != widget.sourceConversationId).where((x) {
      if (q.isEmpty) return true;
      return (x.s('partnerName') ?? '').toLowerCase().contains(lower) ||
          (x.s('partnerPhone') ?? '').contains(q) ||
          (x.s('partnerUniqueCode') ?? '').toLowerCase().contains(lower);
    }).toList();
    final contacts = _contacts.where((x) {
      if (q.isEmpty) return true;
      return (x.s('name') ?? '').toLowerCase().contains(lower) ||
          (x.s('phoneNumber') ?? '').contains(q) ||
          (x.s('uniqueCode') ?? '').toLowerCase().contains(lower);
    }).toList();
    final forward = Icon(LucideIcons.forward, size: 16, color: c.textMuted);
    Widget title(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(s, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textMuted)),
        );

    return Stack(children: [
      ModernPage(
      title: t('conversationChat.shareToConversation'),
      backTo: _backTo,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SearchField(controller: _search, hint: t('conversationChat.shareSearchPlaceholder'), onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        if (!_loading) ...[
          if (convs.isNotEmpty) ...[
            title(t('conversations.title')),
            for (final x in convs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ModernListRow(
                  leading: UserAvatar(url: x.s('partnerAvatar'), name: x.s('partnerName') ?? '?'),
                  title: x.s('partnerName') ?? '—',
                  trailing: forward,
                  onTap: _sending ? null : () => _toConversation(x.str('id')),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (contacts.isNotEmpty) ...[
            title(t('contacts.title')),
            for (final x in contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ModernListRow(
                  leading: UserAvatar(url: x.s('avatar'), name: x.s('name') ?? '?'),
                  title: x.s('name') ?? '—',
                  trailing: forward,
                  onTap: _sending ? null : () => _toContact(x),
                ),
              ),
          ],
          if (convs.isEmpty && contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                q.isNotEmpty ? t('conversationChat.noSearchResults') : t('conversationChat.noOtherConversations'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 14),
              ),
            ),
        ],
      ]),
    ),
      LoaderOverlay(show: _loading, text: t('common.loading')),
    ]);
  }
}
