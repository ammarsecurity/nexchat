import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/video_poster.dart';
import '../../shared/widgets.dart';
import 'short_film_engagement.dart';
import 'short_film_progress.dart';
import 'short_films_controller.dart';

/// Soft slate palette for short-films light mode (matches series detail / library).
abstract final class _HubLight {
  static const sheet = Color(0xFFE6EBF3);
  static const card = Color(0xFFEEF2F8);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const hairline = Color(0x1F0F172A);
  static const shadow = Color(0x14000000);
}

/// views/ShortFilmsHubView.vue
class ShortFilmsHubScreen extends ConsumerStatefulWidget {
  const ShortFilmsHubScreen({super.key});

  @override
  ConsumerState<ShortFilmsHubScreen> createState() => _ShortFilmsHubScreenState();
}

class _ShortFilmsHubScreenState extends ConsumerState<ShortFilmsHubScreen> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
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
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final sheet = light ? _HubLight.sheet : c.bgPrimary;
    final surface = light ? _HubLight.card : c.bgCard;
    final muted = light ? _HubLight.muted : c.textMuted;
    final hairline = light ? _HubLight.hairline : c.border;
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

    Widget content;
    if (st.loading && !st.loaded) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          RotationTransition(turns: _spin, child: Icon(LucideIcons.refreshCw, size: 28, color: c.primary.withValues(alpha: 0.7))),
          const SizedBox(height: 12),
          Text(t('common.loading'), style: TextStyle(color: muted)),
        ]),
      );
    } else if (emptyResults) {
      content = EmptyState(
        icon: LucideIcons.film,
        text: searching ? t('shortFilms.noSearchResults') : t('shortFilms.empty'),
      );
    } else {
      final w = MediaQuery.sizeOf(context).width;
      final rowCardW = (w * 0.32).clamp(108.0, 130.0);
      final showContinue = _continue.isNotEmpty && !searching && st.selectedSectionId == null;
      final showReco = _recommended.isNotEmpty && !searching && st.selectedSectionId == null;
      final showLater = _watchLater.isNotEmpty && !searching && st.selectedSectionId == null;
      content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showContinue) ...[
          _SectionTitle(t('shortFilms.continueWatching')),
          SizedBox(
            height: rowCardW * 14 / 9 + 8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _continue.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
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
          if (showReco || showLater || showFeatured || series.isNotEmpty || grid.isNotEmpty) const SizedBox(height: 20),
        ],
        if (showReco) ...[
          _SectionTitle(t('shortFilms.recommended')),
          SizedBox(
            height: rowCardW * 14 / 9,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recommended.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                width: rowCardW,
                child: FilmCard(film: _recommended[i], onTap: () => _openFilm(_recommended[i])),
              ),
            ),
          ),
          if (showLater || showFeatured || series.isNotEmpty || grid.isNotEmpty) const SizedBox(height: 20),
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
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                width: rowCardW,
                child: FilmCard(film: _watchLater[i], onTap: () => _openFilm(_watchLater[i])),
              ),
            ),
          ),
          if (showFeatured || series.isNotEmpty || grid.isNotEmpty) const SizedBox(height: 20),
        ],
        if (showFeatured) ...[
          _SectionTitle(t('shortFilms.featured')),
          SizedBox(
            height: rowCardW * 14 / 9,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: featured.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(width: rowCardW, child: FilmCard(film: featured[i], onTap: () => _openFilm(featured[i]))),
            ),
          ),
        ],
        if (series.isNotEmpty) ...[
          if (showFeatured) const SizedBox(height: 20),
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
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(width: rowCardW, child: SeriesCard(series: series[i], onTap: () => _openSeries(series[i]))),
            ),
          ),
        ],
        if (grid.isNotEmpty) ...[
          if (showFeatured || series.isNotEmpty) const SizedBox(height: 20),
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
                crossAxisCount: 3,
                crossAxisSpacing: w <= 360 ? 4 : 8,
                mainAxisSpacing: w <= 360 ? 4 : 8,
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
          child: st.loadingMore ? RotationTransition(turns: _spin, child: Icon(LucideIcons.refreshCw, size: 20, color: muted)) : null,
        ),
      ]);
    }

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: sheet,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 8),
          child: Row(
            children: [
              GlassIconButton(
                icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                backgroundColor: light ? surface : null,
                borderColor: light ? hairline : null,
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('shortFilms.title'),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: light ? _HubLight.ink : c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GlassIconButton(
                icon: LucideIcons.bookmark,
                backgroundColor: light ? surface : null,
                borderColor: light ? hairline : null,
                onTap: () => context.push('/short-films/library?tab=watch-later'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  controller: _search,
                  hint: t('shortFilms.searchPlaceholder'),
                  onChanged: _store.setSearch,
                  fillColor: light ? surface : null,
                  borderColor: light ? hairline : null,
                  trailing: st.searchQuery.isEmpty
                      ? null
                      : IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _search.clear();
                            _store.clearSearch();
                          },
                          icon: Icon(LucideIcons.x, size: 18, color: muted),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: LucideIcons.refreshCw,
                size: 44,
                backgroundColor: light ? surface : null,
                borderColor: light ? hairline : null,
                onTap: st.loading
                    ? null
                    : () async {
                        await _store.fetchAll(force: true);
                        await Future.wait([_loadContinue(), _loadLibrary()]);
                      },
              ),
            ],
          ),
        ),
        if (st.sections.isNotEmpty)
          Container(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: hairline))),
            child: SizedBox(
              height: 74,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                children: [
                  ShortFilmSectionRing(
                    label: t('shortFilms.allSections'),
                    active: st.selectedSectionId == null,
                    onTap: () => _store.setSection(null),
                    bg: surface,
                    ringBorder: sheet,
                    child: Icon(
                      LucideIcons.layoutGrid,
                      size: 20,
                      color: st.selectedSectionId == null ? c.primary : (light ? muted : c.textSecondary),
                    ),
                  ),
                  for (final s in st.sections)
                    ShortFilmSectionRing(
                      label: s.name,
                      active: st.selectedSectionId == s.id,
                      onTap: () => _store.setSection(s.id),
                      bg: surface,
                      ringBorder: sheet,
                      child: s.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: Api.absoluteUrl(s.imageUrl)!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              memCacheWidth: 144,
                            )
                          : Text(
                              s.name.trim().isEmpty ? '?' : s.name.trim().characters.first.toUpperCase(),
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.primary),
                            ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: () async {
              await _store.fetchAll(force: true);
              await Future.wait([_loadContinue(), _loadLibrary()]);
            },
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: 8, bottom: bottom),
              child: content,
            ),
          ),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.onSeeAll});
  final String text;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: light ? _HubLight.ink : c.textPrimary,
              ),
            ),
          ),
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primary),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                      size: 16,
                      color: c.primary,
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

/// Horizontal section filter chip (hub + catalog).
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
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
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
                color: active ? null : (light ? _HubLight.hairline : c.border),
                gradient: active
                    ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2563EB), Color(0xFF60A5FA)])
                    : null,
              ),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg ?? (light ? _HubLight.card : c.bgElevated),
                  border: Border.all(color: ringBorder ?? (light ? _HubLight.sheet : c.bgPrimary), width: 2),
                ),
                child: ClipOval(
                  child: SizedBox.expand(
                    child: child is Icon || child is Text
                        ? Center(child: child)
                        : child,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: active
                      ? (light ? _HubLight.ink : c.textPrimary)
                      : (light ? _HubLight.muted : c.textSecondary),
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                )),
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
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.05, 1.0),
                child: Container(color: const Color(0xFF60A5FA)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.film-card` thumbnail with duration pill and title.
class FilmCard extends StatelessWidget {
  const FilmCard({super.key, required this.film, required this.onTap, this.small = false});
  final ShortFilm film;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    final fallback = Container(
      color: light ? const Color(0xFFE8ECF2) : c.bgCard,
      alignment: Alignment.center,
      child: Icon(LucideIcons.film, size: small ? 22 : 24, color: c.primary.withValues(alpha: 0.5)),
    );
    Widget thumb;
    if (film.thumbnailUrl != null) {
      thumb = CachedNetworkImage(
          imageUrl: Api.absoluteUrl(film.thumbnailUrl)!, fit: BoxFit.cover, memCacheWidth: 480, errorWidget: (_, _, _) => fallback);
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
          color: light ? _HubLight.card : c.bgElevated,
          borderRadius: BorderRadius.circular(narrow ? 8 : AppRadius.md),
          border: light ? Border.all(color: _HubLight.hairline) : null,
          boxShadow: [
            BoxShadow(
              color: light ? _HubLight.shadow : c.shadow,
              blurRadius: light ? 10 : 6,
              offset: light ? const Offset(0, 3) : Offset.zero,
            ),
          ],
        ),
        child: Stack(fit: StackFit.expand, children: [
          thumb,
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xBF000000), Color(0x00000000)],
                stops: [0, 0.55],
              ),
            ),
          ),
          if (film.durationSeconds != null && film.durationSeconds! > 0)
            PositionedDirectional(
              top: 6,
              start: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(5)),
                child: Text(formatFilmDuration(film.durationSeconds),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: narrow ? const EdgeInsets.fromLTRB(4, 16, 4, 4) : const EdgeInsets.fromLTRB(6, 20, 6, 6),
              child: Text(film.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: narrow ? 9 : 10, fontWeight: FontWeight.w600, height: 1.25)),
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
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    final fallback = Container(
      color: light ? const Color(0xFFE8ECF2) : c.bgCard,
      alignment: Alignment.center,
      child: Icon(LucideIcons.tv, size: 24, color: c.primary.withValues(alpha: 0.5)),
    );
    final cover = series.coverUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: light ? _HubLight.card : c.bgElevated,
          borderRadius: BorderRadius.circular(narrow ? 8 : AppRadius.md),
          border: light ? Border.all(color: _HubLight.hairline) : null,
          boxShadow: [
            BoxShadow(
              color: light ? _HubLight.shadow : c.shadow,
              blurRadius: light ? 10 : 6,
              offset: light ? const Offset(0, 3) : Offset.zero,
            ),
          ],
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (cover != null && cover.isNotEmpty)
            CachedNetworkImage(imageUrl: Api.absoluteUrl(cover)!, fit: BoxFit.cover, memCacheWidth: 480, errorWidget: (_, _, _) => fallback)
          else
            fallback,
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xBF000000), Color(0x00000000)],
                stops: [0, 0.55],
              ),
            ),
          ),
          PositionedDirectional(
            top: 6,
            start: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(5)),
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
              padding: narrow ? const EdgeInsets.fromLTRB(4, 16, 4, 4) : const EdgeInsets.fromLTRB(6, 20, 6, 6),
              child: Text(series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: narrow ? 9 : 10, fontWeight: FontWeight.w600, height: 1.25)),
            ),
          ),
        ]),
      ),
    );
  }
}
