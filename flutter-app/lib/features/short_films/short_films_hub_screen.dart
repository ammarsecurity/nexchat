import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/layout.dart';
import '../../shared/video_poster.dart';
import 'short_film_engagement.dart';
import 'short_film_progress.dart';
import 'short_films_controller.dart';
import 'short_films_theme.dart';

/// DramaWave-style discovery home for short films.
class ShortFilmsHubScreen extends ConsumerStatefulWidget {
  const ShortFilmsHubScreen({super.key});

  @override
  ConsumerState<ShortFilmsHubScreen> createState() => _ShortFilmsHubScreenState();
}

class _ShortFilmsHubScreenState extends ConsumerState<ShortFilmsHubScreen> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  final _heroPage = PageController(viewportFraction: 0.92);
  int _heroIndex = 0;
  List<({ContinueWatchItem progress, ShortFilm film})> _continue = const [];
  List<ShortFilm> _recommended = const [];
  List<ShortFilm> _watchLater = const [];

  ShortFilmsController get _store => ref.read(shortFilmsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(() async {
      await _store.fetchAll(force: true);
      await Future.wait([_loadContinue(), _loadLibrary()]);
    });
  }

  Future<void> _loadLibrary() async {
    try {
      final (reco, later) = await (
        ShortFilmEngagementApi.instance.recommended(),
        ShortFilmEngagementApi.instance.watchLaterList(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _recommended = reco;
        _watchLater = later;
      });
    } catch (_) {}
  }

  Future<void> _loadContinue() async {
    final rows = ShortFilmProgress.listContinue(limit: 12);
    if (rows.isEmpty) {
      if (mounted) setState(() => _continue = const []);
      return;
    }
    final store = _store;
    final out = <({ContinueWatchItem progress, ShortFilm film})>[];
    for (final row in rows) {
      ShortFilm? film = store.current.feed.where((f) => f.id == row.filmId).firstOrNull ??
          store.current.featured.where((f) => f.id == row.filmId).firstOrNull;
      film ??= await store.fetchById(row.filmId);
      if (film != null) out.add((progress: row, film: film));
    }
    if (mounted) setState(() => _continue = out);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _spin.dispose();
    _heroPage.dispose();
    super.dispose();
  }

  void _onScroll() {
    final st = _store.current;
    if (!_scroll.hasClients || !st.hasMore || st.loadingMore || st.loading) return;
    if (_scroll.position.extentAfter < 160) _store.loadMore();
  }

  void _fillViewport() {
    if (!mounted || !_scroll.hasClients || !_store.current.hasMore) return;
    if (_scroll.position.maxScrollExtent < 160) _onScroll();
  }

  void _openFilm(ShortFilm f) {
    if (f.seriesId != null && f.seriesId!.isNotEmpty) {
      context.push('/short-films/watch?start=${f.id}&series=${f.seriesId}');
    } else {
      context.push('/short-films/watch?start=${f.id}');
    }
  }

  void _openSeries(FilmSeries s) => context.push('/short-films/series/${s.id}');

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(shortFilmsProvider);
    ref.listen(shortFilmsProvider, (prev, next) {
      final wasBusy = prev == null || prev.loading || prev.loadingMore;
      if (wasBusy && !next.loading && !next.loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
      }
    });
    if (st.loading || st.loadingMore) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    final featured = st.visibleFeatured;
    final showFeatured = featured.isNotEmpty;
    final series = st.visibleSeries;
    final grid = st.gridFilms;
    final searching = st.isSearching;
    final gridTitle = searching
        ? t('common.search')
        : st.selectedSectionId == null
            ? t('shortFilms.allFilms')
            : st.sections.where((s) => s.id == st.selectedSectionId).firstOrNull?.name ?? t('shortFilms.allFilms');
    final bottom = tabScrollPadding(context, extra: 16);
    final emptyResults = st.loaded && !st.loading && featured.isEmpty && grid.isEmpty && series.isEmpty;
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final w = MediaQuery.sizeOf(context).width;
    final rowCardW = shortFilmRowCardWidth(w);
    final gridCols = shortFilmGridColumns(w);

    Widget content;
    if (st.loading && !st.loaded) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(children: [
          RotationTransition(
            turns: _spin,
            child: const Icon(LucideIcons.refreshCw, size: 28, color: DramaWave.gold),
          ),
          const SizedBox(height: 12),
          Text(t('common.loading'), style: DramaWave.body()),
        ]),
      );
    } else if (emptyResults) {
      content = DramaWaveEmpty(
        icon: LucideIcons.film,
        text: searching ? t('shortFilms.noSearchResults') : t('shortFilms.empty'),
      );
    } else {
      final showContinue = _continue.isNotEmpty && !searching && st.selectedSectionId == null;
      final showReco = _recommended.isNotEmpty && !searching && st.selectedSectionId == null;
      final showLater = _watchLater.isNotEmpty && !searching && st.selectedSectionId == null;

      content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showFeatured && !searching && st.selectedSectionId == null) ...[
          _FeaturedHero(
            films: featured.take(8).toList(),
            controller: _heroPage,
            index: _heroIndex,
            onIndex: (i) => setState(() => _heroIndex = i),
            onPlay: _openFilm,
          ),
          const SizedBox(height: 18),
        ],
        if (showContinue) ...[
          _SectionTitle(t('shortFilms.continueWatching')),
          SizedBox(
            height: rowCardW * 14 / 9 + 8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _continue.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final item = _continue[i];
                return SizedBox(
                  width: rowCardW,
                  child: _ContinueCard(
                    film: item.film,
                    fraction: item.progress.fraction,
                    onTap: () => _openFilm(item.film),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (showReco) ...[
          _SectionTitle(t('shortFilms.recommended')),
          SizedBox(
            height: rowCardW * 14 / 9,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recommended.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: rowCardW,
                child: FilmCard(film: _recommended[i], onTap: () => _openFilm(_recommended[i])),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (series.isNotEmpty && !searching) ...[
          _SectionTitle(
            t('shortFilms.ranking'),
            onSeeAll: () => context.push('/short-films/catalog?kind=series'),
          ),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: series.take(12).length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final s = series[i];
                return _RankingCard(
                  rank: i + 1,
                  title: s.title,
                  subtitle: t('shortFilms.episodesCount').replaceAll('{n}', '${s.episodesCount}'),
                  coverUrl: s.coverUrl,
                  onTap: () => _openSeries(s),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (showLater) ...[
          _SectionTitle(
            t('shortFilms.watchLater'),
            onSeeAll: () => context.push('/short-films/library?tab=watch-later'),
          ),
          SizedBox(
            height: rowCardW * 14 / 9,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _watchLater.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: rowCardW,
                child: FilmCard(film: _watchLater[i], onTap: () => _openFilm(_watchLater[i])),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (series.isNotEmpty) ...[
          _SectionTitle(
            t('shortFilms.series'),
            onSeeAll: () => context.push('/short-films/catalog?kind=series'),
          ),
          SizedBox(
            height: rowCardW * 14 / 9 + 4,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: series.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: rowCardW,
                child: SeriesCard(series: series[i], onTap: () => _openSeries(series[i])),
              ),
            ),
          ),
          if (grid.isNotEmpty) const SizedBox(height: 20),
        ],
        if (grid.isNotEmpty) ...[
          _SectionTitle(
            gridTitle,
            onSeeAll: searching || st.selectedSectionId != null
                ? null
                : () => context.push('/short-films/catalog?kind=films'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCols,
                crossAxisSpacing: w <= 360 ? 6 : 10,
                mainAxisSpacing: w <= 360 ? 6 : 10,
                childAspectRatio: 9 / 14,
              ),
              itemCount: grid.length,
              itemBuilder: (_, i) => FilmCard(film: grid[i], onTap: () => _openFilm(grid[i]), small: true),
            ),
          ),
        ],
        Container(
          constraints: const BoxConstraints(minHeight: 40),
          margin: const EdgeInsets.only(top: 8),
          alignment: Alignment.center,
          child: st.loadingMore
              ? RotationTransition(
                  turns: _spin,
                  child: const Icon(LucideIcons.refreshCw, size: 20, color: DramaWave.muted),
                )
              : null,
        ),
      ]);
    }

    return Scaffold(
      backgroundColor: DramaWave.bg,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, pad.top + 4, 8, 0),
          child: Row(
            children: [
              _HubIconBtn(
                icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              Expanded(
                child: Text(
                  t('shortFilms.title'),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: DramaWave.title(size: 17),
                ),
              ),
              _HubIconBtn(
                icon: LucideIcons.bookmark,
                onTap: () => context.push('/short-films/library?tab=watch-later'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _HubSearchBar(
            controller: _search,
            hint: t('shortFilms.searchPlaceholder'),
            onChanged: _store.setSearch,
            showClear: st.searchQuery.isNotEmpty,
            onClear: () {
              _search.clear();
              _store.clearSearch();
            },
          ),
        ),
        if (st.sections.isNotEmpty) ...[
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ShortFilmGenreChip(
                  label: t('shortFilms.allSections'),
                  active: st.selectedSectionId == null,
                  onTap: () => _store.setSection(null),
                ),
                for (final s in st.sections)
                  ShortFilmGenreChip(
                    label: s.name,
                    active: st.selectedSectionId == s.id,
                    onTap: () => _store.setSection(s.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: RefreshIndicator(
            color: DramaWave.gold,
            backgroundColor: DramaWave.elevated,
            onRefresh: () async {
              await _store.fetchAll(force: true);
              await Future.wait([_loadContinue(), _loadLibrary()]);
            },
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: 4, bottom: bottom),
              child: content,
            ),
          ),
        ),
      ]),
    );
  }
}

class _FeaturedHero extends StatelessWidget {
  const _FeaturedHero({
    required this.films,
    required this.controller,
    required this.index,
    required this.onIndex,
    required this.onPlay,
  });
  final List<ShortFilm> films;
  final PageController controller;
  final int index;
  final ValueChanged<int> onIndex;
  final ValueChanged<ShortFilm> onPlay;

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.sizeOf(context).width * 0.78).clamp(260.0, 380.0);
    return Column(
      children: [
        SizedBox(
          height: h,
          child: PageView.builder(
            controller: controller,
            itemCount: films.length,
            onPageChanged: onIndex,
            itemBuilder: (_, i) {
              final film = films[i];
              final active = i == index;
              return AnimatedScale(
                scale: active ? 1 : 0.96,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _HeroSlide(film: film, onPlay: () => onPlay(film)),
                ),
              );
            },
          ),
        ),
        if (films.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < films.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index ? DramaWave.gold : DramaWave.hairline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.film, required this.onPlay});
  final ShortFilm film;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: DramaWave.elevated,
      child: Center(child: Icon(LucideIcons.film, size: 40, color: DramaWave.gold.withValues(alpha: 0.55))),
    );
    Widget thumb;
    if (film.thumbnailUrl != null) {
      thumb = CachedNetworkImage(
        imageUrl: Api.absoluteUrl(film.thumbnailUrl)!,
        fit: BoxFit.cover,
        memCacheWidth: 900,
        errorWidget: (_, _, _) => fallback,
      );
    } else if (film.videoUrl != null) {
      thumb = VideoFramePoster(url: film.videoUrl!, placeholder: fallback);
    } else {
      thumb = fallback;
    }

    return GestureDetector(
      onTap: onPlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumb,
            const DecoratedBox(decoration: BoxDecoration(gradient: DramaWave.heroGradient)),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [DramaWave.gold, DramaWave.goldDeep]),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t('shortFilms.exclusive'),
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    film.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DramaWave.title(size: 20),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onPlay,
                        borderRadius: BorderRadius.circular(24),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [DramaWave.gold, DramaWave.goldDeep]),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: DramaWave.gold.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.play, size: 16, color: Colors.black),
                                const SizedBox(width: 8),
                                Text(
                                  t('shortFilms.playNow'),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
  });
  final int rank;
  final String title;
  final String subtitle;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: DramaWave.elevated,
      child: Icon(LucideIcons.tv, size: 28, color: DramaWave.gold.withValues(alpha: 0.5)),
    );
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverUrl != null && coverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: Api.absoluteUrl(coverUrl)!,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            errorWidget: (_, _, _) => fallback,
                          )
                        : fallback,
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        height: 0.85,
                        color: DramaWave.rankColor(rank),
                        shadows: const [
                          Shadow(color: Color(0xEE000000), blurRadius: 8, offset: Offset(2, 2)),
                        ],
                      ),
                    ),
                  ),
                  if (rank <= 3)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: DramaWave.hot,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          t('shortFilms.hot'),
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DramaWave.title(size: 12)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: DramaWave.body(size: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.onSeeAll});
  final String text;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            margin: const EdgeInsetsDirectional.only(end: 8),
            decoration: BoxDecoration(
              color: DramaWave.gold,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(child: Text(text, style: DramaWave.title(size: 16))),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('shortFilms.seeAll'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DramaWave.soft),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevronLeft
                          : LucideIcons.chevronRight,
                      size: 15,
                      color: DramaWave.soft,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HubIconBtn extends StatelessWidget {
  const _HubIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(icon, size: 22, color: DramaWave.ink),
    );
  }
}

class _HubSearchBar extends StatelessWidget {
  const _HubSearchBar({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.showClear,
    required this.onClear,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool showClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsetsDirectional.only(start: 14, end: 6),
      decoration: BoxDecoration(
        color: DramaWave.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 18, color: DramaWave.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: DramaWave.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: DramaWave.gold,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: DramaWave.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (showClear)
            IconButton(
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(LucideIcons.x, size: 16, color: DramaWave.muted),
            ),
        ],
      ),
    );
  }
}

/// DramaWave-style genre / section pill.
class ShortFilmGenreChip extends StatelessWidget {
  const ShortFilmGenreChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? DramaWave.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active ? DramaWave.gold : DramaWave.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.black : DramaWave.soft,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kept for catalog compatibility — circular section avatar (legacy).
class ShortFilmSectionRing extends StatelessWidget {
  const ShortFilmSectionRing({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.child,
    this.bg,
    this.ringBorder,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget child;
  final Color? bg;
  final Color? ringBorder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 60,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? null : DramaWave.hairline,
                gradient: active
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [DramaWave.gold, DramaWave.goldDeep],
                      )
                    : null,
              ),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg ?? DramaWave.elevated,
                  border: Border.all(color: ringBorder ?? DramaWave.bg, width: 2),
                ),
                child: ClipOval(
                  child: SizedBox.expand(
                    child: child is Icon || child is Text ? Center(child: child) : child,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                color: active ? DramaWave.ink : DramaWave.muted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.film, required this.fraction, required this.onTap});
  final ShortFilm film;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FilmCard(film: film, onTap: onTap),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.05, 1.0),
                child: const ColoredBox(color: DramaWave.gold),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Poster card with DramaWave fade + duration pill.
class FilmCard extends StatelessWidget {
  const FilmCard({super.key, required this.film, required this.onTap, this.small = false});
  final ShortFilm film;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    final fallback = Container(
      color: DramaWave.elevated,
      alignment: Alignment.center,
      child: Icon(LucideIcons.film, size: small ? 22 : 24, color: DramaWave.gold.withValues(alpha: 0.5)),
    );
    Widget thumb;
    if (film.thumbnailUrl != null) {
      thumb = CachedNetworkImage(
        imageUrl: Api.absoluteUrl(film.thumbnailUrl)!,
        fit: BoxFit.cover,
        memCacheWidth: 480,
        errorWidget: (_, _, _) => fallback,
      );
    } else if (film.videoUrl != null) {
      thumb = VideoFramePoster(url: film.videoUrl!, placeholder: fallback);
    } else {
      thumb = fallback;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DramaWave.elevated,
          borderRadius: BorderRadius.circular(narrow ? 10 : 12),
        ),
        child: Stack(fit: StackFit.expand, children: [
          thumb,
          const DecoratedBox(decoration: BoxDecoration(gradient: DramaWave.cardFade)),
          if (film.durationSeconds != null && film.durationSeconds! > 0)
            PositionedDirectional(
              top: 6,
              start: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(5)),
                child: Text(
                  formatFilmDuration(film.durationSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: narrow ? const EdgeInsets.fromLTRB(5, 16, 5, 5) : const EdgeInsets.fromLTRB(7, 20, 7, 7),
              child: Text(
                film.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 10 : 11,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.series, required this.onTap});
  final FilmSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    final fallback = Container(
      color: DramaWave.elevated,
      alignment: Alignment.center,
      child: Icon(LucideIcons.tv, size: 24, color: DramaWave.gold.withValues(alpha: 0.5)),
    );
    final cover = series.coverUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DramaWave.elevated,
          borderRadius: BorderRadius.circular(narrow ? 10 : 12),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (cover != null && cover.isNotEmpty)
            CachedNetworkImage(
              imageUrl: Api.absoluteUrl(cover)!,
              fit: BoxFit.cover,
              memCacheWidth: 480,
              errorWidget: (_, _, _) => fallback,
            )
          else
            fallback,
          const DecoratedBox(decoration: BoxDecoration(gradient: DramaWave.cardFade)),
          PositionedDirectional(
            top: 6,
            start: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(5)),
              child: Text(
                t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: narrow ? const EdgeInsets.fromLTRB(5, 16, 5, 5) : const EdgeInsets.fromLTRB(7, 20, 7, 7),
              child: Text(
                series.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 10 : 11,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
