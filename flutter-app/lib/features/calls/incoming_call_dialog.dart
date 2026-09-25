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
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../conversations/conversations_list_controller.dart';
import 'call_state.dart';
import 'video_call_screen.dart';
import 'whatsapp_call_ui.dart';

bool incomingCallAsBool(Object? v) => v == true || v == 'true' || v == '1';

/// Native accept/ring events that arrived before auth/hubs were ready.
Map<String, dynamic>? _pendingNativeIncoming;

bool isInAnotherCall(WidgetRef ref, {String? exceptId}) {
  final id = ref.read(activeCallProvider).sessionId;
  if (id != null && id.isNotEmpty && id != exceptId) return true;
  final incoming = ref.read(incomingConvCallProvider);
  if (incoming.visible &&
      incoming.conversationId != null &&
      incoming.conversationId != exceptId) {
    return true;
  }
  return false;
}

void declineBusyConversationCall(String conversationId) {
  Hubs.conversation
      .ensureConnected()
      .then((_) => Hubs.conversation.invoke('DeclineVideoCall', [conversationId, true]))
      .catchError((_) => null);
}

/// Tell the caller their call is actually ringing on this device.
void notifyOutgoingCallRinging(String conversationId) {
  Hubs.conversation
      .ensureConnected()
      .then((_) => Hubs.conversation.invoke('NotifyVideoCallRinging', [conversationId]))
      .catchError((_) => null);
}

Future<void> acceptIncomingCall(WidgetRef ref, {BuildContext? context}) async {
  final s = ref.read(incomingConvCallProvider);
  final id = s.conversationId;
  if (id == null) return;
  final active = ref.read(activeCallProvider);
  if (active.sessionId == id) {
    ref.read(incomingConvCallProvider.notifier).clear();
    unawaited(CallNative.dismissIncoming());
    unawaited(CallNative.clearLockScreen());
    unawaited(RingSound.stop());
    ref.read(activeCallProvider.notifier).expand();
    openVideoRoute(ref.read(routerProvider), id, {'voiceOnly': s.voiceOnly || active.voiceOnly, 'fromConversation': true});
    return;
  }
  if (isInAnotherCall(ref, exceptId: id)) {
    declineBusyConversationCall(id);
    ref.read(incomingConvCallProvider.notifier).clear();
    unawaited(CallNative.dismissIncoming());
    unawaited(RingSound.stop());
    if (context != null && context.mounted) showToast(context, t('videoCall.alreadyInCall'), error: true);
    return;
  }

  // Navigate first so notification Accept lands on the call UI, not the ringing overlay.
  final voiceOnly = s.voiceOnly;
  final item = ref.read(conversationsListProvider).where((c) => c.str('id') == id).firstOrNull;
  ref.read(incomingConvCallProvider.notifier).clear();
  ref.read(activeCallProvider.notifier).syncMeta(
        sessionId: id,
        voiceOnly: voiceOnly,
        isConversation: true,
        partnerName: s.callerName,
        partnerAvatar: s.callerAvatar,
        partnerUserId: item?.s('partnerId'),
      );
  ref.read(activeCallProvider.notifier).expand();
  openVideoRoute(ref.read(routerProvider), id, {'voiceOnly': voiceOnly, 'fromConversation': true});

  unawaited(CallNative.dismissIncoming());
  unawaited(CallNative.clearLockScreen());
  unawaited(RingSound.stop());

  var accepted = false;
  for (var i = 0; i < 6 && !accepted; i++) {
    try {
      await Hubs.conversation.ensureConnected();
      await Hubs.conversation.invoke('AcceptVideoCall', [id]);
      accepted = true;
    } catch (_) {
      await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
    }
  }
  if (!accepted && context != null && context.mounted) {
    showToast(context, t('common.error'), error: true);
  }
}

void declineIncomingCall(WidgetRef ref, {bool missed = false}) {
  unawaited(CallNative.dismissIncoming());
  unawaited(RingSound.stop());
  final id = ref.read(incomingConvCallProvider).conversationId;
  ref.read(incomingConvCallProvider.notifier).clear();
  if (id == null) return;
  final outcome = missed ? 'missed' : 'declined';
  Hubs.conversation
      .ensureConnected()
      .then((_) => Hubs.conversation.invoke('DeclineVideoCall', [id, false, outcome]))
      .catchError((_) => null);
}

void applyIncomingCallEvent(WidgetRef ref, Map<String, dynamic> e) {
  final conversationId = e['conversationId']?.toString();
  final sessionId = e['sessionId']?.toString();
  final voiceOnly = incomingCallAsBool(e['voiceOnly']);
  final callerName = e['callerName']?.toString() ?? '';
  final callerAvatar = e['callerAvatar']?.toString();
  final action = e['action']?.toString() ?? 'ring';

  if (conversationId != null && conversationId.isNotEmpty) {
    if (isInAnotherCall(ref, exceptId: conversationId)) {
      if (action != 'decline') declineBusyConversationCall(conversationId);
      return;
    }
    ref.read(incomingConvCallProvider.notifier).setIncoming(IncomingConvCall(
          conversationId: conversationId,
          voiceOnly: voiceOnly,
          callerName: callerName,
          callerAvatar: callerAvatar,
        ));
    notifyOutgoingCallRinging(conversationId);
    if (action == 'accept') {
      unawaited(acceptIncomingCall(ref));
    } else if (action == 'decline') {
      declineIncomingCall(ref);
    }
    return;
  }

  if (sessionId != null && sessionId.isNotEmpty) {
    unawaited(CallNative.dismissIncoming());
    if (action == 'decline') {
      Hubs.chat.ensureConnected().then((_) => Hubs.chat.invoke('DeclineVideoCall', [sessionId])).catchError((_) => null);
      return;
    }
    if (isInAnotherCall(ref, exceptId: sessionId)) {
      Hubs.chat.ensureConnected().then((_) => Hubs.chat.invoke('DeclineVideoCall', [sessionId])).catchError((_) => null);
      return;
    }
    final q = {
      'incomingVideoCall': '1',
      if (action == 'accept') 'autoAccept': '1',
    };
    ref.read(routerProvider).go(Uri(path: '/chat/$sessionId', queryParameters: q).toString());
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
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  Timer? _expire;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(incomingConvCallProvider).visible) _onVisible(true);
    });
  }

  @override
  void dispose() {
    _expire?.cancel();
    RingSound.stop();
    super.dispose();
  }

  bool get _resumed => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _onVisible(bool v) {
    _expire?.cancel();
    _expire = null;
    if (v) {
      final s = ref.read(incomingConvCallProvider);
      final cid = s.conversationId;
      if (cid != null) notifyOutgoingCallRinging(cid);
      if (_resumed) {
        unawaited(RingSound.start(RingKind.incoming));
        unawaited(CallNative.dismissIncoming());
      } else {
        unawaited(CallNative.showIncoming(
          conversationId: s.conversationId,
          voiceOnly: s.voiceOnly,
          callerName: s.callerName,
          callerAvatar: s.callerAvatar,
        ));
      }
      _expire = Timer(kIncomingCallRingTimeout, () {
        unawaited(RingSound.stop());
        declineIncomingCall(ref, missed: true);
      });
    } else {
      unawaited(RingSound.stop());
      unawaited(CallNative.dismissIncoming());
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
    ref.listen(incomingConvCallProvider.select((s) => s.visible), (_, v) => _onVisible(v));
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
          status: s.voiceOnly ? t('conversationChat.incomingVoiceCall') : t('conversationChat.incomingVideoCall'),
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
void openAcceptedCall(GoRouter router, String cid, bool voiceOnly) =>
    openVideoRoute(router, cid, {'initiator': true, 'voiceOnly': voiceOnly, 'fromConversation': true});
