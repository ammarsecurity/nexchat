import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/countries.dart';
import 'widgets.dart';

/// حقل هاتف موحّد بأسلوب AuthField: مفتاح الدولة كبادئة قابلة للضغط + الرقم.
class PhoneAuthField extends StatelessWidget {
  const PhoneAuthField({
    super.key,
    required this.countryCode,
    required this.controller,
    required this.onCountryChanged,
    this.onChanged,
    this.hint,
    this.error = false,
  });

  final String? countryCode;
  final TextEditingController controller;
  final ValueChanged<Country> onCountryChanged;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final country = countryByCode(countryCode);
    final dial = country?.plusDial ?? '+…';
    final borderColor = error ? c.danger : c.border;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: borderColor),
    );

    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      maxLength: 15,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
      style: TextStyle(fontFamily: kAppFont, color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint ?? t('completeProfile.phonePlaceholder'),
        hintStyle: TextStyle(fontFamily: kAppFont, color: c.textMuted),
        filled: true,
        fillColor: c.bgCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: error ? c.danger : c.primary),
        ),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final picked = await showCountryPicker(context, selectedCode: countryCode);
                if (picked != null) onCountryChanged(picked);
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.globe, size: 18, color: c.primary),
                    const SizedBox(width: 6),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        dial,
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(LucideIcons.chevronDown, size: 16, color: c.textMuted),
                    Container(
                      margin: const EdgeInsetsDirectional.only(start: 8),
                      width: 1,
                      height: 22,
                      color: c.border,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

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
      color: c.bgCard,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      shadowColor: c.shadow,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showCountryPicker(context, selectedCode: value);
          if (picked != null) onChanged(picked);
        },
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 4)],
          ),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(LucideIcons.globe, size: 18, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: selected == null
                  ? Text(hint ?? t('completeProfile.selectCountry'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: kAppFont, fontSize: 15, fontWeight: FontWeight.w500, color: c.textMuted))
                  : Text(selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: kAppFont, fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ),
            if (selected != null) ...[
              const SizedBox(width: 8),
              _DialChip(text: selected.plusDial, emphasized: true),
              const SizedBox(width: 6),
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
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
          child: Text(
            t('completeProfile.selectCountry'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: kAppFont, fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: SearchField(
            controller: _search,
            hint: t('completeProfile.searchCountry'),
            autofocus: true,
            onChanged: (_) => setState(() {}),
            trailing: q.isEmpty
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                    icon: Icon(LucideIcons.x, size: 18, color: c.textMuted),
                  ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                        child: Icon(LucideIcons.searchSlash, size: 28, color: c.primary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t('common.noResults'),
                        style: TextStyle(fontFamily: kAppFont, fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary),
                      ),
                    ]),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final x = list[i];
                    final active = x.code == widget.selectedCode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: active ? c.primarySoft : c.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(context, x),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: active ? c.primary.withValues(alpha: 0.35) : c.border),
                              boxShadow: active ? null : [BoxShadow(color: c.shadow, blurRadius: 4)],
                            ),
                            child: Row(children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active ? c.primary.withValues(alpha: 0.15) : c.bgElevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  x.code,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: active ? c.primary : c.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  x.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 15,
                                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _DialChip(text: x.plusDial, emphasized: active),
                              if (active) ...[
                                const SizedBox(width: 8),
                                Icon(LucideIcons.check, size: 18, color: c.primary),
                              ],
                            ]),
                          ),
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

class _DialChip extends StatelessWidget {
  const _DialChip({required this.text, this.emphasized = false});
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: emphasized ? c.primary.withValues(alpha: 0.12) : c.bgElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: emphasized ? c.primary.withValues(alpha: 0.25) : c.border),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: kAppFont,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: emphasized ? c.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }
}
