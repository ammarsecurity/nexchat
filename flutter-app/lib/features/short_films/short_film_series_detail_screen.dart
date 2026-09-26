import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'short_films_controller.dart';

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
    if (!mounted) return;
    setState(() {
      _series = series;
      _loading = false;
    });
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
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final series = _series;
    final title = series?.title ?? t('shortFilms.series');

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (series == null)
            Column(children: [
              SizedBox(height: pad.top + 60),
              Expanded(child: EmptyState(icon: LucideIcons.tv, text: t('shortFilms.emptySeries'))),
            ])
          else
            RefreshIndicator(
              color: c.primary,
              onRefresh: _load,
              edgeOffset: pad.top + 48,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _SeriesHero(
                      series: series,
                      onPlay: series.episodes.isEmpty ? null : _playFirst,
                    ),
                  ),
                  if (series.description?.isNotEmpty ?? false)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text(
                          series.description!,
                          style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                      child: Row(
                        children: [
                          Text(
                            t('shortFilms.episodes'),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary),
                          ),
                          const Spacer(),
                          Text(
                            t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                            style: TextStyle(fontSize: 13, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (series.episodes.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: EmptyState(icon: LucideIcons.film, text: t('shortFilms.emptySeries')),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 28),
                      sliver: SliverList.separated(
                        itemCount: series.episodes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _EpisodeRow(
                          episode: series.episodes[i],
                          index: i + 1,
                          onTap: () => _openEpisode(series.episodes[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Floating header — overlays the hero, no bulky title bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.fromLTRB(12, pad.top + 8, 12, 10),
              decoration: BoxDecoration(
                color: _titleVisible ? c.bgPrimary.withValues(alpha: 0.92) : Colors.transparent,
                border: _titleVisible ? Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.6))) : null,
              ),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                    onTap: _back,
                    overlay: !_titleVisible,
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (series != null && series.episodes.isNotEmpty)
                    GlassIconButton(
                      icon: LucideIcons.share2,
                      onTap: _shareSeries,
                      overlay: !_titleVisible,
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
  const _SeriesHero({required this.series, this.onPlay});
  final FilmSeries series;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    final cover = series.coverUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    final fallback = ColoredBox(
      color: c.bgCard,
      child: Center(child: Icon(LucideIcons.tv, size: 48, color: c.primary.withValues(alpha: 0.45))),
    );

    return SizedBox(
      height: top + 340,
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
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  c.bgPrimary.withValues(alpha: 0.55),
                  c.bgPrimary,
                ],
                stops: const [0, 0.28, 0.72, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (onPlay != null) ...[
                  const SizedBox(height: 14),
                  GradientButton(
                    label: t('shortFilms.watchFromStart'),
                    icon: LucideIcons.play,
                    height: 46,
                    onPressed: onPlay,
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

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.index, required this.onTap});
  final ShortFilm episode;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = episode.episodeNumber ?? index;
    final label = t('shortFilms.episodeN').replaceAll('{n}', '$n');
    final duration = formatFilmDuration(episode.durationSeconds);
    final thumbUrl = episode.thumbnailUrl;
    final fallback = ColoredBox(
      color: c.bgElevated,
      child: Icon(LucideIcons.film, size: 22, color: c.primary.withValues(alpha: 0.45)),
    );

    return Material(
      color: c.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withValues(alpha: 0.14),
                ),
                child: Text(
                  '$n',
                  style: TextStyle(color: c.primary, fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 88,
                  child: thumbUrl != null && thumbUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: Api.absoluteUrl(thumbUrl)!,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          errorWidget: (_, _, _) => fallback,
                        )
                      : fallback,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (episode.title.isNotEmpty && episode.title != label) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.35),
                      ),
                    ],
                    if (duration.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(LucideIcons.clock, size: 13, color: c.textMuted),
                          const SizedBox(width: 4),
                          Text(duration, style: TextStyle(color: c.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withValues(alpha: 0.14),
                ),
                child: Icon(LucideIcons.play, size: 16, color: c.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
