import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../core/device_phone_contacts.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../data/countries.dart';
import '../../shared/widgets.dart';
import 'avatar_overrides.dart';
import 'conversations_list_controller.dart';
import 'open_private.dart';

/// مطابقة سجل هاتف الجهاز مع حسابات NexChat.
class PhoneBookSyncSheet extends ConsumerStatefulWidget {
  const PhoneBookSyncSheet({super.key});

  @override
  ConsumerState<PhoneBookSyncSheet> createState() => _PhoneBookSyncSheetState();
}

class _PhoneBookSyncSheetState extends ConsumerState<PhoneBookSyncSheet> {
  bool _loading = true;
  String _error = '';
  List<Json> _matches = [];
  final Set<String> _busy = {};
  bool _addedAny = false;
  bool _deniedForever = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() {
      _loading = true;
      _error = '';
      _deniedForever = false;
    });
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      final allowed = status == PermissionStatus.granted || status == PermissionStatus.limited;
      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _deniedForever =
              status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted;
          _error = _deniedForever ? t('contacts.phoneBookDeniedForever') : t('contacts.phoneBookDenied');
        });
        return;
      }

      final dial = await _userDialCode();
      final device = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.name},
      );
      final payload = <Map<String, String>>[];
      final seen = <String>{};

      for (final c in device) {
        final name = (c.displayName ?? '').trim();
        for (final p in c.phones) {
          final raws = <String>{
            p.number,
            if (p.normalizedNumber != null && p.normalizedNumber!.isNotEmpty) p.normalizedNumber!,
          };
          for (final raw in raws) {
            for (final candidate in candidatePhonesFromDevice(raw, defaultDialCode: dial)) {
              if (seen.add(candidate)) {
                final row = <String, String>{'phone': candidate};
                if (name.isNotEmpty) row['name'] = name;
                payload.add(row);
              }
            }
          }
        }
      }

      if (payload.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _matches = [];
          _error = t('contacts.phoneBookEmpty');
        });
        return;
      }

      final all = <Json>[];
      const chunk = 400;
      for (var i = 0; i < payload.length; i += chunk) {
        final end = i + chunk > payload.length ? payload.length : i + chunk;
        final slice = payload.sublist(i, end);
        final res = await Api.post('/contacts/lookup', {'contacts': slice});
        all.addAll(asJsonList(res));
      }

      final byId = <String, Json>{};
      for (final m in all) {
        byId[m.str('userId')] = m;
      }

      if (!mounted) return;
      setState(() {
        _matches = byId.values.toList()
          ..sort((a, b) {
            final ac = a.b('isContact') ? 1 : 0;
            final bc = b.b('isContact') ? 1 : 0;
            if (ac != bc) return ac.compareTo(bc);
            return a.str('name').toLowerCase().compareTo(b.str('name').toLowerCase());
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Api.errorMessage(e, t('common.error'));
      });
    }
  }

  Future<String> _userDialCode() async {
    try {
      final me = await Api.get('/user/me') as Map;
      final country = me.s('country');
      final fromCountry = countryByCode(country)?.dialCode;
      if (fromCountry != null && fromCountry.isNotEmpty) return fromCountry;

      final phone = (me.s('phoneNumber') ?? '').replaceAll(RegExp(r'\D'), '');
      for (final c in countries) {
        if (phone.startsWith(c.dialCode) && phone.length > c.dialCode.length + 6) {
          return c.dialCode;
        }
      }
    } catch (_) {}
    return '964';
  }

  Future<void> _addFriend(Json match) async {
    final id = match.str('userId');
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      if (!match.b('isContact')) {
        await Api.post('/contacts/by-user/$id');
      }
      _addedAny = true;

      // بعد الإضافة: افتح محادثة إن وُجد قبول متبادل، وإلا أرسل طلب صداقة/مراسلة
      final convId = await createPrivateConversationOrRequest(id);
      if (!mounted) return;

      if (convId != null) {
        Navigator.pop(context, true);
        context.push('/conversation/$convId');
        return;
      }

      setState(() {
        final i = _matches.indexWhere((m) => m.str('userId') == id);
        if (i >= 0) {
          final copy = Map<String, dynamic>.from(_matches[i]);
          copy['isContact'] = true;
          copy['hasOutgoingRequest'] = true;
          _matches[i] = copy;
        }
      });
      await ref.read(pendingRequestsProvider.notifier).fetch();
      if (!mounted) return;
      Navigator.pop(context, true);
      goToMessageRequestsOutgoingNotice(context);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _message(Json match) async {
    final id = match.str('userId');
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      if (!match.b('isContact')) {
        try {
          await Api.post('/contacts/by-user/$id');
          _addedAny = true;
        } catch (_) {}
      }
      final convId = await createPrivateConversationOrRequest(id);
      if (!mounted) return;
      Navigator.pop(context, _addedAny);
      if (convId != null) {
        context.push('/conversation/$convId');
      } else {
        await ref.read(pendingRequestsProvider.notifier).fetch();
        if (mounted) goToMessageRequestsOutgoingNotice(context);
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overrides = ref.watch(avatarOverridesProvider);
    final found = _matches.where((m) => !m.b('isContact')).length;
    final bottomPad = 12 + MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(children: [
            Text(t('contacts.phoneBookTitle'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
            const SizedBox(height: 6),
            Text(
              _loading ? t('contacts.phoneBookScanning') : t('contacts.phoneBookSubtitle', {'count': '$found'}),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.45, fontWeight: FontWeight.w500),
            ),
          ]),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error.isNotEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                  child: Icon(LucideIcons.contact, size: 32, color: c.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.5, color: c.textSecondary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                if (_deniedForever)
                  PillButton(label: t('contacts.openSettings'), onPressed: openAppSettings)
                else
                  PillButton(label: t('common.retry'), onPressed: _sync),
              ]),
            ),
          )
        else if (_matches.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                  child: Icon(LucideIcons.users, size: 32, color: c.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  t('contacts.phoneBookNoMatches'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.5, color: c.textSecondary, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: _matches.length,
              itemBuilder: (_, i) {
                final m = _matches[i];
                final id = m.str('userId');
                final isContact = m.b('isContact');
                final pending = m.b('hasOutgoingRequest');
                final busy = _busy.contains(id);
                final deviceName = m.s('deviceName');
                final phone = m.s('phoneNumber') ?? '';
                final phoneLabel = phone.isEmpty ? '' : (phone.startsWith('+') ? phone : '+$phone');
                final subtitle = [
                  if (deviceName != null && deviceName.isNotEmpty && deviceName != m.str('name')) deviceName,
                  if (phoneLabel.isNotEmpty) phoneLabel,
                ].where((s) => s.isNotEmpty).join(' · ');

                Widget trailing;
                if (busy) {
                  trailing = SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary));
                } else if (pending) {
                  trailing = Text(t('contacts.requestPending'),
                      style: TextStyle(color: c.textMuted, fontWeight: FontWeight.w600, fontSize: 12));
                } else if (isContact) {
                  trailing = TextButton(
                    onPressed: () => _message(m),
                    child: Text(t('contacts.message'), style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
                  );
                } else {
                  trailing = TextButton(
                    onPressed: () => _addFriend(m),
                    child: Text(t('contacts.addFriend'),
                        style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ModernListRow(
                    leading: UserAvatar(url: overrides[id] ?? m.s('avatar'), name: m.str('name'), size: 48),
                    title: m.str('name'),
                    subtitle: subtitle.isEmpty ? null : subtitle,
                    subtitleLtr: true,
                    trailing: trailing,
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
          child: SoftButton(
            label: t('common.close'),
            onPressed: () => Navigator.pop(context, _addedAny),
          ),
        ),
      ]),
    );
  }
}
