import '../../core/storage/prefs.dart';

class ContinueWatchItem {
  const ContinueWatchItem({
    required this.filmId,
    required this.position,
    required this.updatedAt,
    this.duration,
  });
  final String filmId;
  final Duration position;
  final DateTime updatedAt;
  final Duration? duration;

  double get fraction {
    final d = duration;
    if (d == null || d.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Persists per-film / episode watch position so returning resumes the timeline.
class ShortFilmProgress {
  ShortFilmProgress._();

  static const _prefix = 'nexchat_film_progress_';
  static const _durPrefix = 'nexchat_film_progress_dur_';
  static const _atPrefix = 'nexchat_film_progress_at_';
  static const _minResume = Duration(seconds: 3);
  static const _endMargin = Duration(seconds: 5);

  static String _key(String filmId) => '$_prefix$filmId';
  static String _durKey(String filmId) => '$_durPrefix$filmId';
  static String _atKey(String filmId) => '$_atPrefix$filmId';

  static Duration? get(String filmId) {
    if (filmId.isEmpty) return null;
    final ms = Prefs.instance.sp.getInt(_key(filmId));
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  static Future<void> save(String filmId, Duration position, {Duration? duration}) async {
    if (filmId.isEmpty) return;
    if (position < _minResume) {
      await clear(filmId);
      return;
    }
    if (duration != null && duration > Duration.zero) {
      final remaining = duration - position;
      if (remaining <= _endMargin) {
        await clear(filmId);
        return;
      }
      await Prefs.instance.sp.setInt(_durKey(filmId), duration.inMilliseconds);
    }
    await Prefs.instance.sp.setInt(_key(filmId), position.inMilliseconds);
    await Prefs.instance.sp.setInt(_atKey(filmId), DateTime.now().toUtc().millisecondsSinceEpoch);
  }

  static Future<void> clear(String filmId) async {
    if (filmId.isEmpty) return;
    final sp = Prefs.instance.sp;
    await sp.remove(_key(filmId));
    await sp.remove(_durKey(filmId));
    await sp.remove(_atKey(filmId));
  }

  /// Position to seek when (re)starting playback, or null to start from zero.
  static Duration? resumeAt(String filmId, Duration duration) {
    final saved = get(filmId);
    if (saved == null || saved < _minResume) return null;
    if (duration > Duration.zero && saved >= duration - _endMargin) {
      clear(filmId);
      return null;
    }
    if (duration > Duration.zero && saved >= duration) return null;
    return saved;
  }

  /// Recent in-progress films, newest first (max [limit]).
  static List<ContinueWatchItem> listContinue({int limit = 20}) {
    final sp = Prefs.instance.sp;
    final items = <ContinueWatchItem>[];
    for (final key in sp.getKeys()) {
      if (!key.startsWith(_prefix) || key.startsWith(_durPrefix) || key.startsWith(_atPrefix)) continue;
      final filmId = key.substring(_prefix.length);
      if (filmId.isEmpty) continue;
      final ms = sp.getInt(key);
      if (ms == null || ms < _minResume.inMilliseconds) continue;
      final durMs = sp.getInt(_durKey(filmId));
      final atMs = sp.getInt(_atKey(filmId)) ?? 0;
      items.add(ContinueWatchItem(
        filmId: filmId,
        position: Duration(milliseconds: ms),
        duration: durMs != null && durMs > 0 ? Duration(milliseconds: durMs) : null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true),
      ));
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (items.length <= limit) return items;
    return items.sublist(0, limit);
  }
}
