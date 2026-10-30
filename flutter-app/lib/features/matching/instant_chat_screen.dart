import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../notifications/notifications_controller.dart';
import 'home_tab_accent.dart';
import 'instant_theme.dart';
import 'matching_controller.dart';

/// Instant random match only — no NX codes / saved codes.
class InstantChatScreen extends ConsumerStatefulWidget {
  const InstantChatScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<InstantChatScreen> createState() => _InstantChatScreenState();
}

class _InstantChatScreenState extends ConsumerState<InstantChatScreen> {
  bool _loading = false;
  final List<void Function()> _offs = [];

  MatchingController get _matching => ref.read(matchingProvider.notifier);

  @override
  void initState() {
    super.initState();
    [Permission.camera, Permission.microphone].request().catchError((_) => <Permission, PermissionStatus>{});
    _bindHub();
    if (!widget.embedded) {
      Future.microtask(() {
        if (mounted) ref.read(homeTabAccentProvider.notifier).set(HomeTabAccent.instant);
      });
    }
  }

  Future<void> _bindHub() async {
    Hubs.matching.start().catchError((_) {});
    final h = Hubs.matching;
    _offs.addAll([
      h.on('MatchFound', (_) {
        if (mounted) setState(() => _loading = false);
      }),
      h.on('SearchCancelled', (_) => _matching.setIdle()),
    ]);
  }

  @override
  void dispose() {
    for (final off in _offs) {
      off();
    }
    super.dispose();
  }

  Future<void> _startRandom() async {
    if (!ref.read(networkProvider)) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    setState(() => _loading = true);
    _matching.setSearching();
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('StartSearching', [_matching.current.genderFilter]);
      if (mounted && _matching.current.status != MatchStatus.matched) context.push('/matching');
    } catch (_) {
      _matching.setIdle();
      if (mounted) showToast(context, t('home.connectionError'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final c = context.colors;
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final gender = ref.watch(matchingProvider.select((s) => s.genderFilter));
    final unread = ref.watch(unreadNotificationsProvider);
    final bottomPad = tabScrollPadding(context, extra: 20);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    final filters = [
      ('all', t('home.filterAll'), LucideIcons.globe),
      ('male', t('home.filterMale'), LucideIcons.circleUser),
      ('female', t('home.filterFemale'), LucideIcons.usersRound),
    ];

    final body = Stack(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(gradient: InstantTheme.pageGradient),
          child: SafeArea(
            top: !widget.embedded,
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                if (!widget.embedded)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t('home.hubInstant'),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: InstantTheme.ink,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                          ),
                          Material(
                            color: InstantTheme.violetSoft,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                context.push('/notifications');
                              },
                              child: SizedBox(
                                width: 42,
                                height: 42,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(LucideIcons.bell, size: 20, color: InstantTheme.violet),
                                    if (unread > 0)
                                      PositionedDirectional(
                                        top: 10,
                                        end: 11,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: InstantTheme.violet,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: InstantTheme.mist, width: 1.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, widget.embedded ? 8 : 18, 20, bottomPad),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (user != null) ...[
                          Text(
                            '${t('home.greeting')} ${user.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: InstantTheme.ink.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Text(
                          t('home.instantTitle'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: InstantTheme.ink,
                            height: 1.25,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('home.instantSubtitle'),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: InstantTheme.violetDeep.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: InstantTheme.ctaGradient,
                              boxShadow: InstantTheme.ctaShadow,
                            ),
                            clipBehavior: Clip.antiAlias,
                            alignment: Alignment.center,
                            child: Lottie.asset(
                              'assets/lottie/chat.json',
                              width: 88,
                              height: 88,
                              frameRate: FrameRate.max,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          t('home.filterLabel'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: InstantTheme.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: InstantTheme.violetSoft),
                          ),
                          child: Row(
                            children: [
                              for (final (i, f) in filters.indexed) ...[
                                if (i > 0) const SizedBox(width: 4),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _matching.setGenderFilter(f.$1);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: gender == f.$1 ? InstantTheme.violetSoft : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            f.$3,
                                            size: 18,
                                            color: gender == f.$1 ? InstantTheme.violet : c.textMuted,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            f.$2,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: gender == f.$1 ? InstantTheme.violet : c.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: InstantTheme.ctaGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: InstantTheme.ctaShadow,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _loading ? null : _startRandom,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(LucideIcons.zap, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t('home.startRandom'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            t('matching.secureSearch'),
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.88),
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('home.instantHint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: InstantTheme.violetDeep.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        LoaderOverlay(show: _loading, text: t('home.connecting')),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(backgroundColor: InstantTheme.mist, body: body);
  }
}
