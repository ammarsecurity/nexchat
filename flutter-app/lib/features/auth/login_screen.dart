import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/phone_validation.dart';
import '../../data/countries.dart';
import '../../shared/country_picker.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_hero_shell.dart';
import 'auth_widgets.dart';

/// Login — same visual language as onboarding (hero + wave + pill CTA).
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

  PhoneResult? get _phoneValidation {
    if (_mode != 'phone') return null;
    final national = normalizeNationalNumber(_phone.text);
    if (national.isEmpty) return null;
    return validatePhone(_dial, national);
  }

  String get _phoneError {
    if (_mode != 'phone') return '';
    if (_phone.text.trim().isEmpty) return '';
    final r = _phoneValidation;
    if (r == null) return '';
    return r.valid ? '' : r.message;
  }

  String? get _loginIdentifier {
    if (_mode == 'phone') {
      final check = _phoneValidation;
      if (check == null || !check.valid) return null;
      return '$_dial${check.normalized}';
    }
    final name = _name.text.trim();
    return name.isEmpty ? null : name;
  }

  bool get _canSubmit => _loginIdentifier != null && _password.text.isNotEmpty && !_loading;

  Future<void> _submit() async {
    if (_mode == 'phone') {
      final national = normalizeNationalNumber(_phone.text);
      final check = validatePhone(_dial, national);
      if (!check.valid) {
        setState(() => _error = check.message);
        return;
      }
    }
    if (!_canSubmit) return;
    final id = _loginIdentifier!;
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

    final page = AuthHeroShell(
      heroAsset: 'assets/images/auth_login_hero.jpg',
      heroFraction: 0.32,
      child: AutofillGroup(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthHeroTitle(title: t('login.title'), subtitle: t('login.subtitle')),
              const SizedBox(height: 20),
              _LoginModeTabs(
                mode: _mode,
                onChanged: (m) => setState(() {
                  _mode = m;
                  _error = '';
                }),
              ),
              const SizedBox(height: 16),
              if (_mode == 'name')
                AuthField(
                  controller: _name,
                  hint: t('login.username'),
                  maxLength: 50,
                  autofillHints: const [AutofillHints.username],
                  onChanged: (_) => setState(() {}),
                )
              else ...[
                PhoneAuthField(
                  countryCode: _country,
                  controller: _phone,
                  hint: t('login.phonePlaceholder'),
                  error: _phoneError.isNotEmpty,
                  onCountryChanged: (x) => setState(() {
                    _country = x.code;
                    _error = '';
                  }),
                  onChanged: (_) => setState(() => _error = ''),
                ),
                const SizedBox(height: 6),
                Text(
                  _phoneError.isNotEmpty ? _phoneError : t('login.phoneHint'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: _phoneError.isNotEmpty ? const Color(0xFFE11D48) : kAuthBody,
                  ),
                ),
              ],
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
                  child: Text(
                    t('login.forgotPassword'),
                    style: const TextStyle(
                      color: kAuthBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (_error.isNotEmpty) ...[const SizedBox(height: 8), AuthError(_error)],
              const SizedBox(height: 12),
              AuthPillCta(
                label: t('login.submit'),
                loading: _loading,
                onTap: _canSubmit && !_loading ? _submit : null,
              ),
              const SizedBox(height: 18),
              _NewUserRegisterCard(
                onTap: () => context.go(
                  widget.invite == null || widget.invite!.isEmpty
                      ? '/register'
                      : '/register?invite=${Uri.encodeQueryComponent(widget.invite!)}',
                ),
              ),
              const SizedBox(height: 14),
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
    Widget tab(String id, IconData icon, String label) {
      final active = mode == id;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(id),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 46,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: active
                    ? const [BoxShadow(color: Color(0x140A1931), blurRadius: 10, offset: Offset(0, 2))]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17, color: active ? kAuthBlue : kAuthBody),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? kAuthBlue : kAuthBody,
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
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        tab('name', LucideIcons.userRound, t('login.modeUsername')),
        tab('phone', LucideIcons.phone, t('login.modePhone')),
      ]),
    );
  }
}

class _NewUserRegisterCard extends StatelessWidget {
  const _NewUserRegisterCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kAuthBlue.withValues(alpha: 0.08),
                kAuthPurple.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kAuthBlue.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kAuthBlue, kAuthPurple]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(LucideIcons.userPlus, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('login.newUserQuestion'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kAuthTitle,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('login.newUserAction'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: kAuthBlue,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronLeft, size: 20, color: kAuthBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
