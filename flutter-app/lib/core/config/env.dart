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

  /// API host without the `/api` suffix (SignalR hubs, uploaded files).
  static String get apiHost => apiUrl.replaceFirst(RegExp(r'/api/?$'), '');
}
