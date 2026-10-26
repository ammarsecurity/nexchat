import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'discover_theme.dart';

/// List of mutual Discover matches — open chat from here anytime.
Future<void> showDiscoverMatchesSheet(BuildContext context) {
  return showAppSheet<void>(context, builder: (_) => const _DiscoverMatchesSheet());
}

class _DiscoverMatchesSheet extends StatefulWidget {
  const _DiscoverMatchesSheet();

  @override
  State<_DiscoverMatchesSheet> createState() => _DiscoverMatchesSheetState();
}

class _DiscoverMatchesSheetState extends State<_DiscoverMatchesSheet> {
  bool _loading = true;
  String _error = '';
  List<Json> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await Api.get('/discover/matches');
      final raw = res is Map ? (res['items'] ?? res['Items']) : null;
      final list = <Json>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = Api.errorMessage(e, t('common.error'));
        });
      }
    }
  }

  void _openChat(Json row) {
    final id = row.str('conversationId');
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    Navigator.pop(context);
    context.push('/conversation/$id');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('discover.matchesTitle'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DiscoverTheme.ink),
                ),
              ),
              GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t('discover.matchesHint'),
            style: TextStyle(fontSize: 13, height: 1.35, color: c.textMuted),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator(color: DiscoverTheme.red)),
            )
          else if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Text(_error, textAlign: TextAlign.center, style: TextStyle(color: c.textMuted)),
                  const SizedBox(height: 12),
                  PillButton(label: t('common.retry'), color: DiscoverTheme.red, onPressed: _load),
                ],
              ),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(LucideIcons.heart, size: 40, color: DiscoverTheme.red.withValues(alpha: 0.7)),
                  const SizedBox(height: 12),
                  Text(
                    t('discover.matchesEmpty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: DiscoverTheme.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('discover.matchesEmptyHint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.35),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final row = _items[i];
                  final partner = row['partner'] is Map ? Map<String, dynamic>.from(row['partner'] as Map) : <String, dynamic>{};
                  final name = partner.str('name');
                  final age = partner.i('age');
                  final title = age > 0 ? '$name, $age' : name;
                  return Material(
                    color: c.bgElevated,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openChat(row),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            UserAvatar(
                              url: partner.s('avatar'),
                              name: name,
                              size: 48,
                              featured: partner.b('isFeatured'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: DiscoverTheme.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    t('discover.openChat'),
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DiscoverTheme.red.withValues(alpha: 0.85)),
                                  ),
                                ],
                              ),
                            ),
                            Icon(LucideIcons.messageCircle, size: 20, color: DiscoverTheme.red.withValues(alpha: 0.85)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
