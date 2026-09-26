import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/feature_flags.dart';
import '../core/share_links.dart';
import '../core/storage/prefs.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/complete_profile_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/calls/calls_screen.dart';
import '../features/calls/video_call_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/conversations/conversation_chat_screen.dart';
import '../features/conversations/conversation_options_screen.dart';
import '../features/conversations/conversations_screen.dart';
import '../features/conversations/share_message_screen.dart';
import '../features/groups/create_group_screen.dart';
import '../features/groups/group_info_screen.dart';
import '../features/matching/connection_history_screen.dart';
import '../features/matching/home_screen.dart';
import '../features/matching/invite_join_screen.dart';
import '../features/matching/matching_screen.dart';
import '../features/matching/saved_codes_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/settings/blocked_screen.dart';
import '../features/settings/legal_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/short_films/short_film_series_detail_screen.dart';
import '../features/short_films/short_films_feed_screen.dart';
import '../features/short_films/short_films_hub_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/stories/story_create_screen.dart';
import '../features/stories/story_viewer_screen.dart';
import 'app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

enum _Requires { none, codeConnect, randomChat, stories, shortFilms }

class _Meta {
  const _Meta({this.public = false, this.requires = _Requires.none});
  final bool public;
  final _Requires requires;
}

final Map<RegExp, _Meta> _meta = {
  RegExp(r'^/$'): const _Meta(public: true),
  RegExp(r'^/onboarding$'): const _Meta(public: true),
  RegExp(r'^/login$'): const _Meta(public: true),
  RegExp(r'^/register$'): const _Meta(public: true),
  RegExp(r'^/forgot-password$'): const _Meta(public: true),
  RegExp(r'^/privacy$'): const _Meta(public: true),
  RegExp(r'^/terms$'): const _Meta(public: true),
  RegExp(r'^/join/'): const _Meta(public: true, requires: _Requires.codeConnect),
  RegExp(r'^/saved-codes$'): const _Meta(requires: _Requires.codeConnect),
  RegExp(r'^/connection-history$'): const _Meta(requires: _Requires.codeConnect),
  RegExp(r'^/matching$'): const _Meta(requires: _Requires.randomChat),
  RegExp(r'^/chat/'): const _Meta(requires: _Requires.randomChat),
  RegExp(r'^/stories/'): const _Meta(requires: _Requires.stories),
  RegExp(r'^/short-films'): const _Meta(requires: _Requires.shortFilms),
};

_Meta _metaFor(String path) {
  for (final e in _meta.entries) {
    if (e.key.hasMatch(path)) return e.value;
  }
  return const _Meta();
}

/// Paths that show the bottom tab bar (useAppNav.js tabBarPaths).
bool isTabRoot(String path, FeatureFlags flags) {
  if (path == '/conversations' || path == '/settings') return true;
  if (path == '/home') return !flags.messagingOnly;
  if (path == '/short-films') return flags.shortFilms;
  return false;
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider.select((s) => (s.isLoggedIn, s.needsProfileContactRedirect)), (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  Future<String?> guard(BuildContext context, GoRouterState state) async {
    final auth = ref.read(authProvider);
    final path = state.uri.path;
    final meta = _metaFor(path);

    if (!meta.public && !auth.isLoggedIn) return '/login';
    if (auth.isLoggedIn && auth.needsProfileContactRedirect && path != '/complete-profile') return '/complete-profile';

    if (meta.requires == _Requires.none && path != '/home') return null;
    final flags = await ref.read(featureFlagsProvider.future);

    switch (meta.requires) {
      case _Requires.codeConnect:
        if (!flags.codeConnect) return auth.isLoggedIn ? flags.defaultRoute : '/login';
      case _Requires.randomChat:
        final supportChat = path.startsWith('/chat/') && state.uri.queryParameters['support'] == '1';
        if (auth.isLoggedIn && !flags.randomChat && !supportChat) return flags.defaultRoute;
      case _Requires.stories:
        if (auth.isLoggedIn && !flags.stories) return '/conversations';
      case _Requires.shortFilms:
        if (auth.isLoggedIn && !flags.shortFilms) return flags.defaultRoute;
      case _Requires.none:
        break;
    }
    if (auth.isLoggedIn && path == '/home' && flags.messagingOnly) return '/conversations';
    return null;
  }

  GoRoute page(String path, Widget Function(GoRouterState s) build, {bool swipeBack = true}) => GoRoute(
        path: path,
        pageBuilder: (context, s) => swipeBack && defaultTargetPlatform == TargetPlatform.iOS
            ? CupertinoPage<void>(key: s.pageKey, child: build(s))
            : _fade(s, build(s)),
      );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: guard,
    routes: [
      page('/', (_) => const SplashScreen(), swipeBack: false),
      page('/onboarding', (_) => const OnboardingScreen(), swipeBack: false),
      page('/login', (s) => LoginScreen(invite: s.uri.queryParameters['invite']), swipeBack: false),
      page('/register', (s) => RegisterScreen(invite: s.uri.queryParameters['invite']), swipeBack: false),
      page('/forgot-password', (_) => const ForgotPasswordScreen(), swipeBack: false),
      page('/complete-profile', (s) => CompleteProfileScreen(fromSettings: s.uri.queryParameters['from'] == 'settings'),
          swipeBack: false),
      GoRoute(path: '/match', redirect: (_, _) => '/matching'),
      GoRoute(
        path: '/message-requests',
        redirect: (_, s) {
          final notice = s.uri.queryParameters['notice'];
          return Uri(path: '/conversations', queryParameters: {'tab': 'requests', 'notice': ?notice}).toString();
        },
      ),
      GoRoute(path: '/contacts', redirect: (_, _) => '/conversations?tab=contacts'),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          page('/home', (s) => TabRootGuard(child: HomeScreen(invite: s.uri.queryParameters['invite'])), swipeBack: false),
          page(
            '/conversations',
            (s) => TabRootGuard(
              child: ConversationsScreen(
                tab: s.uri.queryParameters['tab'],
                notice: s.uri.queryParameters['notice'],
                openId: s.uri.queryParameters['open'],
              ),
            ),
            swipeBack: false,
          ),
          page('/short-films', (_) => const TabRootGuard(child: ShortFilmsHubScreen()), swipeBack: false),
          page('/settings', (_) => const TabRootGuard(child: SettingsScreen()), swipeBack: false),
        ],
      ),
      page('/join/:code', (s) => InviteJoinScreen(code: s.pathParameters['code']!)),
      page('/saved-codes', (_) => const SavedCodesScreen()),
      page('/connection-history', (_) => const ConnectionHistoryScreen()),
      page('/blocked', (_) => const BlockedScreen()),
      page('/calls', (_) => const CallsScreen()),
      page('/matching', (_) => const MatchingScreen(), swipeBack: false),
      page('/chat/:sessionId', (s) {
        final e = s.extra is Map ? s.extra as Map : const {};
        final q = s.uri.queryParameters['incomingVideoCall'];
        return ChatScreen(
          sessionId: s.pathParameters['sessionId']!,
          initialPartner: e['partner'] is Map ? Map<String, dynamic>.from(e['partner'] as Map) : null,
          incomingVideoCall: q == '1' || q == 'true',
          autoAcceptCall: s.uri.queryParameters['autoAccept'] == '1',
          supportChat: s.uri.queryParameters['support'] == '1',
        );
      }),
      GoRoute(
        path: '/video/:sessionId',
        pageBuilder: (context, s) {
          final e = s.extra is Map ? s.extra as Map : const {};
          return NoTransitionPage<void>(
            key: s.pageKey,
            name: s.name,
            child: VideoCallScreen(
              sessionId: s.pathParameters['sessionId']!,
              voiceOnly: e['voiceOnly'] == true || s.uri.queryParameters['voice'] == '1',
              fromConversation: e['fromConversation'] == true || s.uri.queryParameters['conv'] == '1',
            ),
          );
        },
      ),
      page('/stories/create', (_) => const StoryCreateScreen()),
      page(
        '/stories/view/:userId',
        (s) => StoryViewerScreen(
          userId: s.pathParameters['userId']!,
          slideId: s.uri.queryParameters['slideId'],
          from: s.uri.queryParameters['from'],
        ),
      ),
      page('/short-films/watch', (s) => ShortFilmsFeedScreen(
            startId: s.uri.queryParameters['start'],
            seriesId: s.uri.queryParameters['series'],
          )),
      page('/short-films/series/:id', (s) => ShortFilmSeriesDetailScreen(seriesId: s.pathParameters['id']!)),
      page('/conversations/create-group', (_) => const CreateGroupScreen()),
      page('/conversation/:conversationId/group-info', (s) => GroupInfoScreen(conversationId: s.pathParameters['conversationId']!)),
      page('/conversations/:conversationId/options', (s) => ConversationOptionsScreen(conversationId: s.pathParameters['conversationId']!)),
      page('/conversation/:conversationId', (s) => ConversationChatScreen(conversationId: s.pathParameters['conversationId']!)),
      page('/profile/:userId', (s) => UserProfileScreen(userId: s.pathParameters['userId']!, conversationId: (s.extra as Map?)?['conversationId'] as String?)),
      page('/share-message', (s) {
        final e = s.extra is Map ? s.extra as Map : const {};
        return ShareMessageScreen(
          shareMessage: e['shareMessage'] is Map ? Map<String, dynamic>.from(e['shareMessage'] as Map) : null,
          sourceConversationId: e['sourceConversationId']?.toString(),
          returnPath: e['returnPath']?.toString(),
        );
      }),
      page('/notifications', (_) => const NotificationsScreen()),
      page('/privacy', (_) => const LegalScreen.privacy()),
      page('/terms', (_) => const LegalScreen.terms()),
    ],
  );
});

/// Same feel as the Vue `page` transition (short fade + slight slide).
CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );

/// navigateAfterAuth() from utils/appRouting.js.
Future<void> navigateAfterAuth(BuildContext context, WidgetRef ref, {String? invite, bool needsProfile = false}) async {
  final router = GoRouter.of(context);
  if (needsProfile) {
    router.go('/complete-profile');
    return;
  }
  final flags = await ref.read(featureFlagsProvider.future);
  final code = normalizeInviteCode(invite);
  if (code.isNotEmpty && flags.codeConnect) {
    router.go('/home?invite=${Uri.encodeQueryComponent(code)}');
    return;
  }
  await Prefs.instance.setString(Keys.pendingInvite, null);
  router.go(flags.defaultRoute);
}

/// navigateDefaultForSession() from utils/appRouting.js.
Future<void> navigateDefaultForSession(GoRouter router, WidgetRef ref) async {
  if (!ref.read(authProvider).isLoggedIn) {
    router.go('/login');
    return;
  }
  final flags = await ref.read(featureFlagsProvider.future);
  router.go(flags.defaultRoute);
}
