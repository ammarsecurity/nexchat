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
Future<void> navigateFromNotification(WidgetRef ref, Map<String, dynamic> input) async {
  final d = parseNotificationData(input);
  final type = d['type'] ?? input['type']?.toString();
  final router = ref.read(routerProvider);

  if (type == 'code_connected') {
    final flags = await ref.read(featureFlagsProvider.future);
    if (!flags.codeConnect) {
      router.push('/conversations');
      return;
    }
    if (d['requesterId'] != null) NotificationHooks.onConnectionRequest?.call(d);
    router.push('/home');
    return;
  }
  if (type == 'story_published' && d['userId'] != null) {
    final slide = d['slideId'];
    router.push(slide != null && slide.isNotEmpty ? '/stories/view/${d['userId']}?slideId=$slide' : '/stories/view/${d['userId']}');
    return;
  }
  if (type == 'conversation_message' && d['conversationId'] != null) {
    router.push(Uri(path: '/conversations', queryParameters: {'open': d['conversationId']}).toString());
    return;
  }
  if (type == 'message_request') {
    router.push('/conversations?tab=requests');
    return;
  }
  if (type == 'video_call') {
    if (d['conversationId'] != null) {
      NotificationHooks.onConversationCall?.call(d);
      router.push('/conversations');
      return;
    }
    if (d['sessionId'] != null) {
      final flags = await ref.read(featureFlagsProvider.future);
      router.push(flags.randomChat ? '/chat/${d['sessionId']}?incomingVideoCall=1' : '/conversations');
      return;
    }
  }
  if (d['sessionId'] != null) router.push('/chat/${d['sessionId']}');
}
