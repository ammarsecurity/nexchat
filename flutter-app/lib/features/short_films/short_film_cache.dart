import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import 'short_film_downloads.dart';
import 'short_films_controller.dart';

const maxCacheBytes = 300 * 1024 * 1024;
const maxConcurrentDownloads = 2;
const prefetchAhead = 3;

enum CachePriority { high, normal, low }

class _Job {
  _Job(this.film, this.priority);
  final ShortFilm film;
  CachePriority priority;
}

/// services/shortFilmCache.js — videos stored on disk with an LRU cap and a small priority queue.
class ShortFilmCache {
  ShortFilmCache._();
  static final instance = ShortFilmCache._();

  Directory? _dir;
  final Map<String, String> _state = {};
  final List<_Job> _queue = [];
  final Map<String, int> _inUse = {};
  final _cachedCtrl = StreamController<String>.broadcast();
  int _active = 0;

  /// Fires with film id when a full-file cache download finishes.
  Stream<String> get onCached => _cachedCtrl.stream;

  void markInUse(String id) => _inUse[id] = (_inUse[id] ?? 0) + 1;

  void releaseInUse(String id) {
    final n = (_inUse[id] ?? 0) - 1;
    if (n <= 0) {
      _inUse.remove(id);
    } else {
      _inUse[id] = n;
    }
  }

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationCacheDirectory();
    final d = Directory('${base.path}/short_films');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  Future<File> _fileFor(String id) async => File('${(await _root()).path}/$id.mp4');

  Future<File?> cachedVideo(String id) async {
    final f = await _fileFor(id);
    if (!f.existsSync()) return null;
    try {
      f.setLastModifiedSync(DateTime.now());
    } catch (_) {}
    return f;
  }

  /// Offline download → LRU cache → network url.
  /// Does **not** enqueue a full download for [film] (avoids racing the streamer).
  /// Neighbors are queued via [prefetchAround].
  Future<Uri?> resolveVideoPlayback(ShortFilm film) async {
    final url = Api.absoluteUrl(film.videoUrl);
    if (url == null) return null;
    final offline = await ShortFilmDownloads.instance.fileFor(film.id);
    if (offline != null) return Uri.file(offline.path);
    final cached = await cachedVideo(film.id);
    if (cached != null) return Uri.file(cached.path);
    return Uri.parse(url);
  }

  void prefetchFilms(Iterable<ShortFilm> films, {CachePriority priority = CachePriority.normal}) {
    for (final f in films) {
      enqueue(f, priority);
    }
  }

  /// Prefetch upcoming films only (skip current — it's already streaming).
  void prefetchAround(List<ShortFilm> films, int index) {
    if (films.isEmpty) return;
    final i = index.clamp(0, films.length - 1);
    prefetchFilms(
      [for (var o = 1; o <= prefetchAhead; o++) if (i + o < films.length) films[i + o]],
      priority: CachePriority.high,
    );
  }

  void enqueue(ShortFilm film, CachePriority priority) {
    if (film.videoUrl == null || film.id.isEmpty) return;
    final s = _state[film.id];
    if (s == 'done' || s == 'downloading') return;
    final existing = _queue.where((j) => j.film.id == film.id).firstOrNull;
    if (existing != null) {
      if (existing.priority.index > priority.index) existing.priority = priority;
    } else {
      _queue.add(_Job(film, priority));
    }
    _queue.sort((a, b) => a.priority.index - b.priority.index);
    _pump();
  }

  void _pump() {
    while (_active < maxConcurrentDownloads && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      _download(job.film).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  Future<void> _download(ShortFilm film) async {
    final target = await _fileFor(film.id);
    if (target.existsSync()) {
      _state[film.id] = 'done';
      if (!_cachedCtrl.isClosed) _cachedCtrl.add(film.id);
      return;
    }
    _state[film.id] = 'downloading';
    final tmp = File('${target.path}.part');
    try {
      await Api.dio.download(Api.absoluteUrl(film.videoUrl)!, tmp.path);
      final size = tmp.lengthSync();
      await _evictIfNeeded(size);
      if (await _totalBytes() + size > maxCacheBytes) {
        tmp.deleteSync();
        _state[film.id] = 'failed';
        return;
      }
      tmp.renameSync(target.path);
      _state[film.id] = 'done';
      if (!_cachedCtrl.isClosed) _cachedCtrl.add(film.id);
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      _state[film.id] = 'failed';
    }
  }

  Future<List<File>> _files() async =>
      (await _root()).listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();

  Future<int> _totalBytes() async {
    var total = 0;
    for (final f in await _files()) {
      total += f.lengthSync();
    }
    return total;
  }

  Future<void> _evictIfNeeded(int required) async {
    var total = await _totalBytes();
    if (total + required <= maxCacheBytes) return;
    final files = await _files()
      ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final f in files) {
      if (total + required <= maxCacheBytes) break;
      final id = f.uri.pathSegments.last.replaceAll('.mp4', '');
      if (_inUse.containsKey(id)) continue;
      final size = f.lengthSync();
      try {
        f.deleteSync();
      } catch (_) {
        continue;
      }
      _state.remove(id);
      total -= size;
    }
  }

  Future<void> clear() async {
    _queue.clear();
    _state.clear();
    try {
      final d = await _root();
      if (d.existsSync()) {
        d.deleteSync(recursive: true);
        d.createSync(recursive: true);
      }
    } catch (_) {}
  }
}
