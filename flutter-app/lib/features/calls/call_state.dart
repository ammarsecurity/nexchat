import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import 'call_identity.dart';
export 'call_identity.dart';
import '../../services/call_native.dart';

const kIncomingCallRingTimeout = Duration(seconds: 60);
const kCallPeerWaitTimeout = Duration(seconds: 45);

/// Callbacks wired by VideoCallScreen (or the minimized bar) — services/livekit.js `handlers`.
class LiveKitHandlers {
  void Function(Track track)? onRemoteTrack;
  void Function()? onDisconnected;
  void Function()? onParticipantLeft;
  void Function(LocalTrack track)? onLocalTrack;
  void Function(Object error)? onMediaError;
  void Function(bool reconnecting)? onReconnecting;
  void Function()? onTracksChanged;
}

/// services/livekit.js — one room shared between the full call screen and the floating bar.
class LiveKitService {
  LiveKitService._();
  static final instance = LiveKitService._();

  Room? room;
  String? _lastSessionId;
  String? _callId;
  Timer? _heartbeat;
  EventsListener<RoomEvent>? _listener;
  int _generation = 0;
  Completer<bool?>? _joinWait;
  String? _joinWaitSid;
  final handlers = LiveKitHandlers();

  /// Returns true when an already-connected room for the same session was reused, null when a [leave]
  /// cancelled the join (the half-connected room is discarded).
  int get generation => _generation;
  String? get sessionId => _lastSessionId;
  String? get callId => _callId;
  bool ownsCall(String roomId, String? attempt) =>
      sameCall(_lastSessionId, _callId, roomId, attempt);

  Future<void> leaveCall(String roomId, String? attempt) async {
    if (ownsCall(roomId, attempt)) await leave();
  }

  bool isInSession(String sessionId) =>
      room != null &&
      _lastSessionId == sessionId &&
      room!.connectionState != ConnectionState.disconnected;

  Future<bool?> join(
    String sessionId, {
    required String callId,
    required bool isConversation,
    required bool voiceOnly,
    String partnerName = '',
  }) async {
    final r = room;
    if (r != null &&
        r.connectionState == ConnectionState.connected &&
        _lastSessionId == sessionId &&
        _callId == callId) {
      return true;
    }
    final pending = _joinWait;
    if (pending != null && _joinWaitSid == sessionId && _callId == callId) {
      return pending.future;
    }
    final savedDc = handlers.onDisconnected;
    handlers.onDisconnected = null;
    final cleanup = leave();
    final gen = _generation;
    final wait = Completer<bool?>();
    // Publish ownership before cleanup yields, so an End can cancel even this phase.
    _lastSessionId = sessionId;
    _callId = callId;
    _joinWait = wait;
    _joinWaitSid = sessionId;
    try {
      await cleanup;
      if (gen != _generation) {
        _finishJoin(wait, null);
        return null;
      }
      handlers.onDisconnected = savedDc;
      _cameraPosition = CameraPosition.front;
      final data = await Api.post('livekit/token', {
        'roomName': sessionId,
        'callId': callId,
      }) as Map;
      if (gen != _generation) {
        _finishJoin(wait, null);
        return null;
      }
      final newRoom = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      room = newRoom;
      final l = newRoom.createListener();
      _listener = l;
      l
        ..on<TrackSubscribedEvent>((e) => handlers.onRemoteTrack?.call(e.track))
        ..on<TrackUnsubscribedEvent>((_) => handlers.onTracksChanged?.call())
        ..on<TrackMutedEvent>((_) => handlers.onTracksChanged?.call())
        ..on<TrackUnmutedEvent>((_) => handlers.onTracksChanged?.call())
        ..on<LocalTrackPublishedEvent>((e) {
          final track = e.publication.track;
          if (track is LocalVideoTrack) handlers.onLocalTrack?.call(track);
        })
        ..on<RoomReconnectingEvent>((_) => handlers.onReconnecting?.call(true))
        ..on<RoomReconnectedEvent>((_) => handlers.onReconnecting?.call(false))
        ..on<ParticipantDisconnectedEvent>(
          (_) => handlers.onParticipantLeft?.call(),
        )
        ..on<RoomDisconnectedEvent>((_) => handlers.onDisconnected?.call());

      Future<bool> cancelled() async {
        if (gen == _generation) return false;
        await _discard(newRoom, l);
        return true;
      }

      try {
        await newRoom.connect(data.str('url'), data.str('token'));
      } catch (e) {
        if (await cancelled()) {
          _finishJoin(wait, null);
          return null;
        }
        _finishJoin(wait, null);
        rethrow;
      }
      if (await cancelled()) {
        _finishJoin(wait, null);
        return null;
      }
      // CallNative.start is owned by VideoCallScreen after the first paint — starting FGS mid-join
      // raced the route transition and left a black window with live mic.
      final lp = newRoom.localParticipant;
      try {
        await lp?.setMicrophoneEnabled(true);
        if (await cancelled()) {
          _finishJoin(wait, null);
          return null;
        }
        if (!voiceOnly) await lp?.setCameraEnabled(true);
      } catch (e) {
        if (gen == _generation) handlers.onMediaError?.call(e);
      }
      if (await cancelled()) {
        _finishJoin(wait, null);
        return null;
      }
      _heartbeat?.cancel();
      Future<void> renew() async {
        if (!ownsCall(sessionId, callId)) return;
        final hub = isConversation ? Hubs.conversation : Hubs.chat;
        try {
          await hub.ensureConnected();
          final alive = await hub.invoke('HeartbeatVideoCall', [
            sessionId,
            callId,
          ]);
          if (alive == false && ownsCall(sessionId, callId)) {
            final ended = handlers.onDisconnected;
            unawaited(leave());
            ended?.call();
          }
        } catch (_) {
          /* Transport loss uses the server's lease grace period. */
        }
      }

      unawaited(renew());
      _heartbeat = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(renew()),
      );
      _finishJoin(wait, false);
      return false;
    } catch (e) {
      _finishJoin(wait, null);
      rethrow;
    }
  }

  void _finishJoin(Completer<bool?> wait, bool? value) {
    if (!wait.isCompleted) wait.complete(value);
    if (_joinWait == wait) {
      _joinWait = null;
      _joinWaitSid = null;
    }
  }

  Future<void> _discard(Room r, EventsListener<RoomEvent> l) async {
    try {
      await l.dispose();
    } catch (_) {}
    try {
      await r.disconnect();
      await r.dispose();
    } catch (_) {}
  }

  Future<void> leave() async {
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    final endingCallId = _callId;
    if (endingCallId != null) unawaited(CallNative.stop(callId: endingCallId));
    final wait = _joinWait;
    _joinWait = null;
    _joinWaitSid = null;
    if (wait != null && !wait.isCompleted) wait.complete(null);
    final r = room;
    room = null;
    _lastSessionId = null;
    _callId = null;
    final listener = _listener;
    _listener = null;
    try {
      await listener?.dispose();
    } catch (_) {}
    if (r != null) {
      try {
        await r.disconnect();
        await r.dispose();
      } catch (_) {}
      try {
        await AudioManager.instance.setSpeakerOutputPreferred(false);
      } catch (_) {}
    }
  }

  VideoTrack? get remoteVideo {
    for (final p
        in room?.remoteParticipants.values ?? const <RemoteParticipant>[]) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t != null && !pub.muted) return t;
      }
    }
    return null;
  }

  CameraPosition _cameraPosition = CameraPosition.front;
  CameraPosition get cameraPosition => _cameraPosition;

  Future<void> flipCamera() async {
    final track = localVideo;
    if (track is! LocalVideoTrack) return;
    final next = _cameraPosition.switched();
    await track.setCameraPosition(next);
    _cameraPosition = next;
  }

  VideoTrack? get localVideo {
    for (final pub
        in room?.localParticipant?.videoTrackPublications ??
            const <LocalTrackPublication<LocalVideoTrack>>[]) {
      final t = pub.track;
      if (t != null) return t;
    }
    return null;
  }
}

/// stores/activeCall.js
class ActiveCall {
  const ActiveCall({
    this.minimized = false,
    this.sessionId,
    this.callId,
    this.voiceOnly = false,
    this.isConversation = false,
    this.partnerName = '',
    this.partnerAvatar,
    this.partnerUserId,
    this.startedAt,
  });

  final bool minimized;
  final String? sessionId;
  final String? callId;
  final bool voiceOnly;
  final bool isConversation;
  final String partnerName;
  final String? partnerAvatar;
  final String? partnerUserId;
  final DateTime? startedAt;

  bool get showFloatingBar => minimized && sessionId != null;

  ActiveCall copyWith({bool? minimized, String? partnerAvatar}) => ActiveCall(
    minimized: minimized ?? this.minimized,
    sessionId: sessionId,
    callId: callId,
    voiceOnly: voiceOnly,
    isConversation: isConversation,
    partnerName: partnerName,
    partnerAvatar: partnerAvatar ?? this.partnerAvatar,
    partnerUserId: partnerUserId,
    startedAt: startedAt,
  );
}

class ActiveCallController extends Notifier<ActiveCall> {
  @override
  ActiveCall build() => const ActiveCall();

  ActiveCall get current => state;

  void syncMeta({
    required String sessionId,
    String? callId,
    required bool voiceOnly,
    required bool isConversation,
    String? partnerName,
    String? partnerAvatar,
    String? partnerUserId,
  }) {
    state = ActiveCall(
      minimized: state.minimized,
      sessionId: sessionId,
      callId: callId ?? (state.sessionId == sessionId ? state.callId : null),
      voiceOnly: voiceOnly,
      isConversation: isConversation,
      partnerName: partnerName ?? '',
      partnerAvatar: partnerAvatar,
      partnerUserId: partnerUserId,
      startedAt:
          state.sessionId == sessionId &&
              (callId == null || callId == state.callId)
          ? (state.startedAt ?? DateTime.now())
          : DateTime.now(),
    );
  }

  void minimize() => state = state.copyWith(minimized: true);
  void expand() => state = state.copyWith(minimized: false);
  void clear() => state = const ActiveCall();

  void patchPartnerAvatar(String userId, String? avatar) {
    if (state.partnerUserId != null && state.partnerUserId == userId) {
      state = ActiveCall(
        minimized: state.minimized,
        sessionId: state.sessionId,
        callId: state.callId,
        voiceOnly: state.voiceOnly,
        isConversation: state.isConversation,
        partnerName: state.partnerName,
        partnerAvatar: avatar,
        partnerUserId: state.partnerUserId,
        startedAt: state.startedAt,
      );
    }
  }
}

final activeCallProvider = NotifierProvider<ActiveCallController, ActiveCall>(
  ActiveCallController.new,
);

/// stores/incomingConversationCall.js
class IncomingConvCall {
  const IncomingConvCall({
    this.conversationId,
    this.callId,
    this.voiceOnly = false,
    this.callerName = '',
    this.callerAvatar,
  });
  final String? conversationId;
  final String? callId;
  final bool voiceOnly;
  final String callerName;
  final String? callerAvatar;
  bool get visible => conversationId != null;
}

class IncomingConvCallController extends Notifier<IncomingConvCall> {
  @override
  IncomingConvCall build() => const IncomingConvCall();

  void setIncoming(IncomingConvCall v) => state = v;
  void clear() => state = const IncomingConvCall();
}

final incomingConvCallProvider =
    NotifierProvider<IncomingConvCallController, IncomingConvCall>(
      IncomingConvCallController.new,
    );

/// utils/incomingSignalrPayload.js
IncomingConvCall? parseIncomingConversationCallPayload(List<Object?>? args) {
  final a = args ?? const [];
  Object? at(int i) => i < a.length ? a[i] : null;
  final cid = at(0);
  if (cid is bool) return null;
  String? id;
  var vo = at(1) == true;
  var name = at(2) is String ? at(2) as String : '';
  var avatar = at(3)?.toString();
  var callId = at(4)?.toString();
  if (cid is String && cid.trim().isNotEmpty) {
    id = cid.trim();
  } else if (cid is Map) {
    final v = cid.v('conversationId') ?? cid.v('id');
    if (v != null && '$v'.trim().isNotEmpty) {
      id = '$v'.trim();
      if (cid.b('voiceOnly')) vo = true;
      final cn = cid.v('callerName');
      if (cn is String) name = cn;
      callId = cid.v('callId')?.toString();
      final ca = cid.v('callerAvatar');
      if (ca != null) avatar = '$ca';
    }
  } else if (cid != null) {
    final s = '$cid'.trim();
    if (s.isNotEmpty && s != 'undefined' && s != 'null') id = s;
  }
  if (id == null) return null;
  return IncomingConvCall(
    conversationId: id,
    callId: callId,
    voiceOnly: vo,
    callerName: name,
    callerAvatar: avatar,
  );
}

({String conversationId, String? callId, bool voiceOnly})?
parseVideoCallAcceptedPayload(List<Object?>? args) {
  final a = args ?? const [];
  final first = a.isNotEmpty ? a[0] : null;
  if (first == null) return null;
  if (first is Map) {
    final id =
        first.v('conversationId') ?? first.v('id') ?? first.v('sessionId');
    if (id == null) return null;
    return (
      conversationId: '$id'.trim(),
      callId: first.v('callId')?.toString(),
      voiceOnly:
          first.v('voiceOnly') == true ||
          first.v('isVoiceOnly') == true ||
          first.v('audioOnly') == true,
    );
  }
  final cid = '$first'.trim();
  if (cid.isEmpty || cid == 'undefined' || cid == 'null') return null;
  return (
    conversationId: cid,
    callId: a.length > 2 ? a[2]?.toString() : null,
    voiceOnly: a.length > 1 && a[1] == true,
  );
}

/// Keeps a ticking elapsed-seconds value for call timers.
Stream<int> elapsedSeconds(DateTime? startedAt) =>
    Stream.periodic(const Duration(seconds: 1), (_) {
      if (startedAt == null) return 0;
      return DateTime.now().difference(startedAt).inSeconds;
    });

String formatCallTime(int sec) =>
    '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
