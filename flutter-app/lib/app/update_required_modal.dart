import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n/i18n.dart';
import '../core/theme/app_colors.dart';
import '../shared/widgets.dart';

/// components/UpdateRequiredModal.vue — blocking, not dismissible.
class UpdateRequiredModal extends StatelessWidget {
  const UpdateRequiredModal({super.key, this.downloadUrl});
  final String? downloadUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: PopScope(
        canPop: false,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: ColoredBox(
            color: const Color(0xD9000000),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Material(
                    type: MaterialType.transparency,
                    child: GlassCard(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0x406C63FF), Color(0x1A6C63FF)]),
                            ),
                            child: Icon(LucideIcons.download, size: 40, color: c.primary),
                          ),
                          const SizedBox(height: 20),
                          Text(t('update.requiredTitle'),
                              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          const SizedBox(height: 8),
                          Text(
                            t('update.requiredDesc'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          if (downloadUrl != null)
                            SizedBox(
                              width: double.infinity,
                              child: GradientButton(
                                label: t('update.download'),
                                icon: LucideIcons.download,
                                onPressed: () => launchUrl(Uri.parse(downloadUrl!), mode: LaunchMode.externalApplication),
                              ),
                            )
                          else
                            Text(
                              t('update.noUrl'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: c.textMuted, height: 1.5),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
