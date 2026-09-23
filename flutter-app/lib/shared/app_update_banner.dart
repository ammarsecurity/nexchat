import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../services/update_check.dart';

/// In-app notice on Home / Conversations when a newer version is published.
class AppUpdateBanner extends ConsumerWidget {
  const AppUpdateBanner({super.key, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12)});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appUpdateProvider);
    if (info == null || !info.hasUpdate || info.required) return const SizedBox.shrink();

    final c = context.colors;
    final url = info.downloadUrl;
    final version = info.latestVersion;
    final desc = (version != null && version.isNotEmpty)
        ? t('update.bannerDescVersion').replaceAll('{version}', version)
        : t('update.bannerDesc');

    Future<void> open() async {
      if (url == null) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }

    return Padding(
      padding: margin,
      child: Material(
        color: c.primarySoft,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: url == null ? null : open,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.primaryMuted),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.download, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    t('update.bannerTitle'),
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 13,
                      height: 1.4,
                      color: c.textSecondary,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              if (url != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t('update.updateNow'),
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
