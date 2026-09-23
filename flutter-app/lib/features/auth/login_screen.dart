import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
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
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty && _password.text.isNotEmpty && !_loading;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await ref.read(authProvider.notifier).login(_name.text.trim(), _password.text);
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
      backgroundColor: c.bgPrimary,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 24, 16, pad.bottom + 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 52)),
                  const SizedBox(height: 24),
                  Text(t('login.title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(height: 6),
                  Text(t('login.subtitle'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                  const SizedBox(height: 28),
                  AuthField(
                    controller: _name,
                    hint: t('login.name'),
                    maxLength: 50,
                    autofillHints: const [AutofillHints.username],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  AuthField(
                    controller: _password,
                    hint: t('login.password'),
                    password: true,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 16), AuthError(_error)],
                  const SizedBox(height: 16),
                  AuthSubmit(label: t('login.submit'), onPressed: _canSubmit && !_loading ? _submit : null),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t('login.noAccount'), style: TextStyle(color: c.textSecondary, fontSize: 14)),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => context.go(widget.invite == null ? '/register' : '/register?invite=${widget.invite}'),
                        child: Text(t('login.createAccount'),
                            style: TextStyle(color: c.primary, fontWeight: FontWeight.w600, fontSize: 14)),
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
    );
    return PopScope(
      canPop: false,
      child: Stack(fit: StackFit.expand, children: [page, LoaderOverlay(show: _loading, text: t('login.loading'))]),
    );
  }
}
