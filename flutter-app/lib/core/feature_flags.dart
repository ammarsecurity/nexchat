import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'network/network_status.dart';
import 'storage/prefs.dart';

/// Mirrors mobile-app/src/services/siteContentFlags.js + useConnectFeatures.js.
/// Admin-gated features stay hidden until a successful fetch (or last cached admin value).
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

  /// Fail-closed: discover / connect / random stay hidden until admin enables them.
  static const hiddenUntilLoaded = FeatureFlags(
    randomChat: false,
    codeConnect: false,
    stories: false,
    shortFilms: false,
  );

  Map<String, bool> toJson() => {
        'randomChat': randomChat,
        'codeConnect': codeConnect,
        'stories': stories,
        'shortFilms': shortFilms,
      };

  factory FeatureFlags.fromJson(Map<String, dynamic> j) => FeatureFlags(
        randomChat: j['randomChat'] == true,
        codeConnect: j['codeConnect'] == true,
        stories: j['stories'] == true,
        shortFilms: j['shortFilms'] == true,
      );

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

const _flagsCacheKey = 'nexchat_feature_flags_v2';

/// Admin-gated flags: empty/missing → off. Stories has no admin toggle → empty means on.
bool _parseEnabled(Object? content, {required bool emptyMeansEnabled}) {
  final s = content?.toString().trim().toLowerCase() ?? '';
  if (s.isEmpty) return emptyMeansEnabled;
  return s == 'true' || s == '1';
}

Future<({bool value, bool ok})> _fetchFlag(String key, {required bool emptyMeansEnabled}) async {
  try {
    final data = await Api.get('SiteContent/$key', skipUnauthorized: true);
    final raw = data is Map ? (data['content'] ?? data['Content']) : null;
    return (value: _parseEnabled(raw, emptyMeansEnabled: emptyMeansEnabled), ok: true);
  } catch (_) {
    return (value: false, ok: false);
  }
}

FeatureFlags? _readCachedFlags() {
  try {
    final raw = Prefs.instance.getString(_flagsCacheKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return FeatureFlags.fromJson(Map<String, dynamic>.from(decoded));
  } catch (_) {
    return null;
  }
}

void _writeCachedFlags(FeatureFlags flags) {
  Prefs.instance.setString(_flagsCacheKey, jsonEncode(flags.toJson()));
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

  /// Prefer last successful admin snapshot when offline / fetch fails — never fail-open
  /// for connect/discover. Stories default on (no admin toggle; empty SiteContent = enabled).
  Future<FeatureFlags> _load() async {
    final cached = _readCachedFlags() ?? FeatureFlags.hiddenUntilLoaded;
    final r = await Future.wait([
      _fetchFlag('random_chat_enabled', emptyMeansEnabled: false),
      _fetchFlag('code_connect_features_enabled', emptyMeansEnabled: false),
      _fetchFlag('stories_enabled', emptyMeansEnabled: true),
      _fetchFlag('short_films_enabled', emptyMeansEnabled: false),
    ]);

    final next = FeatureFlags(
      randomChat: r[0].ok ? r[0].value : cached.randomChat,
      codeConnect: r[1].ok ? r[1].value : cached.codeConnect,
      // No cache yet + offline → still show stories (product default).
      stories: r[2].ok ? r[2].value : (cached == FeatureFlags.hiddenUntilLoaded ? true : cached.stories),
      shortFilms: r[3].ok ? r[3].value : cached.shortFilms,
    );

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
      _writeCachedFlags(next);
    }

    // Persist partial success so offline later keeps what we know.
    if (r.any((x) => x.ok) && r.any((x) => !x.ok)) {
      _writeCachedFlags(next);
    }

    return next;
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
