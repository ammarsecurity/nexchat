import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feature_flags.dart';
import '../core/i18n/i18n.dart';
import '../core/network/api_client.dart';
import '../core/network/hubs.dart';
import '../core/network/network_status.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_controller.dart';
import '../features/calls/call_state.dart';
import '../features/matching/matching_controller.dart';
import '../services/ring_sound.dart';
import '../services/update_check.dart';
import '../shared/no_connection_view.dart';
import '../shared/widgets.dart';
import 'global_listeners.dart';
import 'router.dart';
import 'update_required_modal.dart';

class NexChatApp extends ConsumerStatefulWidget {
  const NexChatApp({super.key});

  @override
  ConsumerState<NexChatApp> createState() => _NexChatAppState();
}

class _NexChatAppState extends ConsumerState<NexChatApp> with WidgetsBindingObserver {
  static const _updatePoll = Duration(seconds: 90);
  Timer? _updateTimer;
  UpdateInfo? _requiredUpdate;
  StreamSubscription<void>? _unauthorizedSub;
  bool _handlingUnauthorized = false;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runUpdateCheck();
    _updateTimer = Timer.periodic(_updatePoll, (_) => _runUpdateCheck());
    _unauthorizedSub = Api.unauthorized.stream.listen((_) => _handleUnauthorized());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    _unauthorizedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runUpdateCheck();
      if (ref.read(networkProvider)) unawaited(Hubs.resumeAll());
    }
  }

  Future<void> _runUpdateCheck() async {
    if (!_online) return;
    final info = await fetchUpdateInfo();
    if (!mounted) return;
    setState(() => _requiredUpdate = info != null && info.required ? info : null);
  }

  Future<void> _onCameOnline() async {
    await _runUpdateCheck();
    unawaited(ref.read(featureFlagsProvider.notifier).refresh());
    if (!ref.read(authProvider).isLoggedIn) return;
    unawaited(Hubs.resumeAll());
    unawaited(Hubs.conversation.start());
    unawaited(Hubs.story.start());
    final flags = ref.read(featureFlagsProvider).value;
    if (flags?.connectHub ?? false) unawaited(Hubs.matching.start());
  }

  void _onWentOffline() {
    unawaited(Hubs.pauseAll());
    ref.read(incomingConvCallProvider.notifier).clear();
    ref.read(matchingProvider.notifier)
      ..clearPendingRandomMatch()
      ..clearIncomingConnectionRequest();
    RingSound.stop();
  }

  Future<void> _retryConnection() async {
    final ok = await ref.read(networkProvider.notifier).recheck();
    if (ok) await _onCameOnline();
  }

  Future<void> _handleUnauthorized() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      await ref.read(authProvider.notifier).logout();
      ref.read(routerProvider).go('/login');
    } finally {
      _handlingUnauthorized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final light = ref.watch(lightThemeProvider);
    final router = ref.watch(routerProvider);
    final rtl = locale.languageCode == 'ar';
    final loggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));

    ref.listen(networkProvider, (prev, next) {
      _online = next;
      if (prev == false && next) unawaited(_onCameOnline());
      if (prev == true && next == false) _onWentOffline();
    });
    _online = ref.watch(networkProvider);

    SystemChrome.setSystemUIOverlayStyle(light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light);

    return MaterialApp.router(
      title: 'NexChat',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(light: light),
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: GlobalListeners(
          child: Stack(
            children: [
              if (!_online && !loggedIn)
                Positioned.fill(child: NoConnectionView(onRetry: _retryConnection))
              else ...[
                Padding(
                  padding: EdgeInsets.only(top: !_online ? MediaQuery.paddingOf(context).top + 52 : 0),
                  child: child ?? const SizedBox.shrink(),
                ),
                if (!_online) Positioned(top: 0, left: 0, right: 0, child: OfflineBanner(onRetry: _retryConnection)),
              ],
              if (_requiredUpdate != null) UpdateRequiredModal(downloadUrl: _requiredUpdate!.downloadUrl),
              const AppToastHost(),
              ValueListenableBuilder<bool>(
                valueListenable: Api.loadingOverlay,
                builder: (_, show, _) => LoaderOverlay(show: show, text: t('common.loading')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
