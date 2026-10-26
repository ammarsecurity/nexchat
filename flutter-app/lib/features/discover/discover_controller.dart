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

class DiscoverState {
  const DiscoverState({
    this.deck = const [],
    this.loading = false,
    this.swiping = false,
    this.error = '',
    this.eligibility = DiscoverEligibility.unknown,
    this.eligibilityLoaded = false,
  });

  final List<Json> deck;
  final bool loading;
  final bool swiping;
  final String error;
  final DiscoverEligibility eligibility;
  final bool eligibilityLoaded;

  Json? get top => deck.isEmpty ? null : deck.first;

  DiscoverState copyWith({
    List<Json>? deck,
    bool? loading,
    bool? swiping,
    String? error,
    DiscoverEligibility? eligibility,
    bool? eligibilityLoaded,
  }) =>
      DiscoverState(
        deck: deck ?? this.deck,
        loading: loading ?? this.loading,
        swiping: swiping ?? this.swiping,
        error: error ?? this.error,
        eligibility: eligibility ?? this.eligibility,
        eligibilityLoaded: eligibilityLoaded ?? this.eligibilityLoaded,
      );
}

class DiscoverController extends Notifier<DiscoverState> {
  @override
  DiscoverState build() {
    // Clear/refetch when auth account changes (avoid leaking A→B candidates).
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

      // Profile birth date: if already 18+, never ask again on Discover.
      if (!eligibility.hasBirthDate || !eligibility.ageOk) {
        try {
          final me = await Api.get('/user/me');
          if (me is Map) {
            final bd = Map<String, dynamic>.from(me).s('birthDate');
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
        } catch (_) {}
      }

      if (!eligibility.canSwipe) {
        state = state.copyWith(
          loading: false,
          deck: const [],
          eligibility: eligibility,
          eligibilityLoaded: true,
        );
        return;
      }

      final feed = await Api.get('/discover/feed', query: {'limit': '20'});
      final items = asJsonList(feed is Map ? (feed['items'] ?? feed['Items']) : feed);
      state = state.copyWith(
        loading: false,
        deck: items,
        eligibility: eligibility,
        eligibilityLoaded: true,
        error: '',
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        eligibilityLoaded: true,
        error: Api.errorMessage(e, 'error'),
      );
    }
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
      final next = List<Json>.from(state.deck)..removeAt(0);
      state = state.copyWith(deck: next, swiping: false);
      if (next.length < 5) unawaitedLoadMore();
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      final msg = Api.errorMessage(e);
      state = state.copyWith(swiping: false, error: msg);
      if (msg.contains('PROFILE') || e.toString().contains('PROFILE_INCOMPLETE')) {
        await refresh();
      }
      rethrow;
    }
  }

  void unawaitedLoadMore() {
    // Fire-and-forget top-up when the deck runs low.
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
    state = state.copyWith(deck: List<Json>.from(state.deck)..removeAt(0));
  }

  /// After birth-date sheet save — hide that step immediately, then refresh.
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
