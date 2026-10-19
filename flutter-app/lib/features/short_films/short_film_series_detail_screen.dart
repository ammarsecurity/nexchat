import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets.dart';
import 'short_film_cache.dart';
import 'short_film_engagement.dart';
import 'short_films_controller.dart';
import 'short_films_theme.dart';

class ShortFilmSeriesDetailScreen extends ConsumerStatefulWidget {
  const ShortFilmSeriesDetailScreen({super.key, required this.seriesId});
  final String seriesId;

  @override
  ConsumerState<ShortFilmSeriesDetailScreen> createState() => _ShortFilmSeriesDetailScreenState();
}

class _ShortFilmSeriesDetailScreenState extends ConsumerState<ShortFilmSeriesDetailScreen> {
  final _scroll = ScrollController();
  FilmSeries? _series;
  bool _loading = true;
  bool _titleVisible = false;
  bool _following = false;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 140;
    if (show != _titleVisible) setState(() => _titleVisible = show);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final series = await ref.read(shortFilmsProvider.notifier).fetchSeriesDetail(widget.seriesId);
    var following = false;
    try {
      following = (await ShortFilmEngagementApi.instance.followingSeriesIds()).contains(widget.seriesId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _series = series;
      _following = following;
      _loading = false;
    });
    final eps = series?.episodes;
    if (eps != null && eps.isNotEmpty) {
      ShortFilmCache.instance.prefetchFilms(eps.take(3), priority: CachePriority.high);
    }
  }

  Future<void> _toggleFollow() async {
    final next = !_following;
    setState(() => _following = next);
    try {
      await ShortFilmEngagementApi.instance.setFollowSeries(widget.seriesId, next);
    } catch (_) {
      if (mounted) setState(() => _following = !next);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/short-films');
    }
  }

  void _openEpisode(ShortFilm ep) {
    context.push('/short-films/watch?start=${ep.id}&series=${widget.seriesId}');
  }

  void _playFirst() {
    final eps = _series?.episodes;
    if (eps == null || eps.isEmpty) return;
    _openEpisode(eps.first);
  }

  void _shareSeries() {
    final series = _series;
    if (series == null || series.episodes.isEmpty) return;
    final ep = series.episodes.first;
    context.push('/share-message', extra: {
      'shareMessage': {
        'type': 'short_film',
        'content': buildShortFilmShareContent(
          ep.id,
          '${series.title} · ${t('shortFilms.episodeN').replaceAll('{n}', '${ep.episodeNumber ?? 1}')}',
          ep.thumbnailUrl ?? series.coverUrl,
        ),
      },
      'returnPath': '/short-films/series/${widget.seriesId}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final series = _series;
    final title = series?.title ?? t('shortFilms.series');

    return Scaffold(
      backgroundColor: DramaWave.bg,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: DramaWave.gold))
          else if (series == null)
            Column(children: [
              SizedBox(height: pad.top + 60),
              Expanded(child: DramaWaveEmpty(icon: LucideIcons.tv, text: t('shortFilms.emptySeries'))),
            ])
          else
            RefreshIndicator(
              color: DramaWave.gold,
              backgroundColor: DramaWave.elevated,
              onRefresh: _load,
              edgeOffset: pad.top + 48,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _SeriesHero(
                      series: series,
                      following: _following,
                      onPlay: series.episodes.isEmpty ? null : _playFirst,
                      onFollow: _toggleFollow,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Transform.translate(
                      offset: const Offset(0, -28),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: DramaWave.bg,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: DramaWave.hairline,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            if (series.description?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      series.description!,
                                      maxLines: _descExpanded ? 40 : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: DramaWave.body(size: 14, color: DramaWave.soft),
                                    ),
                                    if ((series.description?.length ?? 0) > 90)
                                      GestureDetector(
                                        onTap: () => setState(() => _descExpanded = !_descExpanded),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            _descExpanded ? t('shortFilms.showLess') : t('shortFilms.showMore'),
                                            style: const TextStyle(
                                              color: DramaWave.gold,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
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
                                  Text(t('shortFilms.episodes'), style: DramaWave.title(size: 16)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: DramaWave.elevated,
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: DramaWave.hairline),
                                    ),
                                    child: Text(
                                      t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                                      style: DramaWave.body(size: 12, color: DramaWave.soft),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (series.episodes.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: DramaWaveEmpty(icon: LucideIcons.film, text: t('shortFilms.emptySeries')),
                              )
                            else
                              Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 36),
                                child: _EpisodeNumberGrid(
                                  episodes: series.episodes,
                                  onTap: _openEpisode,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.fromLTRB(12, pad.top + 8, 12, 10),
              decoration: BoxDecoration(
                color: _titleVisible ? DramaWave.bg.withValues(alpha: 0.96) : Colors.transparent,
                border: _titleVisible ? const Border(bottom: BorderSide(color: DramaWave.hairline)) : null,
              ),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                    onTap: _back,
                    overlay: !_titleVisible,
                    backgroundColor: _titleVisible ? DramaWave.elevated : null,
                    borderColor: _titleVisible ? DramaWave.hairline : null,
                    color: DramaWave.ink,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _titleVisible ? 1 : 0,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DramaWave.title(size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (series != null)
                    GlassIconButton(
                      icon: _following ? LucideIcons.bellRing : LucideIcons.bell,
                      onTap: _toggleFollow,
                      overlay: !_titleVisible,
                      backgroundColor: _titleVisible ? DramaWave.elevated : null,
                      borderColor: _titleVisible ? DramaWave.hairline : null,
                      color: _following ? DramaWave.gold : DramaWave.ink,
                    )
                  else
                    const SizedBox(width: 48),
                  const SizedBox(width: 6),
                  if (series != null && series.episodes.isNotEmpty)
                    GlassIconButton(
                      icon: LucideIcons.share2,
                      onTap: _shareSeries,
                      overlay: !_titleVisible,
                      backgroundColor: _titleVisible ? DramaWave.elevated : null,
                      borderColor: _titleVisible ? DramaWave.hairline : null,
                      color: DramaWave.ink,
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesHero extends StatelessWidget {
  const _SeriesHero({required this.series, this.onPlay, this.onFollow, this.following = false});
  final FilmSeries series;
  final VoidCallback? onPlay;
  final VoidCallback? onFollow;
  final bool following;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final cover = series.coverUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    final fallback = ColoredBox(
      color: DramaWave.elevated,
      child: Center(child: Icon(LucideIcons.tv, size: 48, color: DramaWave.gold.withValues(alpha: 0.55))),
    );

    return SizedBox(
      height: top + 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCover)
            CachedNetworkImage(
              imageUrl: Api.absoluteUrl(cover)!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              memCacheWidth: 1080,
              errorWidget: (_, _, _) => fallback,
            )
          else
            fallback,
          const DecoratedBox(decoration: BoxDecoration(gradient: DramaWave.heroGradient)),
          Positioned(
            left: 16,
            right: 16,
            bottom: 44,
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
                const SizedBox(height: 10),
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DramaWave.title(size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                  style: DramaWave.body(size: 13, color: DramaWave.soft),
                ),
                if (onPlay != null || onFollow != null) ...[
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack = constraints.maxWidth < 380;
                      final play = onPlay == null
                          ? null
                          : _GoldButton(
                              label: t('shortFilms.watchFromStart'),
                              icon: LucideIcons.play,
                              onPressed: onPlay!,
                            );
                      final follow = onFollow == null
                          ? null
                          : OutlinedButton(
                              onPressed: onFollow,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    following ? LucideIcons.bellRing : LucideIcons.bell,
                                    size: 18,
                                    color: following ? DramaWave.gold : Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      following
                                          ? t('shortFilms.followingSeries')
                                          : t('shortFilms.followSeries'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: following ? DramaWave.gold : Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (play != null) play,
                            if (play != null && follow != null) const SizedBox(height: 10),
                            if (follow != null) follow,
                          ],
                        );
                      }

                      return Row(children: [
                        if (play != null) Expanded(child: play),
                        if (play != null && follow != null) const SizedBox(width: 10),
                        if (follow != null) Expanded(child: follow),
                      ]);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [DramaWave.gold, DramaWave.goldDeep]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: DramaWave.gold.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.black),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// DramaWave signature: numbered episode cells in a wrap grid.
class _EpisodeNumberGrid extends StatelessWidget {
  const _EpisodeNumberGrid({required this.episodes, required this.onTap});
  final List<ShortFilm> episodes;
  final ValueChanged<ShortFilm> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 10.0;
      final cols = box.maxWidth >= 520
          ? 7
          : box.maxWidth >= 400
              ? 6
              : 5;
      final cell = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < episodes.length; i++)
            SizedBox(
              width: cell,
              height: cell,
              child: _EpisodeCell(
                number: episodes[i].episodeNumber ?? (i + 1),
                highlight: i == 0,
                onTap: () => onTap(episodes[i]),
              ),
            ),
        ],
      );
    });
  }
}

class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({required this.number, required this.onTap, this.highlight = false});
  final int number;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: highlight ? DramaWave.goldSoft : DramaWave.elevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight ? DramaWave.gold : DramaWave.hairline,
              width: highlight ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '$number',
              style: TextStyle(
                color: highlight ? DramaWave.gold : DramaWave.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
