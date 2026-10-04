import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexchat/core/config/env.dart';
import 'package:nexchat/core/network/api_client.dart';
import 'package:nexchat/core/storage/prefs.dart';
import 'package:nexchat/services/media.dart';
import 'package:nexchat/shared/media_widgets.dart';

class RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  List<int> bytes = utf8.encode('test response');
  int statusCode = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await requestStream?.drain<void>();
    return ResponseBody.fromBytes(bytes, statusCode, headers: {Headers.contentTypeHeader: ['application/octet-stream']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingAdapter apiAdapter;
  late RecordingAdapter publicAdapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({Keys.token: 'disposable-test-token'});
    await Prefs.init();
    apiAdapter = RecordingAdapter();
    publicAdapter = RecordingAdapter();
    Api.dio.httpClientAdapter = apiAdapter;
    publicMediaClient.httpClientAdapter = publicAdapter;
  });

  test('JPEG/album, M4A, MP4 and MOV multipart parts carry accepted MIME headers', () async {
    final dir = await Directory.systemTemp.createTemp('nexchat-upload-test-');
    addTearDown(() => dir.delete(recursive: true));
    final cases = [
      ('upload', 'album-1.jpg', 'image/jpeg'),
      ('upload', 'album-2.png', 'image/png'),
      ('upload', 'photo.jpeg', 'image/jpeg'),
      ('upload', 'photo.gif', 'image/gif'),
      ('upload', 'photo.webp', 'image/webp'),
      ('upload-audio', 'voice.m4a', 'audio/mp4'),
      ('upload-chat-video', 'clip.mp4', 'video/mp4'),
      ('upload-chat-video', 'clip.mov', 'video/quicktime'),
      ('upload-file', 'report.pdf', 'application/pdf'),
      ('upload-file', 'notes.txt', 'text/plain'),
      ('upload-file', 'archive.zip', 'application/zip'),
    ];
    for (final (endpoint, filename, mime) in cases) {
      final file = await File('${dir.path}/$filename').writeAsBytes([1, 2, 3]);
      final part = await mediaUploadPart('/media/$endpoint', file.path);
      final form = FormData.fromMap({'file': part});
      final body = latin1.decode(await form.finalize().fold<List<int>>([], (bytes, part) => bytes..addAll(part)));
      expect(body.toLowerCase(), contains('content-type: $mime'));
      expect(body, contains('filename="$filename"'));
    }
    expect(() => mediaContentType('upload', 'image.exe'), throwsArgumentError);
    expect(() => mediaContentType('upload-audio', 'voice.jpg'), throwsArgumentError);
    expect(() => mediaContentType('upload-file', 'malware.exe'), throwsArgumentError);
  });

  test('API interceptor attaches credentials only to the exact API origin', () async {
    await Api.dio.get('${Env.apiUrl}/media/test');
    expect(apiAdapter.requests.last.headers['Authorization'], 'Bearer disposable-test-token');
    expect(apiAdapter.requests.last.followRedirects, isFalse);
    final api = Uri.parse(Env.apiUrl);
    final destinations = [
      'https://external.invalid/uploads/image.jpg',
      '${api.scheme}://${api.host}.external.invalid/api/file',
      api.replace(scheme: api.scheme == 'https' ? 'http' : 'https').toString(),
      api.replace(port: api.port + 1).toString(),
      api.replace(userInfo: 'untrusted').toString(),
    ];
    for (final url in destinations) {
      await Api.dio.get(url, options: Options(headers: {'authorization': 'must-be-stripped'}, extra: {'preserveAuthorization': true}));
      expect(apiAdapter.requests.last.headers.keys.where((key) => key.toLowerCase() == 'authorization'), isEmpty);
    }
    expect(Api.absoluteUrl('//external.invalid/image.jpg'), isNull);
    expect(Api.absoluteUrl('file:///tmp/image.jpg'), isNull);
  });

  test('pinned lifecycle requests do not adopt a newer account token', () async {
    await Api.dio.post('${Env.apiUrl}/test', options: Options(
      headers: {'Authorization': 'Bearer old-disposable-account'},
      extra: {'preserveAuthorization': true},
    ));
    expect(apiAdapter.requests.last.headers['Authorization'], 'Bearer old-disposable-account');
    expect(apiAdapter.requests.last.followRedirects, isFalse);
    await Api.dio.post('${Env.apiUrl}/test', options: Options(extra: {'preserveAuthorization': true}));
    expect(apiAdapter.requests.last.headers['Authorization'], isNull);
  });

  test('public media requests have no authentication interceptor or headers', () async {
    await publicMediaClient.get('https://external.invalid/photo.jpg');
    expect(publicAdapter.requests.single.headers.keys.where((key) => key.toLowerCase() == 'authorization'), isEmpty);
    expect(publicMediaClient.interceptors.whereType<InterceptorsWrapper>(), isEmpty);
  });

  test('protected delivery recognition rejects external lookalikes', () {
    const path = '/api/media/view-once/00000000-0000-0000-0000-000000000001';
    expect(isViewOnceDelivery(path), isTrue);
    expect(isViewOnceDelivery('https://external.invalid$path'), isFalse);
    expect(Api.mediaAuthHeaders('https://external.invalid$path'), isEmpty);
    expect(Api.mediaAuthHeaders(path)['Authorization'], 'Bearer disposable-test-token');
  });

  testWidgets('view-once image uses memory-only provider and is evicted on disposal', (tester) async {
    // A complete 1x1 PNG fixture; no network or persistent cache plugin is used.
    apiAdapter.bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
    const url = '/api/media/view-once/00000000-0000-0000-0000-000000000002';
    await tester.pumpWidget(const MaterialApp(home: ViewOnceImage(url: url)));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(apiAdapter.requests.single.headers['Authorization'], 'Bearer disposable-test-token');
    expect(apiAdapter.requests.single.followRedirects, isFalse);
    expect(apiAdapter.requests.single.headers['Cache-Control'], 'no-store');
    final key = await image.image.obtainKey(const ImageConfiguration());
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
  });

  for (final background in [false, true]) {
    testWidgets('protected image viewer revokes on ${background ? 'background' : 'close'} and hides download', (tester) async {
      apiAdapter.bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
      const url = '/api/media/view-once/00000000-0000-0000-0000-000000000003';
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showImageViewer(context, [url]),
          child: const Text('Open protected image'),
        ),
      ))));
      await tester.tap(find.text('Open protected image'));
      await tester.pumpAndSettle();
      // The only icon action is Close, even if a caller left allowDownload=true.
      expect(find.byType(IconButton), findsOneWidget);
      if (background) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      } else {
        await tester.tap(find.byType(IconButton));
      }
      await tester.pumpAndSettle();
      final closes = apiAdapter.requests.where((request) => request.method == 'DELETE');
      expect(closes, hasLength(1));
      expect(closes.single.uri.path, url);
      expect(closes.single.headers['Authorization'], 'Bearer disposable-test-token');
      if (background) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
      }
      expect(find.byType(ViewOnceImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

}
