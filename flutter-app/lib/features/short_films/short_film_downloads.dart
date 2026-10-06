import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/prefs.dart';
import '../../services/media.dart';
import 'short_films_controller.dart';

/// Persistent offline copies (separate from the LRU playback cache).
class ShortFilmDownloads {
  ShortFilmDownloads._();
  static final instance = ShortFilmDownloads._();

  static const _idsKey = 'nexchat_film_downloads';
  static const _metaKey = 'nexchat_film_download_meta';

  final _busy = <String>{};

  bool isBusy(String id) => _busy.contains(id);

  Set<String> ids() {
    final raw = Prefs.instance.getString(_idsKey);
    if (raw == null || raw.isEmpty) return {};
    return raw.split(',').where((e) => e.isNotEmpty).toSet();
  }

  Future<void> _setIds(Set<String> next) => Prefs.instance.setString(_idsKey, next.join(','));

  Map<String, Map<String, dynamic>> _metaMap() {
    final raw = Prefs.instance.getString(_metaKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is Map)
            e.key as String: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _setMetaMap(Map<String, Map<String, dynamic>> map) =>
      Prefs.instance.setString(_metaKey, jsonEncode(map));

  Future<void> saveMeta(ShortFilm film) async {
    final map = _metaMap();
    map[film.id] = {
      'id': film.id,
      'title': film.title,
      'description': film.description,
      'videoUrl': film.videoUrl,
      'thumbnailUrl': film.thumbnailUrl,
      'durationSeconds': film.durationSeconds,
      'sectionId': film.sectionId,
      'sectionName': film.sectionName,
      'seriesId': film.seriesId,
      'seriesTitle': film.seriesTitle,
      'episodeNumber': film.episodeNumber,
      'episodesCount': film.episodesCount,
      'isFeatured': film.isFeatured,
      'viewCount': film.viewCount,
    };
    await _setMetaMap(map);
  }

  ShortFilm? metaFilm(String id) {
    final m = _metaMap()[id];
    if (m == null) return null;
    return ShortFilm.fromJson(m);
  }

  Future<List<ShortFilm>> listFilms() async {
    final out = <ShortFilm>[];
    for (final id in ids()) {
      final file = await fileFor(id);
      if (file == null) continue;
      out.add(metaFilm(id) ?? ShortFilm(id: id, title: id));
    }
    return out;
  }

  Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final d = Directory('${root.path}/short_film_downloads');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File?> fileFor(String filmId) async {
    final f = File('${(await _dir()).path}/$filmId.mp4');
    return f.existsSync() ? f : null;
  }

  Future<bool> isDownloaded(String filmId) async => (await fileFor(filmId)) != null;

  Future<File?> download(ShortFilm film, {void Function(double)? onProgress}) async {
    final id = film.id;
    final url = film.videoUrl;
    if (url == null || url.isEmpty) throw StateError('no_url');
    if (_busy.contains(id)) return fileFor(id);
    _busy.add(id);
    try {
      final absolute = Api.absoluteUrl(url) ?? url;
      final dest = File('${(await _dir()).path}/$id.mp4');
      await publicMediaClient.download(
        absolute,
        dest.path,
        onReceiveProgress: (r, t) {
          if (t > 0) onProgress?.call(r / t);
        },
      );
      final next = ids()..add(id);
      await _setIds(next);
      await saveMeta(film);
      return dest;
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> remove(String filmId) async {
    final f = await fileFor(filmId);
    if (f != null && await f.exists()) await f.delete();
    final next = ids()..remove(filmId);
    await _setIds(next);
    final map = _metaMap()..remove(filmId);
    await _setMetaMap(map);
  }
}
