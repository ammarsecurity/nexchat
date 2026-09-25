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
            // قابل للإضافة أولاً، ثم المراسلة، ثم بانتظار القبول
            int rank(Json m) {
              if (m.b('hasOutgoingRequest')) return 2;
              if (m.b('isContact')) return 1;
              return 0;
            }

            final r = rank(a).compareTo(rank(b));
            if (r != 0) return r;
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
    final canAdd = _matches.where((m) => !m.b('isContact') && !m.b('hasOutgoingRequest')).length;
    final bottomPad = 12 + MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: c.primary.withValues(alpha: 0.16)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(LucideIcons.contact, size: 20, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    t('contacts.phoneBookTitle'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _loading
                        ? t('contacts.phoneBookScanning')
                        : t('contacts.phoneBookSubtitle', {'count': '$canAdd'}),
                    style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        if (_loading)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: c.primary),
                ),
                const SizedBox(height: 14),
                Text(t('contacts.phoneBookScanning'), style: TextStyle(fontSize: 13, color: c.textMuted, fontWeight: FontWeight.w600)),
              ]),
            ),
          )
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
            child: EmptyState(icon: LucideIcons.users, text: t('contacts.phoneBookNoMatches')),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: _matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = _matches[i];
                final id = m.str('userId');
                final isContact = m.b('isContact');
                final pending = m.b('hasOutgoingRequest');
                final busy = _busy.contains(id);
                final deviceName = m.s('deviceName');
                final phone = m.s('phoneNumber') ?? '';
                final phoneLabel = phone.isEmpty ? '' : (phone.startsWith('+') ? phone : '+$phone');
                final showDevice = deviceName != null && deviceName.isNotEmpty && deviceName != m.str('name');

                return _ContactRow(
                  name: m.str('name'),
                  avatarUrl: overrides[id] ?? m.s('avatar'),
                  deviceName: showDevice ? deviceName : null,
                  phoneLabel: phoneLabel,
                  busy: busy,
                  pending: pending,
                  isContact: isContact,
                  onAdd: () => _addFriend(m),
                  onMessage: () => _message(m),
                );
              },
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
          child: SoftButton(
            label: t('common.close'),
            onPressed: () => Navigator.pop(context, _addedAny),
          ),
        ),
      ]),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.name,
    required this.avatarUrl,
    required this.deviceName,
    required this.phoneLabel,
    required this.busy,
    required this.pending,
    required this.isContact,
    required this.onAdd,
    required this.onMessage,
  });

  final String name;
  final String? avatarUrl;
  final String? deviceName;
  final String phoneLabel;
  final bool busy;
  final bool pending;
  final bool isContact;
  final VoidCallback onAdd;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: c.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: c.border.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(children: [
          UserAvatar(url: avatarUrl, name: name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary),
              ),
              if (deviceName != null) ...[
                const SizedBox(height: 2),
                Text(
                  deviceName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontWeight: FontWeight.w500),
                ),
              ],
              if (phoneLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  phoneLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 12.5, color: c.textMuted, fontWeight: FontWeight.w500),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          if (busy)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: c.primary),
            )
          else if (pending)
            _StatusChip(
              label: t('contacts.requestPending'),
              fg: const Color(0xFFD97706),
              bg: const Color(0x1AF59E0B),
            )
          else if (isContact)
            _ActionChip(label: t('contacts.message'), filled: true, onTap: onMessage)
          else
            _ActionChip(label: t('contacts.addFriend'), filled: false, onTap: onAdd),
        ]),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg, height: 1.1, decoration: TextDecoration.none),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.filled, required this.onTap});
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: filled ? c.primary : c.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: filled ? Colors.white : c.primary,
              height: 1.1,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
