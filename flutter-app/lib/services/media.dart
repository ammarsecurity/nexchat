import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/json.dart';
import '../core/network/api_client.dart';

final _picker = ImagePicker();

Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) =>
    _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2048);

Future<List<XFile>> pickImages({int limit = maxAlbumImages}) => _picker.pickMultiImage(imageQuality: 85, maxWidth: 2048, limit: limit);

Future<XFile?> pickVideo({ImageSource source = ImageSource.gallery}) => _picker.pickVideo(source: source);

/// POST multipart to one of the `/media/upload*` endpoints, returns the stored url.
Future<String> uploadFile(String endpoint, String path, {String? filename, Duration timeout = const Duration(seconds: 60)}) async {
  final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: filename ?? path.split(Platform.pathSeparator).last)});
  final res = await Api.dio.post(
    endpoint.startsWith('/') ? endpoint.substring(1) : endpoint,
    data: form,
    options: Options(sendTimeout: timeout, receiveTimeout: timeout),
  );
  final data = res.data;
  final url = data is Map ? (data['url'] ?? (data['data'] is Map ? data['data']['url'] : null)) : null;
  if (url is! String || url.isEmpty) throw Exception('Invalid upload response');
  return url;
}

Future<File> _download(String url, String name) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await Api.dio.download(Api.absoluteUrl(url)!, file.path);
  return file;
}

String _ext(String url, String fallback) {
  final m = RegExp(r'\.([a-z0-9]{2,5})(\?|$)', caseSensitive: false).firstMatch(url);
  return m?.group(1) ?? fallback;
}

/// utils/mediaDownload.js — fetch then hand off to the system share sheet (Save to Photos / Files).
Future<void> downloadMediaUrl(String url, {String kind = 'image', String? filename}) async {
  final fallback = kind == 'video' ? 'mp4' : kind == 'audio' ? 'webm' : 'jpg';
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
  final content = msg.str('content').trim();
  if (content.isEmpty) return false;
  if (type == 'album') return parseAlbumMessage(content)?.isNotEmpty ?? false;
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
  await downloadMediaUrl(content, kind: type);
}
