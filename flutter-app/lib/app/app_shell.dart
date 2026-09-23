import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/feature_flags.dart';
import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../features/conversations/conversations_list_controller.dart';
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
    final unread = ref.watch(totalUnreadProvider);
    final pending = ref.watch(pendingRequestsProvider);
    final tabs = [
      _Tab('/conversations', t('nav.conversations'), 'chat', unread),
      if (flags.shortFilms) _Tab('/short-films', t('nav.discover'), 'films', 0),
      if (!flags.messagingOnly) _Tab('/home', t('nav.connect'), 'home', 0),
      _Tab('/settings', t('nav.profile'), 'profile', pending),
    ];
    final showBar = isTabRoot(widget.location, flags);

    return Scaffold(
      extendBody: true,
      body: widget.child,
      bottomNavigationBar: showBar ? _TabBar(tabs: tabs, location: widget.location) : null,
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tabs, required this.location});
  final List<_Tab> tabs;
  final String location;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Chrome height must stay near kTabBarContentHeight in layout.dart.
    return Container(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 6 + bottom),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [for (final tab in tabs) Expanded(child: _TabItem(tab: tab, active: location == tab.to))],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.active});
  final _Tab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.primary : c.textMuted;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Widget icon;
    switch (tab.icon) {
      case 'home':
        icon = reduceMotion
            ? Icon(LucideIcons.rocket, size: 22, color: color)
            : Lottie.asset('assets/lottie/rocket.json', width: 32, height: 32, repeat: true);
      case 'chat':
        icon = Icon(LucideIcons.messageCircle, size: 22, color: color);
      case 'films':
        icon = Icon(LucideIcons.clapperboard, size: 22, color: color);
      default:
        icon = Icon(LucideIcons.user, size: 24, color: color);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(999),
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
              decoration: BoxDecoration(color: active ? c.primarySoft : Colors.transparent, shape: BoxShape.circle),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  icon,
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
                          color: c.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [BoxShadow(color: Color(0x593B82F6), blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        child: Text(
                          tab.badge > 99 ? '99+' : '${tab.badge}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1),
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
