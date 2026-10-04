import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexchat/core/network/api_client.dart';
import 'package:nexchat/core/network/network_status.dart';
import 'package:nexchat/core/storage/prefs.dart';
import 'package:nexchat/services/call_native.dart';
import 'package:nexchat/services/push_service.dart';

class CapturedHttp implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<String> events;
  bool failUnregister = false;
  bool failVoip = false;
  CapturedHttp(this.events);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    events.add('http:${options.path}');
    if ((failUnregister && options.path.endsWith('/unregister')) ||
        (failVoip && options.path.endsWith('/voip-token'))) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PushService service;
  late CapturedHttp http;
  late List<String> events;
  String? externalId;
  Completer<void>? initializationGate;
  Completer<void>? initializationStarted;

  setUp(() async {
    events = [];
    externalId = null;
    initializationGate = null;
    initializationStarted = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Prefs.init();
    NetworkStatus.online.value = true;
    http = CapturedHttp(events);
    Api.dio.httpClientAdapter =
        http; // No real provider or application network calls.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'OneSignal',
      'OneSignal#user',
      'OneSignal#pushsubscription',
      'OneSignal#notifications',
      'OneSignal#inappmessages',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        events.add(call.method);
        switch (call.method) {
          case 'OneSignal#initialize':
            initializationStarted?.complete();
            await initializationGate?.future;
          case 'OneSignal#pushSubscriptionId':
            return 'test-subscription';
          case 'OneSignal#pushSubscriptionToken':
            return 'test-provider-token';
          case 'OneSignal#pushSubscriptionOptedIn':
            return true;
          case 'OneSignal#permission':
            return true;
          case 'OneSignal#requestPermission':
            return true;
          case 'OneSignal#getExternalId':
            return externalId;
          case 'OneSignal#login':
            externalId = (call.arguments as Map)['externalId'] as String?;
          case 'OneSignal#logout':
            externalId = null;
        }
        return null;
      });
    }
    OneSignal.User = OneSignalUser();
    OneSignal.Notifications = OneSignalNotifications();
    service = PushService.testing();
  });

  Future<void> login(String user) async {
    await Prefs.instance.setToken('test-token-$user');
    await Prefs.instance.setString(Keys.user, jsonEncode({'id': user}));
    await service.init(user, promptPermission: false);
  }

  test(
    'PUSH01 failed HTTP unregister cannot skip local SDK opt-out/logout',
    () async {
      await login('a');
      events.clear();
      http.failUnregister = true;
      await service.clear();
      expect(events, contains('OneSignal#optOut'));
      expect(events, contains('OneSignal#logout'));
      expect(
        events.indexOf('OneSignal#logout'),
        lessThan(events.indexOf('http:notifications/unregister')),
      );
      expect(
        Prefs.instance.getString('nexchat_push_pending_cleanup_user'),
        'a',
      );
      expect(service.enabled, isFalse);
      events.clear();
      await service.refreshRegistration();
      expect(events, isEmpty);
    },
  );

  test('PUSH01 pending failed cleanup retries before new registration for same account', () async {
    await login('a');
    http.failUnregister = true;
    await service.clear();
    http.failUnregister = false;
    events.clear();
    await login('a');
    final calls = events.where((e) => e.startsWith('http:')).toList();
    expect(calls.first, 'http:notifications/unregister');
    expect(calls.last, 'http:notifications/register');
    expect(
      Prefs.instance.getString('nexchat_push_pending_cleanup_user'),
      isNull,
    );
  });

  test(
    'PUSH opt-out survives resume despite operating-system permission',
    () async {
      await login('a');
      await service.optOut();
      events.clear();
      await service.refreshRegistration();
      expect(Prefs.instance.getString('nexchat_push_enabled'), '0');
      expect(events, isNot(contains('OneSignal#optIn')));
      expect(events.where((e) => e.startsWith('http:')), isEmpty);
      expect(service.enabled, isFalse);
    },
  );

  test('PUSH03 token received before authentication replays with installation after login', () async {
    await service.bootstrap();
    CallNative.onVoipToken!('aabb');
    await Future<void>.delayed(Duration.zero);
    expect(http.requests, isEmpty);
    await login('a');
    final voip = http.requests.singleWhere(
      (r) => r.path.endsWith('/voip-token'),
    );
    final push = http.requests.singleWhere((r) => r.path.endsWith('/register'));
    expect((voip.data as Map)['token'], 'aabb');
    expect(
      (voip.data as Map)['installationId'],
      (push.data as Map)['installationId'],
    );
    expect((voip.data as Map)['installationId'], isNotEmpty);
  });

  test(
    'PUSH03 failed token upload and invalidation replay on resume',
    () async {
      await login('a');
      http.failVoip = true;
      CallNative.onVoipToken!('aabb');
      await service.refreshRegistration();
      http.failVoip = false;
      http.requests.clear();
      await service.refreshRegistration();
      expect(
        (http.requests.firstWhere((r) => r.path.endsWith('/voip-token')).data
            as Map)['token'],
        'aabb',
      );
      http.requests.clear();
      CallNative.onVoipToken!('');
      await service.refreshRegistration();
      expect(
        (http.requests.firstWhere((r) => r.path.endsWith('/voip-token')).data
            as Map)['token'],
        '',
      );
    },
  );
  test('PUSH01 untagged or old-account private notifications never open after switching', () async {
    await login('b');
    final opened = <String>[];
    service.onOpen = (data, title, body) => opened.add(data['type'] as String);
    Future<void> click(Map<String, String> data) async {
      final completion = Completer<void>();
      ServicesBinding.instance.channelBuffers.push(
        'OneSignal#notifications',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('OneSignal#onClickNotification', {
            'notification': {'notificationId': 'test', 'additionalData': data},
            'result': <String, dynamic>{},
          }),
        ),
        (_) => completion.complete(),
      );
      await completion.future;
    }

    await click({'type': 'conversation_message'});
    await click({'type': 'video_call', 'recipientUserId': ''});
    await click({'type': 'conversation_message', 'recipientUserId': 'a'});
    expect(opened, isEmpty);
    await click({'type': 'conversation_message', 'recipientUserId': 'b'});
    await click({'type': 'broadcast'});
    expect(opened, ['conversation_message', 'broadcast']);
    await service.clear();
    await click({'type': 'broadcast'});
    expect(opened.length, 2);
  });
  test('PUSH01 stale startup init cannot bind account A using account B credentials', () async {
    await login('b');
    events.clear();
    http.requests.clear();
    expect(await service.init('a', promptPermission: false), isFalse);
    expect(events, isEmpty);
    expect(http.requests, isEmpty);
    expect(externalId, 'b');
  });
  test('PUSH01 auth switch during SDK bootstrap cannot complete stale registration', () async {
    await Prefs.instance.setToken('test-token-a');
    await Prefs.instance.setString(Keys.user, jsonEncode({'id': 'a'}));
    initializationGate = Completer<void>();
    initializationStarted = Completer<void>();
    final pending = service.init('a', promptPermission: false);
    await initializationStarted!.future;
    await Prefs.instance.setToken('test-token-b');
    await Prefs.instance.setString(Keys.user, jsonEncode({'id': 'b'}));
    initializationGate!.complete();
    expect(await pending, isFalse);
    expect(http.requests, isEmpty);
    expect(events, isNot(contains('OneSignal#login')));
  });
}
