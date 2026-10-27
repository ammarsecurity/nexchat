import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/web_url_strategy_stub.dart'
    if (dart.library.html) 'app/web_url_strategy_web.dart';
import 'core/i18n/i18n.dart';
import 'core/storage/prefs.dart';
import 'services/push_service.dart';
import 'services/tiktok_analytics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureWebUrlStrategy();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Prefs.init();
  await I18n.load();
  // Paint first frame ASAP — OneSignal/TikTok must not block UI on emulators.
  runApp(const ProviderScope(child: NexChatApp()));
  unawaited(PushService.instance.bootstrap());
  unawaited(TikTokAnalyticsService.instance.bootstrap());
}
