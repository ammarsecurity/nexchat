import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// views/ConnectionHistoryView.vue
class ConnectionHistoryScreen extends StatefulWidget {
  const ConnectionHistoryScreen({super.key});

  @override
  State<ConnectionHistoryScreen> createState() => _ConnectionHistoryScreenState();
}

class _ConnectionHistoryScreenState extends State<ConnectionHistoryScreen> {
  String _tab = 'sent';
  bool _loading = false;
  List<Json> _list = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final data = await Api.get('/user/connection-history', query: {'filter': _tab});
      if (mounted) setState(() => _list = asJsonList(data));
    } catch (_) {
      if (mounted) setState(() => _list = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMilliseconds < 60000) return t('connectionHistory.now');
    if (diff.inMilliseconds < 3600000) return t('connectionHistory.minutesAgo', {'n': diff.inMinutes});
    if (diff.inMilliseconds < 86400000) return t('connectionHistory.hoursAgo', {'n': diff.inHours});
    return formatGregorianDateTime(d);
  }

  String _statusLabel(String s) => switch (s) {
        'Pending' => t('connectionHistory.statusPending'),
        'Accepted' => t('connectionHistory.statusAccepted'),
        'Declined' => t('connectionHistory.statusDeclined'),
        'Cancelled' => t('connectionHistory.statusCancelled'),
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = [
      ('sent', t('connectionHistory.sent'), LucideIcons.send),
      ('received', t('connectionHistory.received'), LucideIcons.inbox),
      ('missed', t('connectionHistory.missed'), LucideIcons.clock),
    ];
    return ModernPage(
      title: t('connectionHistory.title'),
      backTo: '/settings',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final tab in tabs)
              GestureDetector(
                onTap: () {
                  if (_tab == tab.$1) return;
                  setState(() => _tab = tab.$1);
                  _fetch();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: _tab == tab.$1 ? c.primary : c.bgCard,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      _tab == tab.$1 ? const BoxShadow(color: Color(0x593B82F6), blurRadius: 14, offset: Offset(0, 4)) : BoxShadow(color: c.shadow, blurRadius: 4),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(tab.$3, size: 14, color: _tab == tab.$1 ? Colors.white : c.textSecondary),
                    const SizedBox(width: 6),
                    Text(tab.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _tab == tab.$1 ? Colors.white : c.textSecondary)),
                  ]),
                ),
              ),
          ]),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted))),
          )
        else if (_list.isEmpty)
          EmptyState(icon: LucideIcons.hash, text: t('connectionHistory.empty'))
        else
          for (final item in _list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: c.bgCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: (item.s('sessionId') ?? '').isEmpty ? null : () => context.push('/chat/${item.s('sessionId')}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      UserAvatar(url: item.s('otherAvatar'), name: item.str('otherName'), size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.str('otherName'),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          Text(item.str('otherCode'), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                          Text('${_statusLabel(item.str('status'))} · ${_formatTime(item.date('createdAt'))}',
                              style: TextStyle(fontSize: 13, color: c.textSecondary)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
      ]),
    );
  }
}
