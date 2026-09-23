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
import '../conversations/conversations_list_controller.dart';
import 'call_state.dart';
import 'video_call_screen.dart';
import 'whatsapp_call_ui.dart';

bool incomingCallAsBool(Object? v) => v == true || v == 'true' || v == '1';

bool isInAnotherCall(WidgetRef ref, {String? exceptId}) {
  final id = ref.read(activeCallProvider).sessionId;
  return id != null && id.isNotEmpty && id != exceptId;
}

Future<void> acceptIncomingCall(WidgetRef ref, {BuildContext? context}) async {
  await CallNative.dismissIncoming();
  await RingSound.stop();
  final s = ref.read(incomingConvCallProvider);
  final id = s.conversationId;
  if (id == null) return;
  final active = ref.read(activeCallProvider);
  if (active.sessionId == id) {
    ref.read(incomingConvCallProvider.notifier).clear();
    ref.read(activeCallProvider.notifier).expand();
    openVideoRoute(ref.read(routerProvider), id, {'voiceOnly': s.voiceOnly || active.voiceOnly, 'fromConversation': true});
    return;
  }
  if (isInAnotherCall(ref, exceptId: id)) {
    declineIncomingCall(ref);
    if (context != null && context.mounted) showToast(context, t('videoCall.alreadyInCall'), error: true);
    return;
  }
  try {
    await Hubs.conversation.ensureConnected();
    await Hubs.conversation.invoke('AcceptVideoCall', [id]);
  } catch (_) {
    if (context != null && context.mounted) {
      showToast(context, t('common.error'), error: true);
      if (ref.read(incomingConvCallProvider).visible) unawaited(RingSound.start());
    }
    return;
  }
  ref.read(incomingConvCallProvider.notifier).clear();
  final item = ref.read(conversationsListProvider).where((c) => c.str('id') == id).firstOrNull;
  ref.read(activeCallProvider.notifier).syncMeta(
        sessionId: id,
        voiceOnly: s.voiceOnly,
        isConversation: true,
        partnerName: s.callerName,
        partnerAvatar: s.callerAvatar,
        partnerUserId: item?.s('partnerId'),
      );
  ref.read(activeCallProvider.notifier).expand();
  openVideoRoute(ref.read(routerProvider), id, {'voiceOnly': s.voiceOnly, 'fromConversation': true});
}

void declineIncomingCall(WidgetRef ref) {
  unawaited(CallNative.dismissIncoming());
  unawaited(RingSound.stop());
  final id = ref.read(incomingConvCallProvider).conversationId;
  ref.read(incomingConvCallProvider.notifier).clear();
  if (id == null) return;
  Hubs.conversation.ensureConnected().then((_) => Hubs.conversation.invoke('DeclineVideoCall', [id])).catchError((_) => null);
}

void applyIncomingCallEvent(WidgetRef ref, Map<String, dynamic> e) {
  final conversationId = e['conversationId']?.toString();
  final sessionId = e['sessionId']?.toString();
  final voiceOnly = incomingCallAsBool(e['voiceOnly']);
  final callerName = e['callerName']?.toString() ?? '';
  final callerAvatar = e['callerAvatar']?.toString();
  final action = e['action']?.toString() ?? 'ring';

  if (conversationId != null && conversationId.isNotEmpty) {
    ref.read(incomingConvCallProvider.notifier).setIncoming(IncomingConvCall(
          conversationId: conversationId,
          voiceOnly: voiceOnly,
          callerName: callerName,
          callerAvatar: callerAvatar,
        ));
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
    ref.read(routerProvider).push(Uri(path: '/chat/$sessionId', queryParameters: q).toString());
  }
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
      if (_resumed) {
        unawaited(RingSound.start());
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
        declineIncomingCall(ref);
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

    return IgnorePointer(
      ignoring: !s.visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: s.visible ? 1 : 0,
        child: !s.visible
            ? const SizedBox.shrink()
            : AnnotatedRegion<SystemUiOverlayStyle>(
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
              ),
      ),
    );
  }
}

/// Opens the video route used by VideoCallAccepted (caller side).
void openAcceptedCall(GoRouter router, String cid, bool voiceOnly) =>
    openVideoRoute(router, cid, {'initiator': true, 'voiceOnly': voiceOnly, 'fromConversation': true});
