import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexchat/core/i18n/i18n.dart';
import 'package:nexchat/core/network/api_client.dart';
import 'package:nexchat/core/network/network_status.dart';
import 'package:nexchat/core/storage/prefs.dart';
import 'package:nexchat/core/theme/app_colors.dart';
import 'package:nexchat/features/auth/auth_controller.dart';
import 'package:nexchat/features/conversations/share_message_screen.dart';

class ShareTestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(token: 'fake', user: AppUser(id: 'owner', name: 'Owner'));
}

class ShareApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool registered = true;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async {
    requests.add(options);
    Object result;
    if (options.path == 'conversations') {
      result = [
        {'id': 'chat-1', 'partnerName': 'الشخص الآخر', 'partnerPhone': '9647700000001'},
        {'id': 'group-1', 'isGroup': true, 'groupName': 'مجموعة الأصدقاء'},
        {'id': 'official', 'partnerName': 'Official', 'isOfficial': true},
      ];
    } else if (options.path == 'contacts') {
      result = [{'contactUserId': 'contact-1', 'name': 'جهة الاتصال', 'phoneNumber': '9647700000002'}];
    } else if (options.path == 'contacts/lookup') {
      result = registered ? [{'userId': 'phone-1', 'name': 'صاحب الرقم', 'phoneNumber': '9647700000003', 'uniqueCode': 'NX-TEST'}] : [];
    } else {
      throw StateError('Unexpected external mutation ${options.method} ${options.path}');
    }
    return ResponseBody.fromString(jsonEncode(result), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShareApiAdapter adapter;
  late HttpClientAdapter originalAdapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Prefs.init();
    await I18n.load();
    I18n.current = 'ar';
    NetworkStatus.online.value = true;
    originalAdapter = Api.dio.httpClientAdapter;
    adapter = ShareApiAdapter();
    Api.dio.httpClientAdapter = adapter;
  });
  tearDown(() { Api.dio.httpClientAdapter = originalAdapter; });

  Future<void> mountPicker(WidgetTester tester, String type) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(ShareTestAuth.new)],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: ShareMessageScreen(
        shareMessage: {'type': type, 'content': jsonEncode({'id': 'sample', 'userId': 'story-owner', 'caption': 'visible'})},
      )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('reel picker confirms exact chat and cancelling does not send', (tester) async {
    await mountPicker(tester, 'short_film');
    expect(find.text('Official'), findsNothing);
    await tester.tap(find.text('الشخص الآخر'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('9647700000001'), findsOneWidget);
    await tester.tap(find.text(t('common.cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
  });

  testWidgets('story picker includes group and direct contact; cancelled contact does not create chat', (tester) async {
    await mountPicker(tester, 'story_share');
    expect(find.text('مجموعة الأصدقاء'), findsOneWidget);
    await tester.tap(find.text('جهة الاتصال'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9647700000002'), findsOneWidget);
    await tester.tap(find.text(t('common.cancel')));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.path.contains('open-private')), isEmpty);
  });

  testWidgets('registered phone lookup is explicit and cancellation never creates a conversation', (tester) async {
    await mountPicker(tester, 'story_share');
    await tester.enterText(find.byType(TextField), '+9647700000003');
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.path == 'contacts/lookup'), isEmpty);
    await tester.tap(find.text('البحث عن الرقم في NexChat'));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.path == 'contacts/lookup'), hasLength(1));
    expect(adapter.requests.last.data, {'contacts': [{'phone': '9647700000003'}]});
    await tester.tap(find.text('صاحب الرقم'));
    await tester.pumpAndSettle();
    expect(find.textContaining('إرسال إلى صاحب الرقم'), findsOneWidget);
    await tester.tap(find.text(t('common.cancel')));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.path.contains('open-private')), isEmpty);
  });

  testWidgets('unregistered number never triggers contact creation, SMS, or invite', (tester) async {
    adapter.registered = false;
    await mountPicker(tester, 'short_film');
    await tester.enterText(find.byType(TextField), '+9647700000003');
    await tester.pumpAndSettle();
    await tester.tap(find.text('البحث عن الرقم في NexChat'));
    await tester.pumpAndSettle();
    expect(find.text('صاحب الرقم'), findsNothing);
    expect(adapter.requests.where((r) => r.method == 'POST').map((r) => r.path), ['contacts/lookup']);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
