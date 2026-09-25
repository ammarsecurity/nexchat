import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  String? _country = 'IQ';
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _loading = false;
  String _error = '';
  bool? _otpEnabled;
  bool _otpSent = false;
  int _resendIn = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOtpStatus();
  }

  @override
  void dispose() {
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

  Future<void> _finishSuccess() async {
    ref.read(authProvider.notifier).setNeedsProfileContact(false);
    if (!mounted) return;
    if (widget.fromSettings) {
      _leave();
      return;
    }
    await navigateDefaultForSession(GoRouter.of(context), ref);
  }

  Future<void> _submitDirect() async {
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
      await _finishSuccess();
    } catch (e) {
      final msg = Api.errorMessage(e, t('common.error'));
      final requireOtp = e is DioException && e.response?.data is Map && (e.response!.data as Map)['requireOtp'] == true;
      if (msg.contains('واتساب') || requireOtp) {
        setState(() {
          _otpEnabled = true;
          _loading = false;
        });
        await _sendOtp();
        return;
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
        'purpose': 'verify_phone',
        'countryCode': _dial,
        'phoneNumber': r.normalized,
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

  void _tickResend() async {
    while (mounted && _resendIn > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendIn--);
    }
  }

  Future<void> _verifyOtp() async {
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
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Api.post('/otp/verify-phone', {
        'countryCode': _dial,
        'phoneNumber': r.normalized,
        'country': _country,
        'code': code,
      });
      await _finishSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_otpEnabled == true) {
      if (_otpSent) {
        await _verifyOtp();
      } else {
        await _sendOtp();
      }
    } else {
      await _submitDirect();
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
    final otpLoading = _otpEnabled == null;
    final otpMode = _otpEnabled == true;
    final canSubmit = !otpLoading &&
        _country != null &&
        (validation?.valid ?? false) &&
        !_loading &&
        (!otpMode || !_otpSent || _otp.text.trim().length >= 4);

    Widget label(IconData icon, String text) => Row(children: [
          Icon(icon, size: 16, color: c.primary),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ]);

    final submitLabel = otpLoading
        ? t('common.loading')
        : (!otpMode ? t('completeProfile.submit') : (_otpSent ? t('otp.verify') : t('otp.sendWhatsApp')));

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
                      child: Text(
                          otpMode ? t('otp.completeSubtitle') : t('completeProfile.subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, height: 1.55, color: c.textSecondary)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        label(LucideIcons.phone, t('completeProfile.phone')),
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
                        const SizedBox(height: 8),
                        Text(
                          phoneError.isNotEmpty ? phoneError : t('completeProfile.phoneHint'),
                          style: TextStyle(fontSize: 12, height: 1.45, color: phoneError.isNotEmpty ? c.danger : c.textMuted),
                        ),
                        if (otpMode && _otpSent) ...[
                          const SizedBox(height: 18),
                          label(LucideIcons.shieldCheck, t('otp.code')),
                          const SizedBox(height: 8),
                          AuthField(
                            controller: _otp,
                            hint: t('otp.codeHint'),
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
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
                        if (_error.isNotEmpty) ...[const SizedBox(height: 18), AuthError(_error)],
                        const SizedBox(height: 22),
                        GradientButton(
                          label: submitLabel,
                          height: 52,
                          onPressed: canSubmit ? _submit : null,
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
