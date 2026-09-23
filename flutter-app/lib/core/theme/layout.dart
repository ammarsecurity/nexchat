import 'package:flutter/widgets.dart';

/// Visual height of the AppShell tab bar (inner padding + icon well + label),
/// excluding the system safe inset. Keep in sync with `_TabBar` in app_shell.dart.
const kTabBarContentHeight = 70.0;
const kFabSize = 56.0;
const kFabScreenGap = 16.0;

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
