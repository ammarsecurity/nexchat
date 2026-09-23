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
import '../../services/ring_sound.dart';
import '../../shared/widgets.dart';
import '../conversations/conversations_list_controller.dart';
import 'call_state.dart';
import 'video_call_screen.dart';
import 'whatsapp_call_ui.dart';

const _ringTimeout = Duration(milliseconds: 120000);

/// Incoming conversation call — full-screen WhatsApp-style ringing.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  Timer? _expire;

  @override
  void dispose() {
    _expire?.cancel();
    RingSound.stop();
    super.dispose();
  }

  void _onVisible(bool v) {
    _expire?.cancel();
    _expire = null;
    if (v) {
      RingSound.start();
      _expire = Timer(_ringTimeout, () {
        RingSound.stop();
        final id = ref.read(incomingConvCallProvider).conversationId;
        ref.read(incomingConvCallProvider.notifier).clear();
        if (id != null) {
          Hubs.conversation.ensureConnected().then((_) => Hubs.conversation.invoke('DeclineVideoCall', [id])).catchError((_) => null);
        }
      });
    } else {
      RingSound.stop();
    }
  }

  Future<void> _accept() async {
    _expire?.cancel();
    RingSound.stop();
    final s = ref.read(incomingConvCallProvider);
    final id = s.conversationId;
    if (id == null) return;
    try {
      await Hubs.conversation.ensureConnected();
      await Hubs.conversation.invoke('AcceptVideoCall', [id]);
    } catch (_) {
      if (mounted) {
        showToast(context, t('common.error'), error: true);
        if (ref.read(incomingConvCallProvider).visible) RingSound.start();
      }
      return;
    }
    ref.read(incomingConvCallProvider.notifier).clear();
    if (!mounted) return;
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

  void _decline() {
    _expire?.cancel();
    RingSound.stop();
    final id = ref.read(incomingConvCallProvider).conversationId;
    ref.read(incomingConvCallProvider.notifier).clear();
    if (id == null) return;
    Hubs.conversation.ensureConnected().then((_) => Hubs.conversation.invoke('DeclineVideoCall', [id])).catchError((_) => null);
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
