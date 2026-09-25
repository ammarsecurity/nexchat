import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/phone_validation.dart';
import '../../core/theme/app_colors.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_widgets.dart';

/// views/auth/RegisterView.vue
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
  final _otp = TextEditingController();
  String _country = 'IQ';
  int? _day, _month, _year;
  String _gender = '';
  bool _accepted = false;
  bool _loading = false;
  String _error = '';
  bool? _otpEnabled;
  bool _otpSent = false;
  int _resendIn = 0;

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
    _otp.dispose();
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
    if (_otpEnabled == true) return _otpSent && _otp.text.trim().length >= 4;
    return true;
  }

  void _clampDay() {
    if (_day != null && _day! > _daysInMonth) _day = _daysInMonth;
  }

  void _tickResend() async {
    while (mounted && _resendIn > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendIn--);
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneValidation;
    if (phone == null || !phone.valid) {
      setState(() => _error = phone?.message ?? t('phoneValidation.required'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Api.post('/otp/send', {
        'purpose': 'register',
        'countryCode': _dial,
        'phoneNumber': phone.normalized,
        'country': _country,
      });
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _resendIn = 45;
        _otp.clear();
      });
      _tickResend();
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_otpEnabled == true && !_otpSent) {
      await _sendOtp();
      return;
    }
    if (!_canSubmit) return;
    final phone = _phoneValidation!;
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
            otpCode: _otpEnabled == true ? _otp.text.trim() : null,
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
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final pad = MediaQuery.paddingOf(context);
    final now = DateTime.now().year;
    final years = [for (var y = now - 18; y >= now - 120; y--) y];
    final phoneError = _phone.text.trim().isEmpty
        ? ''
        : (_phoneValidation?.valid == true ? '' : (_phoneValidation?.message ?? ''));

    Widget sectionLabel(String text, [IconData? icon]) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 15, color: c.primary), const SizedBox(width: 6)],
            Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textSecondary, letterSpacing: 0.5)),
          ]),
        );

    final submitLabel = _loading
        ? t('register.loading')
        : (_otpEnabled == true && !_otpSent ? t('otp.sendWhatsApp') : t('register.submit'));

    final page = Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthPatternBackground(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 16, 16, pad.bottom + 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 88)),
                  const SizedBox(height: 20),
                  Text(t('register.title'),
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.textPrimary)),
                  const SizedBox(height: 6),
                  Text(t('register.subtitle'),
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: c.textSecondary)),
                  const SizedBox(height: 24),
                  sectionLabel(t('register.sectionAccount')),
                  const SizedBox(height: 10),
                  AuthField(controller: _name, hint: t('register.namePlaceholder'), maxLength: 50, onChanged: (_) => setState(() {})),
                  const SizedBox(height: 10),
                  AuthField(
                    controller: _password,
                    hint: t('register.passwordPlaceholder'),
                    password: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  sectionLabel(t('register.sectionPhone'), LucideIcons.phone),
                  const SizedBox(height: 10),
                  PhoneAuthField(
                    countryCode: _country,
                    controller: _phone,
                    error: phoneError.isNotEmpty,
                    onCountryChanged: (x) => setState(() {
                      _country = x.code;
                      _otpSent = false;
                    }),
                    onChanged: (_) => setState(() => _otpSent = false),
                  ),
                  if (phoneError.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(phoneError, style: TextStyle(fontSize: 12, color: c.danger)),
                  ] else ...[
                    const SizedBox(height: 6),
                    Text(t('register.phoneHint'), style: TextStyle(fontSize: 12, height: 1.4, color: c.textMuted)),
                  ],
                  if (_otpEnabled == true && _otpSent) ...[
                    const SizedBox(height: 12),
                    AuthField(
                      controller: _otp,
                      hint: t('otp.codeHint'),
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      onChanged: (_) => setState(() {}),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _resendIn > 0 || _loading ? null : _sendOtp,
                        child: Text(
                          _resendIn > 0 ? t('otp.resendIn', {'s': _resendIn}) : t('otp.resend'),
                          style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  sectionLabel(t('register.sectionAbout'), LucideIcons.calendar),
                  const SizedBox(height: 10),
                  Text(t('register.birthDateHint'), style: TextStyle(fontSize: 12, height: 1.45, color: c.textMuted)),
                  const SizedBox(height: 10),
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
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 12,
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
                  const SizedBox(height: 14),
                  Text(t('register.gender'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.bgElevated,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      for (final g in [
                        ('male', t('register.male'), LucideIcons.user),
                        ('female', t('register.female'), LucideIcons.users),
                        ('other', t('register.other'), LucideIcons.circleUser),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () => setState(() => _gender = g.$1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: 72,
                                decoration: BoxDecoration(
                                  color: _gender == g.$1 ? c.bgCard : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: _gender == g.$1 ? [BoxShadow(color: c.shadow, blurRadius: 6)] : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(g.$3, size: 20, color: _gender == g.$1 ? c.primary : c.textSecondary),
                                    const SizedBox(height: 6),
                                    Text(g.$2,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _gender == g.$1 ? c.primary : c.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 20), AuthError(_error)],
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 20),
                  AuthSubmit(
                    label: submitLabel,
                    pill: true,
                    onPressed: (_otpEnabled == true && !_otpSent
                            ? (_baseReady && !_loading)
                            : _canSubmit)
                        ? _submit
                        : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t('register.hasAccount'), style: TextStyle(color: c.textSecondary, fontSize: 14)),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => context.go(widget.invite == null || widget.invite!.isEmpty
                            ? '/login'
                            : '/login?invite=${Uri.encodeQueryComponent(widget.invite!)}'),
                        child: Text(t('register.login'), style: TextStyle(color: c.primary, fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LegalLinks(
                    privacy: t('register.privacyPolicy'),
                    terms: t('register.termsOfService'),
                    onPrivacy: () => context.push('/privacy'),
                    onTerms: () => context.push('/terms'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      child: Stack(fit: StackFit.expand, children: [page, LoaderOverlay(show: _loading, text: t('register.loading'))]),
    );
  }
}
