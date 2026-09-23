import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/json.dart';
import '../../core/network/hubs.dart';
import '../../services/ring_sound.dart';
import '../chat/chat_session.dart';

enum MatchStatus { idle, searching, matched }

class ConnectionRequest {
  const ConnectionRequest({required this.requesterId, required this.requesterName, this.requesterGender, this.requesterAvatar, this.requesterIsFeatured = false});
  final String requesterId;
  final String requesterName;
  final String? requesterGender;
  final String? requesterAvatar;
  final bool requesterIsFeatured;

  ConnectionRequest withAvatar(String? avatar) => ConnectionRequest(
        requesterId: requesterId,
        requesterName: requesterName,
        requesterGender: requesterGender,
        requesterAvatar: avatar,
        requesterIsFeatured: requesterIsFeatured,
      );
}

class PendingRandomMatch {
  const PendingRandomMatch({required this.sessionId, this.partner});
  final String sessionId;
  final Json? partner;
}

class MatchingState {
  const MatchingState({
    this.status = MatchStatus.idle,
    this.genderFilter = 'all',
    this.incomingConnectionRequest,
    this.pendingRandomMatch,
  });
  final MatchStatus status;
  final String genderFilter;
  final ConnectionRequest? incomingConnectionRequest;
  final PendingRandomMatch? pendingRandomMatch;

  MatchingState copyWith({
    MatchStatus? status,
    String? genderFilter,
    ConnectionRequest? Function()? incoming,
    PendingRandomMatch? Function()? pending,
  }) =>
      MatchingState(
        status: status ?? this.status,
        genderFilter: genderFilter ?? this.genderFilter,
        incomingConnectionRequest: incoming != null ? incoming() : incomingConnectionRequest,
        pendingRandomMatch: pending != null ? pending() : pendingRandomMatch,
      );
}

/// stores/matching.js
class MatchingController extends Notifier<MatchingState> {
  bool _resumeSearchAfterNav = false;
  bool _skipNextMatchingUnmountCancel = false;
  bool _skipRestartAfterNextRandomDecline = false;

  @override
  MatchingState build() => const MatchingState();

  MatchingState get current => state;

  void setSearching() => state = state.copyWith(status: MatchStatus.searching);
  void setMatched() => state = state.copyWith(status: MatchStatus.matched);
  void setIdle() => state = state.copyWith(status: MatchStatus.idle);
  void setGenderFilter(String v) => state = state.copyWith(genderFilter: v);

  void setIncomingConnectionRequest(ConnectionRequest r) => state = state.copyWith(incoming: () => r);
  void clearIncomingConnectionRequest() => state = state.copyWith(incoming: () => null);

  void setResumeSearchAfterNav(bool v) => _resumeSearchAfterNav = v;
  bool consumeResumeSearchAfterNav() {
    final v = _resumeSearchAfterNav;
    _resumeSearchAfterNav = false;
    return v;
  }

  void armSkipNextMatchingUnmountCancel() => _skipNextMatchingUnmountCancel = true;
  bool consumeSkipNextMatchingUnmountCancel() {
    final v = _skipNextMatchingUnmountCancel;
    _skipNextMatchingUnmountCancel = false;
    return v;
  }

  void setPendingRandomMatch(PendingRandomMatch p) => state = state.copyWith(pending: () => p);
  void clearPendingRandomMatch() => state = state.copyWith(pending: () => null);

  void armSkipRestartAfterRandomDecline() => _skipRestartAfterNextRandomDecline = true;
  bool consumeSkipRestartAfterRandomDecline() {
    final v = _skipRestartAfterNextRandomDecline;
    _skipRestartAfterNextRandomDecline = false;
    return v;
  }

  void patchIncomingRequesterAvatar(String userId, String? avatar) {
    final req = state.incomingConnectionRequest;
    if (req == null || req.requesterId != userId) return;
    state = state.copyWith(incoming: () => req.withAvatar(avatar));
  }

  void patchPendingRandomPartnerAvatar(String userId, String? avatar, String? uniqueCode) {
    final pm = state.pendingRandomMatch;
    final p = pm?.partner;
    if (pm == null || p == null) return;
    final pid = p.s('id') ?? p.s('userId') ?? '';
    final uc = uniqueCode ?? '';
    if (userId == pid || (uc.isNotEmpty && p.s('uniqueCode') == uc)) {
      state = state.copyWith(pending: () => PendingRandomMatch(sessionId: pm.sessionId, partner: {...p, 'avatar': avatar}));
    }
  }

  void reset() {
    _resumeSearchAfterNav = false;
    _skipNextMatchingUnmountCancel = false;
    _skipRestartAfterNextRandomDecline = false;
    state = const MatchingState();
  }
}

final matchingProvider = NotifierProvider<MatchingController, MatchingState>(MatchingController.new);

Json? _firstMap(List<Object?> a) => a.isNotEmpty && a[0] is Map ? Json.from(a[0] as Map) : null;

/// App.vue restartRandomSearch()
Future<void> restartRandomSearch(WidgetRef ref) async {
  final m = ref.read(matchingProvider.notifier)..setSearching();
  try {
    await Hubs.matching.ensureConnected();
    await Hubs.matching.invoke('StartSearching', [m.current.genderFilter]);
  } catch (_) {}
}

/// App.vue setupMatchingHubListeners() — returns disposers.
List<void Function()> bindMatchingHub(WidgetRef ref) {
  final h = Hubs.matching;
  MatchingController m() => ref.read(matchingProvider.notifier);
  void openChat(String sessionId, Json? partner) {
    m().armSkipNextMatchingUnmountCancel();
    ref.read(chatSessionProvider.notifier).setSession(sessionId, partner);
    m().setMatched();
    ref.read(routerProvider).push('/chat/$sessionId');
  }

  return [
    h.on('IncomingConnectionRequest', (a) {
      final d = _firstMap(a);
      if (d == null) return;
      m().setIncomingConnectionRequest(ConnectionRequest(
        requesterId: d.str('requesterId'),
        requesterName: d.str('requesterName'),
        requesterGender: d.s('requesterGender'),
        requesterAvatar: d.s('requesterAvatar'),
        requesterIsFeatured: d.b('requesterIsFeatured'),
      ));
      RingSound.start();
    }),
    h.on('ConnectionRequestExpired', (_) {
      RingSound.stop();
      m().clearIncomingConnectionRequest();
    }),
    h.on('MatchFound', (a) {
      final d = _firstMap(a);
      if (d == null) return;
      final sessionId = d.str('sessionId');
      final partner = d.v('partner') is Map ? Json.from(d.v('partner') as Map) : null;
      if (d.b('requiresPairingAccept')) {
        m().setPendingRandomMatch(PendingRandomMatch(sessionId: sessionId, partner: partner));
        return;
      }
      openChat(sessionId, partner);
    }),
    h.on('RandomMatchReady', (a) {
      final d = _firstMap(a);
      if (d == null) return;
      m().clearPendingRandomMatch();
      openChat(d.str('sessionId'), d.v('partner') is Map ? Json.from(d.v('partner') as Map) : null);
    }),
    h.on('RandomMatchPartnerDeclined', (_) {
      m().clearPendingRandomMatch();
      restartRandomSearch(ref);
    }),
    h.on('RandomMatchDeclined', (_) async {
      m().clearPendingRandomMatch();
      if (m().consumeSkipRestartAfterRandomDecline()) {
        m().setIdle();
        final flags = await ref.read(featureFlagsProvider.future);
        ref.read(routerProvider).push(flags.defaultRoute);
        return;
      }
      restartRandomSearch(ref);
    }),
  ];
}
