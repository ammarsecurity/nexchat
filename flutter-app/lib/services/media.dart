import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/json.dart';
import '../core/network/api_client.dart';

final _picker = ImagePicker();

const chatDocumentExtensions = ['pdf', 'txt', 'doc', 'docx', 'rtf', 'odt', 'zip', 'rar', '7z'];

Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) =>
    _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2048);

Future<List<XFile>> pickImages({int limit = maxAlbumImages}) => _picker.pickMultiImage(imageQuality: 85, maxWidth: 2048, limit: limit);

Future<XFile?> pickVideo({ImageSource source = ImageSource.gallery}) => _picker.pickVideo(source: source);

Future<PlatformFile?> pickChatDocument() async {
  try {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: chatDocumentExtensions,
    );
    if (f == null) return null;
    if (f.path == null || f.path!.isEmpty) return null;
    return f;
  } on MissingPluginException {
    // New native plugins require a full app restart (not hot reload).
    throw StateError('plugin_missing');
  }
}

/// Requests camera (+ mic for video). Returns false if the user denies.
Future<bool> ensureCameraPermission({bool microphone = false}) async {
  final cam = await Permission.camera.request();
  if (!cam.isGranted) return false;
  if (!microphone) return true;
  final mic = await Permission.microphone.request();
  return mic.isGranted;
}

/// Permission + services only (no GPS wait). Throws short reason codes for UI toasts.
Future<void> ensureLocationReady() async {
  try {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) throw StateError('location_disabled');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) throw StateError('location_denied');
    if (permission == LocationPermission.deniedForever) throw StateError('location_denied_forever');
  } on MissingPluginException {
    throw StateError('plugin_missing');
  }
}

/// Resolves a shareable fix without hanging the UI (last-known → medium → low).
Future<Position> getShareablePosition() async {
  await ensureLocationReady();

  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      final age = DateTime.now().toUtc().difference(last.timestamp.toUtc());
      if (age.inMinutes <= 10) return last;
    }
  } catch (_) {}

  LocationSettings settingsFor(LocationAccuracy accuracy, Duration limit) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        timeLimit: limit,
        forceLocationManager: true,
      );
    }
    return LocationSettings(accuracy: accuracy, timeLimit: limit);
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: settingsFor(LocationAccuracy.medium, const Duration(seconds: 8)),
    );
  } on TimeoutException {
    // fall through
  } on MissingPluginException {
    throw StateError('plugin_missing');
  } catch (_) {
    // fall through to coarser attempt
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: settingsFor(LocationAccuracy.low, const Duration(seconds: 5)),
    );
  } on TimeoutException {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return last;
    throw StateError('location_timeout');
  } on MissingPluginException {
    throw StateError('plugin_missing');
  }
}

Future<XFile?> captureImage() async {
  if (!await ensureCameraPermission()) return null;
  return pickImage(source: ImageSource.camera);
}

Future<XFile?> captureVideo() async {
  if (!await ensureCameraPermission(microphone: true)) return null;
  return pickVideo(source: ImageSource.camera);
}

/// POST multipart to one of the `/media/upload*` endpoints, returns the stored url.
Future<String> uploadFile(String endpoint, String path, {String? filename, bool viewOnce = false, Duration timeout = const Duration(seconds: 60)}) async {
  final form = FormData.fromMap({'file': await mediaUploadPart(endpoint, path, filename: filename)});
  final res = await Api.dio.post(
    endpoint.startsWith('/') ? endpoint.substring(1) : endpoint,
    data: form,
    queryParameters: viewOnce ? {'viewOnce': true} : null,
    options: Options(sendTimeout: timeout, receiveTimeout: timeout),
  );
  final data = res.data;
  final url = data is Map ? (data['url'] ?? (data['data'] is Map ? data['data']['url'] : null)) : null;
  if (url is! String || url.isEmpty) throw Exception('Invalid upload response');
  return url;
}

/// Document upload — returns url + original file metadata for the `file` message payload.
Future<FileShare> uploadChatDocument(String path, {String? filename, Duration timeout = const Duration(seconds: 120)}) async {
  final name = filename ?? path.split(Platform.pathSeparator).last;
  final form = FormData.fromMap({'file': await mediaUploadPart('/media/upload-file', path, filename: name)});
  final res = await Api.dio.post(
    'media/upload-file',
    data: form,
    options: Options(sendTimeout: timeout, receiveTimeout: timeout),
  );
  final data = res.data;
  if (data is! Map) throw Exception('Invalid upload response');
  final url = '${data['url'] ?? ''}'.trim();
  if (url.isEmpty) throw Exception('Invalid upload response');
  final serverName = '${data['name'] ?? name}'.trim();
  final sizeRaw = data['size'];
  final size = sizeRaw is int ? sizeRaw : int.tryParse('$sizeRaw');
  final ct = '${data['contentType'] ?? ''}'.trim();
  return FileShare(url: url, name: serverName.isEmpty ? name : serverName, size: size, contentType: ct.isEmpty ? null : ct);
}

/// Explicit format mapping matches the API allowlists; unknown formats fail
/// locally instead of silently sending application/octet-stream.
DioMediaType mediaContentType(String endpoint, String filename) {
  final ext = filename.split('.').last.toLowerCase();
  final kind = endpoint.contains('upload-file')
      ? 'document'
      : endpoint.contains('audio')
          ? 'audio'
          : endpoint.contains('video')
              ? 'video'
              : 'image';
  final types = switch (kind) {
    'audio' => const {'m4a': 'audio/mp4', 'mp4': 'audio/mp4', 'webm': 'audio/webm', 'ogg': 'audio/ogg', 'opus': 'audio/ogg', 'mp3': 'audio/mpeg', 'wav': 'audio/wav'},
    'video' => const {'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm'},
    'document' => const {
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'rtf': 'application/rtf',
        'odt': 'application/vnd.oasis.opendocument.text',
        'zip': 'application/zip',
        'rar': 'application/vnd.rar',
        '7z': 'application/x-7z-compressed',
      },
    _ => const {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp'},
  };
  final type = types[ext];
  if (type == null) throw ArgumentError('Unsupported $kind file format');
  return DioMediaType.parse(type);
}

Future<MultipartFile> mediaUploadPart(String endpoint, String path, {String? filename}) {
  final name = filename ?? path.replaceAll('\\', '/').split('/').last;
  return MultipartFile.fromFile(path, filename: name, contentType: mediaContentType(endpoint, name));
}

// Never attach session credentials to public downloads or their redirects.
final publicMediaClient = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)));

bool isViewOnceDelivery(String url) {
  final absolute = Api.absoluteUrl(url);
  final uri = absolute == null ? null : Uri.tryParse(absolute);
  return uri != null && Api.isApiOrigin(uri) && RegExp(r'^/api/media/view-once/[0-9a-fA-F-]{36}$').hasMatch(uri.path);
}

Future<void> closeViewOnceDelivery(String url) async {
  if (!isViewOnceDelivery(url)) return;
  try { await Api.dio.delete(Api.absoluteUrl(url)!, options: Options(extra: {'skipGlobalLoader': true})); } catch (_) {
    // Offline/app termination cannot extend the fixed server session deadline.
  }
}

Future<File> _download(String url, String name) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  final absolute = Api.absoluteUrl(url);
  if (absolute == null || isViewOnceDelivery(url) || url.contains('/api/media/private/')) {
    throw ArgumentError('This media cannot be downloaded');
  }
  await publicMediaClient.download(absolute, file.path);
  return file;
}

String _ext(String url, String fallback) {
  final m = RegExp(r'\.([a-z0-9]{2,5})(\?|$)', caseSensitive: false).firstMatch(url);
  return m?.group(1) ?? fallback;
}

/// utils/mediaDownload.js — fetch then hand off to the system share sheet (Save to Photos / Files).
Future<void> downloadMediaUrl(String url, {String kind = 'image', String? filename}) async {
  final fallback = kind == 'video'
      ? 'mp4'
      : kind == 'audio'
          ? 'webm'
          : kind == 'file'
              ? 'bin'
              : 'jpg';
  final name = filename ?? '${kind == 'image' ? 'photo' : kind}-${DateTime.now().millisecondsSinceEpoch}.${_ext(url, fallback)}';
  final file = await _download(url, name);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}

Future<void> downloadAlbumImages(List<String> urls) async {
  final files = <XFile>[];
  for (var i = 0; i < urls.length; i++) {
    final f = await _download(urls[i], 'album-${i + 1}.${_ext(urls[i], 'jpg')}');
    files.add(XFile(f.path));
  }
  await SharePlus.instance.share(ShareParams(files: files));
}

bool canDownloadMessage(Json msg) {
  final type = msg.s('type') ?? 'text';
  if (msg.b('deletedForEveryone')) return false;
  if (msg.b('isViewOnce')) return false;
  final content = msg.str('content').trim();
  if (content.isEmpty) return false;
  if (type == 'album') return parseAlbumMessage(content)?.isNotEmpty ?? false;
  if (type == 'file') {
    final file = parseFileMessage(type, content);
    return file != null && !_isLocalPath(file.url);
  }
  if (type != 'image' && type != 'video' && type != 'audio') return false;
  return !_isLocalPath(content);
}

bool _isLocalPath(String s) {
  if (s.startsWith('file:') || s.startsWith('blob:') || s.startsWith('content:')) return true;
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(s)) return true;
  return s.startsWith('/') && !s.startsWith('/uploads');
}

Future<void> downloadMessageMedia(Json msg) async {
  final type = msg.s('type') ?? 'text';
  final content = msg.str('content');
  if (type == 'album') {
    final urls = parseAlbumMessage(content);
    if (urls != null) await downloadAlbumImages(urls);
    return;
  }
  if (type == 'file') {
    final file = parseFileMessage(type, content);
    if (file == null) return;
    await downloadMediaUrl(file.url, kind: 'file', filename: file.name);
    return;
  }
  await downloadMediaUrl(content, kind: type);
}
