import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/share_links.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../services/push_service.dart';
import '../../shared/app_footer.dart';
import '../../shared/app_update_banner.dart';
import '../../shared/banner_strip.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../conversations/conversations_list_controller.dart';
import '../notifications/notifications_controller.dart';
import '../settings/avatar_picker_sheet.dart';
import '../short_films/short_films_controller.dart';
import '../short_films/short_films_hub_screen.dart';
import 'matching_controller.dart';

/// views/HomeView.vue
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.invite});
  final String? invite;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final List<void Function()> _offs = [];
  String _codeError = '';
  bool _copied = false;
  bool _loading = false;
  bool _waitingForAccept = false;
  bool _profileBannerDismissed = false;
  bool _notifLoading = false;
  Timer? _connectionTimeout;
  Timer? _copiedTimer;
  late final GoRouter _router = ref.read(routerProvider);
  bool _visible = true;

  MatchingController get _matching => ref.read(matchingProvider.notifier);

  bool get _isVisible => _router.routerDelegate.currentConfiguration.uri.path == '/home';

  @override
  void initState() {
    super.initState();
    _codeFocus.addListener(() => setState(() {}));
    [Permission.camera, Permission.microphone].request().catchError((_) => <Permission, PermissionStatus>{});
    _visible = _isVisible;
    _router.routerDelegate.addListener(_onRouteChanged);
    Hubs.conversation.start().catchError((_) {});
    _loadConversations();
    _bindHub();
  }

  void _onRouteChanged() {
    final v = _isVisible;
    if (v == _visible) return;
    _visible = v;
    if (!v && mounted && (_waitingForAccept || _loading || _connectionTimeout != null)) {
      unawaited(_cancelConnectionRequest());
    }
  }

  List<Json> _normalizeConversations(List<Json> list) => [
        for (final c in list)
          {...c, 'lastMessagePreview': formatConversationListPreview(c.s('lastMessagePreview'), type: c.s('lastMessageType'))},
      ];

  Future<void> _loadConversations() async {
    if (!NetworkStatus.online.value) {
      final cached = Prefs.instance.getString('nexchat_conversations_cache');
      if (cached != null) {
        try {
          ref.read(conversationsListProvider.notifier).setList(_normalizeConversations(asJsonList(jsonDecode(cached))));
        } catch (_) {}
      }
      return;
    }
    try {
      final data = await Api.get('/conversations', query: {'filter': 'all'});
      if (!mounted) return;
      ref.read(conversationsListProvider.notifier).setList(_normalizeConversations(asJsonList(data)));
    } catch (_) {}
  }

  Future<void> _bindHub() async {
    final flags = await ref.read(featureFlagsProvider.future);
    if (!mounted) return;
    if (flags.connectHub) {
      Hubs.matching.start().catchError((_) {});
      final h = Hubs.matching;
      _offs.addAll([
        h.on('MatchFound', (_) {
          _clearTimeout();
          if (mounted) setState(() => _waitingForAccept = _loading = false);
        }),
        h.on('SearchCancelled', (_) => _matching.setIdle()),
        h.on('CodeError', (a) {
          _clearTimeout();
          if (mounted) {
            setState(() {
              _codeError = a.isNotEmpty ? '${a.first}' : t('home.connectionError');
              _loading = _waitingForAccept = false;
            });
          }
        }),
        h.on('ConnectionRequestSent', (_) {
          if (!mounted) return;
          setState(() => _waitingForAccept = true);
          _startTimeout();
        }),
        h.on('ConnectionDeclined', (_) {
          _clearTimeout();
          if (mounted) {
            setState(() {
              _waitingForAccept = _loading = false;
              _codeError = t('home.requestDeclined');
            });
          }
        }),
        h.on('ConnectionCancelled', (_) {
          _clearTimeout();
          if (mounted) setState(() => _waitingForAccept = _loading = false);
        }),
      ]);
    }
    if (flags.codeConnect) _applyPendingInvite();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.invite?.isNotEmpty ?? false) && widget.invite != oldWidget.invite) {
      ref.read(featureFlagsProvider.future).then((f) {
        if (mounted && f.codeConnect) _applyPendingInvite();
      });
    }
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRouteChanged);
    for (final off in _offs) {
      off();
    }
    if (_waitingForAccept || _loading) {
      Hubs.matching.ensureConnected().then((_) => Hubs.matching.invoke('CancelConnectionRequest')).catchError((_) => null);
    }
    _clearTimeout();
    _copiedTimer?.cancel();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _clearTimeout() {
    _connectionTimeout?.cancel();
    _connectionTimeout = null;
  }

  void _startTimeout() {
    _clearTimeout();
    _connectionTimeout = Timer(const Duration(seconds: 60), () async {
      _connectionTimeout = null;
      if (mounted) {
        setState(() {
          _waitingForAccept = _loading = false;
          _codeError = t('home.timeoutError');
        });
      }
      try {
        await Hubs.matching.ensureConnected();
        await Hubs.matching.invoke('CancelConnectionRequest');
      } catch (_) {}
    });
  }

  Future<void> _startRandom() async {
    if (!ref.read(networkProvider)) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    setState(() => _loading = true);
    _matching.setSearching();
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('StartSearching', [_matching.current.genderFilter]);
      if (mounted && _matching.current.status != MatchStatus.matched) context.push('/matching');
    } catch (_) {
      _matching.setIdle();
      if (mounted) showToast(context, t('home.connectionError'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectByCode() async {
    if (_code.text.trim().isEmpty) return;
    if (!ref.read(networkProvider)) {
      setState(() => _codeError = t('noConnection.actionFailed'));
      return;
    }
    setState(() => _codeError = '');
    final code = _code.text.trim().toUpperCase();
    if (!code.startsWith('NX-') || code.length != 7) {
      setState(() => _codeError = t('home.codeFormatError'));
      return;
    }
    setState(() {
      _loading = true;
      _waitingForAccept = false;
    });
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('ConnectByCode', [code]);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _codeError = t('home.connectionError');
        });
      }
    }
  }

  Future<void> _cancelConnectionRequest() async {
    _clearTimeout();
    setState(() => _waitingForAccept = _loading = false);
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('CancelConnectionRequest');
    } catch (_) {}
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _shareInvite() async {
    final user = ref.read(authProvider).user;
    final msg = await shareInviteCode(user?.uniqueCode, inviterName: user?.name);
    if (mounted && msg != null) showToast(context, msg);
  }

  void _applyPendingInvite() {
    final fromQuery = widget.invite;
    final stored = Prefs.instance.getString(Keys.pendingInvite);
    if (stored != null) Prefs.instance.setString(Keys.pendingInvite, null);
    final code = normalizeInviteCode((fromQuery?.isNotEmpty ?? false) ? fromQuery : stored);
    if (code.isEmpty) return;
    _code.text = code;
    if (fromQuery != null && fromQuery.isNotEmpty) context.replace('/home');
    _connectByCode();
  }

  Future<void> _enableNotifications() async {
    setState(() => _notifLoading = true);
    try {
      await PushService.instance.optIn();
      PushService.promptNotifications.value = false;
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    }
    if (mounted) setState(() => _notifLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkProvider, (prev, next) {
      if (prev == false && next == true) unawaited(_loadConversations());
    });
    final c = context.colors;
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final flags = ref.watch(featureFlagsProvider).value;
    final loaded = flags != null;
    final randomOn = flags?.randomChat ?? false;
    final codeOn = flags?.codeConnect ?? false;
    final filmsOn = flags?.shortFilms ?? false;
    final unread = ref.watch(unreadNotificationsProvider);
    final compact = loaded && !randomOn && !codeOn;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final featured = user?.isFeatured ?? false;
    final uniqueCode = user?.uniqueCode;

    final filmsState = filmsOn ? ref.watch(shortFilmsProvider) : null;
    if (filmsOn && filmsState != null && !filmsState.loaded && !filmsState.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(shortFilmsProvider.notifier).fetchAll(force: true);
      });
    }

    Widget avatarBadge({double size = 40}) {
      if (user == null) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => context.push('/profile/${user.id}'),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: auth.avatarColor,
              border: Border.all(color: c.primaryMuted, width: 2),
              boxShadow: featured ? const [BoxShadow(color: Color(0x66FF7300), spreadRadius: 2)] : null,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: isImageAvatar(auth.avatar)
                ? UserAvatar(url: auth.avatar, name: user.name, size: size - 4)
                : Text(
                    (auth.avatar?.isNotEmpty ?? false) ? auth.avatar! : (user.name.isEmpty ? '?' : user.name.characters.first.toUpperCase()),
                    style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
          ),
          if (featured) const PositionedDirectional(top: -2, end: -2, child: Icon(LucideIcons.crown, size: 12, color: Color(0xFFFF7300))),
        ]),
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTabHeader(
          title: t('nav.connect'),
          actions: [
            GlassIconButton(icon: LucideIcons.bell, badgeDot: unread > 0, onTap: () => context.push('/notifications')),
          ],
        ),
        if (user != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              avatarBadge(size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${t('home.greeting')} ${user.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary),
                ),
              ),
            ]),
          ),
      ],
    );

    final codeChip = (uniqueCode != null && uniqueCode.isNotEmpty && codeOn)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(
                child: Material(
                  color: c.bgCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _copyCode(uniqueCode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Icon(LucideIcons.hash, size: 16, color: c.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              uniqueCode,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.textPrimary),
                            ),
                          ),
                        ),
                        Text(_copied ? t('common.copiedShort') : t('common.copy'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primary)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: c.primarySoft,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _shareInvite,
                  child: SizedBox(width: 44, height: 44, child: Icon(LucideIcons.share2, size: 18, color: c.primary)),
                ),
              ),
            ]),
          )
        : const SizedBox.shrink();

    Widget startButton({required Widget leading, required Widget content, Widget? trailing, VoidCallback? onTap, bool center = false}) => Opacity(
          opacity: onTap == null ? 0.65 : 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x472563EB), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                    leading,
                    SizedBox(width: center ? 10 : 14),
                    if (center) content else Expanded(child: content),
                    ?trailing,
                  ]),
                ),
              ),
            ),
          ),
        );

    final genderFilters = [
      ('all', t('home.filterAll'), LucideIcons.globe),
      ('male', t('home.filterMale'), LucideIcons.circleUser),
      ('female', t('home.filterFemale'), LucideIcons.usersRound),
    ];
    final gender = ref.watch(matchingProvider.select((s) => s.genderFilter));

    final randomBlock = Column(children: [
      startButton(
        onTap: _loading ? null : _startRandom,
        leading: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: Lottie.asset('assets/lottie/chat.json', width: 52, height: 52, frameRate: FrameRate.max, options: LottieOptions(enableMergePaths: true)),
        ),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t('home.startRandom'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 4),
          Text(t('matching.secureSearch'), style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5, fontWeight: FontWeight.w500)),
        ]),
        trailing: Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 22, color: Colors.white.withValues(alpha: 0.85)),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
        child: Row(children: [
          for (final (i, f) in genderFilters.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: () => _matching.setGenderFilter(f.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: gender == f.$1 ? c.bgCard : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: gender == f.$1 ? [BoxShadow(color: c.shadow, blurRadius: 6, offset: const Offset(0, 1))] : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(f.$3, size: 16, color: gender == f.$1 ? c.primary : c.textMuted),
                    const SizedBox(height: 4),
                    Text(f.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: gender == f.$1 ? c.primary : c.textMuted)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    ]);

    final fallbackBlock = Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Lottie.asset('assets/lottie/chat.json', width: 96, height: 64),
      ),
      const SizedBox(height: 8),
      Text(codeOn ? t('home.connectWithCodeTitle') : t('home.randomOffNoCodeTitle'),
          textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
      const SizedBox(height: 8),
      Text(codeOn ? t('home.connectWithCodeDesc') : t('home.randomOffNoCodeDesc'),
          textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.45)),
      const SizedBox(height: 16),
      startButton(
        center: true,
        onTap: () => context.go('/conversations'),
        leading: const Icon(LucideIcons.messageCircle, size: 22, color: Colors.white),
        content: Text(t('home.goToConversations'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    ]);

    final canConnect = _code.text.trim().isNotEmpty && !_loading;
    final codeBlock = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (randomOn)
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 14),
          child: Row(children: [
            Expanded(child: Container(height: 1, color: c.border)),
            const SizedBox(width: 10),
            Text(t('home.orConnectByCode'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textMuted)),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: c.border)),
          ]),
        ),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsetsDirectional.only(start: 14, end: 6),
        decoration: BoxDecoration(
          color: c.bgElevated,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: _codeFocus.hasFocus ? c.primary : c.border),
          boxShadow: _codeFocus.hasFocus ? [BoxShadow(color: c.primarySoft, spreadRadius: 3)] : null,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            Icon(LucideIcons.hash, size: 18, color: c.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _code,
                focusNode: _codeFocus,
                maxLength: 7,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_UpperCaseFormatter()],
                textInputAction: TextInputAction.go,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _connectByCode(),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.9, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: t('home.enterUserCode'),
                  hintStyle: TextStyle(color: c.textMuted, fontWeight: FontWeight.w500, letterSpacing: 0.6),
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Opacity(
              opacity: canConnect ? 1 : 0.4,
              child: Material(
                color: canConnect ? c.primary : c.bgCardHover,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: canConnect ? _connectByCode : null,
                  child: SizedBox(width: 42, height: 42, child: Icon(LucideIcons.phoneCall, size: 20, color: canConnect ? Colors.white : c.textMuted)),
                ),
              ),
            ),
          ]),
        ),
      ),
      if (_codeError.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0x14F44336), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(LucideIcons.circleAlert, size: 15, color: c.danger),
            const SizedBox(width: 8),
            Expanded(child: Text(_codeError, style: TextStyle(fontSize: 13, color: c.danger))),
          ]),
        ),
    ]);

    final hub = Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
          )
        else ...[
          if (randomOn) randomBlock else fallbackBlock,
          if (codeOn) codeBlock,
        ],
      ]),
    );

    void openFilm(ShortFilm f) {
      if (f.seriesId != null && f.seriesId!.isNotEmpty) {
        context.push('/short-films/watch?start=${f.id}&series=${f.seriesId}');
      } else {
        context.push('/short-films/watch?start=${f.id}');
      }
    }

    Widget sectionHeader(String title, {VoidCallback? onSeeAll}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary))),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                behavior: HitTestBehavior.opaque,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(t('shortFilms.seeAll'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.primary)),
                  const SizedBox(width: 2),
                  Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 16, color: c.primary),
                ]),
              ),
          ]),
        );

    Widget shortcutRow({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? accent,
    }) {
      final a = accent ?? c.primary;
      return Material(
        color: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: a.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: a),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textMuted)),
                ]),
              ),
              Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 18, color: c.textMuted),
            ]),
          ),
        ),
      );
    }

    final previewFilms = <ShortFilm>[
      if (filmsState != null) ...filmsState.visibleFeatured,
      if (filmsState != null) ...filmsState.gridFilms,
    ];
    final seenFilmIds = <String>{};
    final uniquePreview = <ShortFilm>[];
    for (final f in previewFilms) {
      if (seenFilmIds.add(f.id)) uniquePreview.add(f);
      if (uniquePreview.length >= 12) break;
    }
    final previewSeries = filmsState?.series.take(8).toList() ?? const <FilmSeries>[];

    final cardW = (MediaQuery.sizeOf(context).width * 0.30).clamp(104.0, 124.0);
    final cardH = cardW * 14 / 9;

    Widget filmsDiscover;
    if (!filmsOn) {
      filmsDiscover = const SizedBox.shrink();
    } else if (uniquePreview.isNotEmpty || previewSeries.isNotEmpty) {
      filmsDiscover = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sectionHeader(t('shortFilms.title'), onSeeAll: () => context.push('/short-films')),
        if (uniquePreview.isNotEmpty)
          SizedBox(
            height: cardH,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: uniquePreview.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: cardW,
                child: FilmCard(film: uniquePreview[i], onTap: () => openFilm(uniquePreview[i])),
              ),
            ),
          ),
        if (previewSeries.isNotEmpty) ...[
          const SizedBox(height: 18),
          sectionHeader(t('shortFilms.series'), onSeeAll: () => context.push('/short-films/catalog?kind=series')),
          SizedBox(
            height: cardH + 4,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: previewSeries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final s = previewSeries[i];
                return SizedBox(
                  width: cardW,
                  child: SeriesCard(series: s, onTap: () => context.push('/short-films/series/${s.id}')),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
      ]);
    } else {
      filmsDiscover = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/short-films'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0x338B5CF6), Color(0x00000000)],
                ),
              ),
              child: Row(children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(color: const Color(0x338B5CF6), borderRadius: BorderRadius.circular(18)),
                  alignment: Alignment.center,
                  child: Lottie.asset('assets/lottie/shortFilm.json', width: 40, height: 40),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('home.exploreFilms'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    const SizedBox(height: 4),
                    Text(t('home.exploreFilmsHint'), style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textMuted)),
                  ]),
                ),
                Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, color: c.textMuted),
              ]),
            ),
          ),
        ),
      );
    }

    final shortcuts = <Widget>[
      if (loaded && codeOn)
        shortcutRow(
          icon: LucideIcons.bookmarkPlus,
          title: t('home.savedCodes'),
          subtitle: t('home.savedCodesTileHint'),
          onTap: () => context.push('/saved-codes'),
        ),
      shortcutRow(
        icon: LucideIcons.messageCircle,
        title: t('home.goToConversations'),
        subtitle: t('home.openChatsHint'),
        onTap: () => context.go('/conversations'),
        accent: const Color(0xFF06B6D4),
      ),
    ];

    final bottomPad = tabScrollPadding(context, extra: 12);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Stack(children: [
        Column(children: [
          header,
          const AppUpdateBanner(),
          Expanded(
            child: RefreshIndicator(
              color: c.primary,
              onRefresh: () async {
                await _loadConversations();
                if (filmsOn) await ref.read(shortFilmsProvider.notifier).fetchAll(force: true);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: bottomPad),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  codeChip,
                  if (!compact) hub,
                  if (compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: hub,
                    ),
                  if (filmsOn) ...[
                    if (uniquePreview.isEmpty && previewSeries.isEmpty) sectionHeader(t('home.discoverSection')),
                    filmsDiscover,
                  ],
                  if (shortcuts.isNotEmpty) ...[
                    sectionHeader(t('home.quickActions')),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          for (var i = 0; i < shortcuts.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            shortcuts[i],
                          ],
                        ],
                      ),
                    ),
                  ],
                  const BannerStrip(placement: 'home'),
                  const AppFooter(),
                ]),
              ),
            ),
          ),
        ]),
        LoaderOverlay(show: _loading, text: _waitingForAccept ? t('home.waitingForAccept') : t('home.connecting')),
        if (_waitingForAccept)
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarClearance(context) + 16,
            child: Center(
              child: Material(
                color: const Color(0xB3000000),
                shape: const StadiumBorder(side: BorderSide(color: Color(0x33FFFFFF))),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _cancelConnectionRequest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.phoneOff, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(t('home.cancelRequest'), style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        if (auth.needsProfileContact && !_profileBannerDismissed)
          _HomeModal(
            icon: LucideIcons.globe,
            title: t('completeProfile.bannerTitle'),
            text: t('completeProfile.bannerText'),
            cancel: t('completeProfile.dismiss'),
            confirm: t('completeProfile.completeNow'),
            onDismiss: () => setState(() => _profileBannerDismissed = true),
            onConfirm: () {
              setState(() => _profileBannerDismissed = true);
              context.push('/complete-profile');
            },
          ),
        ValueListenableBuilder<bool>(
          valueListenable: PushService.promptNotifications,
          builder: (context, show, _) => !show
              ? const SizedBox.shrink()
              : _HomeModal(
                  icon: LucideIcons.bell,
                  title: t('home.enableNotifications'),
                  text: t('home.enableNotificationsText'),
                  cancel: t('home.later'),
                  confirm: _notifLoading ? t('home.enabling') : t('home.enableNow'),
                  busy: _notifLoading,
                  onDismiss: () => PushService.promptNotifications.value = false,
                  onConfirm: _enableNotifications,
                ),
        ),
      ]),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// `.logout-overlay` + `.logout-dialog` used for the profile-complete and notification prompts.
class _HomeModal extends StatelessWidget {
  const _HomeModal({
    required this.icon,
    required this.title,
    required this.text,
    required this.cancel,
    required this.confirm,
    required this.onDismiss,
    required this.onConfirm,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String text;
  final String cancel;
  final String confirm;
  final VoidCallback onDismiss;
  final VoidCallback onConfirm;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: GestureDetector(
        onTap: busy ? null : onDismiss,
        child: ColoredBox(
          color: const Color(0x80000000),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: c.border),
                  boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 48, color: c.primary),
                  const SizedBox(height: 8),
                  Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(height: 12),
                  Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextButton(
                          onPressed: busy ? null : onDismiss,
                          style: TextButton.styleFrom(
                            foregroundColor: c.textSecondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm), side: BorderSide(color: c.border)),
                          ),
                          child: Text(cancel, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: busy ? null : onConfirm,
                          style: FilledButton.styleFrom(
                            backgroundColor: c.primary,
                            disabledBackgroundColor: c.primary.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                          child: Text(confirm, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
