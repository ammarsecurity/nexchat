import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import 'widgets.dart';

/// Full-screen offline state — matches EmptyState + brand tokens.
class NoConnectionView extends StatelessWidget {
  const NoConnectionView({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;

    return ColoredBox(
      color: c.bgPrimary,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft brand wash — same language as splash/empty states, not a flat void.
          Positioned(
            top: -80,
            right: -60,
            child: _WashOrb(color: c.primary.withValues(alpha: light ? 0.10 : 0.16), size: 220),
          ),
          Positioned(
            bottom: -40,
            left: -50,
            child: _WashOrb(color: c.primary.withValues(alpha: light ? 0.07 : 0.12), size: 180),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.primarySoft,
                          border: Border.all(color: c.primary.withValues(alpha: 0.18)),
                          boxShadow: [
                            BoxShadow(
                              color: c.primary.withValues(alpha: light ? 0.12 : 0.22),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(LucideIcons.wifiOff, size: 36, color: c.primary),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        t('noConnection.title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: kAppFont,
                          color: c.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        t('noConnection.desc'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: kAppFont,
                          color: c.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.6,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 28),
                      PillButton(
                        label: t('noConnection.retry'),
                        onPressed: onRetry,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WashOrb extends StatelessWidget {
  const _WashOrb({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Compact offline strip — theme-aware, matches shell chrome.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.onRetry});
  final VoidCallback onRetry;

  /// Content row height (status-bar inset is applied separately via [SafeArea]).
  static const double contentHeight = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final bg = light ? const Color(0xFF1E293B) : c.bgElevated;
    const fg = Color(0xFFF8FAFC);

    final clean = const TextStyle(
      fontFamily: kAppFont,
      color: fg,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      decorationThickness: 0,
    );

    return DefaultTextStyle(
      style: clean,
      child: Material(
        color: bg,
        elevation: 0,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: contentHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(LucideIcons.wifiOff, size: 14, color: fg),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('noConnection.offlineBanner'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: clean.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: onRetry,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Text(
                          t('noConnection.retry'),
                          style: clean.copyWith(fontSize: 12, fontWeight: FontWeight.w700, height: 1.1),
                        ),
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
