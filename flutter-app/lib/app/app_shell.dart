import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/feature_flags.dart';
import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../features/conversations/conversations_list_controller.dart';
import '../features/discover/discover_opt_in.dart';
import '../features/discover/discover_theme.dart';
import '../features/matching/home_tab_accent.dart';
import '../features/matching/instant_theme.dart';
import '../features/matching/people_hub_screen.dart';
import '../features/short_films/short_films_theme.dart';
import 'router.dart';

class _Tab {
  const _Tab(this.to, this.label, this.icon, this.badge);
  final String to;
  final String label;
  final String icon;
  final int badge;
}

/// Tab-root scaffold with the floating bottom bar (components/AppTabBar.vue).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// Android back on a tab root does nothing instead of closing the app (App.vue backButton listener).
class TabRootGuard extends StatelessWidget {
  const TabRootGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(canPop: Navigator.of(context).canPop(), child: child);
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pendingRequestsProvider.notifier).fetch());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.hiddenUntilLoaded;
    final discoverOn = ref.watch(discoverOptInProvider).enabled;
    final unread = ref.watch(totalUnreadProvider);
    final pending = ref.watch(pendingRequestsProvider);
    final rawAccent = widget.location == '/home' ? ref.watch(homeTabAccentProvider) : HomeTabAccent.neutral;
    // Never keep Instant chrome / label when random chat is admin-off.
    final homeAccent = (!flags.randomChat && rawAccent == HomeTabAccent.instant)
        ? (flags.discoverSwipe && discoverOn ? HomeTabAccent.discover : HomeTabAccent.neutral)
        : rawAccent;
    if (homeAccent != rawAccent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(homeTabAccentProvider) == HomeTabAccent.instant && !flags.randomChat) {
          ref.read(homeTabAccentProvider.notifier).set(homeAccent);
        }
      });
    }
    final homeLabel = homeAccent == HomeTabAccent.instant && flags.randomChat
        ? t('home.hubInstant')
        : homeAccent == HomeTabAccent.discover
            ? t('nav.people')
            : peopleOrConnectTabLabel(flags, discoverOn);
    final tabs = [
      _Tab('/conversations', t('nav.conversations'), 'chat', unread),
      if (flags.shortFilms) _Tab('/short-films', t('nav.discover'), 'films', 0),
      if (showPeopleOrConnectTab(flags, discoverOn))
        _Tab('/home', homeLabel, 'home', 0),
      _Tab('/settings', t('nav.profile'), 'profile', pending),
    ];
    final showBar = isTabRoot(widget.location, flags, discoverEnabled: discoverOn);
    final filmsStyle = widget.location == '/short-films' || widget.location.startsWith('/short-films/');
    final peopleStyle = homeAccent == HomeTabAccent.discover;
    final instantStyle = homeAccent == HomeTabAccent.instant && flags.randomChat;

    return Scaffold(
      extendBody: true,
      body: widget.child,
      bottomNavigationBar: showBar
          ? _TabBar(
              tabs: tabs,
              location: widget.location,
              filmsStyle: filmsStyle,
              peopleStyle: peopleStyle,
              instantStyle: instantStyle,
            )
          : null,
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.location,
    this.filmsStyle = false,
    this.peopleStyle = false,
    this.instantStyle = false,
  });
  final List<_Tab> tabs;
  final String location;
  final bool filmsStyle;
  final bool peopleStyle;
  final bool instantStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Chrome height must stay near kTabBarContentHeight in layout.dart.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(16, 6, 16, 6 + bottom),
      decoration: BoxDecoration(
        color: filmsStyle
            ? DramaWave.surface
            : peopleStyle
                ? const Color(0xFFFFF1F2)
                : instantStyle
                    ? InstantTheme.mist
                    : c.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: filmsStyle
            ? const Border(top: BorderSide(color: DramaWave.hairline))
            : peopleStyle
                ? const Border(top: BorderSide(color: Color(0x33E11D48)))
                : instantStyle
                    ? Border(top: BorderSide(color: InstantTheme.violet.withValues(alpha: 0.22)))
                    : null,
        boxShadow: [
          BoxShadow(
            color: filmsStyle
                ? const Color(0x66000000)
                : peopleStyle
                    ? const Color(0x33E11D48)
                    : instantStyle
                        ? const Color(0x337C3AED)
                        : c.shadow,
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final tab in tabs)
            Expanded(
              child: _TabItem(
                tab: tab,
                active: location == tab.to || (tab.to == '/short-films' && location.startsWith('/short-films')),
                filmsStyle: filmsStyle,
                peopleStyle: peopleStyle,
                instantStyle: instantStyle,
              ),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.active,
    this.filmsStyle = false,
    this.peopleStyle = false,
    this.instantStyle = false,
  });
  final _Tab tab;
  final bool active;
  final bool filmsStyle;
  final bool peopleStyle;
  final bool instantStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color color;
    final Color well;
    if (filmsStyle) {
      color = active ? DramaWave.gold : DramaWave.muted;
      well = active ? DramaWave.goldSoft : Colors.transparent;
    } else if (peopleStyle) {
      color = active ? DiscoverTheme.red : c.textMuted;
      well = active ? DiscoverTheme.redSoft : Colors.transparent;
    } else if (instantStyle) {
      color = active ? InstantTheme.violet : c.textMuted;
      well = active ? InstantTheme.violetSoft : Colors.transparent;
    } else {
      color = active ? c.primary : c.textMuted;
      well = active ? c.primarySoft : Colors.transparent;
    }
    final IconData iconData = switch (tab.icon) {
      'home' => instantStyle ? LucideIcons.zap : LucideIcons.heart,
      'chat' => LucideIcons.messageCircle,
      'films' => LucideIcons.clapperboard,
      _ => LucideIcons.user,
    };
    final iconSize = tab.icon == 'profile' || tab.icon == 'user' ? 24.0 : 22.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        if (!active) GoRouter.of(context).go(tab.to);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: well, shape: BoxShape.circle),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(iconData, size: iconSize, color: color),
                  if (tab.badge > 0 && tab.icon == 'chat')
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: filmsStyle
                              ? DramaWave.gold
                              : peopleStyle
                                  ? DiscoverTheme.red
                                  : instantStyle
                                      ? InstantTheme.violet
                                      : c.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: filmsStyle
                                  ? const Color(0x59E8B923)
                                  : peopleStyle
                                      ? const Color(0x59E11D48)
                                      : instantStyle
                                          ? const Color(0x597C3AED)
                                          : const Color(0x593B82F6),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          tab.badge > 99 ? '99+' : '${tab.badge}',
                          style: TextStyle(
                            color: filmsStyle ? Colors.black : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
