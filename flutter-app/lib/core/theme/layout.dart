import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Visual height of the AppShell tab bar (inner padding + icon well + label),
/// excluding the system safe inset. Keep in sync with `_TabBar` in app_shell.dart.
const kTabBarContentHeight = 70.0;
const kFabSize = 56.0;
const kFabScreenGap = 16.0;

/// Windows / Linux / macOS (not phones/tablets, not web).
bool get isDesktopPlatform {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// Wide enough for split auth / desktop chrome (also covers large tablets).
bool isWideAuthLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= 880;

/// Compact desktop (laptop) — form-first, narrower hero.
bool isCompactDesktopAuth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w >= 880 && w < 1180;
}

/// Prefer desktop-style auth chrome on desktop OS or wide windows.
bool useDesktopAuthLayout(BuildContext context) =>
    isDesktopPlatform || isWideAuthLayout(context);

/// Short-film poster grid columns — more columns on wide screens so tiles stay small.
int shortFilmGridColumns(double width) {
  if (width >= 1600) return 8;
  if (width >= 1280) return 7;
  if (width >= 1024) return 6;
  if (width >= 820) return 5;
  if (width >= 560) return 4;
  return 3;
}

/// Horizontal strip poster width (continue / series / featured).
double shortFilmRowCardWidth(double width) {
  if (width >= 1200) return 118;
  if (width >= 900) return 122;
  return (width * 0.32).clamp(108.0, 130.0);
}

/// Space the floating tab bar occupies from the bottom of a tab-root screen.
///
/// `extendBody: true` sometimes already folds the bar into [MediaQuery.padding];
/// other times padding is only the system inset. Never add the bar twice.
double tabBarClearance(BuildContext context) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  if (bottom >= kTabBarContentHeight) return bottom;
  return kTabBarContentHeight + bottom;
}

/// Offset from the screen bottom so a FAB sits just above the tab bar.
double tabFabOffset(BuildContext context) => tabBarClearance(context) + kFabScreenGap;

/// Bottom padding for scrollable content on a tab-root screen.
double tabScrollPadding(BuildContext context, {double extra = 0}) => tabBarClearance(context) + extra;
