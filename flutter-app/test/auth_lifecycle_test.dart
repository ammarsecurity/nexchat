import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The platform fake lets tests suspend real secure-storage operations.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexchat/core/network/api_client.dart';
import 'package:nexchat/core/network/network_status.dart';
import 'package:nexchat/core/storage/prefs.dart';
import 'package:nexchat/features/auth/auth_controller.dart';

class DelayedSecureStorage extends TestFlutterSecureStoragePlatform {
  DelayedSecureStorage(super.data);
  Completer<void>? nextDelete;
  Completer<void>? deleteEntered;
  Completer<void>? nextWrite;
  Completer<void>? writeEntered;

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    final pause = nextDelete;
    nextDelete = null;
    if (pause != null) {
      deleteEntered?.complete();
      await pause.future;
    }
    await super.delete(key: key, options: options);
  }

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    final pause = nextWrite;
    nextWrite = null;
    if (pause != null) {
      writeEntered?.complete();
      await pause.future;
    }
    await super.write(key: key, value: value, options: options);
  }
}

class AuthAdapter implements HttpClientAdapter {
  Completer<ResponseBody>? profile;
  final requests = <RequestOptions>[];
  ResponseBody json(Map<String, dynamic> value) => ResponseBody.fromString(jsonEncode(value), 200,
      headers: {Headers.contentTypeHeader: ['application/json']});

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (options.path == 'user/me') return profile!.future;
    if (options.path == 'auth/login') {
      final name = (options.data as Map)['name'];
      return json({'userId': name, 'name': name, 'token': 'token-$name'});
    }
    return json({});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DelayedSecureStorage storage;
  late AuthAdapter adapter;
  late ProviderContainer container;
  late AuthController auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({Keys.user: jsonEncode({'id': 'A', 'name': 'A'}), Keys.avatar: 'avatar-A'});
    storage = DelayedSecureStorage({Keys.token: 'token-A'});
    FlutterSecureStoragePlatform.instance = storage;
    await Prefs.init();
    NetworkStatus.online.value = true;
    adapter = AuthAdapter();
    Api.dio.httpClientAdapter = adapter;
    container = ProviderContainer();
    auth = container.read(authProvider.notifier);
  });

  tearDown(() async {
    // Drain the unawaited initialization callbacks before disposing providers.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    container.dispose();
  });

  void expectAccount(String id) {
    expect(container.read(authProvider).user?.id, id);
    expect(Prefs.instance.token, 'token-$id');
    expect(storage.data[Keys.token], 'token-$id');
    expect(jsonDecode(Prefs.instance.getString(Keys.user)!)['id'], id);
  }

  test('delayed logout secure cleanup cannot erase the next login identity', () async {
    final release = Completer<void>();
    storage.nextDelete = release;
    storage.deleteEntered = Completer<void>();
    final logout = auth.logout();
    await storage.deleteEntered!.future;
    expect(container.read(authProvider).isLoggedIn, isFalse);
    expect(Prefs.instance.token, isNull);
    final login = auth.login('B', 'not-a-real-password');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    release.complete();
    await Future.wait([logout, login]);
    expectAccount('B');
    expect(Prefs.instance.getString(Keys.avatar), isNull);
  });

  test('logout waits out an old token write and removes both memory and disk auth', () async {
    final release = Completer<void>();
    storage.nextWrite = release;
    storage.writeEntered = Completer<void>();
    final login = auth.login('B', 'not-a-real-password');
    await storage.writeEntered!.future;
    final logout = auth.logout();
    release.complete();
    await Future.wait([login, logout]);
    expect(container.read(authProvider).isLoggedIn, isFalse);
    expect(Prefs.instance.token, isNull);
    expect(storage.data[Keys.token], isNull);
    expect(Prefs.instance.getString(Keys.user), isNull);
  });

  test('newest overlapping login wins after an older secure write completes', () async {
    final release = Completer<void>();
    storage.nextWrite = release;
    storage.writeEntered = Completer<void>();
    final oldLogin = auth.login('B', 'not-a-real-password');
    await storage.writeEntered!.future;
    final newLogin = auth.login('C', 'not-a-real-password');
    release.complete();
    await Future.wait([oldLogin, newLogin]);
    expectAccount('C');
  });

  test('old profile response cannot restore avatar across logout and same-account login', () async {
    adapter.profile = Completer<ResponseBody>();
    final oldProfile = auth.fetchProfileContactStatus();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await auth.logout();
    await auth.login('A', 'not-a-real-password');
    adapter.profile!.complete(adapter.json({'avatar': 'stale-avatar', 'country': '', 'phoneNumber': ''}));
    await oldProfile;
    expectAccount('A');
    expect(container.read(authProvider).avatar, isNull);
    expect(Prefs.instance.getString(Keys.avatar), isNull);
    expect(container.read(authProvider).needsProfileContact, isFalse);
    final request = adapter.requests.firstWhere((r) => r.path == 'user/me');
    expect(request.headers['Authorization'], 'Bearer token-A');
    expect(request.extra['preserveAuthorization'], isTrue);
  });
}
