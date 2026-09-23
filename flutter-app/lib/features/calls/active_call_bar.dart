import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import 'call_state.dart';
import 'video_call_screen.dart';
import 'whatsapp_call_ui.dart';

/// WhatsApp-style green “tap to return to call” bar inside the chat.
class ActiveCallBar extends ConsumerStatefulWidget {
  const ActiveCallBar({super.key, this.embeddedFor, this.conversation = true});
  final String? embeddedFor;
  final bool conversation;

  @override
  ConsumerState<ActiveCallBar> createState() => _ActiveCallBarState();
}

class _ActiveCallBarState extends ConsumerState<ActiveCallBar> {
  Timer? _tick;
  int _elapsed = 0;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTimer(ActiveCall a, bool show) {
    if (show && _tick == null && a.startedAt != null) {
      _elapsed = DateTime.now().difference(a.startedAt!).inSeconds;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        final s = ref.read(activeCallProvider).startedAt;
        if (s != null && mounted) setState(() => _elapsed = DateTime.now().difference(s).inSeconds);
      });
    } else if (!show && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _openFull(ActiveCall a) {
    final sid = a.sessionId;
    if (sid == null) return;
    ref.read(activeCallProvider.notifier).expand();
    openVideoRoute(GoRouter.of(context), sid, {'voiceOnly': a.voiceOnly, 'fromConversation': a.isConversation});
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(activeCallProvider);
    final show = a.showFloatingBar &&
        (widget.embeddedFor == null || (a.sessionId == widget.embeddedFor && a.isConversation == widget.conversation));
    _syncTimer(a, show);
    if (!show) return const SizedBox.shrink();
    return Material(
      color: WaCall.teal,
      child: InkWell(
        onTap: () => _openFull(a),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(a.voiceOnly ? LucideIcons.phone : LucideIcons.video, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('videoCall.tapToReturn'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                formatCallTime(_elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  unawaited(LiveKitService.instance.leave());
                  ref.read(activeCallProvider.notifier).clear();
                },
                child: const Icon(LucideIcons.phoneOff, size: 18, color: Colors.white),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
