import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import 'short_film_cache.dart';

const _pageSize = 12;

class ShortFilm {
  const ShortFilm({
    required this.id,
    required this.title,
    this.description,
    this.videoUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.sectionId,
    this.sectionName,
    this.seriesId,
    this.seriesTitle,
    this.episodeNumber,
    this.episodesCount,
    this.isFeatured = false,
    this.viewCount = 0,
  });

  final String id;
  final String title;
  final String? description;
  final String? videoUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String? sectionId;
  final String? sectionName;
  final String? seriesId;
  final String? seriesTitle;
  final int? episodeNumber;
  final int? episodesCount;
  final bool isFeatured;
  final int viewCount;

  bool get isEpisode => seriesId != null && seriesId!.isNotEmpty;

  String get displaySubtitle {
    if (isEpisode && episodeNumber != null) {
      final name = (seriesTitle != null && seriesTitle!.isNotEmpty) ? seriesTitle! : title;
      return '$name · ${t('shortFilms.episodeN', {'n': '$episodeNumber'})}';
    }
    return title;
  }

  factory ShortFilm.fromJson(Map f) => ShortFilm(
        id: f.str('id'),
        title: f.str('title'),
        description: f.s('description'),
        videoUrl: f.s('videoUrl'),
        thumbnailUrl: f.s('thumbnailUrl'),
        durationSeconds: f.v('durationSeconds') == null ? null : f.i('durationSeconds'),
        sectionId: f.s('sectionId'),
        sectionName: f.s('sectionName'),
        seriesId: f.s('seriesId'),
        seriesTitle: f.s('seriesTitle'),
        episodeNumber: f.v('episodeNumber') == null ? null : f.i('episodeNumber'),
        episodesCount: f.v('episodesCount') == null ? null : f.i('episodesCount'),
        isFeatured: f.b('isFeatured'),
        viewCount: f.i('viewCount'),
      );

  ShortFilm withViews(int n) => ShortFilm(
        id: id,
        title: title,
        description: description,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        durationSeconds: durationSeconds,
        sectionId: sectionId,
        sectionName: sectionName,
        seriesId: seriesId,
        seriesTitle: seriesTitle,
        episodeNumber: episodeNumber,
        episodesCount: episodesCount,
        isFeatured: isFeatured,
        viewCount: n,
      );
}

class FilmSeries {
  const FilmSeries({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    this.sectionId,
    this.sectionName,
    this.isFeatured = false,
    this.episodesCount = 0,
    this.episodes = const [],
  });

  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final String? sectionId;
  final String? sectionName;
  final bool isFeatured;
  final int episodesCount;
  final List<ShortFilm> episodes;

  factory FilmSeries.fromJson(Map s) => FilmSeries(
        id: s.str('id'),
        title: s.str('title'),
        description: s.s('description'),
        coverUrl: s.s('coverUrl'),
        sectionId: s.s('sectionId'),
        sectionName: s.s('sectionName'),
        isFeatured: s.b('isFeatured'),
        episodesCount: s.i('episodesCount'),
        episodes: asJsonList(s.v('episodes')).map(ShortFilm.fromJson).toList(),
      );
}

class FilmSection {
  const FilmSection({required this.id, required this.name, this.imageUrl, this.films = const []});
  final String id;
  final String name;
  final String? imageUrl;
  final List<ShortFilm> films;

  factory FilmSection.fromJson(Map s) => FilmSection(
        id: s.str('id'),
        name: s.str('name'),
        imageUrl: s.s('imageUrl'),
        films: asJsonList(s.v('films')).map(ShortFilm.fromJson).toList(),
      );
}

class ShortFilmsState {
  const ShortFilmsState({
    this.list = const [],
    this.featured = const [],
    this.series = const [],
    this.sections = const [],
    this.sectionBrowse = const [],
    this.uncategorizedBrowse = const [],
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.page = 1,
    this.total = 0,
    this.hasMore = true,
    this.selectedSectionId,
    this.searchQuery = '',
  });

  final List<ShortFilm> list;
  final List<ShortFilm> featured;
  final List<FilmSeries> series;
  final List<FilmSection> sections;
  final List<FilmSection> sectionBrowse;
  final List<ShortFilm> uncategorizedBrowse;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final int page;
  final int total;
  final bool hasMore;
  final String? selectedSectionId;
  final String searchQuery;

  bool get isSearching => searchQuery.trim().isNotEmpty;

  List<FilmSeries> get visibleSeries {
    final section = selectedSectionId;
    var rows = section == null ? series : series.where((s) => s.sectionId == section);
    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((s) =>
          s.title.toLowerCase().contains(q) ||
          (s.description?.toLowerCase().contains(q) ?? false));
    }
    return rows.toList();
  }

  List<ShortFilm> get gridFilms {
    final ids = featured.map((f) => f.id).toSet();
    final q = searchQuery.trim();
    // When searching, show all matching films (including episodes).
    if (q.isNotEmpty) return list.where((f) => !ids.contains(f.id)).toList();
    return list.where((f) => !ids.contains(f.id) && !f.isEpisode).toList();
  }

  List<ShortFilm> get visibleFeatured {
    if (isSearching || selectedSectionId != null) return const [];
    return featured;
  }

  /// Feed order: featured → section browse → uncategorized → paged list (deduped).
  List<ShortFilm> get feed {
    final seen = <String>{};
    final out = <ShortFilm>[];
    void add(ShortFilm f) {
      if (seen.add(f.id)) out.add(f);
    }

    featured.forEach(add);
    for (final row in sectionBrowse) {
      row.films.forEach(add);
    }
    uncategorizedBrowse.forEach(add);
    list.forEach(add);
    return out;
  }

  ShortFilmsState copyWith({
    List<ShortFilm>? list,
    List<ShortFilm>? featured,
    List<FilmSeries>? series,
    List<FilmSection>? sections,
    List<FilmSection>? sectionBrowse,
    List<ShortFilm>? uncategorizedBrowse,
    bool? loading,
    bool? loadingMore,
    bool? loaded,
    int? page,
    int? total,
    bool? hasMore,
    String? Function()? selectedSectionId,
    String? searchQuery,
  }) =>
      ShortFilmsState(
        list: list ?? this.list,
        featured: featured ?? this.featured,
        series: series ?? this.series,
        sections: sections ?? this.sections,
        sectionBrowse: sectionBrowse ?? this.sectionBrowse,
        uncategorizedBrowse: uncategorizedBrowse ?? this.uncategorizedBrowse,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        loaded: loaded ?? this.loaded,
        page: page ?? this.page,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        selectedSectionId: selectedSectionId != null ? selectedSectionId() : this.selectedSectionId,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

/// stores/shortFilms.js
class ShortFilmsController extends Notifier<ShortFilmsState> {
  final Set<String> _viewed = {};
  Timer? _searchDebounce;

  @override
  ShortFilmsState build() {
    ref.onDispose(() => _searchDebounce?.cancel());
    return const ShortFilmsState();
  }

  ShortFilmsState get current => state;

  Future<void> fetchSections() async {
    try {
      final data = await Api.get('/short-films/sections');
      state = state.copyWith(sections: asJsonList(data).map(FilmSection.fromJson).toList());
    } catch (_) {}
  }

  Future<void> fetchSeriesList({String? search}) async {
    try {
      final q = (search ?? state.searchQuery).trim();
      final data = await Api.get('/short-films/series', query: {
        'sectionId': ?state.selectedSectionId,
        if (q.isNotEmpty) 'search': q,
      });
      state = state.copyWith(series: asJsonList(data).map(FilmSeries.fromJson).toList());
    } catch (_) {}
  }

  Future<FilmSeries?> fetchSeriesDetail(String id) async {
    try {
      final data = await Api.get('/short-films/series/$id');
      if (data is! Map) return null;
      return FilmSeries.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<ShortFilm?> fetchById(String id) async {
    if (id.isEmpty) return null;
    try {
      final data = await Api.get('/short-films/$id');
      if (data is! Map) return null;
      return ShortFilm.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchBrowse({int previewSize = 8}) async {
    try {
      final data = await Api.get('/short-films/browse', query: {'previewSize': previewSize});
      final m = data is Map ? data : const {};
      state = state.copyWith(
        sectionBrowse: asJsonList(m.v('sections')).map(FilmSection.fromJson).toList(),
        uncategorizedBrowse: asJsonList(m.v('uncategorizedFilms')).map(ShortFilm.fromJson).toList(),
      );
    } catch (_) {}
  }

  Future<void> fetchPage({bool reset = false}) async {
    if (state.loading || state.loadingMore) return;
    if (!reset && !state.hasMore) return;
    state = reset ? state.copyWith(page: 1, hasMore: true, loading: true) : state.copyWith(loadingMore: true);
    final section = state.selectedSectionId;
    final search = state.searchQuery.trim();
    final searching = search.isNotEmpty;
    try {
      final params = <String, dynamic>{
        'page': state.page,
        'pageSize': _pageSize,
        'excludeFeatured': !searching,
        'standaloneOnly': !searching,
        'sectionId': ?section,
        if (searching) 'search': search,
      };
      if (reset) {
        if (searching) {
          await Future.wait([fetchSections(), fetchSeriesList(search: search)]);
          state = state.copyWith(featured: const []);
        } else {
          final (featured, _) = await (
            Api.get('/short-films/featured', query: {'sectionId': ?section}),
            Future.wait([fetchSections(), fetchSeriesList()]),
          ).wait;
          state = state.copyWith(featured: asJsonList(featured).map(ShortFilm.fromJson).toList());
        }
      }
      final data = await Api.get('/short-films', query: params);
      final m = data is Map ? data : const {};
      final items = asJsonList(m.v('items')).map(ShortFilm.fromJson).toList();
      List<ShortFilm> list;
      if (reset) {
        list = items;
      } else {
        final ids = state.list.map((f) => f.id).toSet();
        list = [...state.list, ...items.where((f) => ids.add(f.id))];
      }
      final total = m.v('total') == null ? list.length : m.i('total');
      final hasMore = m.v('hasMore') != null ? m.b('hasMore') : state.page * _pageSize < total;
      state = state.copyWith(list: list, total: total, hasMore: hasMore, page: state.page + 1, loaded: true);
      if (reset && !searching) ShortFilmCache.instance.prefetchFilms(state.featured, priority: CachePriority.high);
    } catch (_) {
      if (reset && !state.loaded) {
        state = state.copyWith(list: const [], featured: const [], series: const [], total: 0, hasMore: false);
      }
    } finally {
      state = state.copyWith(loading: false, loadingMore: false);
    }
  }

  Future<void> fetchAll({bool force = false}) async {
    if (state.loading && !force) return;
    if (state.loaded && !force) return;
    await fetchPage(reset: true);
  }

  Future<void> setSection(String? sectionId) async {
    if (state.selectedSectionId == sectionId) return;
    state = state.copyWith(selectedSectionId: () => sectionId);
    await fetchPage(reset: true);
  }

  void setSearch(String query) {
    final next = query.trimLeft();
    if (next == state.searchQuery) return;
    state = state.copyWith(searchQuery: next);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      fetchPage(reset: true);
    });
  }

  Future<void> clearSearch() async {
    _searchDebounce?.cancel();
    if (state.searchQuery.isEmpty) return;
    state = state.copyWith(searchQuery: '');
    await fetchPage(reset: true);
  }

  Future<void> loadMore() => fetchPage();

  void invalidate() {
    _searchDebounce?.cancel();
    _viewed.clear();
    state = const ShortFilmsState();
    ShortFilmCache.instance.clear();
  }

  void _patchViews(String id, int Function(int) f) {
    List<ShortFilm> patch(List<ShortFilm> l) => [for (final x in l) x.id == id ? x.withViews(f(x.viewCount)) : x];
    state = state.copyWith(
      list: patch(state.list),
      featured: patch(state.featured),
      uncategorizedBrowse: patch(state.uncategorizedBrowse),
      sectionBrowse: [for (final r in state.sectionBrowse) FilmSection(id: r.id, name: r.name, imageUrl: r.imageUrl, films: patch(r.films))],
    );
  }

  Future<void> recordView(String id) async {
    if (id.isEmpty || !_viewed.add(id)) return;
    try {
      final res = await Api.post('/short-films/$id/view', const {});
      final count = res is Map && res.v('viewCount') != null ? res.i('viewCount') : null;
      _patchViews(id, (n) => count ?? n + 1);
    } catch (_) {
      _viewed.remove(id);
    }
  }
}

final shortFilmsProvider = NotifierProvider<ShortFilmsController, ShortFilmsState>(ShortFilmsController.new);

String formatFilmDuration(int? sec) {
  if (sec == null || sec == 0) return '';
  final m = sec ~/ 60, s = sec % 60;
  return m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '${s}s';
}
