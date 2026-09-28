import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_widgets.dart';

/// Payload from [RegisterScreen] → dedicated WhatsApp OTP step.
class RegisterOtpArgs {
  const RegisterOtpArgs({
    required this.name,
    required this.password,
    required this.gender,
    required this.birthDate,
    required this.country,
    required this.countryCode,
    required this.phoneNumber,
    this.invite,
  });

  final String name;
  final String password;
  final String gender;
  final String birthDate;
  final String country;
  final String countryCode;
  final String phoneNumber;
  final String? invite;

  String get maskedPhone {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return '+$countryCode $digits';
    final tail = digits.substring(digits.length - 4);
    final head = digits.length > 7 ? digits.substring(0, 3) : '';
    return '+$countryCode ${head.isEmpty ? '' : '$head '}•••• $tail';
  }
}

/// Standalone WhatsApp OTP verification after registration form.
class RegisterOtpScreen extends ConsumerStatefulWidget {
  const RegisterOtpScreen({super.key, required this.args});
  final RegisterOtpArgs args;

  @override
  ConsumerState<RegisterOtpScreen> createState() => _RegisterOtpScreenState();
}

class _RegisterOtpScreenState extends ConsumerState<RegisterOtpScreen> {
  final _otp = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  bool _sending = false;
  String _error = '';
  int _resendIn = 0;
  bool _sentOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendOtp(initial: true);
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _otp.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tickResend() async {
    while (mounted && _resendIn > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendIn--);
    }
  }

  Future<void> _sendOtp({bool initial = false}) async {
    if (_sending || _resendIn > 0) return;
    setState(() {
      _sending = true;
      if (!initial) _error = '';
    });
    try {
      await Api.post('/otp/send', {
        'purpose': 'register',
        'countryCode': widget.args.countryCode,
        'phoneNumber': widget.args.phoneNumber,
        'country': widget.args.country,
      });
      if (!mounted) return;
      setState(() {
        _sentOnce = true;
        _error = '';
        _resendIn = 60;
        _otp.clear();
      });
      _tickResend();
      _focus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyOtpError(e);
          // Cooldown even on failure so resend always shows a 1-minute timer.
          _resendIn = 60;
        });
        _tickResend();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _friendlyOtpError(Object e) {
    final raw = Api.errorMessage(e, t('common.error'));
    final lower = raw.toLowerCase();
    if (lower.contains('exists') && (lower.contains('false') || lower.contains(':false'))) {
      return t('otp.numberNotOnWhatsApp');
    }
    if (raw.contains('{') || raw.contains('[') || lower.contains('jid') || lower.contains('bad request')) {
      return t('otp.sendFailed');
    }
    if (raw.startsWith('فشل إرسال واتساب:')) {
      return t('otp.sendFailed');
    }
    return raw;
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length < 4) {
      setState(() => _error = t('otp.invalidCode'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final a = widget.args;
      await ref.read(authProvider.notifier).register(
            a.name,
            a.password,
            a.gender,
            a.birthDate,
            country: a.country,
            countryCode: a.countryCode,
            phoneNumber: a.phoneNumber,
            otpCode: code,
          );
      if (!mounted) return;
      final invite = takePendingInvite(a.invite);
      await navigateAfterAuth(
        context,
        ref,
        invite: invite,
        needsProfile: ref.read(authProvider).needsProfileContact,
      );
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyOtpError(e));
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
    final busy = _loading || _sending;
    final code = _otp.text.trim();
    final canVerify = code.length >= 4 && !busy && _sentOnce;

    return PopScope(
      canPop: !busy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            body: AuthPatternBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: busy ? null : () => context.pop(),
                            icon: Icon(LucideIcons.arrowRight, color: c.textPrimary),
                            tooltip: t('common.back'),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, pad.bottom + 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 12),
                                Center(
                                  child: Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: light ? const Color(0xFFE8F8EF) : const Color(0xFF163528),
                                      border: Border.all(
                                        color: light ? const Color(0xFF86EFAC) : const Color(0xFF166534),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF22C55E).withValues(alpha: light ? 0.18 : 0.28),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(LucideIcons.messageCircle, size: 40, color: Color(0xFF16A34A)),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Text(
                                  t('otp.verifyTitle'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  t('otp.verifySubtitle'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15, height: 1.55, color: c.textSecondary),
                                ),
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: c.bgCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: c.border),
                                    boxShadow: [BoxShadow(color: c.shadow, blurRadius: 10, offset: const Offset(0, 2))],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: c.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(LucideIcons.phone, size: 20, color: c.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t('otp.sentTo'),
                                              style: TextStyle(fontSize: 12, color: c.textMuted, fontWeight: FontWeight.w500),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              widget.args.maskedPhone,
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: c.textPrimary,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Text(
                                  t('otp.code'),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textSecondary),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _otp,
                                  focusNode: _focus,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.oneTimeCode],
                                  maxLength: 8,
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (_) {
                                    if (canVerify) _verify();
                                  },
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 10,
                                    color: c.textPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    counterText: '',
                                    hintText: '••••••',
                                    hintStyle: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 10,
                                      color: c.textMuted.withValues(alpha: 0.45),
                                    ),
                                    filled: true,
                                    fillColor: c.bgElevated,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: c.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: c.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: c.primary, width: 2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t('otp.codeHint'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.4),
                                ),
                                if (_error.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  AuthError(_error),
                                ],
                                const SizedBox(height: 28),
                                AuthSubmit(
                                  label: t('otp.verifyAndCreate'),
                                  pill: true,
                                  loading: _loading,
                                  onPressed: canVerify ? _verify : null,
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: _sending && !_sentOnce
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(t('otp.sending'), style: TextStyle(color: c.textSecondary, fontSize: 14)),
                                          ],
                                        )
                                      : TextButton(
                                          onPressed: (_resendIn > 0 || busy) ? null : () => _sendOtp(),
                                          child: Text(
                                            _resendIn > 0
                                                ? t('otp.resendIn', {'s': _resendIn})
                                                : t('otp.resend'),
                                            style: TextStyle(
                                              color: (_resendIn > 0 || busy) ? c.textMuted : c.primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: busy ? null : () => context.pop(),
                                  child: Text(
                                    t('otp.changeNumber'),
                                    style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          LoaderOverlay(show: _loading, text: t('register.loading')),
        ],
      ),
    );
  }
}
