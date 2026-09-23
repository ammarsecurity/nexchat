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

/// App.vue `.offline-banner` — shown while logged in and offline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      color: c.textPrimary,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10 + top, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(t('noConnection.offlineBanner'),
                  style: TextStyle(color: c.bgPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: c.bgPrimary,
                side: BorderSide(color: c.bgPrimary),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(t('noConnection.retry'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
