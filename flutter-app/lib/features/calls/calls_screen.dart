import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// صفحة سجل المكالمات — مثل واتساب.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  bool _loading = true;
  List<Json> _items = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final data = await Api.get('/calls', query: {'take': 150});
      if (mounted) setState(() => _items = asJsonList(data));
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteOne(Json item) async {
    final ok = await confirmDialog(
      context,
      title: t('calls.deleteOneTitle'),
      message: t('calls.deleteOneDesc'),
      confirm: t('common.delete'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.delete('/calls/${item.str('messageId')}');
      if (mounted) setState(() => _items.removeWhere((x) => x.str('messageId') == item.str('messageId')));
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: t('calls.clearAllTitle'),
      message: t('calls.clearAllDesc'),
      confirm: t('common.delete'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.delete('/calls');
      if (mounted) setState(() => _items = []);
      if (mounted) showToast(context, t('calls.cleared'));
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  String _label(Json item) => formatCallMessagePreview(
        jsonEncode({
          'status': item.s('status') ?? 'missed',
          'voiceOnly': item.b('voiceOnly'),
          'durationSec': item.i('durationSec'),
        }),
        mine: item.b('isOutgoing'),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ModernPage(
      title: t('calls.title'),
      backTo: '/conversations',
      scroll: false,
      padding: EdgeInsets.zero,
      actions: [
        if (_items.isNotEmpty)
          IconButton(
            tooltip: t('calls.clearAll'),
            onPressed: _clearAll,
            icon: Icon(LucideIcons.trash2, size: 20, color: c.danger),
          ),
      ],
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted))),
              )
            else if (_items.isEmpty)
              EmptyState(icon: LucideIcons.phoneOff, text: t('calls.empty'))
            else
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: c.bgCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      side: BorderSide(color: c.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/conversation/${item.str('conversationId')}'),
                      onLongPress: () => _deleteOne(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          UserAvatar(url: item.s('partnerAvatar'), name: item.str('partnerName'), size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                item.str('partnerName'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary),
                              ),
                              const SizedBox(height: 3),
                              Row(children: [
                                Icon(
                                  item.b('voiceOnly') ? LucideIcons.phone : LucideIcons.video,
                                  size: 14,
                                  color: _statusColor(c, item),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _label(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _statusColor(c, item)),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 2),
                              Text(
                                formatRelative(item.date('sentAt')),
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ]),
                          ),
                          IconButton(
                            onPressed: () => _deleteOne(item),
                            icon: Icon(LucideIcons.trash2, size: 18, color: c.textMuted),
                            tooltip: t('common.delete'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(AppColors c, Json item) {
    final s = item.s('status') ?? 'missed';
    if (s == 'ended') return c.primary;
    return c.danger;
  }
}
