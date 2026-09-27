import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/widgets.dart';
import 'short_films_controller.dart';
import 'short_films_hub_screen.dart';

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
    final c = context.colors;
    final st = ref.watch(shortFilmsProvider);
    final title = _isSeries ? t('shortFilms.series') : t('shortFilms.allFilms');
    final series = st.visibleSeries;
    final films = st.gridFilms;
    final bottom = tabScrollPadding(context, extra: 16);
    final empty = _isSeries ? series.isEmpty : films.isEmpty;
    final loading = st.loading && !st.loaded;

    // Keep search field in sync if cleared from store elsewhere.
    if (_search.text != st.searchQuery && st.searchQuery.isEmpty && _search.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search.clear();
      });
    }

    return ModernPage(
      title: title,
      backTo: '/short-films',
      scroll: false,
      padding: EdgeInsets.zero,
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
        if (st.sections.isNotEmpty)
          Container(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
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
                    bg: c.bgCard,
                    child: Icon(LucideIcons.layoutGrid, size: 20, color: st.selectedSectionId == null ? c.primary : c.textSecondary),
                  ),
                  for (final s in st.sections)
                    ShortFilmSectionRing(
                      label: s.name,
                      active: st.selectedSectionId == s.id,
                      onTap: () => _store.setSection(s.id),
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
          child: loading
              ? Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted)))
              : empty
                  ? EmptyState(
                      icon: _isSeries ? LucideIcons.tv : LucideIcons.film,
                      text: st.isSearching || st.selectedSectionId != null
                          ? t('shortFilms.empty')
                          : (_isSeries ? t('shortFilms.emptySeriesList') : t('shortFilms.empty')),
                    )
                  : RefreshIndicator(
                      color: c.primary,
                      onRefresh: () async {
                        await _store.fetchAll(force: true);
                        if (_isSeries) await _store.fetchSeriesList();
                      },
                      child: GridView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 9 / 14,
                        ),
                        itemCount: _isSeries ? series.length : films.length + (st.loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (!_isSeries && i >= films.length) {
                            return Center(child: Icon(LucideIcons.refreshCw, size: 20, color: c.textMuted));
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
