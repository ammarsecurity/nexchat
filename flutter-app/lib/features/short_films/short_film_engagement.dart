import '../../core/json.dart';
import '../../core/network/api_client.dart';
import 'short_films_controller.dart';

class FilmEngagement {
  const FilmEngagement({
    this.liked = false,
    this.watchLater = false,
    this.reaction,
    this.followingSeries = false,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  final bool liked;
  final bool watchLater;
  final String? reaction;
  final bool followingSeries;
  final int likeCount;
  final int commentCount;

  factory FilmEngagement.fromJson(Map m) => FilmEngagement(
        liked: m.b('liked'),
        watchLater: m.b('watchLater'),
        reaction: m.s('reaction'),
        followingSeries: m.b('followingSeries'),
        likeCount: m.i('likeCount'),
        commentCount: m.i('commentCount'),
      );

  FilmEngagement copyWith({
    bool? liked,
    bool? watchLater,
    String? Function()? reaction,
    bool? followingSeries,
    int? likeCount,
    int? commentCount,
  }) =>
      FilmEngagement(
        liked: liked ?? this.liked,
        watchLater: watchLater ?? this.watchLater,
        reaction: reaction != null ? reaction() : this.reaction,
        followingSeries: followingSeries ?? this.followingSeries,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
      );
}

class ShortFilmEngagementApi {
  ShortFilmEngagementApi._();
  static final instance = ShortFilmEngagementApi._();

  Future<FilmEngagement> get(String filmId) async {
    final data = await Api.get('/short-films/me/engagement/$filmId');
    if (data is Map) return FilmEngagement.fromJson(data);
    return const FilmEngagement();
  }

  Future<void> setLiked(String filmId, bool liked) async {
    if (liked) {
      await Api.post('/short-films/films/$filmId/like', const {});
    } else {
      await Api.delete('/short-films/films/$filmId/like');
    }
  }

  Future<void> setWatchLater(String filmId, bool on) async {
    if (on) {
      await Api.post('/short-films/films/$filmId/watch-later', const {});
    } else {
      await Api.delete('/short-films/films/$filmId/watch-later');
    }
  }

  Future<void> setReaction(String filmId, String? emoji) async {
    if (emoji == null || emoji.isEmpty) {
      await Api.delete('/short-films/films/$filmId/reaction');
    } else {
      await Api.put('/short-films/films/$filmId/reaction', {'emoji': emoji});
    }
  }

  Future<void> setFollowSeries(String seriesId, bool on) async {
    if (on) {
      await Api.post('/short-films/series/$seriesId/follow', const {});
    } else {
      await Api.delete('/short-films/series/$seriesId/follow');
    }
  }

  Future<List<ShortFilm>> recommended() async {
    final data = await Api.get('/short-films/recommended');
    return asJsonList(data).map(ShortFilm.fromJson).toList();
  }

  Future<List<ShortFilm>> watchLaterList() async {
    final data = await Api.get('/short-films/me/watch-later');
    return asJsonList(data).map(ShortFilm.fromJson).toList();
  }

  Future<List<ShortFilm>> likesList() async {
    final data = await Api.get('/short-films/me/likes');
    return asJsonList(data).map(ShortFilm.fromJson).toList();
  }

  Future<Set<String>> followingSeriesIds() async {
    final data = await Api.get('/short-films/me/following-series');
    if (data is! Map) return {};
    final raw = data.v('seriesIds');
    if (raw is! List) return {};
    return {for (final e in raw) '$e'.trim()}.where((e) => e.isNotEmpty).toSet();
  }
}
