import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/storage/prefs.dart';
import '../../core/phone_validation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import '../auth/auth_widgets.dart';
import 'avatar_overrides.dart';
import 'conversations_list_controller.dart';
import 'open_private.dart';
import 'phone_book_sync_sheet.dart';

/// components/ContactsPanel.vue
class ContactsPanel extends ConsumerStatefulWidget {
  const ContactsPanel({super.key});

  @override
  ConsumerState<ContactsPanel> createState() => ContactsPanelState();
}

class ContactsPanelState extends ConsumerState<ContactsPanel> {
  List<Json> _contacts = [];
  bool _loaded = false;
  bool _needPhone = false;
  String? _openingId;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchContacts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> fetchContacts() async {
    _needPhone = false;
    const cacheKey = 'nexchat_contacts_cache';
    final cached = Prefs.instance.getString(cacheKey);
    if (cached != null) {
      try {
        _contacts = asJsonList(jsonDecode(cached));
      } catch (_) {}
    }
    if (!NetworkStatus.online.value) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      _contacts = asJsonList(await Api.get('/contacts'));
      Prefs.instance.setString(cacheKey, jsonEncode(_contacts));
    } catch (e) {
      if (Api.errorMessage(e).contains('رقم الهاتف')) _needPhone = true;
      if (_contacts.isEmpty) _contacts = [];
    }
    if (mounted) setState(() => _loaded = true);
  }

  String _phone(Json c) {
    final p = c.s('phoneNumber')?.trim() ?? '';
    if (p.isEmpty) return t('profile.phoneNotSet');
    return p.startsWith('+') ? p : '+${p.replaceAll(RegExp(r'\D'), '')}';
  }

  Future<void> _start(Json contact) async {
    if (_openingId != null) return;
    if (!NetworkStatus.online.value) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    final id = contact.str('contactUserId');
    setState(() => _openingId = id);
    try {
      final convId = await createPrivateConversationOrRequest(id);
      if (!mounted) return;
      if (convId != null) {
        context.push('/conversation/$convId');
      } else {
        await ref.read(pendingRequestsProvider.notifier).fetch();
        if (mounted) goToMessageRequestsOutgoingNotice(context);
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _remove(Json contact) async {
    try {
      await Api.delete('/contacts/${contact.str('contactUserId')}');
      if (!mounted) return;
      setState(() => _contacts.removeWhere((c) => c.str('contactUserId') == contact.str('contactUserId')));
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  Future<void> _block(Json contact) async {
    try {
      await Api.post('/blocks/${contact.str('contactUserId')}');
      if (!mounted) return;
      setState(() => _contacts.removeWhere((c) => c.str('contactUserId') == contact.str('contactUserId')));
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  void _openMenu(Json contact) {
    final avatar = ref.read(avatarOverridesProvider)[contact.str('contactUserId')] ?? contact.s('avatar');
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            UserAvatar(url: avatar, name: contact.str('name'), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(contact.str('name'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.colors.textPrimary)),
            ),
          ]),
        ),
        SheetAction(
          icon: LucideIcons.userMinus,
          label: t('contacts.removeFriend'),
          onTap: () {
            Navigator.pop(ctx);
            _remove(contact);
          },
        ),
        SheetAction(
          icon: LucideIcons.ban,
          label: t('contacts.block'),
          danger: true,
          onTap: () {
            Navigator.pop(ctx);
            _block(contact);
          },
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SoftButton(label: t('common.cancel'), onPressed: () => Navigator.pop(ctx)),
        ),
      ]),
    );
  }

  void openAddModal() {
    showAppSheet<bool>(context, builder: (ctx) => const _AddContactSheet()).then((added) {
      if (added == true) fetchContacts();
    });
  }

  void openPhoneBookSync() {
    showAppSheet<bool>(context, builder: (ctx) => const PhoneBookSyncSheet()).then((added) {
      if (added == true) fetchContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overrides = ref.watch(avatarOverridesProvider);
    final q = _search.text.trim();
    final list = q.isEmpty
        ? _contacts
        : _contacts.where((x) => x.str('name').toLowerCase().contains(q.toLowerCase()) || x.str('phoneNumber').contains(q)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, tabScrollPadding(context, extra: 16)),
      children: [
        if (_needPhone)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 8),
            color: const Color(0x26FFC107),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Icon(LucideIcons.circleAlert, size: 20, color: c.textPrimary),
              Text(t('contacts.needPhone'), style: TextStyle(color: c.textPrimary)),
              GestureDetector(
                onTap: () => context.push('/complete-profile'),
                child: Text(t('completeProfile.completeNow'), style: TextStyle(color: c.primary, decoration: TextDecoration.underline)),
              ),
            ]),
          ),
        if (!_needPhone && _loaded)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: c.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: openPhoneBookSync,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(LucideIcons.contact, size: 20, color: c.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('contacts.findFromPhoneBook'), style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
                        const SizedBox(height: 2),
                        Text(t('contacts.findFromPhoneBookHint'), style: TextStyle(fontSize: 12, color: c.textSecondary)),
                      ]),
                    ),
                    Icon(LucideIcons.chevronLeft, size: 18, color: c.textMuted),
                  ]),
                ),
              ),
            ),
          ),
        if (_contacts.isNotEmpty) ...[
          SearchField(controller: _search, hint: t('contacts.searchPlaceholder'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
        ],
        if (!_loaded)
          Padding(padding: const EdgeInsets.all(48), child: Center(child: CircularProgressIndicator(color: c.primary)))
        else if (_contacts.isEmpty && !_needPhone)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Column(children: [
              Icon(LucideIcons.userPlus, size: 48, color: c.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(t('contacts.empty'), style: TextStyle(color: c.textMuted, fontSize: 15)),
              const SizedBox(height: 6),
              Text(t('contacts.addFirst'), style: TextStyle(color: c.textMuted, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(width: 240, child: PillButton(label: t('contacts.addContact'), onPressed: openAddModal)),
              const SizedBox(height: 10),
              SizedBox(
                width: 240,
                child: SoftButton(
                  label: t('contacts.findFromPhoneBook'),
                  onPressed: _needPhone ? null : openPhoneBookSync,
                ),
              ),
            ]),
          )
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(48),
            child: Center(child: Text(t('contacts.noSearchResults'), style: TextStyle(color: c.textMuted))),
          )
        else
          for (final contact in list)
            Stack(children: [
              ModernListRow(
                leading: UserAvatar(url: overrides[contact.str('contactUserId')] ?? contact.s('avatar'), name: contact.str('name'), size: 52),
                title: contact.str('name'),
                subtitle: _phone(contact),
                subtitleLtr: true,
                onTap: () => _start(contact),
                onLongPress: () => _openMenu(contact),
                trailing: IconButton(
                  onPressed: () => _openMenu(contact),
                  icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: c.textMuted),
                ),
              ),
              if (_openingId == contact.str('contactUserId'))
                Positioned.fill(
                  bottom: 8,
                  child: Container(
                    decoration: BoxDecoration(color: c.bgCard.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(AppRadius.lg)),
                    alignment: Alignment.center,
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
                  ),
                ),
            ]),
      ],
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet();

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  String _country = 'IQ';
  final _phone = TextEditingController();
  bool _loading = false;
  String _error = '';

  String get _dial => countryByCode(_country)?.dialCode ?? countries.first.dialCode;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final code = _dial.isEmpty ? '964' : _dial;
    final r = validatePhone(code, _phone.text);
    if (!r.valid) {
      setState(() => _error = r.message);
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Api.post('/contacts', {'countryCode': code, 'phoneNumber': r.normalized});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget label(IconData icon, String text) => Row(children: [
          Icon(icon, size: 16, color: c.textSecondary),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ]);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('contacts.addByPhone'),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
        const SizedBox(height: 16),
        label(LucideIcons.phone, t('completeProfile.phone')),
        const SizedBox(height: 8),
        PhoneAuthField(
          countryCode: _country,
          controller: _phone,
          hint: t('contacts.phonePlaceholder'),
          onCountryChanged: (x) => setState(() => _country = x.code),
          onChanged: (_) => setState(() {}),
        ),
        if (_error.isNotEmpty) ...[const SizedBox(height: 12), AuthError(_error)],
        const SizedBox(height: 20),
        PillButton(label: _loading ? t('common.loading') : t('contacts.addContact'), onPressed: _loading ? null : _add),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('common.cancel'), style: TextStyle(color: c.textSecondary))),
      ]),
    );
  }
}
