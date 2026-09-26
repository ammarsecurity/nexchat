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
import 'short_films_controller.dart';

/// Discover hub: dedicated Films tab + Series tab (not mixed on one scroll).
class ShortFilmsHubScreen extends ConsumerStatefulWidget {
  const ShortFilmsHubScreen({super.key});

  @override
  ConsumerState<ShortFilmsHubScreen> createState() => _ShortFilmsHubScreenState();
}

class _ShortFilmsHubScreenState extends ConsumerState<ShortFilmsHubScreen> with TickerProviderStateMixin {
  final _filmsScroll = ScrollController();
  final _seriesScroll = ScrollController();
  final _search = TextEditingController();
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final _tabs = TabController(length: 2, vsync: this);

  ShortFilmsController get _store => ref.read(shortFilmsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _filmsScroll.addListener(_onFilmsScroll);
    Future.microtask(() => _store.fetchAll(force: true));
  }

  @override
  void dispose() {
    _filmsScroll.dispose();
    _seriesScroll.dispose();
    _search.dispose();
    _spin.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onFilmsScroll() {
    final st = _store.current;
    if (!_filmsScroll.hasClients || !st.hasMore || st.loadingMore || st.loading) return;
    if (_filmsScroll.position.extentAfter < 160) _store.loadMore();
  }

  void _fillViewport() {
    if (!mounted || !_filmsScroll.hasClients || !_store.current.hasMore) return;
    if (_filmsScroll.position.maxScrollExtent < 160) _onFilmsScroll();
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

    final bottom = tabScrollPadding(context, extra: 16);

    return ModernPage(
      title: t('shortFilms.title'),
      backTo: '/home',
      scroll: false,
      padding: EdgeInsets.zero,
      actions: [
        GlassIconButton(
          icon: LucideIcons.refreshCw,
          onTap: st.loading ? null : () => _store.fetchAll(force: true),
        ),
      ],
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchField(
            controller: _search,
            hint: t('shortFilms.searchPlaceholder'),
            onChanged: _store.setSearch,
            trailing: st.searchQuery.isEmpty
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _search.clear();
                      _store.clearSearch();
                    },
                    icon: Icon(LucideIcons.x, size: 18, color: c.textMuted),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.bgElevated,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: c.border),
            ),
            child: TabBar(
              controller: _tabs,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: c.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.md - 2),
              ),
              labelColor: c.primary,
              unselectedLabelColor: c.textSecondary,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: t('shortFilms.filmsTab')),
                Tab(text: t('shortFilms.seriesTab')),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _FilmsPage(
                scroll: _filmsScroll,
                spin: _spin,
                bottomPad: bottom,
                onOpenFilm: _openFilm,
                onRefresh: () => _store.fetchAll(force: true),
              ),
              _SeriesPage(
                scroll: _seriesScroll,
                spin: _spin,
                bottomPad: bottom,
                onOpenSeries: _openSeries,
                onRefresh: () => _store.fetchAll(force: true),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _FilmsPage extends ConsumerWidget {
  const _FilmsPage({
    required this.scroll,
    required this.spin,
    required this.bottomPad,
    required this.onOpenFilm,
    required this.onRefresh,
  });

  final ScrollController scroll;
  final AnimationController spin;
  final double bottomPad;
  final void Function(ShortFilm) onOpenFilm;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final st = ref.watch(shortFilmsProvider);
    final store = ref.read(shortFilmsProvider.notifier);
    final featured = st.visibleFeatured;
    final grid = st.gridFilms;
    final searching = st.isSearching;
    final showFeatured = featured.isNotEmpty;
    final empty = st.loaded && !st.loading && featured.isEmpty && grid.isEmpty;
    final w = MediaQuery.sizeOf(context).width;

    Widget body;
    if (st.loading && !st.loaded) {
      body = _LoadingBlock(spin: spin, color: c);
    } else if (empty) {
      body = EmptyState(
        icon: LucideIcons.film,
        text: searching ? t('shortFilms.noSearchResults') : t('shortFilms.empty'),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showFeatured) ...[
          _SectionTitle(t('shortFilms.featured')),
          SizedBox(
            height: ((w * 0.32).clamp(108.0, 130.0)) * 14 / 9,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: featured.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = featured[i];
                return SizedBox(
                  width: (w * 0.32).clamp(108.0, 130.0),
                  child: FilmCard(film: f, onTap: () => onOpenFilm(f)),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        _SectionTitle(searching
            ? t('common.search')
            : st.selectedSectionId == null
                ? t('shortFilms.allFilms')
                : st.sections.where((s) => s.id == st.selectedSectionId).firstOrNull?.name ?? t('shortFilms.allFilms')),
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
            itemBuilder: (_, i) => FilmCard(film: grid[i], onTap: () => onOpenFilm(grid[i]), small: true),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 40),
          margin: const EdgeInsets.only(top: 8),
          alignment: Alignment.center,
          child: st.loadingMore
              ? RotationTransition(turns: spin, child: Icon(LucideIcons.refreshCw, size: 20, color: c.textMuted))
              : null,
        ),
      ]);
    }

    return Column(children: [
      _SectionRingsBar(sections: st.sections, selectedId: st.selectedSectionId, onSelect: store.setSection),
      Expanded(
        child: RefreshIndicator(
          color: c.primary,
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(top: 8, bottom: bottomPad),
            child: body,
          ),
        ),
      ),
    ]);
  }
}

class _SeriesPage extends ConsumerWidget {
  const _SeriesPage({
    required this.scroll,
    required this.spin,
    required this.bottomPad,
    required this.onOpenSeries,
    required this.onRefresh,
  });

  final ScrollController scroll;
  final AnimationController spin;
  final double bottomPad;
  final void Function(FilmSeries) onOpenSeries;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final st = ref.watch(shortFilmsProvider);
    final store = ref.read(shortFilmsProvider.notifier);
    final series = st.visibleSeries;
    final searching = st.isSearching;
    final empty = st.loaded && !st.loading && series.isEmpty;
    final w = MediaQuery.sizeOf(context).width;
    final sectionName = st.selectedSectionId == null
        ? null
        : st.sections.where((s) => s.id == st.selectedSectionId).firstOrNull?.name;

    Widget body;
    if (st.loading && !st.loaded) {
      body = _LoadingBlock(spin: spin, color: c);
    } else if (empty) {
      body = EmptyState(
        icon: LucideIcons.tv,
        text: searching ? t('shortFilms.noSearchResults') : t('shortFilms.emptySeriesList'),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionTitle(sectionName ?? t('shortFilms.series')),
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
            itemCount: series.length,
            itemBuilder: (_, i) => SeriesCard(series: series[i], onTap: () => onOpenSeries(series[i])),
          ),
        ),
      ]);
    }

    return Column(children: [
      _SectionRingsBar(sections: st.sections, selectedId: st.selectedSectionId, onSelect: store.setSection),
      Expanded(
        child: RefreshIndicator(
          color: c.primary,
          onRefresh: onRefresh,
          child: SingleChildScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(top: 8, bottom: bottomPad),
            child: body,
          ),
        ),
      ),
    ]);
  }
}

/// Horizontal section rings — shared by Films and Series tabs.
class _SectionRingsBar extends StatelessWidget {
  const _SectionRingsBar({required this.sections, required this.selectedId, required this.onSelect});
  final List<FilmSection> sections;
  final String? selectedId;
  final Future<void> Function(String?) onSelect;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: SizedBox(
        height: 74,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          children: [
            _SectionRing(
              label: t('shortFilms.allSections'),
              active: selectedId == null,
              onTap: () => onSelect(null),
              bg: c.bgCard,
              child: Icon(LucideIcons.layoutGrid, size: 20, color: selectedId == null ? c.primary : c.textSecondary),
            ),
            for (final s in sections)
              _SectionRing(
                label: s.name,
                active: selectedId == s.id,
                onTap: () => onSelect(s.id),
                child: s.imageUrl != null
                    ? CachedNetworkImage(imageUrl: Api.absoluteUrl(s.imageUrl)!, fit: BoxFit.cover, width: 48, height: 48)
                    : Text(
                        s.name.trim().isEmpty ? '?' : s.name.trim().characters.first.toUpperCase(),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.primary),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.spin, required this.color});
  final AnimationController spin;
  final AppColors color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          RotationTransition(turns: spin, child: Icon(LucideIcons.refreshCw, size: 28, color: color.primary.withValues(alpha: 0.7))),
          const SizedBox(height: 12),
          Text(t('common.loading'), style: TextStyle(color: color.textMuted)),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
      );
}

class _SectionRing extends StatelessWidget {
  const _SectionRing({required this.label, required this.active, required this.onTap, required this.child, this.bg});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget child;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                color: active ? null : c.border,
                gradient: active
                    ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2563EB), Color(0xFF60A5FA)])
                    : null,
              ),
              child: Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: bg ?? c.bgElevated, border: Border.all(color: c.bgPrimary, width: 2)),
                child: child,
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
                  color: active ? c.textPrimary : c.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                )),
          ]),
        ),
      ),
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
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    final fallback = Container(
      color: c.bgCard,
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
          color: c.bgElevated,
          borderRadius: BorderRadius.circular(narrow ? 8 : AppRadius.md),
          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6)],
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
    final narrow = MediaQuery.sizeOf(context).width <= 360;
    final fallback = Container(
      color: c.bgCard,
      alignment: Alignment.center,
      child: Icon(LucideIcons.tv, size: 24, color: c.primary.withValues(alpha: 0.5)),
    );
    final cover = series.coverUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.bgElevated,
          borderRadius: BorderRadius.circular(narrow ? 8 : AppRadius.md),
          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6)],
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
