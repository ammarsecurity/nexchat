import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'discover_theme.dart';

/// Local “already asked” flag — per account. Server `discoverEnabled` is authoritative for feed.
String _askedKey(String userId) => 'nexchat_discover_optin_asked_$userId';

class DiscoverOptInState {
  const DiscoverOptInState({
    this.enabled = false,
    this.loaded = false,
    this.asked = false,
  });

  final bool enabled;
  final bool loaded;
  final bool asked;

  DiscoverOptInState copyWith({bool? enabled, bool? loaded, bool? asked}) => DiscoverOptInState(
        enabled: enabled ?? this.enabled,
        loaded: loaded ?? this.loaded,
        asked: asked ?? this.asked,
      );
}

class DiscoverOptInNotifier extends Notifier<DiscoverOptInState> {
  @override
  DiscoverOptInState build() {
    ref.listen(authProvider.select((s) => s.user?.id), (prev, next) {
      if (next == null) {
        state = const DiscoverOptInState();
      } else if (next != prev) {
        unawaited(refresh());
      }
    });
    Future.microtask(refresh);
    return const DiscoverOptInState();
  }

  Future<void> refresh() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      state = const DiscoverOptInState();
      return;
    }
    final asked = Prefs.instance.getString(_askedKey(userId)) == '1';
    try {
      final data = await Api.get('/user/me');
      if (data is! Map) {
        state = DiscoverOptInState(loaded: true, asked: asked);
        return;
      }
      final j = Json.from(data);
      state = DiscoverOptInState(
        enabled: j.v('discoverEnabled') == true,
        loaded: true,
        asked: asked || j.v('discoverEnabled') == true,
      );
    } catch (_) {
      state = DiscoverOptInState(loaded: true, asked: asked);
    }
  }

  Future<void> markAsked() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId != null) await Prefs.instance.setString(_askedKey(userId), '1');
    state = state.copyWith(asked: true);
  }

  Future<bool> setEnabled(bool value) async {
    try {
      await Api.put('/user/discover-enabled', {'discoverEnabled': value});
      final userId = ref.read(authProvider).user?.id;
      if (userId != null) await Prefs.instance.setString(_askedKey(userId), '1');
      state = DiscoverOptInState(enabled: value, loaded: true, asked: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final discoverOptInProvider = NotifierProvider<DiscoverOptInNotifier, DiscoverOptInState>(DiscoverOptInNotifier.new);

bool showPeopleOrConnectTab(FeatureFlags flags, bool discoverEnabled) =>
    (flags.discoverSwipe && discoverEnabled) || flags.randomChat || flags.codeConnect;

bool useDiscoverHomeTab(FeatureFlags flags, bool discoverEnabled) => flags.discoverSwipe && discoverEnabled;

/// First-run consent: enable Discover or skip (can re-enable in Settings).
class DiscoverOptInOverlay extends ConsumerWidget {
  const DiscoverOptInOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.hiddenUntilLoaded;
    final opt = ref.watch(discoverOptInProvider);
    final loggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));

    final shouldAsk = loggedIn &&
        flags.discoverSwipe &&
        opt.loaded &&
        !opt.enabled &&
        !opt.asked;

    if (!shouldAsk) return const SizedBox.shrink();

    return Material(
      color: Colors.black.withValues(alpha: 0.48),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 12))],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: DiscoverTheme.ctaGradient,
                          boxShadow: DiscoverTheme.likeShadow,
                        ),
                        child: const Icon(LucideIcons.heartHandshake, color: Colors.white, size: 34),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        t('discover.optInTitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.colors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        t('discover.optInBody'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: DiscoverTheme.ctaGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final ok = await ref.read(discoverOptInProvider.notifier).setEnabled(true);
                                if (!context.mounted) return;
                                if (!ok) {
                                  showToast(context, t('common.error'), error: true);
                                  return;
                                }
                                context.go('/home');
                              },
                              child: Center(
                                child: Text(
                                  t('discover.optInEnable'),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => ref.read(discoverOptInProvider.notifier).markAsked(),
                        child: Text(
                          t('discover.optInLater'),
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
