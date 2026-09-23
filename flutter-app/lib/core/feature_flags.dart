import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'network/network_status.dart';

/// Mirrors mobile-app/src/services/siteContentFlags.js + useConnectFeatures.js.
class FeatureFlags {
  const FeatureFlags({
    required this.randomChat,
    required this.codeConnect,
    required this.stories,
    required this.shortFilms,
  });

  final bool randomChat;
  final bool codeConnect;
  final bool stories;
  final bool shortFilms;

  bool get messagingOnly => !randomChat && !codeConnect;
  bool get connectHub => randomChat || codeConnect;
  String get defaultRoute => messagingOnly ? '/conversations' : '/home';

  static const hiddenUntilLoaded = FeatureFlags(randomChat: false, codeConnect: false, stories: false, shortFilms: false);

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags &&
      other.randomChat == randomChat &&
      other.codeConnect == codeConnect &&
      other.stories == stories &&
      other.shortFilms == shortFilms;

  @override
  int get hashCode => Object.hash(randomChat, codeConnect, stories, shortFilms);
}

bool _parseEnabled(Object? content) {
  final s = content?.toString().trim().toLowerCase() ?? '';
  if (s.isEmpty) return true;
  return s == 'true' || s == '1';
}

Future<({bool value, bool ok})> _fetchFlag(String key, {required bool onError}) async {
  try {
    final data = await Api.get('SiteContent/$key', skipUnauthorized: true);
    return (value: _parseEnabled(data is Map ? (data['content'] ?? data['Content']) : null), ok: true);
  } catch (_) {
    return (value: onError, ok: false);
  }
}

Future<Object?> fetchSiteContent(String key) async {
  try {
    final data = await Api.get('SiteContent/$key', skipUnauthorized: true);
    return data is Map ? (data['content'] ?? data['Content']) : null;
  } catch (_) {
    return null;
  }
}

class FeatureFlagsNotifier extends AsyncNotifier<FeatureFlags> {
  Timer? _retry;
  int _retryAttempt = 0;

  /// siteContentFlags.js caches only successful lookups; failed ones are fetched again.
  Future<FeatureFlags> _load() async {
    final r = await Future.wait([
      _fetchFlag('random_chat_enabled', onError: true),
      _fetchFlag('code_connect_features_enabled', onError: false),
      _fetchFlag('stories_enabled', onError: true),
      _fetchFlag('short_films_enabled', onError: true),
    ]);
    _retry?.cancel();
    if (r.any((x) => !x.ok)) {
      if (!NetworkStatus.online.value) {
        _retryAttempt = 0;
      } else {
        final delay = Duration(seconds: [5, 15, 30, 60][_retryAttempt.clamp(0, 3)]);
        _retryAttempt++;
        _retry = Timer(delay, refresh);
      }
    } else {
      _retryAttempt = 0;
    }
    return FeatureFlags(randomChat: r[0].value, codeConnect: r[1].value, stories: r[2].value, shortFilms: r[3].value);
  }

  @override
  Future<FeatureFlags> build() {
    ref.onDispose(() => _retry?.cancel());
    return _load();
  }

  Future<void> refresh() async {
    final next = await _load();
    if (state.value != next) state = AsyncData(next);
  }
}

final featureFlagsProvider = AsyncNotifierProvider<FeatureFlagsNotifier, FeatureFlags>(FeatureFlagsNotifier.new);

extension FeatureFlagsRef on Ref {
  Future<FeatureFlags> flags() => read(featureFlagsProvider.future);
}
