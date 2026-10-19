import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/layout.dart';
import 'short_films_controller.dart';
import 'short_films_hub_screen.dart';
import 'short_films_theme.dart';

/// Full-grid catalog for series or standalone films (opened via «عرض الكل»).
class ShortFilmsCatalogScreen extends ConsumerStatefulWidget {
  const ShortFilmsCatalogScreen({super.key, required this.kind});

  /// `series` | `films`
  final String kind;

  @override
  ConsumerState<ShortFilmsCatalogScreen> createState() => _ShortFilmsCatalogScreenState();
}

class _ShortFilmsCatalogScreenState extends ConsumerState<ShortFilmsCatalogScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  bool get _isSeries => widget.kind == 'series';

  ShortFilmsController get _store => ref.read(shortFilmsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(() {
      final st = _store.current;
      _search.text = st.searchQuery;
      if (st.sections.isEmpty) _store.fetchSections();
      if (!st.loaded) {
        _store.fetchAll(force: true);
      }
      if (_isSeries) _store.fetchSeriesList();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isSeries) return;
    final st = _store.current;
    if (!_scroll.hasClients || !st.hasMore || st.loadingMore || st.loading) return;
    if (_scroll.position.extentAfter < 160) _store.loadMore();
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
    final title = _isSeries ? t('shortFilms.series') : t('shortFilms.allFilms');
    final series = st.visibleSeries;
    final films = st.gridFilms;
    final bottom = tabScrollPadding(context, extra: 16);
    final empty = _isSeries ? series.isEmpty : films.isEmpty;
    final loading = st.loading && !st.loaded;
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final w = MediaQuery.sizeOf(context).width;

    if (_search.text != st.searchQuery && st.searchQuery.isEmpty && _search.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search.clear();
      });
    }

    return Scaffold(
      backgroundColor: DramaWave.bg,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, pad.top + 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/short-films');
                  }
                },
                icon: Icon(
                  rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                  size: 22,
                  color: DramaWave.ink,
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: DramaWave.title(size: 17),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
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
                    controller: _search,
                    onChanged: _store.setSearch,
                    style: const TextStyle(color: DramaWave.ink, fontSize: 14, fontWeight: FontWeight.w600),
                    cursorColor: DramaWave.gold,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: t('shortFilms.searchPlaceholder'),
                      hintStyle: const TextStyle(color: DramaWave.muted, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                if (st.searchQuery.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _search.clear();
                      _store.clearSearch();
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(LucideIcons.x, size: 16, color: DramaWave.muted),
                  ),
              ],
            ),
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
          child: loading
              ? Center(child: Text(t('common.loading'), style: DramaWave.body()))
              : empty
                  ? DramaWaveEmpty(
                      icon: _isSeries ? LucideIcons.tv : LucideIcons.film,
                      text: st.isSearching || st.selectedSectionId != null
                          ? t('shortFilms.empty')
                          : (_isSeries ? t('shortFilms.emptySeriesList') : t('shortFilms.empty')),
                    )
                  : RefreshIndicator(
                      color: DramaWave.gold,
                      backgroundColor: DramaWave.elevated,
                      onRefresh: () async {
                        await _store.fetchAll(force: true);
                        if (_isSeries) await _store.fetchSeriesList();
                      },
                      child: GridView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: shortFilmGridColumns(w),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 9 / 14,
                        ),
                        itemCount: _isSeries ? series.length : films.length + (st.loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (!_isSeries && i >= films.length) {
                            return const Center(
                              child: Icon(LucideIcons.refreshCw, size: 20, color: DramaWave.muted),
                            );
                          }
                          if (_isSeries) {
                            final s = series[i];
                            return SeriesCard(series: s, onTap: () => _openSeries(s));
                          }
                          final f = films[i];
                          return FilmCard(film: f, onTap: () => _openFilm(f), small: true);
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
