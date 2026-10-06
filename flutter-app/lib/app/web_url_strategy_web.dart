import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Keep `/#/...` URLs so existing share redirects from the API keep working.
void configureWebUrlStrategy() {
  setUrlStrategy(HashUrlStrategy());
}
