import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../core/feature_flags.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.hasUpdate,
    required this.required,
    required this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
  });

  final bool hasUpdate;
  final bool required;
  final String currentVersion;
  final String? latestVersion;
  final String? downloadUrl;
}

int compareVersions(String a, String b) {
  List<int> parse(String v) => v.split('.').map((n) => int.tryParse(n) ?? 0).toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p < q ? -1 : 1;
  }
  return 0;
}

bool _validUrl(String? url) => url != null && url.trim() != '#' && RegExp(r'^https?://', caseSensitive: false).hasMatch(url.trim());

/// Mirrors mobile-app/src/services/updateCheck.js (SiteContent `app_update`).
Future<UpdateInfo?> fetchUpdateInfo() async {
  try {
    final current = (await PackageInfo.fromPlatform()).version;
    final content = await fetchSiteContent('app_update');
    if (content == null || '$content'.isEmpty) return null;
    final config = jsonDecode('$content') as Map<String, dynamic>;
    final minVersion = '${config['minVersion'] ?? config['min_version'] ?? '1.0'}';
    final latest = '${config['latestVersion'] ?? config['latest_version'] ?? minVersion}';
    final android = '${config['downloadUrl'] ?? config['download_url'] ?? ''}'.trim();
    final ios = '${config['iosDownloadUrl'] ?? config['ios_download_url'] ?? ''}'.trim();
    var url = Platform.isIOS ? ios : android;
    if (!_validUrl(url)) url = _validUrl(android) ? android : (_validUrl(ios) ? ios : '');
    final cmpMin = compareVersions(current, minVersion);
    return UpdateInfo(
      hasUpdate: cmpMin < 0 || compareVersions(current, latest) < 0,
      required: cmpMin < 0,
      currentVersion: current,
      latestVersion: latest,
      downloadUrl: _validUrl(url) ? url : null,
    );
  } catch (_) {
    return null;
  }
}
