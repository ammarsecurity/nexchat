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
import '../auth/auth_controller.dart';
import 'conversation_cache.dart';
import 'message_contract.dart';
import 'message_outbox.dart';
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
  bool _choosing = false;
  bool _lookingUp = false;
  String? _lookupQuery;
  List<Json> _phoneMatches = [];
  late final String _accountId;
  final Map<String, String> _requestIds = {};
  bool get _busy => _sending || _choosing || _lookingUp;
  bool get _sameAccount => mounted && ref.read(authProvider).user?.id == _accountId;

  String get _backTo =>
      widget.returnPath ?? (widget.sourceConversationId != null ? '/conversation/${widget.sourceConversationId}' : '/conversations');

  @override
  void initState() {
    super.initState();
    _accountId = ref.read(authProvider).user?.id ?? '';
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
        final cached = Prefs.instance.getString(ConversationCache.inboxKey(_accountId));
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
      if (!_sameAccount) return;
      _conversations = asJsonList(r[0]);
      _contacts = asJsonList(r[1]);
    } catch (_) {
      if (_conversations.isEmpty) _conversations = [];
      if (_contacts.isEmpty) _contacts = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send(String cid) async {
    if (!_sameAccount) throw StateError('Account changed');
    final msg = widget.shareMessage!;
    if (msg.b('isViewOnce') || msg.b('deletedForEveryone') || msg.b('restricted')) throw StateError('هذه الرسالة غير قابلة للمشاركة');
    final clientId = _requestIds.putIfAbsent(cid, newClientMessageId);
    final acknowledgment = await Hubs.conversation.invokeReliable('SendMessageWithClientId',
        conversationSendArguments(cid, msg.str('content'), msg.s('type') ?? 'text', '', false, clientId));
    if (acknowledgment is! Map || acknowledgment.str('id').isEmpty ||
        !belongsToConversation(acknowledgment, cid) || acknowledgment.str('clientMessageId') != clientId) {
      throw StateError('لم يؤكد الخادم حفظ الرسالة. يمكنك إعادة المحاولة بأمان.');
    }
    await MessageOutbox.acknowledge(_accountId, {...normalizeMsg(acknowledgment), 'status': 'sent'});
  }

  Future<bool> _confirmTarget(String name, String? identity) => confirmDialog(
    context,
    title: 'إعادة توجيه الرسالة',
    message: 'إرسال إلى $name${identity == null || identity.isEmpty ? '' : '\n$identity'}؟',
    confirm: 'إرسال',
    cancel: t('common.cancel'),
  );

  String _failure(Object error) {
    if (!NetworkStatus.online.value) return t('noConnection.sendFailed');
    final detail = Api.errorMessage(error, '');
    if (detail.isNotEmpty) return detail;
    return 'تعذر إرسال الرسالة. تحقق من صلاحية المحادثة وحاول مجدداً.';
  }

  Future<void> _lookupPhone() async {
    if (_busy || !_sameAccount || !_requireOnline()) return;
    final query = _search.text.trim();
    final phone = query.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(query) || phone.length < 8 || phone.length > 15) {
      showToast(context, 'اكتب الرقم كاملاً مع مفتاح الدولة', error: true);
      return;
    }
    setState(() { _lookingUp = true; _phoneMatches = []; _lookupQuery = null; });
    try {
      final result = await Api.post('/contacts/lookup', {'contacts': [{'phone': phone}]});
      if (!_sameAccount || _search.text.trim() != query) return;
      setState(() { _phoneMatches = asJsonList(result); _lookupQuery = query; });
      if (mounted && _phoneMatches.isEmpty) showToast(context, 'لم يتم العثور على مستخدم متاح بهذا الرقم');
    } catch (error) {
      if (mounted && _sameAccount) showToast(context, _failure(error), error: true);
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  bool _requireOnline() {
    if (NetworkStatus.online.value) return true;
    if (mounted) showToast(context, t('noConnection.sendFailed'), error: true);
    return false;
  }

  Future<void> _toConversation(Json conversation) async {
    if (_busy || !_sameAccount || !_requireOnline()) return;
    final cid = conversation.str('id');
    final name = conversation.s('partnerName') ?? conversation.s('groupName') ?? 'المحادثة';
    setState(() => _choosing = true);
    try {
      if (!await _confirmTarget(name, conversation.s('partnerPhone') ?? conversation.s('partnerUniqueCode'))) return;
      if (!_sameAccount) return;
      setState(() => _sending = true);
      await _send(cid);
      if (mounted && _sameAccount) context.go('/conversation/$cid');
    } catch (error) {
      if (mounted && _sameAccount) showToast(context, _failure(error), error: true);
    } finally {
      if (mounted) setState(() { _sending = false; _choosing = false; });
    }
  }

  Future<void> _toContact(Json contact) async {
    if (_busy || !_sameAccount || !_requireOnline()) return;
    final uid = contact.s('contactUserId') ?? contact.s('userId');
    if (uid == null || uid.isEmpty) return;
    setState(() => _choosing = true);
    try {
      if (!await _confirmTarget(contact.s('name') ?? 'المستخدم', contact.s('phoneNumber') ?? contact.s('uniqueCode'))) return;
      if (!_sameAccount) return;
      setState(() => _sending = true);
      // Only this explicit, confirmed selection may open a private chat/request.
      final cid = await createPrivateConversationOrRequest(uid);
      if (!_sameAccount) return;
      if (cid == null) {
        await ref.read(pendingRequestsProvider.notifier).fetch();
        if (mounted && _sameAccount) goToMessageRequestsOutgoingNotice(context, share: true);
        return;
      }
      await _send(cid);
      if (mounted && _sameAccount) context.go('/conversation/$cid');
    } catch (error) {
      if (mounted && _sameAccount) showToast(context, _failure(error), error: true);
    } finally {
      if (mounted) setState(() { _sending = false; _choosing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _search.text.trim();
    final lower = q.toLowerCase();
    final convs = _conversations.where((x) => x.str('id') != widget.sourceConversationId && !x.b('isOfficial') && !x.b('isReadOnly')).where((x) {
      if (q.isEmpty) return true;
      return (x.s('partnerName') ?? x.s('groupName') ?? '').toLowerCase().contains(lower) ||
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
        SearchField(controller: _search, hint: t('conversationChat.shareSearchPlaceholder'), onChanged: (_) => setState(() { _phoneMatches = []; _lookupQuery = null; })),
        if (RegExp(r'^\+?[0-9 ()-]{8,}$').hasMatch(q))
          TextButton.icon(
            onPressed: _busy ? null : _lookupPhone,
            icon: _lookingUp ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(LucideIcons.search),
            label: const Text('البحث عن الرقم في NexChat'),
          ),
        if (_lookupQuery == q && _phoneMatches.isNotEmpty) ...[
          title('مستخدمو NexChat بهذا الرقم'),
          for (final contact in _phoneMatches)
            ModernListRow(
              leading: UserAvatar(url: contact.s('avatar'), name: contact.s('name') ?? '?'),
              title: contact.s('name') ?? '—',
              subtitle: contact.s('phoneNumber') ?? contact.s('uniqueCode'),
              trailing: forward,
              onTap: _busy ? null : () => _toContact(contact),
            ),
        ],
        const SizedBox(height: 16),
        if (!_loading) ...[
          if (convs.isNotEmpty) ...[
            title(t('conversations.title')),
            for (final x in convs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ModernListRow(
                  leading: UserAvatar(url: x.s('partnerAvatar'), name: x.s('partnerName') ?? x.s('groupName') ?? '?'),
                  title: x.s('partnerName') ?? x.s('groupName') ?? '—',
                  trailing: forward,
                  onTap: _busy ? null : () => _toConversation(x),
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
                  onTap: _busy ? null : () => _toContact(x),
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
      LoaderOverlay(show: _loading || _sending, text: t('common.loading')),
    ]);
  }
}
