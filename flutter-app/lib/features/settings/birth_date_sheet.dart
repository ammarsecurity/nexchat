import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import '../auth/auth_widgets.dart';

/// Day / month / year selects (same UX as register & settings).
/// Pass [accent] (e.g. Discover red) so the save CTA matches the host screen.
Future<String?> showBirthDateSheet(BuildContext context, {String? initial, Color? accent}) =>
    showAppSheet<String>(context, builder: (_) => BirthDateSheet(initial: initial, accent: accent));

class BirthDateSheet extends StatefulWidget {
  const BirthDateSheet({super.key, this.initial, this.accent});
  final String? initial;
  final Color? accent;

  @override
  State<BirthDateSheet> createState() => _BirthDateSheetState();
}

class _BirthDateSheetState extends State<BirthDateSheet> {
  int? _d, _m, _y;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _applyInitial(widget.initial);
    if (widget.initial == null || widget.initial!.trim().isEmpty) {
      // Prefill from profile without blocking the sheet from opening.
      () async {
        try {
          final me = await Api.get('/user/me');
          if (!mounted || me is! Map) return;
          final bd = (me['birthDate'] ?? me['BirthDate'])?.toString();
          if (bd == null || bd.isEmpty) return;
          setState(() => _applyInitial(bd));
        } catch (_) {}
      }();
    }
  }

  void _applyInitial(String? raw) {
    final b = raw?.split('T').first;
    if (b == null || b.isEmpty) return;
    final p = b.split('-').map(int.tryParse).toList();
    if (p.length >= 3 && p[0] != null && p[1] != null && p[2] != null) {
      _y = p[0];
      _m = p[1];
      _d = p[2];
      _clampDay();
    }
  }

  int get _daysInMonth {
    final m = _m, y = _y;
    if (m == null) return 31;
    final leap = y != null && (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
    return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
  }

  String? get _dateStr {
    if (_d == null || _m == null || _y == null) return null;
    return '$_y-${'$_m'.padLeft(2, '0')}-${'$_d'.padLeft(2, '0')}';
  }

  void _clampDay() {
    if (_d != null && _d! > _daysInMonth) _d = _daysInMonth;
  }

  Future<void> _save() async {
    final s = _dateStr;
    if (s == null) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await Api.put('/user/birth-date', {'birthDate': s});
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final year = DateTime.now().year;
    final years = [for (var y = year - 18; y >= year - 120; y--) y];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('settings.editBirthDate'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 2,
            child: DateSelect(
              hint: t('register.day'),
              value: _d,
              items: [for (var i = 1; i <= _daysInMonth; i++) i],
              onChanged: (v) => setState(() => _d = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: DateSelect(
              hint: t('register.month'),
              value: _m,
              items: [for (var i = 1; i <= 12; i++) i],
              onChanged: (v) => setState(() {
                _m = v;
                _clampDay();
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DateSelect(
              hint: t('register.year'),
              value: _y,
              items: years,
              onChanged: (v) => setState(() {
                _y = v;
                _clampDay();
              }),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(t('register.birthDateHint'), style: TextStyle(fontSize: 12, color: c.textMuted)),
        if (_error.isNotEmpty) ...[const SizedBox(height: 12), AuthError(_error)],
        const SizedBox(height: 12),
        PillButton(
          label: _saving ? t('common.loading') : t('settings.saveBirthDate'),
          color: widget.accent,
          onPressed: _saving || _dateStr == null ? null : _save,
        ),
      ]),
    );
  }
}

/// True when [iso] is a birth date of someone at least 18 (Iraq-ish: local calendar day).
bool isAdultBirthDate(String? iso) {
  final b = iso?.split('T').first;
  if (b == null || b.isEmpty) return false;
  final p = b.split('-');
  if (p.length < 3) return false;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return false;
  final birth = DateTime(y, m, d);
  final now = DateTime.now();
  var age = now.year - birth.year;
  if (birth.month > now.month || (birth.month == now.month && birth.day > now.day)) age--;
  return age >= 18;
}
