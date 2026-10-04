import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexchat/core/i18n/i18n.dart';
import 'package:nexchat/core/storage/prefs.dart';
import 'package:nexchat/core/theme/app_colors.dart';
import 'package:nexchat/features/auth/auth_controller.dart';
import 'package:nexchat/features/conversations/active_conversation.dart';
import 'package:nexchat/features/conversations/conversation_cache.dart';
import 'package:nexchat/features/conversations/conversations_list_controller.dart';
import 'package:nexchat/features/conversations/message_contract.dart';
import 'package:nexchat/features/conversations/message_copy_action.dart';
import 'package:nexchat/features/conversations/message_outbox.dart';

class TestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(token: 'test', user: AppUser(id: 'A', name: 'A'));
  void switchTo(String id) => state = AuthState(token: 'test-$id', user: AppUser(id: id, name: id));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Prefs.init();
  });

  test('M1 requires exact conversation scope before accepting an event', () {
    expect(belongsToConversation({'conversationId': 'AC'}, 'AB'), isFalse);
    expect(belongsToConversation({'content': 'unscoped'}, 'AB'), isFalse);
    expect(belongsToConversation({'ConversationId': 'ab'}, 'AB'), isTrue);
  });

  test('M5 stable acknowledgment never consumes another pending message', () {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(TestAuth.new)]);
    addTearDown(container.dispose);
    final store = container.read(activeConversationProvider.notifier);
    store.setConversation('AB', {'id': 'B'});
    store.addMessage({'tempId': 'c1', 'clientMessageId': 'c1', 'senderId': 'A', 'content': 'one', 'status': 'pending'});
    store.addMessage({'tempId': 'c2', 'clientMessageId': 'c2', 'senderId': 'A', 'content': 'two', 'status': 'pending'});
    final first = {'id': 's1', 'conversationId': 'AB', 'clientMessageId': 'c1', 'senderId': 'A', 'content': 'masked one'};
    expect(store.updatePendingMessage(first), isTrue);
    expect(store.updatePendingMessage(first), isTrue);
    expect(container.read(activeConversationProvider).messages.length, 2);
    expect(container.read(activeConversationProvider).messages.last['content'], 'two');
    expect(store.updatePendingMessage({'id': 's2', 'conversationId': 'AC', 'clientMessageId': 'c2', 'senderId': 'A'}), isFalse);
    expect(store.updatePendingMessage({'id': 's2', 'conversationId': 'AB', 'senderId': 'A'}), isFalse);
  });

  test('M8 read watermark is monotonic', () {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(TestAuth.new)]);
    addTearDown(container.dispose);
    final store = container.read(activeConversationProvider.notifier);
    final newest = DateTime.utc(2026, 10, 4);
    store.setPartnerLastReadAt(newest);
    store.setPartnerLastReadAt(newest.subtract(const Duration(days: 1)));
    expect(container.read(activeConversationProvider).partnerLastReadAt, newest);
  });

  test('M2 switching account resets private providers', () async {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(TestAuth.new)]);
    addTearDown(container.dispose);
    container.read(activeConversationProvider.notifier).setConversation('AB', {'id': 'B'});
    container.read(conversationsListProvider.notifier).setList([{'id': 'AB', 'lastMessagePreview': 'private'}]);
    (container.read(authProvider.notifier) as TestAuth).switchTo('C');
    expect(container.read(activeConversationProvider).messages, isEmpty);
    expect(container.read(activeConversationProvider).conversationId, isNull);
    expect(container.read(conversationsListProvider), isEmpty);
  });

  test('M2 private cache cannot cross accounts or filters', () async {
    await ConversationCache.save('cache-A', 'AB', [{'id': 'one', 'content': 'secret'}]);
    expect(ConversationCache.read('cache-A', 'AB').single['content'], 'secret');
    expect(ConversationCache.read('cache-B', 'AB'), isEmpty);
    expect(ConversationCache.inboxKey('A', 'hidden'), isNot(ConversationCache.inboxKey('A')));
    await Prefs.instance.setString('nexchat_conversations_cache', 'legacy');
    await ConversationCache.removeLegacy();
    expect(Prefs.instance.getString('nexchat_conversations_cache'), isNull);
    expect(ConversationCache.read('cache-A', 'AB'), hasLength(1));
  });

  test('M7 cold offline outbox survives without any history cache', () async {
    await MessageOutbox.enqueue('offline-A', {'conversationId': 'AB', 'tempId': 'queued1', 'clientMessageId': 'queued1', 'content': 'offline', 'status': 'pending', 'type': 'text'});
    expect(ConversationCache.read('offline-A', 'AB'), isEmpty);
    expect(MessageOutbox.read('offline-A', 'AB').single['content'], 'offline');
    expect(MessageOutbox.read('offline-B', 'AB'), isEmpty);
    await MessageOutbox.enqueue('offline-A', {'conversationId': 'AB', 'tempId': 'queued1', 'clientMessageId': 'queued1', 'content': 'offline', 'status': 'failed', 'type': 'text'});
    expect(MessageOutbox.read('offline-A', 'AB'), hasLength(1));
  });

  test('M11 only durable own acknowledgment removes outbox; late save cannot restore it', () async {
    final queued = {'conversationId': 'AB', 'clientMessageId': 'ack1', 'tempId': 'ack1', 'content': 'hello', 'status': 'pending'};
    await MessageOutbox.enqueue('ack-A', queued);
    await MessageOutbox.acknowledge('ack-A', {'clientMessageId': 'ack1', 'senderId': 'ack-A'});
    expect(MessageOutbox.read('ack-A'), hasLength(1));
    await MessageOutbox.acknowledge('ack-A', {...queued, 'id': 'server1', 'senderId': 'ack-A'});
    await MessageOutbox.enqueue('ack-A', queued);
    expect(MessageOutbox.read('ack-A'), isEmpty);
  });

  test('ACTION1/2 durable tombstones defeat stale cache writes and redact quotes', () async {
    final original = {'id': 'original', 'content': 'private original'};
    final reply = {'id': 'reply', 'replyToMessageId': 'original', 'replyToContent': 'private original', 'content': 'reply'};
    await ConversationCache.save('delete-A', 'AB', [original, reply]);
    final deleting = ConversationCache.redact('delete-A', 'AB', ['original']);
    final staleSave = ConversationCache.save('delete-A', 'AB', [original, reply]);
    await Future.wait([deleting, staleSave]);
    final restored = ConversationCache.read('delete-A', 'AB');
    expect(restored, hasLength(1));
    expect(restored.single['replyToContent'], isNot('private original'));
    expect(restored.single['replyToSenderName'], isNull);
  });

  test('ACTION2 expired quote redacts even if original is on an older unloaded page', () {
    final reply = {'id': 'reply', 'replyToMessageId': 'old', 'replyToContent': 'expired secret', 'replyToExpiresAt': DateTime.utc(2000).toIso8601String()};
    expect(withoutExpiredMessages([reply]).single['replyToContent'], isNot('expired secret'));
  });

  test('reel/story forwarding emits all six arguments and retains one retry identity', () {
    for (final type in ['text', 'image', 'short_film', 'story_share']) {
      final content = type == 'text' ? 'مرحبا\nhello' : jsonEncode({'id': 'reel', 'caption': 'visible caption'});
      final args = conversationSendArguments('target', content, type, '', false, 'stable');
      expect(args, ['target', content, type, '', false, 'stable']);
      expect(conversationSendArguments('target', content, type, '', false, 'stable'), args);
    }
  });

  test('copy includes only visible text and preserves RTL/newlines', () {
    const text = 'مرحبا 👋\nhello world';
    expect(copyableMessageText({'type': 'text', 'content': text}), text);
    expect(copyableMessageText({'type': 'image', 'content': 'https://media/private'}), isNull);
    expect(copyableMessageText({'type': 'text', 'content': text, 'isViewOnce': true}), isNull);
    expect(copyableMessageText({'type': 'text', 'content': text, 'deletedForEveryone': true}), isNull);
    expect(copyableMessageText({'type': 'text', 'content': text, 'restricted': true}), isNull);
    expect(copyableMessageText({'type': 'story_share', 'content': jsonEncode({'caption': text, 'mediaUrl': 'private', 'token': 'secret'})}), text);
    expect(copyableMessageText({'type': 'story_reply', 'content': jsonEncode({'text': text, 'caption': 'other caption', 'token': 'secret'})}), text);
  });

  testWidgets('copy modal action uses Clipboard and gives one success callback', (tester) async {
    await I18n.load();
    I18n.current = 'ar';
    String? copied;
    var closed = 0;
    var successes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: Scaffold(body: MessageCopyAction(
      message: const {'type': 'text', 'content': 'نص\nhello'},
      onClose: () => closed++, onCopied: () => successes++, onFailure: () => fail('clipboard failed'),
    ))));
    await tester.tap(find.text('نسخ'));
    await tester.pump();
    expect(copied, 'نص\nhello');
    expect(closed, 1);
    expect(successes, 1);
  });
}
