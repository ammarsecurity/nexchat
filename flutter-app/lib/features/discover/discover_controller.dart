import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';
import '../settings/birth_date_sheet.dart';

class DiscoverEligibility {
  const DiscoverEligibility({
    required this.canSwipe,
    required this.hasAvatar,
    required this.hasBirthDate,
    required this.ageOk,
    this.message = '',
  });

  final bool canSwipe;
  final bool hasAvatar;
  final bool hasBirthDate;
  final bool ageOk;
  final String message;

  factory DiscoverEligibility.fromJson(Map raw) {
    final j = Map<String, dynamic>.from(raw);
    return DiscoverEligibility(
      canSwipe: j.b('canSwipe'),
      hasAvatar: j.b('hasAvatar'),
      hasBirthDate: j.b('hasBirthDate'),
      ageOk: j.b('ageOk'),
      message: j.str('message'),
    );
  }

  static const unknown = DiscoverEligibility(
    canSwipe: false,
    hasAvatar: false,
    hasBirthDate: false,
    ageOk: false,
  );
}

class DiscoverPrefs {
  const DiscoverPrefs({
    this.preferGender = 'all',
    this.ageMin = 18,
    this.ageMax = 60,
  });

  final String preferGender;
  final int ageMin;
  final int ageMax;

  factory DiscoverPrefs.fromJson(Map? raw) {
    if (raw == null) return const DiscoverPrefs();
    final j = Map<String, dynamic>.from(raw);
    var min = j.i('ageMin');
    var max = j.i('ageMax');
    if (min < 18) min = 18;
    if (max < 18) max = 60;
    if (min > max) {
      final t = min;
      min = max;
      max = t;
    }
    final g = j.str('preferGender').toLowerCase();
    return DiscoverPrefs(
      preferGender: g == 'male' || g == 'female' ? g : 'all',
      ageMin: min.clamp(18, 60),
      ageMax: max.clamp(18, 60),
    );
  }

  DiscoverPrefs copyWith({String? preferGender, int? ageMin, int? ageMax}) => DiscoverPrefs(
        preferGender: preferGender ?? this.preferGender,
        ageMin: ageMin ?? this.ageMin,
        ageMax: ageMax ?? this.ageMax,
      );
}

class DiscoverState {
  const DiscoverState({
    this.deck = const [],
    this.loading = false,
    this.swiping = false,
    this.error = '',
    this.eligibility = DiscoverEligibility.unknown,
    this.eligibilityLoaded = false,
    this.prefs = const DiscoverPrefs(),
    this.canUndo = false,
    this.nextResetAt,
  });

  final List<Json> deck;
  final bool loading;
  final bool swiping;
  final String error;
  final DiscoverEligibility eligibility;
  final bool eligibilityLoaded;
  final DiscoverPrefs prefs;
  final bool canUndo;
  /// When deck is empty: UTC time when oldest non-match swipe leaves the 24h window.
  final DateTime? nextResetAt;

  Json? get top => deck.isEmpty ? null : deck.first;

  DiscoverState copyWith({
    List<Json>? deck,
    bool? loading,
    bool? swiping,
    String? error,
    DiscoverEligibility? eligibility,
    bool? eligibilityLoaded,
    DiscoverPrefs? prefs,
    bool? canUndo,
    DateTime? nextResetAt,
    bool clearNextResetAt = false,
  }) =>
      DiscoverState(
        deck: deck ?? this.deck,
        loading: loading ?? this.loading,
        swiping: swiping ?? this.swiping,
        error: error ?? this.error,
        eligibility: eligibility ?? this.eligibility,
        eligibilityLoaded: eligibilityLoaded ?? this.eligibilityLoaded,
        prefs: prefs ?? this.prefs,
        canUndo: canUndo ?? this.canUndo,
        nextResetAt: clearNextResetAt ? null : (nextResetAt ?? this.nextResetAt),
      );
}

class DiscoverController extends Notifier<DiscoverState> {
  @override
  DiscoverState build() {
    ref.listen(authProvider.select((s) => s.user?.id), (prev, next) {
      if (prev == next) return;
      state = const DiscoverState();
      if (next != null) Future.microtask(refresh);
    });
    return const DiscoverState();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: '');
    try {
      final eligRaw = await Api.get('/discover/eligibility');
      var eligibility = DiscoverEligibility.fromJson(eligRaw is Map ? eligRaw : {});

      DiscoverPrefs prefs = state.prefs;
      try {
        final me = await Api.get('/user/me');
        if (me is Map) {
          final m = Map<String, dynamic>.from(me);
          prefs = DiscoverPrefs.fromJson({
            'preferGender': m.s('discoverPreferGender') ?? m.s('DiscoverPreferGender') ?? 'all',
            'ageMin': m.v('discoverAgeMin') ?? m.v('DiscoverAgeMin') ?? 18,
            'ageMax': m.v('discoverAgeMax') ?? m.v('DiscoverAgeMax') ?? 60,
          });
          if (!eligibility.hasBirthDate || !eligibility.ageOk) {
            final bd = m.s('birthDate');
            if (isAdultBirthDate(bd)) {
              eligibility = DiscoverEligibility(
                canSwipe: eligibility.hasAvatar,
                hasAvatar: eligibility.hasAvatar,
                hasBirthDate: true,
                ageOk: true,
                message: eligibility.hasAvatar ? '' : eligibility.message,
              );
            }
          }
        }
      } catch (_) {}

      if (!eligibility.canSwipe) {
        state = state.copyWith(
          loading: false,
          deck: const [],
          eligibility: eligibility,
          eligibilityLoaded: true,
          prefs: prefs,
          canUndo: false,
        );
        return;
      }

      final feed = await Api.get('/discover/feed', query: {'limit': '20'});
      final items = asJsonList(feed is Map ? (feed['items'] ?? feed['Items']) : feed);
      if (feed is Map && feed['prefs'] is Map) {
        prefs = DiscoverPrefs.fromJson(Map<String, dynamic>.from(feed['prefs'] as Map));
      }
      DateTime? nextResetAt;
      if (feed is Map) {
        final raw = feed['nextResetAt'] ?? feed['NextResetAt'];
        if (raw != null) {
          nextResetAt = DateTime.tryParse(raw.toString())?.toUtc();
        }
      }
      state = state.copyWith(
        loading: false,
        deck: items,
        eligibility: eligibility,
        eligibilityLoaded: true,
        prefs: prefs,
        // Session-local: only enable after a successful new swipe this session.
        canUndo: false,
        error: '',
        nextResetAt: nextResetAt,
        clearNextResetAt: nextResetAt == null,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        eligibilityLoaded: true,
        canUndo: false,
        error: Api.errorMessage(e, 'error'),
      );
    }
  }

  Future<void> savePrefs(DiscoverPrefs prefs) async {
    await Api.put('/user/discover-prefs', {
      'preferGender': prefs.preferGender,
      'ageMin': prefs.ageMin,
      'ageMax': prefs.ageMax,
    });
    state = state.copyWith(prefs: prefs);
    await refresh();
  }

  Future<Json?> swipe({required bool like}) async {
    final card = state.top;
    if (card == null || state.swiping) return null;
    final id = card.str('id');
    if (id.isEmpty) return null;

    state = state.copyWith(swiping: true, error: '');
    try {
      final res = await Api.post('/discover/swipe', {
        'targetUserId': id,
        'direction': like ? 'like' : 'pass',
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final next = List<Json>.from(state.deck)..removeAt(0);
      // alreadySwiped means no new row was written — undo would revert a different swipe.
      final canUndo = !map.b('matched') && !map.b('alreadySwiped');
      state = state.copyWith(deck: next, swiping: false, canUndo: canUndo);
      if (next.length < 5) unawaitedLoadMore();
      return map.isEmpty ? null : map;
    } catch (e) {
      final msg = Api.errorMessage(e);
      state = state.copyWith(swiping: false, error: msg);
      if (msg.contains('PROFILE') || e.toString().contains('PROFILE_INCOMPLETE')) {
        await refresh();
      }
      rethrow;
    }
  }

  Future<Json?> undo() async {
    if (state.swiping || !state.canUndo) return null;
    state = state.copyWith(swiping: true, error: '');
    try {
      final res = await Api.post('/discover/undo', {});
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final card = map['card'] is Map ? Map<String, dynamic>.from(map['card'] as Map) : null;
      if (card != null) {
        final id = card.str('id');
        final deck = List<Json>.from(state.deck);
        deck.removeWhere((c) => c.str('id') == id);
        deck.insert(0, card);
        state = state.copyWith(deck: deck, swiping: false, canUndo: false);
      } else {
        state = state.copyWith(swiping: false, canUndo: false);
        await refresh();
      }
      return map;
    } catch (e) {
      state = state.copyWith(swiping: false, error: Api.errorMessage(e));
      rethrow;
    }
  }

  void unawaitedLoadMore() {
    () async {
      try {
        final feed = await Api.get('/discover/feed', query: {'limit': '15'});
        final items = asJsonList(feed is Map ? (feed['items'] ?? feed['Items']) : feed);
        if (items.isEmpty) return;
        final seen = state.deck.map((c) => c.str('id')).toSet();
        final extra = items.where((c) => !seen.contains(c.str('id'))).toList();
        if (extra.isEmpty) return;
        state = state.copyWith(deck: [...state.deck, ...extra]);
      } catch (_) {}
    }();
  }

  void removeTopLocally() {
    if (state.deck.isEmpty) return;
    state = state.copyWith(deck: List<Json>.from(state.deck)..removeAt(0), canUndo: false);
  }

  void markBirthDateComplete() {
    final e = state.eligibility;
    state = state.copyWith(
      eligibility: DiscoverEligibility(
        canSwipe: e.hasAvatar,
        hasAvatar: e.hasAvatar,
        hasBirthDate: true,
        ageOk: true,
        message: e.hasAvatar ? '' : e.message,
      ),
    );
  }
}

final discoverProvider = NotifierProvider<DiscoverController, DiscoverState>(DiscoverController.new);
