import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../discover/discover_opt_in.dart';
import '../discover/discover_screen.dart';
import '../discover/discover_theme.dart';
import '../notifications/notifications_controller.dart';
import 'home_screen.dart';
import 'home_tab_accent.dart';
import 'instant_chat_screen.dart';
import 'instant_theme.dart';

enum PeopleHubSection { discover, connect }

/// Single home tab when Discover + Instant Chat / Code Connect are all available.
class PeopleHubScreen extends ConsumerStatefulWidget {
  const PeopleHubScreen({super.key, this.invite});
  final String? invite;

  @override
  ConsumerState<PeopleHubScreen> createState() => _PeopleHubScreenState();
}

class _PeopleHubScreenState extends ConsumerState<PeopleHubScreen> {
  PeopleHubSection _section = PeopleHubSection.discover;
  /// Lazy-mount Instant so Discover open doesn't spin up cam/mic / old page flash.
  bool _instantMounted = false;

  void _syncAccent(PeopleHubSection section) {
    ref.read(homeTabAccentProvider.notifier).set(
          section == PeopleHubSection.discover ? HomeTabAccent.discover : HomeTabAccent.instant,
        );
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.hiddenUntilLoaded;
    final discoverOn = ref.watch(discoverOptInProvider).enabled;
    final showDiscover = flags.discoverSwipe && discoverOn;
    final showInstant = flags.randomChat;

    // Random chat off → Discover only (no segment, no Instant mount).
    if (!showInstant) {
      if (showDiscover) return const DiscoverScreen();
      return HomeScreen(invite: widget.invite);
    }
    if (!showDiscover) return const InstantChatScreen();
    // Keep section valid if flags flip while mounted.
    if (_section == PeopleHubSection.discover && !showDiscover) {
      _section = PeopleHubSection.connect;
      _instantMounted = true;
    } else if (_section == PeopleHubSection.connect && !showInstant) {
      _section = PeopleHubSection.discover;
    }

    final unread = ref.watch(unreadNotificationsProvider);
    final onDiscover = _section == PeopleHubSection.discover;
    // Keep tab bar in sync with the visible hub section.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final want = onDiscover ? HomeTabAccent.discover : HomeTabAccent.instant;
      if (ref.read(homeTabAccentProvider) != want) {
        ref.read(homeTabAccentProvider.notifier).set(want);
      }
    });

    return Scaffold(
      backgroundColor: onDiscover ? const Color(0xFFFFF7F8) : InstantTheme.mist,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: onDiscover ? const Color(0xFFFFF7F8) : InstantTheme.mist,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('nav.peopleHub'),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.15,
                              color: onDiscover ? DiscoverTheme.ink : InstantTheme.ink,
                            ),
                          ),
                        ),
                        Material(
                          color: onDiscover ? DiscoverTheme.redSoft : InstantTheme.violetSoft,
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
                                  Icon(
                                    LucideIcons.bell,
                                    size: 20,
                                    color: onDiscover ? DiscoverTheme.red : InstantTheme.violet,
                                  ),
                                  if (unread > 0)
                                    PositionedDirectional(
                                      top: 10,
                                      end: 11,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: onDiscover ? DiscoverTheme.red : InstantTheme.violet,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: onDiscover ? const Color(0xFFFFF7F8) : InstantTheme.mist,
                                            width: 1.5,
                                          ),
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
                    const SizedBox(height: 12),
                    _HubSegmentBar(
                      section: _section,
                      onChanged: (s) {
                        if (s == _section) return;
                        HapticFeedback.selectionClick();
                        setState(() {
                          _section = s;
                          if (s == PeopleHubSection.connect) _instantMounted = true;
                        });
                        _syncAccent(s);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: onDiscover
                ? const DiscoverScreen(embedded: true)
                : (_instantMounted
                    ? const InstantChatScreen(embedded: true)
                    : const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}

class _HubSegmentBar extends StatelessWidget {
  const _HubSegmentBar({required this.section, required this.onChanged});
  final PeopleHubSection section;
  final ValueChanged<PeopleHubSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final onDiscover = section == PeopleHubSection.discover;
    final accent = onDiscover ? DiscoverTheme.red : InstantTheme.violet;

    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _Seg(
              selected: onDiscover,
              icon: LucideIcons.heartHandshake,
              label: t('home.hubDiscover'),
              gradient: DiscoverTheme.ctaGradient,
              accent: DiscoverTheme.red,
              onTap: () => onChanged(PeopleHubSection.discover),
            ),
          ),
          Expanded(
            child: _Seg(
              selected: !onDiscover,
              icon: LucideIcons.zap,
              label: t('home.hubInstant'),
              gradient: InstantTheme.ctaGradient,
              accent: InstantTheme.violet,
              onTap: () => onChanged(PeopleHubSection.connect),
            ),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.selected,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Gradient gradient;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textPrimary.withValues(alpha: 0.55);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: selected ? gradient : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: accent.withValues(alpha: 0.06),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : accent.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: selected ? Colors.white : muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nav label for the unified /home tab.
String peopleOrConnectTabLabel(FeatureFlags flags, bool discoverEnabled) {
  final d = flags.discoverSwipe && discoverEnabled;
  if (d && flags.randomChat) return t('nav.peopleHub');
  if (d) return t('nav.people');
  if (flags.randomChat) return t('home.hubInstant');
  return t('nav.connect');
}

bool usePeopleHub(FeatureFlags flags, bool discoverEnabled) =>
    flags.discoverSwipe && discoverEnabled && flags.randomChat;
