import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/hubs.dart';
import '../../services/call_native.dart';
import '../../services/ring_sound.dart';
import '../../services/secure_screen.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../conversations/conversations_list_controller.dart';
import 'call_state.dart';
import 'video_call_screen.dart';
import 'whatsapp_call_ui.dart';

bool incomingCallAsBool(Object? v) => v == true || v == 'true' || v == '1';

/// Native accept/ring events that arrived before auth/hubs were ready.
Map<String, dynamic>? _pendingNativeIncoming;

bool isInAnotherCall(WidgetRef ref, {String? exceptId, String? exceptCallId}) {
  clearGhostActiveCall(ref);
  final active = ref.read(activeCallProvider);
  final id = active.sessionId;
  if (id != null &&
      id.isNotEmpty &&
      (id != exceptId ||
          (exceptCallId != null && active.callId != exceptCallId))) {
    return true;
  }
  final incoming = ref.read(incomingConvCallProvider);
  if (incoming.visible &&
      incoming.conversationId != null &&
      (incoming.conversationId != exceptId ||
          (exceptCallId != null && incoming.callId != exceptCallId))) {
    return true;
  }
  return false;
}

/// Drops leftover [activeCallProvider] after decline/end when LiveKit/UI are already gone,
/// and asks the server to release stuck busy so the user can place a new call.
void clearGhostActiveCall(WidgetRef ref) {
  final active = ref.read(activeCallProvider);
  final sid = active.sessionId;
  if (sid == null || sid.isEmpty) return;
  if (videoScreenMounts(sid) > 0) return;
  if (LiveKitService.instance.isInSession(sid)) return;
  if (active.startedAt != null &&
      DateTime.now().difference(active.startedAt!) < kIncomingCallRingTimeout) {
    return;
  }

  ref.read(activeCallProvider.notifier).clear();
  unawaited(LiveKitService.instance.leave());
  if (active.isConversation) {
    Hubs.conversation
        .ensureConnected()
        .then(
          (_) => Hubs.conversation.invoke('ReleaseVideoCallBusyV2', [
            sid,
            active.callId ?? '',
          ]),
        )
        .catchError((_) => null);
  }
}

void declineBusyConversationCall(String conversationId, String? callId) {
  if (callId == null || callId.isEmpty) return;
  Hubs.conversation
      .ensureConnected()
      .then(
        (_) => Hubs.conversation.invoke('DeclineVideoCallV2', [
          conversationId,
          true,
          'busy',
          callId,
        ]),
      )
      .catchError((_) => null);
}

/// Tell the caller their call is actually ringing on this device.
void notifyOutgoingCallRinging(String conversationId, String? callId) {
  if (callId == null || callId.isEmpty) return;
  Hubs.conversation
      .ensureConnected()
      .then(
        (_) => Hubs.conversation.invoke('NotifyVideoCallRingingV2', [
          conversationId,
          callId,
        ]),
      )
      .catchError((_) => null);
}

/// One terminal transition for full-screen, minimized, and still-joining calls.
void terminateMatchingCall(
  WidgetRef ref,
  String roomId,
  String? callId, {
  required bool isConversation,
}) {
  final active = ref.read(activeCallProvider);
  final incoming = ref.read(incomingConvCallProvider);
  if (sameCall(incoming.conversationId, incoming.callId, roomId, callId)) {
    ref.read(incomingConvCallProvider.notifier).clear();
    unawaited(CallNative.dismissIncoming(callId: callId));
    unawaited(RingSound.stop());
  }
  if (!sameCall(active.sessionId, active.callId, roomId, callId)) return;
  // leaveCall synchronously invalidates the join before the first await.
  unawaited(LiveKitService.instance.leaveCall(roomId, callId));
  ref.read(activeCallProvider.notifier).clear();
  unawaited(CallNative.dismissIncoming(callId: callId));
  unawaited(RingSound.stop());
  final router = ref.read(routerProvider);
  if (router.routerDelegate.currentConfiguration.uri.path == '/video/$roomId') {
    returnToRoute(
      router,
      isConversation ? '/conversation/$roomId' : '/chat/$roomId',
    );
  }
}

Future<void> acceptIncomingCall(WidgetRef ref, {BuildContext? context}) async {
  final s = ref.read(incomingConvCallProvider);
  final id = s.conversationId;
  final callId = s.callId;
  if (id == null || callId == null || callId.isEmpty) return;
  final active = ref.read(activeCallProvider);
  if (sameCall(active.sessionId, active.callId, id, callId)) {
    ref.read(incomingConvCallProvider.notifier).clear();
    unawaited(CallNative.acceptIncoming(callId: callId));
    unawaited(RingSound.stop());
    ref.read(activeCallProvider.notifier).expand();
    openVideoRoute(ref.read(routerProvider), id, {
      'voiceOnly': s.voiceOnly || active.voiceOnly,
      'fromConversation': true,
      'callId': callId,
    });
    return;
  }
  if (isInAnotherCall(ref, exceptId: id, exceptCallId: callId)) {
    declineBusyConversationCall(id, callId);
    ref.read(incomingConvCallProvider.notifier).clear();
    unawaited(CallNative.dismissIncoming(callId: callId));
    unawaited(RingSound.stop());
    if (context != null && context.mounted) {
      showToast(context, t('videoCall.alreadyInCall'), error: true);
    }
    return;
  }
  var accepted = false;
  for (var i = 0; i < 6 && !accepted; i++) {
    try {
      await Hubs.conversation.ensureConnected();
      accepted =
          await Hubs.conversation.invoke('AcceptVideoCallV2', [id, callId]) ==
          true;
      break; // A negative authoritative result is terminal, not a transport failure.
    } catch (_) {
      await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
    }
  }
  final current = ref.read(incomingConvCallProvider);
  if (!sameCall(current.conversationId, current.callId, id, callId)) return;
  ref.read(incomingConvCallProvider.notifier).clear();
  if (accepted) {
    unawaited(CallNative.acceptIncoming(callId: callId));
  } else {
    unawaited(CallNative.dismissIncoming(callId: callId));
  }
  unawaited(CallNative.clearLockScreen());
  unawaited(RingSound.stop());
  if (!accepted) {
    if (context != null && context.mounted) {
      showToast(context, t('common.error'), error: true);
    }
    return;
  }
  final item = ref
      .read(conversationsListProvider)
      .where((c) => c.str('id') == id)
      .firstOrNull;
  ref
      .read(activeCallProvider.notifier)
      .syncMeta(
        sessionId: id,
        callId: callId,
        voiceOnly: s.voiceOnly,
        isConversation: true,
        partnerName: s.callerName,
        partnerAvatar: s.callerAvatar,
        partnerUserId: item?.s('partnerId'),
      );
  ref.read(activeCallProvider.notifier).expand();
  openVideoRoute(ref.read(routerProvider), id, {
    'voiceOnly': s.voiceOnly,
    'fromConversation': true,
    'callId': callId,
  });
}

void declineIncomingCall(WidgetRef ref, {bool missed = false}) {
  unawaited(RingSound.stop());
  final incoming = ref.read(incomingConvCallProvider);
  final id = incoming.conversationId;
  final callId = incoming.callId;
  ref.read(incomingConvCallProvider.notifier).clear();
  if (id == null || callId == null) return;
  unawaited(CallNative.dismissIncoming(callId: callId));
  if (sameCall(
    ref.read(activeCallProvider).sessionId,
    ref.read(activeCallProvider).callId,
    id,
    callId,
  )) {
    terminateMatchingCall(ref, id, callId, isConversation: true);
  }
  final outcome = missed ? 'missed' : 'declined';
  Hubs.conversation
      .ensureConnected()
      .then(
        (_) => Hubs.conversation.invoke('DeclineVideoCallV2', [
          id,
          false,
          outcome,
          callId,
        ]),
      )
      .catchError((_) => null);
}

void applyIncomingCallEvent(WidgetRef ref, Map<String, dynamic> e) {
  final recipient = e['recipientUserId']?.toString();
  final currentUser = ref.read(authProvider).user?.id;
  if (recipient == null || currentUser == null || recipient != currentUser) {
    return;
  }
  final conversationId = e['conversationId']?.toString();
  final sessionId = e['sessionId']?.toString();
  final voiceOnly = incomingCallAsBool(e['voiceOnly']);
  final callerName = e['callerName']?.toString() ?? '';
  final callerAvatar = e['callerAvatar']?.toString();
  final action = e['action']?.toString() ?? 'ring';
  final callId = e['callId']?.toString();
  if (callId == null || callId.isEmpty) return;
  if (action == 'end') {
    final active = ref.read(activeCallProvider);
    final roomId = conversationId ?? sessionId;
    if (roomId == null) return;
    if (!sameCall(active.sessionId, active.callId, roomId, callId)) {
      terminateMatchingCall(
        ref,
        roomId,
        callId,
        isConversation: conversationId != null,
      );
      return;
    }
    final hub = active.isConversation ? Hubs.conversation : Hubs.chat;
    final secs = active.startedAt == null
        ? 0
        : DateTime.now().difference(active.startedAt!).inSeconds;
    unawaited(
      hub
          .ensureConnected()
          .then((_) => hub.invoke('EndVideoCallV2', [roomId, secs, callId]))
          .catchError((_) => null),
    );
    terminateMatchingCall(
      ref,
      roomId,
      callId,
      isConversation: active.isConversation,
    );
    return;
  }

  if (conversationId != null && conversationId.isNotEmpty) {
    if (isInAnotherCall(ref, exceptId: conversationId, exceptCallId: callId)) {
      if (action != 'decline') {
        declineBusyConversationCall(conversationId, callId);
      }
      return;
    }
    ref
        .read(incomingConvCallProvider.notifier)
        .setIncoming(
          IncomingConvCall(
            conversationId: conversationId,
            callId: callId,
            voiceOnly: voiceOnly,
            callerName: callerName,
            callerAvatar: callerAvatar,
          ),
        );
    notifyOutgoingCallRinging(conversationId, callId);
    if (action == 'accept') {
      unawaited(acceptIncomingCall(ref));
    } else if (action == 'decline') {
      declineIncomingCall(ref);
    }
    return;
  }

  if (sessionId != null && sessionId.isNotEmpty) {
    if (action == 'decline') {
      unawaited(CallNative.dismissIncoming(callId: callId));
      Hubs.chat
          .ensureConnected()
          .then(
            (_) => Hubs.chat.invoke('DeclineVideoCallV2', [
              sessionId,
              'declined',
              callId,
            ]),
          )
          .catchError((_) => null);
      return;
    }
    if (isInAnotherCall(ref, exceptId: sessionId, exceptCallId: callId)) {
      Hubs.chat
          .ensureConnected()
          .then(
            (_) => Hubs.chat.invoke('DeclineVideoCallV2', [
              sessionId,
              'declined',
              callId,
            ]),
          )
          .catchError((_) => null);
      return;
    }
    final q = {
      'incomingVideoCall': '1',
      'callId': callId,
      if (action == 'accept') 'autoAccept': '1',
    };
    ref
        .read(routerProvider)
        .go(Uri(path: '/chat/$sessionId', queryParameters: q).toString());
  }
}

/// Flush a native incoming-call event that was buffered before login.
void flushPendingIncomingCall(WidgetRef ref) {
  final pending = _pendingNativeIncoming;
  if (pending == null) return;
  _pendingNativeIncoming = null;
  applyIncomingCallEvent(ref, pending);
}

void queueOrApplyIncomingCall(WidgetRef ref, Map<String, dynamic> e) {
  if (!ref.read(authProvider).isLoggedIn) {
    _pendingNativeIncoming = e;
    return;
  }
  applyIncomingCallEvent(ref, e);
}

/// Incoming conversation call — full-screen WhatsApp-style ringing.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  ConsumerState<IncomingCallOverlay> createState() =>
      _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  Timer? _expire;
  bool _secured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(incomingConvCallProvider).visible) {
        _onVisible(true);
      }
    });
  }

  @override
  void dispose() {
    _expire?.cancel();
    RingSound.stop();
    if (_secured) {
      _secured = false;
      unawaited(SecureScreen.release());
    }
    super.dispose();
  }

  bool get _resumed =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _onVisible(bool v) {
    _expire?.cancel();
    _expire = null;
    if (v) {
      if (!_secured) {
        _secured = true;
        unawaited(SecureScreen.acquire());
      }
      final s = ref.read(incomingConvCallProvider);
      final cid = s.conversationId;
      if (cid != null) notifyOutgoingCallRinging(cid, s.callId);
      if (_resumed) {
        unawaited(RingSound.start(RingKind.incoming));
      } else {
        unawaited(
          CallNative.showIncoming(
            conversationId: s.conversationId,
            callId: s.callId,
            voiceOnly: s.voiceOnly,
            callerName: s.callerName,
            callerAvatar: s.callerAvatar,
          ),
        );
      }
      _expire = Timer(kIncomingCallRingTimeout, () {
        final current = ref.read(incomingConvCallProvider);
        if (!sameCall(
          current.conversationId,
          current.callId,
          s.conversationId,
          s.callId,
        )) {
          return;
        }
        unawaited(RingSound.stop());
        declineIncomingCall(ref, missed: true);
      });
    } else {
      unawaited(RingSound.stop());
      if (_secured) {
        _secured = false;
        unawaited(SecureScreen.release());
      }
    }
  }

  Future<void> _accept() async {
    _expire?.cancel();
    await acceptIncomingCall(ref, context: context);
  }

  void _decline() {
    _expire?.cancel();
    declineIncomingCall(ref);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      incomingConvCallProvider,
      (_, value) => _onVisible(value.visible),
    );
    final s = ref.watch(incomingConvCallProvider);
    final name = s.callerName.isEmpty ? '…' : s.callerName;

    if (!s.visible) return const SizedBox.shrink();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: WaCall.bgTop,
        child: WhatsAppRingingLayout(
          avatarUrl: s.callerAvatar,
          name: name,
          status: s.voiceOnly
              ? t('conversationChat.incomingVoiceCall')
              : t('conversationChat.incomingVideoCall'),
          actions: [
            CallCircleButton(
              icon: LucideIcons.phoneOff,
              onTap: _decline,
              background: WaCall.decline,
              size: 68,
              label: t('incomingRequest.decline'),
            ),
            CallCircleButton(
              icon: s.voiceOnly ? LucideIcons.phone : LucideIcons.video,
              onTap: _accept,
              background: WaCall.accept,
              size: 68,
              label: t('incomingRequest.accept'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the video route used by VideoCallAccepted (caller side).
void openAcceptedCall(
  GoRouter router,
  String cid,
  bool voiceOnly,
  String callId,
) => openVideoRoute(router, cid, {
  'initiator': true,
  'voiceOnly': voiceOnly,
  'fromConversation': true,
  'callId': callId,
});
