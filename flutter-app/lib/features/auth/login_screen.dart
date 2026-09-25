import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/phone_validation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_widgets.dart';

/// views/auth/LoginView.vue
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.invite});
  final String? invite;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// `name` | `phone`
  String _mode = 'name';
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _country = 'IQ';
  bool _loading = false;
  String _error = '';

  Country get _selectedCountry => countryByCode(_country) ?? countries.first;
  String get _dial => _selectedCountry.dialCode;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  String? get _loginIdentifier {
    if (_mode == 'phone') {
      final national = normalizeNationalNumber(_phone.text);
      if (national.isEmpty) return null;
      return '$_dial$national';
    }
    final name = _name.text.trim();
    return name.isEmpty ? null : name;
  }

  bool get _canSubmit => _loginIdentifier != null && _password.text.isNotEmpty && !_loading;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final id = _loginIdentifier!;
    if (_mode == 'phone') {
      final check = validatePhone(_dial, normalizeNationalNumber(_phone.text));
      if (!check.valid) {
        setState(() => _error = check.message);
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await ref.read(authProvider.notifier).login(id, _password.text);
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
    final page = Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthPatternBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, pad.top + 24, 16, pad.bottom + 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 88)),
                    const SizedBox(height: 22),
                    Text(t('login.title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: kAppFont, fontSize: 24, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    const SizedBox(height: 6),
                    Text(t('login.subtitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: kAppFont, fontSize: 14.5, color: c.textSecondary, height: 1.45)),
                    const SizedBox(height: 22),
                    _LoginModeTabs(
                      mode: _mode,
                      onChanged: (m) => setState(() {
                        _mode = m;
                        _error = '';
                      }),
                    ),
                    const SizedBox(height: 18),
                    if (_mode == 'name')
                      AuthField(
                        controller: _name,
                        hint: t('login.username'),
                        maxLength: 50,
                        autofillHints: const [AutofillHints.username],
                        onChanged: (_) => setState(() {}),
                      )
                    else
                      PhoneAuthField(
                        countryCode: _country,
                        controller: _phone,
                        hint: t('login.phonePlaceholder'),
                        onCountryChanged: (x) => setState(() => _country = x.code),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    AuthField(
                      controller: _password,
                      hint: t('login.password'),
                      password: true,
                      autofillHints: const [AutofillHints.password],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => context.push('/forgot-password'),
                        child: Text(t('login.forgotPassword'),
                            style: TextStyle(
                                fontFamily: kAppFont, color: c.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                    if (_error.isNotEmpty) ...[const SizedBox(height: 10), AuthError(_error)],
                    const SizedBox(height: 14),
                    AuthSubmit(label: t('login.submit'), onPressed: _canSubmit && !_loading ? _submit : null),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t('login.noAccount'),
                            style: TextStyle(fontFamily: kAppFont, color: c.textSecondary, fontSize: 14)),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => context.go(widget.invite == null ? '/register' : '/register?invite=${widget.invite}'),
                          child: Text(t('login.createAccount'),
                              style: TextStyle(fontFamily: kAppFont, color: c.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LegalLinks(
                      privacy: t('login.privacyPolicy'),
                      terms: t('login.termsOfService'),
                      onPrivacy: () => context.push('/privacy'),
                      onTerms: () => context.push('/terms'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: false,
      child: Stack(fit: StackFit.expand, children: [page, LoaderOverlay(show: _loading, text: t('login.loading'))]),
    );
  }
}

class _LoginModeTabs extends StatelessWidget {
  const _LoginModeTabs({required this.mode, required this.onChanged});
  final String mode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tab(String id, IconData icon, String label) {
      final active = mode == id;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(id),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 46,
              decoration: BoxDecoration(
                color: active ? c.bgCard : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: active ? [BoxShadow(color: c.shadow, blurRadius: 8, offset: const Offset(0, 1))] : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17, color: active ? c.primary : c.textMuted),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? c.primary : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        tab('name', LucideIcons.userRound, t('login.modeUsername')),
        tab('phone', LucideIcons.phone, t('login.modePhone')),
      ]),
    );
  }
}
