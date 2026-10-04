import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexchat/core/network/api_client.dart';
import 'package:nexchat/features/calls/call_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new call IDs are unique UUIDs, independent of the room', () {
    final ids = List.generate(100, (_) => newCallId());
    expect(ids.toSet().length, 100);
    expect(
      ids.every(
        (id) => RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
      ),
      isTrue,
    );
  });

  test(
    'terminal matching rejects a previous attempt and uncorrelated event',
    () {
      expect(sameCall('room', 'new', 'room', 'old'), isFalse);
      expect(sameCall('room', 'new', 'other', 'new'), isFalse);
      expect(sameCall('room', null, 'room', null), isFalse);
      expect(sameCall('room', 'new', 'room', 'new'), isTrue);
    },
  );

  test(
    'minimize and expand preserve attempt identity; new call resets start time',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(activeCallProvider.notifier);
      controller.syncMeta(
        sessionId: 'room',
        callId: 'one',
        voiceOnly: true,
        isConversation: true,
      );
      final started = controller.current.startedAt;
      controller.minimize();
      expect(controller.current.showFloatingBar, isTrue);
      expect(controller.current.callId, 'one');
      controller.expand();
      expect(controller.current.startedAt, started);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      controller.syncMeta(
        sessionId: 'room',
        callId: 'two',
        voiceOnly: false,
        isConversation: true,
      );
      expect(controller.current.callId, 'two');
      expect(controller.current.startedAt!.isAfter(started!), isTrue);
    },
  );

  test('incoming and accepted payloads retain call ID', () {
    final incoming = parseIncomingConversationCallPayload([
      'room',
      true,
      'Caller',
      '',
      'attempt',
    ]);
    expect(incoming!.callId, 'attempt');
    final accepted = parseVideoCallAcceptedPayload(['room', true, 'attempt']);
    expect(accepted!.callId, 'attempt');
    expect(accepted.voiceOnly, isTrue);
  });

  group('actual LiveKit service join cancellation, no network or media', () {
    final service = LiveKitService.instance;
    late List<Interceptor> interceptors;
    setUp(() async {
      await service.leave();
      interceptors = List.of(Api.dio.interceptors);
      Api.dio.interceptors.clear();
    });
    tearDown(() async {
      await service.leave();
      Api.dio.interceptors
        ..clear()
        ..addAll(interceptors);
    });

    test(
      'terminal during initial asynchronous teardown prevents token request',
      () async {
        var requests = 0;
        Api.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.reject(DioException(requestOptions: options));
            },
          ),
        );
        final joining = service.join(
          'room',
          callId: 'attempt',
          isConversation: true,
          voiceOnly: true,
        );
        await service.leaveCall('room', 'attempt');
        expect(await joining, isNull);
        expect(service.room, isNull);
        expect(requests, 0);
      },
    );

    test('terminal during token fetch cancels media creation; old attempt cannot cancel new', () async {
      final requested = Completer<void>();
      late RequestInterceptorHandler response;
      late RequestOptions options;
      Api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            options = o;
            response = handler;
            requested.complete();
          },
        ),
      );
      final joining = service.join(
        'room',
        callId: 'current',
        isConversation: true,
        voiceOnly: true,
      );
      await requested.future;
      final generation = service.generation;
      await service.leaveCall('room', 'old');
      expect(service.generation, generation);
      expect(service.ownsCall('room', 'current'), isTrue);
      await service.leaveCall('room', 'current');
      response.resolve(
        Response(
          requestOptions: options,
          data: {'url': 'not-used', 'token': 'not-used'},
        ),
      );
      expect(await joining, isNull);
      expect(service.room, isNull);
      expect(service.sessionId, isNull);
    });
  });
}
