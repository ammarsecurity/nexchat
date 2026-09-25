import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/phone_validation.dart';
import '../../core/theme/app_colors.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import 'auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  String? _country = 'IQ';
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String _error = '';
  bool _otpSent = false;
  bool _done = false;
  int _resendIn = 0;
  bool? _otpAvailable;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final data = await Api.get('otp/status', skipUnauthorized: true);
      final map = data is Map ? data : <String, dynamic>{};
      final enabled = map['enabled'] == true || map['Enabled'] == true;
      final configured = map['configured'] == true || map['Configured'] == true;
      if (mounted) setState(() => _otpAvailable = enabled && configured);
    } catch (_) {
      if (mounted) setState(() => _otpAvailable = false);
    }
  }

  String get _dial => countryByCode(_country)?.dialCode ?? '';

  PhoneResult? get _validation =>
      _dial.isEmpty || _phone.text.trim().isEmpty ? null : validatePhone(_dial, _phone.text);

  Future<void> _sendOtp() async {
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
      await Api.post('/otp/send', {
        'purpose': 'reset_password',
        'countryCode': _dial,
        'phoneNumber': r.normalized,
      });
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _resendIn = 45;
      });
      _tickResend();
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tickResend() async {
    while (mounted && _resendIn > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendIn--);
    }
  }

  Future<void> _reset() async {
    final r = _validation;
    final code = _otp.text.trim();
    if (r == null || !r.valid) {
      setState(() => _error = r?.message ?? t('phoneValidation.required'));
      return;
    }
    if (code.length < 4) {
      setState(() => _error = t('otp.invalidCode'));
      return;
    }
    if (_password.text.length < 4) {
      setState(() => _error = t('otp.passwordShort'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = t('otp.passwordMismatch'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Api.post('/otp/reset-password', {
        'countryCode': _dial,
        'phoneNumber': r.normalized,
        'code': code,
        'newPassword': _password.text,
      });
      if (!mounted) return;
      setState(() => _done = true);
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
    final validation = _validation;
    final phoneError = validation != null && !validation.valid ? validation.message : '';

    if (_otpAvailable == null) {
      return Scaffold(
        backgroundColor: c.bgPrimary,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_otpAvailable == false) {
      return Scaffold(
        backgroundColor: c.bgPrimary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.circleAlert, size: 48, color: c.danger),
                const SizedBox(height: 16),
                Text(t('otp.unavailable'), textAlign: TextAlign.center, style: TextStyle(color: c.textPrimary, fontSize: 16)),
                const SizedBox(height: 24),
                TextButton(onPressed: () => context.go('/login'), child: Text(t('otp.backToLogin'))),
              ],
            ),
          ),
        ),
      );
    }

    if (_done) {
      return Scaffold(
        backgroundColor: c.bgPrimary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.circleCheck, size: 56, color: c.success),
                const SizedBox(height: 16),
                Text(t('otp.resetSuccess'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 24),
                GradientButton(label: t('otp.backToLogin'), onPressed: () => context.go('/login')),
              ],
            ),
          ),
        ),
      );
    }

    final canSend = _country != null && (validation?.valid ?? false) && !_loading;
    final canReset = canSend && _otpSent && _otp.text.trim().length >= 4 && _password.text.length >= 4 && _confirm.text.isNotEmpty;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, pad.top + 16, 16, pad.bottom + 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(LucideIcons.arrowRight, size: 18),
                        label: Text(t('otp.backToLogin')),
                      ),
                    ),
                    Center(child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 48)),
                    const SizedBox(height: 20),
                    Text(t('otp.forgotTitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    const SizedBox(height: 8),
                    Text(t('otp.forgotSubtitle'),
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.5)),
                    const SizedBox(height: 24),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t('completeProfile.phone'),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
                          const SizedBox(height: 8),
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
                          ],
                          if (!_otpSent) ...[
                            const SizedBox(height: 22),
                            GradientButton(
                              label: t('otp.sendWhatsApp'),
                              onPressed: canSend ? _sendOtp : null,
                            ),
                          ] else ...[
                            const SizedBox(height: 18),
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
                                child: Text(_resendIn > 0 ? t('otp.resendIn', {'s': _resendIn}) : t('otp.resend')),
                              ),
                            ),
                            const SizedBox(height: 8),
                            AuthField(
                              controller: _password,
                              hint: t('otp.newPassword'),
                              password: true,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            AuthField(
                              controller: _confirm,
                              hint: t('otp.confirmPassword'),
                              password: true,
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_error.isNotEmpty) ...[const SizedBox(height: 14), AuthError(_error)],
                            const SizedBox(height: 18),
                            GradientButton(
                              label: t('otp.resetPassword'),
                              onPressed: canReset ? _reset : null,
                            ),
                          ],
                          if (!_otpSent && _error.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            AuthError(_error),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          LoaderOverlay(show: _loading, text: t('common.loading')),
        ],
      ),
    );
  }
}
