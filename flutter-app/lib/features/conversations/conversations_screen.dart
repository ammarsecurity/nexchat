import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/feature_flags.dart';
import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/widgets.dart';
import '../notifications/notifications_controller.dart';
import '../stories/stories_strip.dart';
import 'active_conversation.dart';
import 'avatar_overrides.dart';
import 'contacts_panel.dart';
import 'conversations_list_controller.dart';
import 'message_requests_panel.dart';

const _cacheKey = 'nexchat_conversations_cache';

/// views/ConversationsView.vue (mobile layout of MessagingLayout).
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key, this.tab, this.notice, this.openId});
  final String? tab;
  final String? notice;
  final String? openId;

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  String _filter = 'all';
  final _search = TextEditingController();
  bool _ready = false;
  bool _loading = true;
  bool _needPhone = false;
  bool _markingAll = false;
  bool _fabOpen = false;
  final _contactsKey = GlobalKey<ContactsPanelState>();
  void Function()? _removeReturnListener;

  String get _section => switch (widget.tab) { 'contacts' => 'contacts', 'requests' => 'requests', _ => 'chats' };

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(notificationsProvider.notifier).load();
      if (NetworkStatus.online.value) ref.read(pendingRequestsProvider.notifier).fetch();
      ref.read(activeConversationProvider.notifier).clear();
    });
    _fetch();
    Hubs.conversation.start().catchError((_) {});
  }

  @override
  void didUpdateWidget(ConversationsScreen old) {
    super.didUpdateWidget(old);
    if (widget.openId != null && widget.openId != old.openId) _maybeOpen();
  }

  @override
  void dispose() {
    _removeReturnListener?.call();
    _search.dispose();
    super.dispose();
  }

  void _maybeOpen() {
    final id = widget.openId;
    if (id == null || !_ready) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/conversation/$id');
    });
  }

  List<Json> _normalize(List<Json> list) => [
        for (final c in list)
          {
            ...c,
            'lastMessagePreview': formatConversationListPreview(c.s('lastMessagePreview'), type: c.s('lastMessageType')),
          },
      ];

  Future<void> _fetch({bool background = false}) async {
    if (!background) setState(() => _loading = true);
    final list = ref.read(conversationsListProvider.notifier);
    if (!background) {
      final cached = Prefs.instance.getString(_cacheKey);
      if (cached != null) {
        try {
          list.setList(asJsonList(jsonDecode(cached)));
        } catch (_) {}
      }
    }
    _needPhone = false;
    if (!ref.read(networkProvider)) {
      if (mounted) {
        setState(() {
          _ready = true;
          if (!background) _loading = false;
        });
        _maybeOpen();
      }
      return;
    }
    try {
      final data = await Api.get('/conversations', query: {
        'filter': _filter,
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
      });
      final items = _normalize(asJsonList(data));
      list.setList(items);
      if (_filter == 'all') Prefs.instance.setString(_cacheKey, jsonEncode(items));
    } catch (e) {
      final msg = Api.errorMessage(e);
      if (msg.contains('رقم الهاتف')) _needPhone = true;
    } finally {
      if (mounted) {
        setState(() {
          _ready = true;
          if (!background) _loading = false;
        });
        _maybeOpen();
      }
    }
  }

  /// Pushed chats may come back via pop or `context.go('/conversations')`, so watch the router location.
  void _refreshOnReturn() {
    _removeReturnListener?.call();
    final delegate = GoRouter.of(context).routerDelegate;
    var away = false;
    void listener() {
      if (delegate.currentConfiguration.uri.path != '/conversations') {
        away = true;
        return;
      }
      if (!away) return;
      _removeReturnListener?.call();
      if (!mounted) return;
      _fetch(background: true);
      ref.read(pendingRequestsProvider.notifier).fetch();
    }

    delegate.addListener(listener);
    _removeReturnListener = () {
      delegate.removeListener(listener);
      _removeReturnListener = null;
    };
  }

  Future<void> _markAllRead(int total) async {
    if (_markingAll || total <= 0) return;
    if (!ref.read(networkProvider)) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    setState(() => _markingAll = true);
    try {
      await Api.put('/conversations/read-all');
      await _fetch(background: true);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _setSection(String s) => context.go(s == 'chats' ? '/conversations' : '/conversations?tab=$s');

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    ref.listen(networkProvider, (prev, next) {
      if (prev == false && next == true) {
        unawaited(_fetch(background: true));
        unawaited(ref.read(pendingRequestsProvider.notifier).fetch());
      }
    });
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    final pending = ref.watch(pendingRequestsProvider);
    final notifCount = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Stack(children: [
        Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 8),
            child: Row(children: [
              Expanded(
                child: Text(t('conversations.title'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.textPrimary)),
              ),
              if (_section == 'contacts') ...[
                GlassIconButton(icon: LucideIcons.userPlus, color: c.primary, onTap: () => _contactsKey.currentState?.openAddModal()),
                const SizedBox(width: 8),
              ],
              GlassIconButton(icon: LucideIcons.bell, badgeDot: notifCount > 0, onTap: () => context.push('/notifications')),
            ]),
          ),
          _MainTabs(section: _section, pending: pending, onChanged: _setSection),
          Expanded(
            child: switch (_section) {
              'contacts' => ContactsPanel(key: _contactsKey),
              'requests' => MessageRequestsPanel(notice: widget.notice),
              _ => _buildChats(context),
            },
          ),
        ]),
        if (_section == 'chats') _buildFab(context),
      ]),
    );
  }

  Widget _buildChats(BuildContext context) {
    final c = context.colors;
    final all = ref.watch(conversationsListProvider);
    final totalUnread = ref.watch(totalUnreadProvider);
    final storiesEnabled = ref.watch(featureFlagsProvider).value?.stories ?? false;
    final activeId = ref.watch(activeConversationProvider).conversationId;
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
            .where((x) =>
                x.str('partnerName').toLowerCase().contains(q) ||
                x.str('partnerPhone').contains(q) ||
                x.str('partnerUniqueCode').toLowerCase().contains(q))
            .toList();
    final pinned = filtered.where((x) => x.b('isPinned')).toList();
    final showPinned = pinned.isNotEmpty && _filter != 'archived';
    final rest = showPinned ? filtered.where((x) => !x.b('isPinned')).toList() : filtered;

    final light = Theme.of(context).brightness == Brightness.light;

    return RefreshIndicator(
      color: c.primary,
      onRefresh: () => _fetch(background: true),
      child: ListView(
        padding: EdgeInsets.only(bottom: tabScrollPadding(context, extra: kFabSize + kFabScreenGap)),
        children: [
          if (_needPhone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0x26FFC107),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Text(t('conversations.needPhone'), style: TextStyle(fontSize: 14, color: c.textPrimary)),
                GestureDetector(
                  onTap: () => context.push('/complete-profile'),
                  child: Text(t('completeProfile.completeNow'),
                      style: TextStyle(color: c.primary, decoration: TextDecoration.underline)),
                ),
              ]),
            ),
          _StoriesHeroCard(
            light: light,
            storiesEnabled: storiesEnabled,
            search: _search,
            markingAll: _markingAll,
            totalUnread: totalUnread,
            onSearch: (_) => setState(() {}),
            onMarkAllRead: () => _markAllRead(totalUnread),
          ),
          // filter chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final f in ['all', 'unread', 'archived'])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: _FilterChip(
                      label: f == 'all'
                          ? t('conversations.filterAll')
                          : f == 'unread'
                              ? t('conversations.filterUnread')
                              : t('conversations.filterArchived'),
                      active: _filter == f,
                      badge: f == 'unread' ? totalUnread : 0,
                      dim: _loading && _filter != f,
                      onTap: _loading
                          ? null
                          : () {
                              setState(() => _filter = f);
                              _fetch();
                            },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading)
            const _ListSkeleton()
          else if (_ready && filtered.isEmpty)
            EmptyState(
              icon: LucideIcons.messageCircle,
              text: t('conversations.empty'),
              action: PillButton(label: t('conversations.newChat'), onPressed: () => _setSection('contacts')),
            )
          else
            for (final row in [
              if (showPinned) ...[
                _SectionHead(icon: LucideIcons.pin, title: t('conversations.pinnedChats')),
                for (final conv in pinned)
                  ConversationTile(key: ValueKey('p${conv.str('id')}'), conv: conv, active: activeId == conv.str('id'), onOpen: _refreshOnReturn),
              ],
              if (rest.isNotEmpty || filtered.isEmpty) ...[
                _SectionHead(icon: LucideIcons.messageCircle, title: t('conversations.allChats')),
                for (final conv in rest)
                  ConversationTile(key: ValueKey('c${conv.str('id')}'), conv: conv, active: activeId == conv.str('id'), onOpen: _refreshOnReturn),
              ],
            ])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: row),
        ],
      ),
    );
  }

  Widget _buildFab(BuildContext context) {
    final c = context.colors;
    final bottom = tabFabOffset(context);
    Widget item(String label, IconData icon, Color bg, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6)],
                ),
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary)),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 2))],
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
            ]),
          ),
        );

    return PositionedDirectional(
      end: 16,
      bottom: bottom,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), alignment: Alignment.bottomRight, child: child),
          ),
          child: _fabOpen
              ? Column(key: const ValueKey('menu'), crossAxisAlignment: CrossAxisAlignment.end, children: [
                  item(t('conversations.newGroup'), LucideIcons.usersRound, const Color(0xFF5C6BC0), () {
                    setState(() => _fabOpen = false);
                    context.push('/conversations/create-group');
                  }),
                  item(t('conversations.newChat'), LucideIcons.messageCircle, c.primary, () {
                    setState(() => _fabOpen = false);
                    _setSection('contacts');
                  }),
                ])
              : const SizedBox.shrink(key: ValueKey('none')),
        ),
        GestureDetector(
          onTap: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _fabOpen ? c.bgCard : c.primary,
              shape: BoxShape.circle,
              boxShadow: [
                _fabOpen
                    ? const BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 2))
                    : const BoxShadow(color: Color(0x663B82F6), blurRadius: 20, offset: Offset(0, 6)),
              ],
            ),
            child: Icon(_fabOpen ? LucideIcons.x : LucideIcons.messageSquarePlus, size: 24, color: _fabOpen ? c.textPrimary : Colors.white),
          ),
        ),
      ]),
    );
  }
}

class _StoriesHeroCard extends StatelessWidget {
  const _StoriesHeroCard({
    required this.light,
    required this.storiesEnabled,
    required this.search,
    required this.markingAll,
    required this.totalUnread,
    required this.onSearch,
    required this.onMarkAllRead,
  });

  final bool light;
  final bool storiesEnabled;
  final TextEditingController search;
  final bool markingAll;
  final int totalUnread;
  final ValueChanged<String> onSearch;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? const [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA)]
              : const [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF3B82F6)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: light ? 0.28 : 0.14)),
        boxShadow: [BoxShadow(color: const Color(0x472563EB), blurRadius: light ? 22 : 24, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _HeroPatternPainter()))),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              t('stories.allStory'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x1F0F172A), blurRadius: 2, offset: Offset(0, 1))],
              ),
            ),
            const SizedBox(height: 2),
            if (storiesEnabled) const StoriesStrip() else const SizedBox(height: 6),
            Container(
              height: 40,
              padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Row(children: [
                Icon(LucideIcons.search, size: 18, color: c.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: onSearch,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: t('conversations.searchRecent'),
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                    ),
                  ),
                ),
                Opacity(
                  opacity: markingAll || totalUnread <= 0 ? 0.4 : 1,
                  child: Material(
                    color: c.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onMarkAllRead,
                      child: SizedBox(width: 36, height: 36, child: Icon(LucideIcons.checkCheck, size: 18, color: c.primary)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HeroPatternPainter extends CustomPainter {
  const _HeroPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.32],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.84, -0.84),
          radius: 0.55,
          colors: const [Color(0x42FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.88, 0.8),
          radius: 0.5,
          colors: const [Color(0x24FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.16),
          radius: 0.7,
          colors: const [Color(0x52BFDBFE), Color(0x00BFDBFE)],
        ).createShader(rect),
    );

    final dot = Paint()..color = const Color(0x1AFFFFFF);
    const step = 11.0;
    for (var y = 5.0; y < size.height; y += step) {
      for (var x = 5.0; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }

    canvas.saveLayer(rect, Paint());
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-32 * math.pi / 180);
    final stripe = Paint()
      ..color = const Color(0x0BFFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    for (var i = -diag; i < diag; i += 19) {
      canvas.drawLine(Offset(-diag, i), Offset(diag, i), stripe);
    }
    canvas.restore();
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          center: const Alignment(0, -0.24),
          radius: 0.82,
          colors: const [Color(0xFF000000), Color(0x00000000)],
          stops: const [0.18, 0.7],
        ).createShader(rect),
    );
    canvas.restore();

    final orb = Rect.fromLTWH(-24, -28, 100, 100);
    canvas.drawOval(
      orb,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.68],
        ).createShader(orb)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MainTabs extends StatelessWidget {
  const _MainTabs({required this.section, required this.pending, required this.onChanged});
  final String section;
  final int pending;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tab(String id, IconData icon, String label, [int badge = 0]) {
      final active = section == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? c.bgCard : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: active ? [BoxShadow(color: c.shadow, blurRadius: 6)] : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                Icon(icon, size: 18, color: active ? c.primary : c.textMuted),
                if (badge > 0)
                  PositionedDirectional(
                    top: -5,
                    end: -9,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: active ? c.bgCard : c.bgElevated, width: 2),
                      ),
                      child: Text(badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, height: 1)),
                    ),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? c.primary : c.textMuted, height: 1.2)),
            ]),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
      child: Row(children: [
        tab('chats', LucideIcons.messageCircle, t('nav.conversations')),
        const SizedBox(width: 6),
        tab('contacts', LucideIcons.users, t('nav.contacts')),
        const SizedBox(width: 6),
        tab('requests', LucideIcons.mail, t('conversations.messageRequestsShort'), pending),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.badge, required this.onTap, this.dim = false});
  final String label;
  final bool active;
  final int badge;
  final VoidCallback? onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: dim ? 0.72 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: active ? c.primary : c.bgCard,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              active ? const BoxShadow(color: Color(0x593B82F6), blurRadius: 14, offset: Offset(0, 4)) : BoxShadow(color: c.shadow, blurRadius: 4),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (active) ...[const Icon(LucideIcons.check, size: 14, color: Colors.white), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : c.textSecondary)),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Colors.white.withValues(alpha: 0.22) : c.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badge > 99 ? '99+' : '$badge',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : c.primary)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Row(children: [
        Icon(icon, size: 16, color: c.primary),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
      ]),
    );
  }
}

class ConversationTile extends ConsumerWidget {
  const ConversationTile({super.key, required this.conv, this.active = false, this.onOpen});
  final Json conv;
  final bool active;
  final VoidCallback? onOpen;

  void _open(BuildContext context, String location) {
    onOpen?.call();
    context.push(location);
  }

  String _preview() {
    final type = conv.s('lastMessageType');
    final formatted = formatConversationListPreview(conv.s('lastMessagePreview'), type: type);
    if (formatted.isNotEmpty) return formatted;
    return switch (type) {
      'video' => t('conversationChat.videoMessage'),
      'album' => t('conversationChat.albumMessage'),
      'image' => t('conversationChat.replyPreviewImage'),
      'audio' => t('conversationChat.voiceMessage'),
      _ => '—',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final isGroup = conv.b('isGroup');
    final unread = conv.i('unreadCount');
    final name = conv.s('partnerName') ?? '—';
    final partnerId = conv.s('partnerId');
    final avatar = (partnerId != null ? ref.watch(avatarOverridesProvider)[partnerId] : null) ?? conv.s('partnerAvatar');
    final hasImage = avatar != null && (avatar.startsWith('http') || avatar.startsWith('/'));
    final hasEmoji = avatar != null && avatar.trim().isNotEmpty && !hasImage;

    Widget avatarWidget;
    if (isGroup && !hasImage) {
      avatarWidget = Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x336C63FF),
          border: Border.all(color: c.border),
        ),
        alignment: Alignment.center,
        child: Icon(LucideIcons.users, size: 16, color: c.primary),
      );
    } else {
      avatarWidget = UserAvatar(url: hasImage || hasEmoji ? avatar : null, name: name, size: 50);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? c.bgCardHover : c.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: () => _open(context, '/conversation/${conv.str('id')}'),
          onLongPress: () => _open(context, '/conversations/${conv.str('id')}/options'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: EdgeInsetsDirectional.fromSTEB(isGroup ? 11 : 14, 12, 14, 12),
            decoration: BoxDecoration(
              border: isGroup ? BorderDirectional(start: BorderSide(color: c.primary, width: 3)) : null,
              boxShadow: [BoxShadow(color: c.shadow, blurRadius: 4)],
            ),
            child: Row(children: [
              avatarWidget,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16, height: 1.2, fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600, color: c.textPrimary)),
                    ),
                    Text(formatRelative(conv.date('lastMessageAt')), style: TextStyle(fontSize: 11, color: c.textMuted)),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(
                      child: Text(_preview(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: c.textSecondary,
                              fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.w400)),
                    ),
                    if (isGroup)
                      Container(
                        margin: const EdgeInsetsDirectional.only(start: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(color: const Color(0x266C63FF), borderRadius: BorderRadius.circular(4)),
                        child: Text(t('groups.groupLabel'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.primary)),
                      ),
                    if (unread > 0)
                      Container(
                        margin: const EdgeInsetsDirectional.only(start: 6),
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [BoxShadow(color: Color(0x4D3B82F6), blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        child: Text(unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1)),
                      ),
                    if (conv.s('partnerId') != null || conv.b('isGroup'))
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _open(context, '/conversations/${conv.str('id')}/options'),
                          icon: Icon(LucideIcons.ellipsisVertical, size: 16, color: c.textMuted),
                        ),
                      ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatefulWidget {
  const _ListSkeleton();

  @override
  State<_ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<_ListSkeleton> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_ctrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 120,
            height: 14,
            margin: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(6)),
          ),
          for (var i = 0; i < 7; i++)
            Container(
              height: 72,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(AppRadius.lg)),
              child: Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: c.bgElevated, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 140, height: 12, decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 8),
                    Container(width: 200, height: 10, decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(6))),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}