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
    final unread = ref.watch(notificationsProvider).where((x) => x['isRead'] != true).length;
    final compact = loaded && !randomOn && !codeOn;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final featured = user?.isFeatured ?? false;
    final uniqueCode = user?.uniqueCode;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 16, 8),
      child: Row(children: [
        Expanded(child: Text(t('nav.connect'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.textPrimary))),
        GlassIconButton(icon: LucideIcons.bell, color: c.textSecondary, badgeDot: unread > 0, onTap: () => context.push('/notifications')),
      ]),
    );

    final profile = user == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/profile/${user.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: auth.avatarColor,
                        border: Border.all(color: c.primaryMuted, width: 2),
                        boxShadow: featured ? const [BoxShadow(color: Color(0x66FF7300), spreadRadius: 2)] : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: isImageAvatar(auth.avatar)
                          ? UserAvatar(url: auth.avatar, name: user.name, size: 44)
                          : Text((auth.avatar?.isNotEmpty ?? false) ? auth.avatar! : (user.name.isEmpty ? '?' : user.name.characters.first.toUpperCase()),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    if (featured) const PositionedDirectional(top: -2, end: -2, child: Icon(LucideIcons.crown, size: 14, color: Color(0xFFFF7300))),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('home.greeting'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                      Text(user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    ]),
                  ),
                  if (uniqueCode != null && uniqueCode.isNotEmpty && codeOn) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: c.primarySoft,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _copyCode(uniqueCode),
                        child: Stack(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(LucideIcons.hash, size: 13, color: c.primary),
                                const SizedBox(width: 5),
                                Text(uniqueCode,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.66, color: c.primary)),
                                const SizedBox(width: 5),
                                Icon(LucideIcons.copy, size: 13, color: c.primary),
                              ]),
                            ),
                          ),
                          if (_copied)
                            Positioned.fill(
                              child: Container(
                                color: c.success,
                                alignment: Alignment.center,
                                child: Text(t('common.copiedShort'), style: const TextStyle(color: Colors.white, fontSize: 10)),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: c.bgElevated,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _shareInvite,
                        child: SizedBox(width: 36, height: 36, child: Icon(LucideIcons.share2, size: 16, color: c.primary)),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          );

    Widget startButton({required Widget leading, required Widget content, Widget? trailing, VoidCallback? onTap, bool center = false}) => Opacity(
          opacity: onTap == null ? 0.65 : 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x472563EB), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: Lottie.asset('assets/lottie/chat.json', width: 52, height: 52, frameRate: FrameRate.max, options: LottieOptions(enableMergePaths: true)),
        ),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t('home.startRandom'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
          const SizedBox(height: 2),
          Text(t('matching.secureSearch'), style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
        trailing: Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 22, color: Colors.white.withValues(alpha: 0.85)),
      ),
      const SizedBox(height: 14),
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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

    final narrow = MediaQuery.sizeOf(context).width <= 360;
    Widget shortcut({required Widget icon, required String label, required String to}) => Material(
          color: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(to),
            child: Container(
              constraints: BoxConstraints(minHeight: narrow ? 72 : 96),
              padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 10, vertical: 14),
              child: Flex(
                direction: narrow ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: narrow ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(14)),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: icon,
                  ),
                  SizedBox(width: narrow ? 12 : 0, height: narrow ? 0 : 8),
                  Text(label,
                      textAlign: narrow ? TextAlign.start : TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary, height: 1.3)),
                ],
              ),
            ),
          ),
        );
    final shortcuts = [
      if (loaded && filmsOn)
        shortcut(icon: Lottie.asset('assets/lottie/shortFilm.json', width: 32, height: 32), label: t('shortFilms.title'), to: '/short-films'),
      if (loaded && codeOn) shortcut(icon: Icon(LucideIcons.bookmarkPlus, size: 22, color: c.primary), label: t('home.savedCodes'), to: '/saved-codes'),
    ];

    final primary = Column(mainAxisSize: MainAxisSize.min, children: [
      hub,
      if (shortcuts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: narrow
              ? Column(children: [for (final (i, s) in shortcuts.indexed) Padding(padding: EdgeInsets.only(top: i > 0 ? 10 : 0), child: s)])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final (i, s) in shortcuts.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: s)],
                  if (shortcuts.length == 1) ...[const SizedBox(width: 10), const Expanded(child: SizedBox())],
                ]),
        ),
    ]);

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Stack(children: [
        Column(children: [
          header,
          const AppUpdateBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(children: [profile, if (!compact) primary]),
                    if (compact) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: primary),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Column(children: [BannerStrip(placement: 'home'), AppFooter()]),
                    ),
                  ]),
                ),
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
