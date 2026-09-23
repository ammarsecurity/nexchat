import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/phone_validation.dart';
import '../../core/theme/app_colors.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_widgets.dart';

/// views/auth/CompleteProfileView.vue — back button only when opened from settings.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key, this.fromSettings = false});
  final bool fromSettings;

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  String? _country;
  final _phone = TextEditingController();
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await Api.get('/user/me') as Map;
      final c = me.s('country');
      final p = me.s('phoneNumber');
      if (!mounted) return;
      setState(() {
        if (c != null && countries.any((x) => x.code == c)) _country = c;
        if (p != null) {
          final dial = _dialFor(c);
          _phone.text = dial.isNotEmpty && p.startsWith(dial) ? p.substring(dial.length) : p;
        }
      });
    } catch (_) {}
  }

  String _dialFor(String? code) => countryByCode(code)?.dialCode ?? '';

  String get _dial => _dialFor(_country);

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/settings');
    }
  }

  PhoneResult? get _validation =>
      _dial.isEmpty || _phone.text.trim().isEmpty ? null : validatePhone(_dial, _phone.text);

  Future<void> _submit() async {
    final r = _validation;
    if (r == null || !r.valid) {
      setState(() => _error = r?.message ?? t('phoneValidation.required'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Api.put('/user/profile-contact', {'country': _country, 'countryCode': _dial, 'phoneNumber': r.normalized});
      ref.read(authProvider.notifier).setNeedsProfileContact(false);
      if (!mounted) return;
      if (widget.fromSettings) {
        _leave();
        return;
      }
      await navigateDefaultForSession(GoRouter.of(context), ref);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    final validation = _validation;
    final phoneError = validation != null && !validation.valid ? validation.message : '';
    final canSubmit = _country != null && (validation?.valid ?? false) && !_loading;

    Widget label(IconData icon, String text) => Row(children: [
          Icon(icon, size: 16, color: c.primary),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ]);

    final fieldBorder = BorderRadius.circular(AppRadius.sm);

    final page = PopScope(
      canPop: widget.fromSettings,
      child: Scaffold(
        backgroundColor: c.bgPrimary,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.fromSettings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Material(
                          color: c.bgCard,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _leave,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft, size: 22, color: c.textPrimary),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(t('completeProfile.title'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
                        ),
                        const SizedBox(width: 44),
                      ]),
                    ),
                  Center(child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 48)),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: c.primarySoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: c.primaryMuted),
                      ),
                      child: Icon(LucideIcons.userRound, size: 28, color: c.primary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!widget.fromSettings) ...[
                    Text(t('completeProfile.title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.25, color: c.textPrimary)),
                    const SizedBox(height: 8),
                  ],
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(t('completeProfile.subtitle'),
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.55, color: c.textSecondary)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        label(LucideIcons.globe, t('completeProfile.country')),
                        const SizedBox(height: 8),
                        CountryPickerField(
                          value: _country,
                          onChanged: (x) => setState(() => _country = x.code),
                        ),
                        const SizedBox(height: 18),
                        label(LucideIcons.phone, t('completeProfile.phone')),
                        const SizedBox(height: 8),
                        Container(
                          height: 50,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: c.bgElevated,
                            borderRadius: fieldBorder,
                            border: Border.all(color: phoneError.isNotEmpty ? c.danger : c.border),
                          ),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(children: [
                              Container(
                                constraints: const BoxConstraints(minWidth: 68),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.primarySoft,
                                  border: BorderDirectional(end: BorderSide(color: c.border)),
                                ),
                                child: Text('+${_dial.isEmpty ? '…' : _dial}',
                                    style: TextStyle(color: c.primary, fontSize: 15, fontWeight: FontWeight.w700)),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 15,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(color: c.textPrimary, fontSize: 16),
                                  decoration: InputDecoration(
                                    counterText: '',
                                    hintText: t('completeProfile.phonePlaceholder'),
                                    hintStyle: TextStyle(color: c.textMuted),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          phoneError.isNotEmpty ? phoneError : t('completeProfile.phoneHint'),
                          style: TextStyle(fontSize: 12, height: 1.45, color: phoneError.isNotEmpty ? c.danger : c.textMuted),
                        ),
                        if (_error.isNotEmpty) ...[const SizedBox(height: 18), AuthError(_error)],
                        const SizedBox(height: 22),
                        GradientButton(
                          label: t('completeProfile.submit'),
                          height: 52,
                          onPressed: canSubmit && !_loading ? _submit : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(fit: StackFit.expand, children: [page, LoaderOverlay(show: _loading, text: t('completeProfile.saving'))]);
  }
}
