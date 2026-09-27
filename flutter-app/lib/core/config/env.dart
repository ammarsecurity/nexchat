class Env {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://nexchat-cloud.xaronhost.com/api',
  );
  static const publicAppUrl = String.fromEnvironment(
    'PUBLIC_APP_URL',
    defaultValue: 'https://web.nexchat.site',
  );
  static const oneSignalAppId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: 'ba2d847b-b62a-41eb-9814-4b7f1d8a8091',
  );

  /// Play Store / Android applicationId registered in TikTok Events Manager.
  static const tikTokAndroidAppId = String.fromEnvironment(
    'TIKTOK_ANDROID_APP_ID',
    defaultValue: 'site.nexchat.app',
  );

  /// iOS bundle identifier registered in TikTok Events Manager.
  static const tikTokIosAppId = String.fromEnvironment(
    'TIKTOK_IOS_APP_ID',
    defaultValue: 'com.nexchat.userapp',
  );

  /// TikTok App ID from Events Manager (same for Android/iOS unless you create separate apps).
  static const tikTokAppId = String.fromEnvironment(
    'TIKTOK_APP_ID',
    defaultValue: '7690289134248394760',
  );

  /// TikTok App Secret (Events Manager). Overridable via `--dart-define=TIKTOK_APP_SECRET=...`.
  static const tikTokAppSecret = String.fromEnvironment(
    'TIKTOK_APP_SECRET',
    defaultValue: 'TT1DNC64WSh0uIKrPSJ2Aski6ezBFcxk',
  );

  /// API host without the `/api` suffix (SignalR hubs, uploaded files).
  static String get apiHost => apiUrl.replaceFirst(RegExp(r'/api/?$'), '');
}
