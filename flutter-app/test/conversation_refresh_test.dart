import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexchat/app/router.dart';
import 'package:nexchat/core/json.dart';
import 'package:nexchat/features/auth/auth_controller.dart';
import 'package:nexchat/features/conversations/conversation_refresh.dart';
import 'package:nexchat/services/notification_nav.dart';

Json msg(String id, int minute, {String? client, String sender = 'B'}) => {
  'id': id,
  'conversationId': 'AB',
  'content': id,
  'senderId': sender,
  'sentAt': DateTime.utc(2026, 10, 4, 12, minute).toIso8601String(),
  'clientMessageId': client,
};
Json snapshot(List<Json> messages, {String cid = 'AB', bool more = false}) => {
  'conversationId': cid,
  'messages': messages,
  'hasMore': more,
};

class FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    token: 'sessionA',
    user: AppUser(id: 'A', name: 'A'),
  );
}

void main() {
  test('cold/terminated open fetches immediately without waiting for hub readiness', () async {
    final reply = Completer<Json>();
    var messages = <Json>[];
    var loading = false;
    final controller = ConversationRefreshController(
      conversation: 'AB',
      isCurrent: () => true,
      load: () => reply.future,
      readMessages: () => messages,
      apply: (value, _) => messages = value,
      onState: (value, _) => loading = value,
    );
    final pending = controller.refresh();
    expect(loading, isTrue);
    reply.complete(snapshot([msg('notification-message', 1)]));
    await pending;
    expect(messages.single['id'], 'notification-message');
    expect(loading, isFalse);
  });

  test('background cached rows stay visible; resume and reconnect responses cannot regress', () async {
    final first = Completer<Json>(), second = Completer<Json>();
    var requests = 0;
    var messages = [msg('cached', 0)];
    final controller = ConversationRefreshController(
      conversation: 'AB',
      isCurrent: () => true,
      load: () => ++requests == 1 ? first.future : second.future,
      readMessages: () => messages,
      apply: (value, _) => messages = value,
      onState: (_, _) {},
    );
    final resume = controller.refresh();
    expect(messages.single['id'], 'cached');
    final reconnect = controller.refresh();
    second.complete(snapshot([msg('cached', 0), msg('latest', 2)]));
    await reconnect;
    first.complete(snapshot([msg('cached', 0)]));
    await resume;
    expect(messages.map((m) => m['id']), ['cached', 'latest']);
  });

  test(
    'delayed snapshot merges arrivals/outbox acknowledgments and later edits',
    () {
      final old = msg('old', 0);
      final pending = {
        ...msg('', 1, client: 'one', sender: 'A'),
        'tempId': 'one',
        'status': 'pending',
      };
      final current = [
        {...old, 'content': 'edited'},
        pending,
        msg('live', 3),
      ];
      final merged = mergeConversationSnapshot(
        baseline: [old, pending],
        current: current,
        server: [
          old,
          msg('ack', 1, client: 'one', sender: 'A'),
          msg('snapshot', 2),
        ],
        hasMore: false,
      );
      expect(merged.map((m) => m['id']), ['old', 'ack', 'snapshot', 'live']);
      expect(merged.first['content'], 'edited');
    },
  );

  test(
    'delayed HTTP/join cannot resurrect removed or privacy-redacted content',
    () {
      final old = msg('deleted', 0),
          reply = {
            ...msg('reply', 1),
            'replyToMessageId': 'deleted',
            'replyToContent': 'secret',
          };
      final merged = mergeConversationSnapshot(
        baseline: [old, reply],
        current: [reply],
        server: [old, reply],
        hasMore: false,
      );
      expect(merged.map((m) => m['id']), ['reply']);
      expect(merged.single['replyToContent'], isNot('secret'));
      final opened = {...msg('viewonce', 2), 'viewOnceOpened': true};
      final snapshotResult = mergeConversationSnapshot(
        baseline: [opened],
        current: [opened],
        server: [
          {...opened, 'viewOnceOpened': false},
        ],
        hasMore: false,
      );
      expect(snapshotResult.single['viewOnceOpened'], isTrue);
      final joined = mergeConversationSnapshot(
        baseline: [],
        current: [msg('live', 3)],
        server: [old],
        hasMore: false,
        additive: true,
        removedIds: {'deleted'},
      );
      expect(joined.single['id'], 'live');
    },
  );

  test(
    'account switch, navigation and dispose discard delayed responses',
    () async {
      for (final dispose in [false, true]) {
        final response = Completer<Json>();
        var current = true;
        var applied = false;
        final controller = ConversationRefreshController(
          conversation: 'AB',
          isCurrent: () => current,
          load: () => response.future,
          readMessages: () => [],
          apply: (_, _) => applied = true,
          onState: (_, _) {},
        );
        final pending = controller.refresh();
        if (dispose) {
          controller.dispose();
        } else {
          current = false;
        }
        response.complete(snapshot([msg('private', 0)]));
        await pending;
        expect(applied, isFalse);
      }
    },
  );

  test(
    'failure keeps cache, exposes retry and rejects wrong conversation',
    () async {
      var messages = [msg('cached', 0)];
      Object? error;
      var attempts = 0;
      final controller = ConversationRefreshController(
        conversation: 'AB',
        isCurrent: () => true,
        load: () async => ++attempts == 1
            ? snapshot([msg('wrong', 1)], cid: 'OTHER')
            : snapshot([msg('new', 2)]),
        readMessages: () => messages,
        apply: (value, _) => messages = value,
        onState: (_, failure) => error = failure,
      );
      await controller.refresh();
      expect(error, isA<StateError>());
      expect(messages.single['id'], 'cached');
      await controller.refresh();
      expect(error, isNull);
      expect(messages.single['id'], 'new');
    },
  );

  test('older loaded history survives a partial newest-page snapshot', () {
    final old = msg('older', 0), newest = msg('newest', 4);
    final merged = mergeConversationSnapshot(
      baseline: [old],
      current: [old],
      server: [newest],
      hasMore: true,
    );
    expect(merged.map((m) => m['id']), ['older', 'newest']);
  });

  testWidgets(
    'same-open-chat notification always emits a fresh refresh intent',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/conversation/AB',
        routes: [
          GoRoute(
            path: '/conversation/:id',
            builder: (_, _) => const SizedBox(),
          ),
        ],
      );
      addTearDown(router.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(FakeAuth.new),
            routerProvider.overrideWithValue(router),
          ],
          child: Consumer(
            builder: (_, value, _) {
              ref = value;
              return const SizedBox();
            },
          ),
        ),
      );
      for (var revision = 1; revision <= 2; revision++) {
        await navigateFromNotification(ref, {
          'type': 'conversation_message',
          'conversationId': 'AB',
        });
        expect(ref.read(conversationRefreshIntentProvider).conversation, 'AB');
        expect(ref.read(conversationRefreshIntentProvider).revision, revision);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/conversation/AB',
        );
      }
    },
  );
}
