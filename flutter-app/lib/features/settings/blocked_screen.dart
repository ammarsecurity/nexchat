import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// views/BlockedView.vue
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  bool _loading = false;
  bool _error = false;
  List<Json> _list = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      _list = asJsonList(await Api.get('/blocks'));
      _error = false;
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unblock(Json b) async {
    if (!NetworkStatus.online.value) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    final id = b.s('blockedUserId');
    try {
      await Api.delete('/blocks/$id');
      if (!mounted) return;
      setState(() => _list = _list.where((x) => x.s('blockedUserId') != id).toList());
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(children: [
      ModernPage(
        title: t('blocked.title'),
        backTo: '/settings',
        scroll: _list.isNotEmpty,
        body: !_loading && _list.isEmpty
            ? EmptyState(
                icon: LucideIcons.ban,
                text: t(_error ? 'common.error' : 'blocked.empty'),
                action: _error
                    ? SizedBox(width: 200, child: PillButton(label: t('noConnection.retry'), onPressed: _fetch))
                    : null,
              )
            : Column(children: [
                for (final b in _list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ModernListRow(
                      leading: UserAvatar(url: b.s('avatar'), name: b.s('name') ?? '?'),
                      title: b.s('name') ?? '',
                      subtitle: b.s('uniqueCode'),
                      subtitleLtr: true,
                      trailing: TextButton(
                        onPressed: () => _unblock(b),
                        style: TextButton.styleFrom(
                          backgroundColor: c.primarySoft,
                          foregroundColor: c.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(t('blocked.unblock'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ]),
      ),
      LoaderOverlay(show: _loading, text: t('common.loading')),
    ]);
  }
}
