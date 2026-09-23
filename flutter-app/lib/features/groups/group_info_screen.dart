import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../conversations/active_conversation.dart';
import '../conversations/conversations_list_controller.dart';

/// views/GroupInfoView.vue
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  String get _cid => widget.conversationId;
  String _groupName = '';
  String? _groupImageUrl;
  List<Json> _members = [];
  bool _loading = true;
  bool _leaving = false;
  String? _removingUserId;
  bool _editing = false;
  final _editCtrl = TextEditingController();
  bool _savingGroup = false;
  bool _uploadingPhoto = false;
  String _editError = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (await _fetchGroup()) await _fetchMembers();
  }

  Future<bool> _fetchGroup() async {
    try {
      final data = await Api.get('/conversations/$_cid') as Map;
      if (data.s('type') != 'group') {
        if (mounted) context.go('/conversations');
        return false;
      }
      _groupName = data.s('groupName') ?? 'مجموعة';
      _groupImageUrl = data.s('groupImageUrl');
      return true;
    } catch (_) {
      final fromList = ref.read(conversationsListProvider).where((c) => c.str('id') == _cid).firstOrNull;
      final active = ref.read(activeConversationProvider);
      if (fromList != null && fromList.b('isGroup')) {
        _groupName = fromList.s('partnerName') ?? fromList.s('groupName') ?? 'مجموعة';
        _groupImageUrl = fromList.s('partnerAvatar') ?? fromList.s('groupImageUrl');
        return true;
      }
      if (active.conversationId == _cid && active.isGroup) {
        _groupName = active.partner?.s('name') ?? 'مجموعة';
        _groupImageUrl = active.partner?.s('avatar');
        return true;
      }
      if (mounted && NetworkStatus.online.value) context.go('/conversations');
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMembers() async {
    try {
      _members = asJsonList(await Api.get('/conversations/$_cid/members'));
    } catch (_) {
      _members = [];
    }
    if (mounted) setState(() {});
  }

  String? get _me => ref.read(authProvider).user?.id;
  bool get _isAdmin => _members.where((m) => m.str('userId') == _me).firstOrNull?.s('role') == 'Admin';

  Future<void> _leave() async {
    if (!NetworkStatus.online.value) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: t('groups.leaveGroup'), message: t('groups.leaveConfirm'), confirm: t('groups.leaveGroup'), cancel: t('common.cancel'), danger: true);
    if (!ok) return;
    setState(() => _leaving = true);
    try {
      await Api.post('/conversations/$_cid/leave');
      if (mounted) context.go('/conversations');
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
    if (mounted) setState(() => _leaving = false);
  }

  Future<void> _remove(String userId) async {
    if (!NetworkStatus.online.value) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    setState(() => _removingUserId = userId);
    try {
      await Api.delete('/conversations/$_cid/members/$userId');
      await _fetchMembers();
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
    if (mounted) setState(() => _removingUserId = null);
  }

  Future<void> _openAdd() async {
    final added = await showAppSheet<bool>(
      context,
      builder: (_) => _AddMemberSheet(conversationId: _cid, memberIds: _members.map((m) => m.str('userId')).toSet()),
    );
    if (added == true) _fetchMembers();
  }

  Future<void> _saveName() async {
    final name = _editCtrl.text.trim();
    if (name.isEmpty || name.length > 100) {
      setState(() => _editError = name.isNotEmpty ? t('groups.groupNameRequired') : '');
      return;
    }
    setState(() {
      _savingGroup = true;
      _editError = '';
    });
    try {
      final data = await Api.put('/conversations/$_cid/group', {'name': name});
      if (!mounted) return;
      final nextName = data is Map && data.s('groupName') != null ? data.s('groupName')! : name;
      setState(() {
        _groupName = nextName;
        _editing = false;
        _editCtrl.clear();
      });
      ref.read(conversationsListProvider.notifier).updateConversation(_cid, {'partnerName': nextName, 'groupName': nextName});
      final active = ref.read(activeConversationProvider);
      if (active.conversationId == _cid) {
        ref.read(activeConversationProvider.notifier).setPartner({...?active.partner, 'name': nextName});
      }
    } catch (e) {
      if (mounted) setState(() => _editError = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _savingGroup = false);
    }
  }

  Future<void> _changePhoto() async {
    final file = await pickImage();
    if (file == null) return;
    setState(() {
      _uploadingPhoto = true;
      _editError = '';
    });
    try {
      final url = await uploadFile('/media/upload', file.path, filename: file.name);
      await Api.put('/conversations/$_cid/group', {'imageUrl': url});
      if (!mounted) return;
      setState(() => _groupImageUrl = url);
      ref.read(conversationsListProvider.notifier).updateConversation(_cid, {'partnerAvatar': url, 'groupImageUrl': url});
      final active = ref.read(activeConversationProvider);
      if (active.conversationId == _cid) {
        ref.read(activeConversationProvider.notifier).setPartner({...?active.partner, 'avatar': url});
      }
    } catch (e) {
      if (mounted) setState(() => _editError = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final admin = _isAdmin;
    final me = _me;

    Widget avatar = SizedBox(
      width: 96,
      height: 96,
      child: _uploadingPhoto
          ? Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.bgElevated),
              alignment: Alignment.center,
              child: Text('...', style: TextStyle(color: c.textMuted, fontSize: 24)),
            )
          : UserAvatar(url: _groupImageUrl, name: _groupName, size: 96),
    );
    if (admin) {
      avatar = GestureDetector(
        onTap: _uploadingPhoto ? null : _changePhoto,
        child: Stack(clipBehavior: Clip.none, children: [
          avatar,
          PositionedDirectional(
            bottom: 4,
            end: 4,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: c.bgCard, width: 2)),
              child: const Icon(LucideIcons.image, size: 14, color: Colors.white),
            ),
          ),
        ]),
      );
    }

    return Stack(children: [
      ModernPage(
      title: t('groups.infoTitle'),
      backTo: '/conversation/$_cid',
      body: _loading
          ? const SizedBox.shrink()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GlassCard(
                child: Column(children: [
                  avatar,
                  const SizedBox(height: 12),
                  if (_editing)
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: _editCtrl,
                        maxLength: 100,
                        autofocus: true,
                        onSubmitted: (_) => _saveName(),
                        style: TextStyle(color: c.textPrimary, fontSize: 16),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: t('groups.groupNamePlaceholder'),
                          filled: true,
                          fillColor: c.bgElevated,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: SoftButton(
                            label: t('common.cancel'),
                            height: 42,
                            onPressed: () => setState(() {
                              _editing = false;
                              _editCtrl.clear();
                              _editError = '';
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: PillButton(label: t('groups.save'), loading: _savingGroup, onPressed: _savingGroup ? null : _saveName)),
                      ]),
                    ])
                  else
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(
                        child: Text(_groupName,
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
                      ),
                      if (admin)
                        IconButton(
                          onPressed: () => setState(() {
                            _editCtrl.text = _groupName;
                            _editError = '';
                            _editing = true;
                          }),
                          icon: Icon(LucideIcons.pencil, size: 18, color: c.textSecondary),
                        ),
                    ]),
                  if (_editError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_editError, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontSize: 13)),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: Text('${t('groups.members')} (${_members.length})',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textMuted)),
                ),
                TextButton.icon(
                  onPressed: _openAdd,
                  icon: Icon(LucideIcons.userPlus, size: 18, color: c.primary),
                  label: Text(t('groups.addMember'), style: TextStyle(color: c.primary, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(backgroundColor: c.primarySoft, shape: const StadiumBorder()),
                ),
              ]),
              const SizedBox(height: 8),
              for (final m in _members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ModernListRow(
                    leading: UserAvatar(url: m.s('avatar'), name: m.s('name') ?? '?'),
                    title: m.s('name') ?? '—',
                    subtitle: m.s('role') == 'Admin' ? t('groups.admin') : t('groups.member'),
                    trailing: admin && me != null && m.str('userId') != me
                        ? IconButton(
                            onPressed: _removingUserId != null ? null : () => _remove(m.str('userId')),
                            icon: Icon(LucideIcons.userMinus, size: 18, color: c.danger),
                          )
                        : null,
                  ),
                ),
              const SizedBox(height: 16),
              Material(
                color: c.danger.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(color: c.danger.withValues(alpha: 0.25)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: _leaving ? null : _leave,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Icon(LucideIcons.logOut, size: 20, color: c.danger),
                      const SizedBox(width: 12),
                      Text(t('groups.leaveGroup'), style: TextStyle(color: c.danger, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ]),
      ),
      LoaderOverlay(show: _loading, text: t('common.loading')),
    ]);
  }
}

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.conversationId, required this.memberIds});
  final String conversationId;
  final Set<String> memberIds;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  List<Json> _contacts = [];
  String? _adding;

  @override
  void initState() {
    super.initState();
    Api.get('/contacts').then((d) {
      if (mounted) setState(() => _contacts = asJsonList(d));
    }).catchError((_) {});
  }

  Future<void> _add(String userId) async {
    setState(() => _adding = userId);
    try {
      await Api.post('/conversations/${widget.conversationId}/members', jsonEncode(userId), Options(contentType: Headers.jsonContentType));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
      if (mounted) setState(() => _adding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _contacts.where((x) => !widget.memberIds.contains(x.str('contactUserId'))).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(children: [
            Expanded(child: Text(t('groups.addMember'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: c.textSecondary)),
          ]),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(LucideIcons.users, size: 32, color: c.textMuted),
              const SizedBox(height: 8),
              Text(t('contacts.empty'), style: TextStyle(color: c.textSecondary)),
            ]),
          )
        else
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
              for (final ct in list)
                ListTile(
                  onTap: _adding != null ? null : () => _add(ct.str('contactUserId')),
                  leading: UserAvatar(url: ct.s('avatar'), name: ct.s('name') ?? '?', size: 40),
                  title: Text(ct.s('name') ?? '—', style: TextStyle(color: c.textPrimary)),
                  trailing: _adding == ct.str('contactUserId')
                      ? Text('...', style: TextStyle(color: c.textMuted))
                      : Icon(LucideIcons.userPlus, size: 18, color: c.primary),
                ),
            ]),
          ),
      ]),
    );
  }
}
