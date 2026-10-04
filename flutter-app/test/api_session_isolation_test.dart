import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexchat/core/network/api_client.dart';
import 'package:nexchat/core/storage/prefs.dart';

class DelayedUnauthorizedAdapter implements HttpClientAdapter {
  final entered = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    entered.complete(options);
    return response.future;
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({Keys.token: 'account-a-test-token'});
    await Prefs.init();
  });
  for (final changeAccount in [false, true]) {
    test('401 ${changeAccount ? 'from old account cannot invalidate new login' : 'is scoped to the rejected current login'}', () async {
      final adapter = DelayedUnauthorizedAdapter();
      Api.dio.httpClientAdapter = adapter;
      final events = <String>[];
      final subscription = Api.unauthorized.stream.listen(events.add);
      addTearDown(subscription.cancel);
      final request = Api.get('/user/me');
      final completion = expectLater(request, throwsA(isA<DioException>()));
      final captured = await adapter.entered.future;
      expect(captured.headers['Authorization'], 'Bearer account-a-test-token');
      if (changeAccount) await Prefs.instance.setToken('account-b-test-token');
      adapter.response.complete(ResponseBody.fromString('{}', 401, headers: {Headers.contentTypeHeader: ['application/json']}));
      await completion;
      await Future<void>.delayed(Duration.zero);
      expect(events, changeAccount ? isEmpty : ['account-a-test-token']);
      expect(Prefs.instance.token, changeAccount ? 'account-b-test-token' : 'account-a-test-token');
    });
  }
}
