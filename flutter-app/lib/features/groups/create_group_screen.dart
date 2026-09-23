import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../shared/widgets.dart';
import '../settings/avatar_picker_sheet.dart';

/// views/CreateGroupView.vue
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  String? _imageUrl;
  bool _uploading = false;
  List<Json> _contacts = [];
  final Set<String> _selected = {};
  bool _creating = false;
  String _error = '';
  bool _needPhone = false;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetchContacts() async {
    _needPhone = false;
    const cacheKey = 'nexchat_contacts_cache';
    final cached = Prefs.instance.getString(cacheKey);
    if (cached != null) {
      try {
        _contacts = asJsonList(jsonDecode(cached));
      } catch (_) {}
    }
    if (!NetworkStatus.online.value) {
      if (mounted) setState(() {});
      return;
    }
    try {
      _contacts = asJsonList(await Api.get('/contacts'));
      Prefs.instance.setString(cacheKey, jsonEncode(_contacts));
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 400 && Api.errorMessage(e).contains('رقم الهاتف')) _needPhone = true;
      if (_contacts.isEmpty) _contacts = [];
    }
    if (mounted) setState(() {});
  }

  List<Json> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = (c.s('name') ?? '').toLowerCase();
      final phone = (c.s('phone') ?? c.s('phoneNumber') ?? '').toLowerCase();
      final code = (c.s('uniqueCode') ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q) || code.contains(q);
    }).toList();
  }

  Future<void> _pickImage() async {
    final file = await pickImage();
    if (file == null) return;
    setState(() {
      _uploading = true;
      _error = '';
    });
    try {
      final url = await uploadFile('/media/upload', file.path, filename: file.name);
      if (!mounted) return;
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _create() async {
    if (!NetworkStatus.online.value) {
      setState(() => _error = t('noConnection.actionFailed'));
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = t('groups.groupNameRequired'));
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = t('groups.selectAtLeastOne'));
      return;
    }
    setState(() {
      _creating = true;
      _error = '';
    });
    try {
      final data = await Api.post('/conversations/group', {'name': name, 'imageUrl': _imageUrl, 'memberUserIds': _selected.toList()});
      if (mounted) context.go('/conversation/${(data as Map).str('id')}');
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textSecondary);
    final filtered = _filtered;
    final canCreate = !_creating && _name.text.trim().isNotEmpty && _selected.isNotEmpty;

    final contactsSection = _contacts.isEmpty
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
            child: Column(children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: Color(0x1A6C63FF), shape: BoxShape.circle),
                child: Icon(LucideIcons.users, size: 40, color: c.primary),
              ),
              const SizedBox(height: 16),
              Text(t('contacts.empty'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
              const SizedBox(height: 6),
              Text(t('contacts.addFirst'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go('/conversations?tab=contacts'),
                icon: const Icon(LucideIcons.userPlus, size: 20),
                label: Text(t('contacts.addContact'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]),
          )
        : Column(children: [
            SearchField(
              controller: _search,
              hint: t('groups.searchMembersPlaceholder'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: c.border),
                  boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6)],
                ),
                clipBehavior: Clip.antiAlias,
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
                        child: Text(t('groups.noMembersMatch'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textMuted)),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final ct = filtered[i];
                          final id = ct.str('contactUserId');
                          final sel = _selected.contains(id);
                          return InkWell(
                            onTap: () => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                            child: Container(
                              color: sel ? const Color(0x146C63FF) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(children: [
                                UserAvatar(url: ct.s('avatar'), name: ct.s('name') ?? '?', size: 44),
                                const SizedBox(width: 12),
                                Expanded(child: Text(ct.s('name') ?? '—', style: TextStyle(fontSize: 15, color: c.textPrimary))),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: sel ? c.primary : c.border, width: 2),
                                  ),
                                  child: sel
                                      ? Container(width: 10, height: 10, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle))
                                      : null,
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ]);

    return Stack(children: [
      ModernPage(
        title: t('groups.createTitle'),
        backTo: '/conversations',
        scroll: false,
        padding: EdgeInsets.zero,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_needPhone)
            Container(
              color: const Color(0x26FFC107),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Text(t('conversations.needPhone'), style: TextStyle(fontSize: 14, color: c.textPrimary)),
                GestureDetector(
                  onTap: () => context.push('/complete-profile'),
                  child: Text(t('completeProfile.completeNow'),
                      style: TextStyle(color: c.primary, decoration: TextDecoration.underline, fontSize: 14)),
                ),
              ]),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
              child: LayoutBuilder(builder: (context, box) {
                final form = <Widget>[
                  Text(t('groups.groupName'), style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _name,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 16, color: c.textPrimary),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: t('groups.groupNamePlaceholder'),
                      hintStyle: TextStyle(color: c.textMuted),
                      filled: true,
                      fillColor: c.bgCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.primary)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(t('groups.groupPhoto'), style: label),
                  const SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      onTap: _uploading ? null : _pickImage,
                      child: Opacity(
                        opacity: _uploading ? 0.7 : 1,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: c.bgCard, border: Border.all(color: c.border, width: 2)),
                          clipBehavior: Clip.antiAlias,
                          child: _imageUrl != null && isImageAvatar(_imageUrl)
                              ? CachedNetworkImage(imageUrl: Api.absoluteUrl(_imageUrl)!, fit: BoxFit.cover)
                              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(LucideIcons.image, size: 40, color: c.textMuted),
                                  const SizedBox(height: 4),
                                  Text(_uploading ? t('settings.uploading') : t('settings.chooseImage'),
                                      style: TextStyle(fontSize: 12, color: c.textMuted)),
                                ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(t('groups.selectMembers'), style: label),
                  const SizedBox(height: 8),
                ];
                final actions = <Widget>[
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontSize: 14)),
                    ),
                  PillButton(label: t('groups.create'), onPressed: canCreate ? _create : null),
                ];
                if (_contacts.isEmpty) {
                  return SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ...form,
                      contactsSection,
                      const SizedBox(height: 24),
                      ...actions,
                    ]),
                  );
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ...form,
                  Expanded(child: contactsSection),
                  const SizedBox(height: 12),
                  ...actions,
                ]);
              }),
            ),
          ),
        ]),
      ),
      LoaderOverlay(show: _creating, text: t('groups.creating')),
    ]);
  }
}
