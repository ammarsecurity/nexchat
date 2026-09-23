import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/i18n/i18n.dart';
import 'core/storage/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Prefs.init();
  await I18n.load();
  runApp(const ProviderScope(child: NexChatApp()));
}
