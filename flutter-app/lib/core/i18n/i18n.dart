import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs.dart';

/// Loads assets/i18n/{ar,en}.json (generated from the Vue locale files by tool/gen_i18n.mjs)
/// and exposes vue-i18n style dotted keys with `{name}` interpolation.
class I18n {
  I18n._();
  static final Map<String, Map<String, dynamic>> _tables = {};
  static String current = 'ar';

  static Future<void> load() async {
    for (final lang in ['ar', 'en']) {
      final raw = await rootBundle.loadString('assets/i18n/$lang.json');
      _tables[lang] = jsonDecode(raw) as Map<String, dynamic>;
    }
  }

  static String t(String key, [Map<String, Object?> params = const {}]) {
    dynamic node = _tables[current];
    for (final part in key.split('.')) {
      if (node is Map<String, dynamic>) {
        node = node[part];
      } else {
        node = null;
        break;
      }
    }
    var text = node is String ? node : key;
    params.forEach((k, v) => text = text.replaceAll('{$k}', '${v ?? ''}'));
    return text;
  }
}

String t(String key, [Map<String, Object?> params = const {}]) => I18n.t(key, params);

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    final code = Prefs.instance.getString(Keys.locale) ?? 'ar';
    I18n.current = code;
    return Locale(code);
  }

  bool get isRtl => state.languageCode == 'ar';

  void toggle() => set(state.languageCode == 'ar' ? 'en' : 'ar');

  void set(String code) {
    I18n.current = code;
    Prefs.instance.setString(Keys.locale, code);
    state = Locale(code);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class ThemeModeNotifier extends Notifier<bool> {
  /// true = light
  @override
  bool build() => Prefs.instance.getString(Keys.theme) != 'dark';

  void toggle() {
    state = !state;
    Prefs.instance.setString(Keys.theme, state ? 'light' : 'dark');
  }
}

final lightThemeProvider = NotifierProvider<ThemeModeNotifier, bool>(ThemeModeNotifier.new);
