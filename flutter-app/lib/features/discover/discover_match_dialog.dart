import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'discover_theme.dart';

/// Dedupes MatchCreated (HTTP + hub) within a short window.
final _recentMatchKeys = <String>{};

bool claimDiscoverMatchUi(String? matchId, String? conversationId) {
  final key = (matchId != null && matchId.isNotEmpty)
      ? 'm:$matchId'
      : (conversationId != null && conversationId.isNotEmpty ? 'c:$conversationId' : '');
  if (key.isEmpty) return false;
  if (!_recentMatchKeys.add(key)) return false;
  Future<void>.delayed(const Duration(seconds: 8), () => _recentMatchKeys.remove(key));
  return true;
}

Future<void> showDiscoverMatchDialog(BuildContext context, Json data) async {
  if (!context.mounted) return;
  final partner = data['partner'] is Map ? Map<String, dynamic>.from(data['partner'] as Map) : <String, dynamic>{};
  final convId = data.str('conversationId');
  final matchId = data.str('matchId');
  if (!claimDiscoverMatchUi(matchId.isEmpty ? null : matchId, convId.isEmpty ? null : convId)) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final c = ctx.colors;
      return AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(t('discover.matchTitle'), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('discover.matchSubtitle'), textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            UserAvatar(url: partner.s('avatar'), name: partner.str('name'), size: 88, featured: partner.b('isFeatured')),
            const SizedBox(height: 10),
            Text(partner.str('name'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('discover.keepSwiping'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DiscoverTheme.red),
            onPressed: () {
              Navigator.pop(ctx);
              if (convId.isNotEmpty) context.push('/conversation/$convId');
            },
            child: Text(t('discover.openChat')),
          ),
        ],
      );
    },
  );
}
