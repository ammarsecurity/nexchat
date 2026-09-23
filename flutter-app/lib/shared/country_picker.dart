import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/countries.dart';
import 'widgets.dart';

class CountryPickerField extends StatelessWidget {
  const CountryPickerField({super.key, required this.value, required this.onChanged, this.hint});
  final String? value;
  final ValueChanged<Country> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = countryByCode(value);
    return Material(
      color: c.bgElevated,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () async {
          final picked = await showCountryPicker(context, selectedCode: value);
          if (picked != null) onChanged(picked);
        },
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Icon(LucideIcons.globe, size: 18, color: c.primary),
            const SizedBox(width: 10),
            Expanded(
              child: selected == null
                  ? Text(hint ?? t('completeProfile.selectCountry'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: kAppFont, fontSize: 15, color: c.textMuted))
                  : Text(selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: kAppFont, fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
            ),
            if (selected != null) ...[
              const SizedBox(width: 8),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(selected.plusDial,
                    style: TextStyle(fontFamily: kAppFont, fontSize: 14, fontWeight: FontWeight.w700, color: c.primary)),
              ),
              const SizedBox(width: 8),
            ],
            Icon(LucideIcons.chevronDown, size: 18, color: c.textMuted),
          ]),
        ),
      ),
    );
  }
}

Future<Country?> showCountryPicker(BuildContext context, {String? selectedCode}) {
  return showAppSheet<Country>(context, builder: (_) => _CountryPickerSheet(selectedCode: selectedCode));
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selectedCode});
  final String? selectedCode;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _search.text;
    final list = q.trim().isEmpty ? countries : countries.where((x) => x.matches(q)).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(t('completeProfile.selectCountry'),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: kAppFont, fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontFamily: kAppFont, fontSize: 15, color: c.textPrimary),
            decoration: InputDecoration(
              hintText: t('completeProfile.searchCountry'),
              hintStyle: TextStyle(fontFamily: kAppFont, color: c.textMuted),
              prefixIcon: Icon(LucideIcons.search, size: 20, color: c.textMuted),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: Icon(LucideIcons.x, size: 18, color: c.textMuted),
                    ),
              filled: true,
              fillColor: c.bgElevated,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.primary)),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(t('common.noResults'),
                      style: TextStyle(fontFamily: kAppFont, fontSize: 14, color: c.textMuted)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.7)),
                  itemBuilder: (_, i) {
                    final x = list[i];
                    final active = x.code == widget.selectedCode;
                    return Material(
                      color: active ? c.primarySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(context, x),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(children: [
                            Expanded(
                              child: Text(x.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 15,
                                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                    color: c.textPrimary,
                                  )),
                            ),
                            const SizedBox(width: 12),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(x.plusDial,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: active ? c.primary : c.textSecondary,
                                  )),
                            ),
                            if (active) ...[
                              const SizedBox(width: 8),
                              Icon(LucideIcons.check, size: 18, color: c.primary),
                            ],
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
