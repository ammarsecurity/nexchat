import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/phone_validation.dart';
import '../../core/theme/layout.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_hero_shell.dart';
import 'auth_widgets.dart';
import 'register_otp_screen.dart';

/// Register — same visual language as onboarding (hero + wave + pill CTA).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.invite});
  final String? invite;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  String _country = 'IQ';
  int? _day, _month, _year;
  String _gender = '';
  bool _accepted = false;
  bool _loading = false;
  String _error = '';
  bool? _otpEnabled;

  String get _dial => countryByCode(_country)?.dialCode ?? '964';

  @override
  void initState() {
    super.initState();
    _loadOtpStatus();
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadOtpStatus() async {
    try {
      final data = await Api.get('otp/status', skipUnauthorized: true);
      if (!mounted) return;
      final map = data is Map ? data : <String, dynamic>{};
      final enabled = map['enabled'] == true || map['Enabled'] == true;
      final configured = map['configured'] == true || map['Configured'] == true;
      setState(() => _otpEnabled = enabled && configured);
    } catch (_) {
      if (mounted) setState(() => _otpEnabled = false);
    }
  }

  int get _daysInMonth {
    final m = _month;
    if (m == null) return 31;
    final y = _year ?? 0;
    final leap = y != 0 && (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
    return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
  }

  String get _birthDate {
    if (_day == null || _month == null || _year == null) return '';
    return '$_year-${'$_month'.padLeft(2, '0')}-${'$_day'.padLeft(2, '0')}';
  }

  PhoneResult? get _phoneValidation {
    final national = normalizeNationalNumber(_phone.text);
    if (national.isEmpty) return null;
    return validatePhone(_dial, national);
  }

  bool get _baseReady =>
      _name.text.trim().isNotEmpty &&
      _password.text.length >= 4 &&
      _birthDate.isNotEmpty &&
      _gender.isNotEmpty &&
      _accepted &&
      (_phoneValidation?.valid ?? false);

  bool get _canSubmit {
    if (!_baseReady || _loading) return false;
    return true;
  }

  void _clampDay() {
    if (_day != null && _day! > _daysInMonth) _day = _daysInMonth;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final phone = _phoneValidation!;
    if (_otpEnabled == true) {
      context.push(
        '/register/otp',
        extra: RegisterOtpArgs(
          name: _name.text.trim(),
          password: _password.text,
          gender: _gender,
          birthDate: _birthDate,
          country: _country,
          countryCode: _dial,
          phoneNumber: phone.normalized!,
          invite: widget.invite,
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await ref.read(authProvider.notifier).register(
            _name.text.trim(),
            _password.text,
            _gender,
            _birthDate,
            country: _country,
            countryCode: _dial,
            phoneNumber: phone.normalized!,
          );
      if (!mounted) return;
      final invite = takePendingInvite(widget.invite);
      await navigateAfterAuth(context, ref, invite: invite, needsProfile: ref.read(authProvider).needsProfileContact);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final now = DateTime.now().year;
    final years = [for (var y = now - 18; y >= now - 120; y--) y];
    final phoneError = _phone.text.trim().isEmpty
        ? ''
        : (_phoneValidation?.valid == true ? '' : (_phoneValidation?.message ?? ''));

    Widget sectionLabel(String text, [IconData? icon]) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: kAuthBlue),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kAuthBody,
                letterSpacing: 0.3,
              ),
            ),
          ]),
        );

    final submitLabel = _loading
        ? t('register.loading')
        : (_otpEnabled == true ? t('otp.continueToVerify') : t('register.submit'));

    void goLogin() => context.go(
          widget.invite == null || widget.invite!.isEmpty
              ? '/login'
              : '/login?invite=${Uri.encodeQueryComponent(widget.invite!)}',
        );

    final desktop = useDesktopAuthLayout(context);

    Widget fieldLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kAuthBody,
            ),
          ),
        );

    final page = AuthHeroShell(
      heroAsset: 'assets/images/auth_register_hero.jpg',
      heroFraction: 0.22,
      heroContain: true,
      onBack: goLogin,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthHeroTitle(title: t('register.title'), subtitle: t('register.subtitle')),
            SizedBox(height: desktop ? 28 : 18),

            // —— Account ——
            sectionLabel(t('register.sectionAccount')),
            const SizedBox(height: 12),
            if (desktop) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fieldLabel(t('register.namePlaceholder')),
                        AuthField(
                          controller: _name,
                          hint: t('register.namePlaceholder'),
                          maxLength: 50,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fieldLabel(t('register.passwordPlaceholder')),
                        AuthField(
                          controller: _password,
                          hint: '••••••••',
                          password: true,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              AuthField(controller: _name, hint: t('register.namePlaceholder'), maxLength: 50, onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              AuthField(
                controller: _password,
                hint: t('register.passwordPlaceholder'),
                password: true,
                onChanged: (_) => setState(() {}),
              ),
            ],

            SizedBox(height: desktop ? 22 : 14),

            // —— Phone ——
            sectionLabel(t('register.sectionPhone'), LucideIcons.phone),
            const SizedBox(height: 12),
            PhoneAuthField(
              countryCode: _country,
              controller: _phone,
              error: phoneError.isNotEmpty,
              onCountryChanged: (x) => setState(() => _country = x.code),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Text(
              phoneError.isNotEmpty ? phoneError : t('register.phoneHint'),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: phoneError.isNotEmpty ? const Color(0xFFE11D48) : kAuthBody,
              ),
            ),

            SizedBox(height: desktop ? 22 : 16),

            // —— About: birth then gender (separate rows — cleaner on desktop) ——
            sectionLabel(t('register.sectionAbout'), LucideIcons.calendar),
            const SizedBox(height: 8),
            Text(t('register.birthDateHint'), style: const TextStyle(fontSize: 12, height: 1.45, color: kAuthBody)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 10,
                child: DateSelect(
                  hint: t('register.day'),
                  value: _day,
                  items: [for (var d = 1; d <= _daysInMonth; d++) d],
                  onChanged: (v) => setState(() => _day = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 12,
                child: DateSelect(
                  hint: t('register.month'),
                  value: _month,
                  items: [for (var m = 1; m <= 12; m++) m],
                  onChanged: (v) => setState(() {
                    _month = v;
                    _clampDay();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 14,
                child: DateSelect(
                  hint: t('register.year'),
                  value: _year,
                  items: years,
                  onChanged: (v) => setState(() {
                    _year = v;
                    _clampDay();
                  }),
                ),
              ),
            ]),
            SizedBox(height: desktop ? 16 : 14),
            fieldLabel(t('register.gender')),
            _GenderRow(gender: _gender, onChanged: (g) => setState(() => _gender = g)),

            if (_error.isNotEmpty) ...[const SizedBox(height: 16), AuthError(_error)],
            SizedBox(height: desktop ? 20 : 14),
            LegalAcceptRow(
              accepted: _accepted,
              onChanged: (v) => setState(() => _accepted = v),
              prefix: t('register.agreePrefix'),
              privacyLabel: t('register.privacyPolicy'),
              mid: t('register.agreeMid'),
              termsLabel: t('register.termsOfService'),
              onPrivacy: () => context.push('/privacy'),
              onTerms: () => context.push('/terms'),
            ),
            SizedBox(height: desktop ? 22 : 18),
            AuthPillCta(
              label: submitLabel,
              loading: _loading,
              onTap: _canSubmit ? _submit : null,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(t('register.hasAccount'), style: const TextStyle(color: kAuthBody, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: goLogin,
                  child: Text(
                    t('register.login'),
                    style: const TextStyle(color: kAuthBlue, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LegalLinks(
              privacy: t('register.privacyPolicy'),
              terms: t('register.termsOfService'),
              onPrivacy: () => context.push('/privacy'),
              onTerms: () => context.push('/terms'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goLogin();
      },
      child: Stack(fit: StackFit.expand, children: [page, LoaderOverlay(show: _loading, text: t('register.loading'))]),
    );
  }
}

class _GenderRow extends StatelessWidget {
  const _GenderRow({
    required this.gender,
    required this.onChanged,
    this.compact = false,
  });

  final String gender;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        for (final g in [
          ('male', t('register.male'), LucideIcons.user),
          ('female', t('register.female'), LucideIcons.users),
          ('other', t('register.other'), LucideIcons.circleUser),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => onChanged(g.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: compact ? 56 : 72,
                  decoration: BoxDecoration(
                    color: gender == g.$1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: gender == g.$1
                        ? const [BoxShadow(color: Color(0x140A1931), blurRadius: 8, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(g.$3, size: compact ? 18 : 20, color: gender == g.$1 ? kAuthBlue : kAuthBody),
                      SizedBox(height: compact ? 4 : 6),
                      Text(
                        g.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w700,
                          color: gender == g.$1 ? kAuthBlue : kAuthBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
