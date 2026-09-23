import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/share_links.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_controller.dart';

/// views/InviteJoinView.vue — /join/:code landing that forwards to home or login.
class InviteJoinScreen extends ConsumerStatefulWidget {
  const InviteJoinScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    final router = GoRouter.of(context);
    final flags = await ref.read(featureFlagsProvider.future);
    final loggedIn = ref.read(authProvider).isLoggedIn;
    if (!flags.codeConnect) {
      await Prefs.instance.setString(Keys.pendingInvite, null);
      router.go(loggedIn ? flags.defaultRoute : '/login');
      return;
    }
    final code = normalizeInviteCode(widget.code);
    if (code.isEmpty) {
      if (mounted) await navigateDefaultForSession(router, ref);
      return;
    }
    if (loggedIn) {
      router.go('/home?invite=$code');
      return;
    }
    await Prefs.instance.setString(Keys.pendingInvite, code);
    router.go('/login?invite=$code');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t('share.openingInvite'), style: TextStyle(color: c.textMuted)),
        ),
      ),
    );
  }
}
