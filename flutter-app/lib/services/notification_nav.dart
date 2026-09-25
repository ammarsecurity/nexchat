import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart';
import '../core/feature_flags.dart';
import 'push_service.dart';

/// Hooks for notification types whose handling lives in feature modules (calls, matching).
class NotificationHooks {
  static void Function(Map<String, String?> d)? onConversationCall;
  static void Function(Map<String, String?> d)? onConnectionRequest;
}

/// navigateFromNotification() in services/notifications.js.
///
/// Shell/tab destinations must use [GoRouter.go] — not [GoRouter.push] — because
/// `/conversations` / `/home` are already under the shell; pushing them again
/// collisions on `pageKey` (`!keyReservation.contains(key)`).
Future<void> navigateFromNotification(WidgetRef ref, Map<String, dynamic> input) async {
  final d = parseNotificationData(input);
  final type = d['type'] ?? input['type']?.toString();
  final router = ref.read(routerProvider);

  if (type == 'code_connected') {
    final flags = await ref.read(featureFlagsProvider.future);
    if (!flags.codeConnect) {
      router.go('/conversations');
      return;
    }
    // Do not re-open the live "connection request" dialog from an old notification.
    router.go('/home');
    return;
  }
  if (type == 'story_published' && d['userId'] != null) {
    final slide = d['slideId'];
    final path = slide != null && slide.isNotEmpty
        ? '/stories/view/${d['userId']}?slideId=$slide'
        : '/stories/view/${d['userId']}';
    router.push(path);
    return;
  }
  if ((type == 'conversation_message' || type == 'message') && d['conversationId'] != null) {
    router.go('/conversation/${d['conversationId']}');
    return;
  }
  if (type == 'message_request' || type == 'friend_request' || type == 'contact_request') {
    router.go('/conversations?tab=requests');
    return;
  }
  if (type == 'video_call') {
    // History / tray tap must NOT open the ringing UI — the call may be long over.
    // Live ringing comes from SignalR + the Android full-screen incoming-call path only.
    if (d['conversationId'] != null) {
      router.go('/conversation/${d['conversationId']}');
      return;
    }
    if (d['sessionId'] != null) {
      final flags = await ref.read(featureFlagsProvider.future);
      if (flags.randomChat) {
        router.push('/chat/${d['sessionId']}');
      } else {
        router.go('/conversations');
      }
      return;
    }
    router.go('/conversations');
    return;
  }
  if (type == 'story_like' || type == 'story_liked') {
    if (d['userId'] != null) {
      router.push('/stories/view/${d['userId']}');
      return;
    }
    router.go('/conversations');
    return;
  }
  if (d['conversationId'] != null) {
    router.go('/conversation/${d['conversationId']}');
    return;
  }
  if (d['sessionId'] != null) {
    router.push('/chat/${d['sessionId']}');
    return;
  }
  // broadcast / system / unknown — stay on list (already marked read by caller)
}
