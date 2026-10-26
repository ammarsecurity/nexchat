import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'discover_controller.dart';
import 'discover_theme.dart';

Future<bool> showDiscoverFiltersSheet(BuildContext context) async {
  final ok = await showAppSheet<bool>(context, builder: (_) => const _DiscoverFiltersSheet());
  return ok == true;
}

class _DiscoverFiltersSheet extends ConsumerStatefulWidget {
  const _DiscoverFiltersSheet();

  @override
  ConsumerState<_DiscoverFiltersSheet> createState() => _DiscoverFiltersSheetState();
}

class _DiscoverFiltersSheetState extends ConsumerState<_DiscoverFiltersSheet> {
  late String _gender;
  late RangeValues _ages;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(discoverProvider).prefs;
    _gender = p.preferGender;
    // Slider is 18–60; clamp so RangeSlider never asserts on out-of-range prefs.
    final min = p.ageMin.clamp(18, 60).toDouble();
    final max = p.ageMax.clamp(18, 60).toDouble();
    _ages = RangeValues(min, max < min ? min : max);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(discoverProvider.notifier).savePrefs(DiscoverPrefs(
            preferGender: _gender,
            ageMin: _ages.start.round(),
            ageMax: _ages.end.round(),
          ));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('discover.filtersTitle'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DiscoverTheme.ink)),
              ),
              GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context, false)),
            ],
          ),
          const SizedBox(height: 6),
          Text(t('discover.filtersHint'), style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.35)),
          const SizedBox(height: 18),
          Text(t('discover.filterGender'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: DiscoverTheme.ink)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in [
                ('all', t('discover.filterAll')),
                ('male', t('profile.genderMale')),
                ('female', t('profile.genderFemale')),
              ])
                _Chip(
                  label: opt.$2,
                  selected: _gender == opt.$1,
                  onTap: () => setState(() => _gender = opt.$1),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(t('discover.filterAge'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: DiscoverTheme.ink)),
              ),
              Text(
                '${_ages.start.round()} – ${_ages.end.round()}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: DiscoverTheme.red),
              ),
            ],
          ),
          RangeSlider(
            values: _ages,
            min: 18,
            max: 60,
            divisions: 42,
            activeColor: DiscoverTheme.red,
            inactiveColor: DiscoverTheme.red.withValues(alpha: 0.18),
            labels: RangeLabels('${_ages.start.round()}', '${_ages.end.round()}'),
            onChanged: (v) => setState(() => _ages = v),
          ),
          const SizedBox(height: 12),
          PillButton(
            label: _saving ? t('common.loading') : t('discover.filtersApply'),
            color: DiscoverTheme.red,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DiscoverTheme.red : context.colors.bgElevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? Colors.white : DiscoverTheme.ink,
            ),
          ),
        ),
      ),
    );
  }
}
