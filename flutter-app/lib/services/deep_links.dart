import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart';
import '../core/feature_flags.dart';
import '../core/share_links.dart';
import '../features/auth/auth_controller.dart';

/// services/deepLinks.js — invite / story / short-film links opened from outside the app.
class DeepLinks {
  DeepLinks._();

  static StreamSubscription<Uri>? _sub;
  static String? _lastUrl;
  static DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> init(WidgetRef ref) async {
    if (_sub != null) return;
    final links = AppLinks();
    _sub = links.uriLinkStream.listen((u) => handleUrl(ref, u.toString()), onError: (_) {});
    try {
      final initial = await links.getInitialLink();
      if (initial != null) await handleUrl(ref, initial.toString());
    } catch (_) {}
  }

  static Future<bool> handleUrl(WidgetRef ref, String url) async {
    final now = DateTime.now();
    if (url == _lastUrl && now.difference(_lastAt) < const Duration(seconds: 3)) return false;
    _lastUrl = url;
    _lastAt = now;
    final target = parseShareTargetFromUrl(url);
    if (target == null) return false;
    await _waitForStartup(ref);
    return navigateFromShareTarget(ref, target);
  }

  /// Cold start: let the splash screen finish its own redirect first so it doesn't replace ours.
  static Future<void> _waitForStartup(WidgetRef ref) async {
    final router = ref.read(routerProvider);
    final started = DateTime.now();
    while (DateTime.now().difference(started) < const Duration(seconds: 10)) {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path.isNotEmpty && path != '/') return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<bool> navigateFromShareTarget(WidgetRef ref, ShareTarget target) async {
    final router = ref.read(routerProvider);
    switch (target) {
      case InviteTarget(:final code):
        final flags = await ref.read(featureFlagsProvider.future);
        if (!flags.codeConnect) return false;
        if (ref.read(authProvider).isLoggedIn) {
          router.go('/home?invite=${Uri.encodeQueryComponent(code)}');
        } else {
          router.push('/join/${Uri.encodeComponent(code)}');
        }
        return true;
      case ShortFilmTarget(:final filmId):
        router.push('/short-films/watch?start=$filmId');
        return true;
      case StoryTarget(:final userId):
        router.push('/stories/view/$userId');
        return true;
    }
  }
}
