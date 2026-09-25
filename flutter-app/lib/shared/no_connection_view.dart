import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import 'widgets.dart';

/// views/NoConnectionView.vue
class NoConnectionView extends StatelessWidget {
  const NoConnectionView({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.bgPrimary,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.wifiOff, size: 80, color: c.textMuted.withValues(alpha: 0.8)),
                  const SizedBox(height: 24),
                  Text(t('noConnection.title'),
                      textAlign: TextAlign.center, style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(t('noConnection.desc'),
                      textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.6)),
                  const SizedBox(height: 28),
                  GradientButton(label: t('noConnection.retry'), icon: LucideIcons.refreshCw, onPressed: onRetry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact offline strip — clean row, no underlines.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.onRetry});
  final VoidCallback onRetry;

  /// Content row height (status-bar inset is applied separately via [SafeArea]).
  static const double contentHeight = 36;

  static const _fg = Color(0xFFF8FAFC);
  static const _bg = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    // Kill any inherited text decoration (theme/DefaultTextStyle) that draws yellow underlines.
    final clean = const TextStyle(
      color: _fg,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      decorationThickness: 0,
    );

    return DefaultTextStyle(
      style: clean,
      child: Material(
        color: _bg,
        elevation: 0,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: contentHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(LucideIcons.wifiOff, size: 15, color: _fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('noConnection.offlineBanner'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: clean.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: onRetry,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
