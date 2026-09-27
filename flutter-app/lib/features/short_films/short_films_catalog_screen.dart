import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
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

  bool get _isSeries => widget.kind == 'series';

  ShortFilmsController get _store => ref.read(shortFilmsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(() {
      final st = _store.current;
      if (!st.loaded) _store.fetchAll(force: true);
      if (_isSeries && st.series.isEmpty) _store.fetchSeriesList();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
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

    return ModernPage(
      title: title,
      backTo: '/short-films',
      scroll: false,
      padding: EdgeInsets.zero,
      body: loading
          ? Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted)))
          : empty
              ? EmptyState(
                  icon: _isSeries ? LucideIcons.tv : LucideIcons.film,
                  text: _isSeries ? t('shortFilms.emptySeriesList') : t('shortFilms.empty'),
                )
              : RefreshIndicator(
                  color: c.primary,
                  onRefresh: () => _store.fetchAll(force: true),
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
    );
  }
}
