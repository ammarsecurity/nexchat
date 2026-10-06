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
import 'short_film_cache.dart';
import 'short_film_engagement.dart';
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
  bool _following = false;

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
    // Warm first episodes so Play / episode tap starts faster.
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
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final series = _series;
    final title = series?.title ?? t('shortFilms.series');
    final light = Theme.of(context).brightness == Brightness.light;
    // Soft slate sheet — no pure white wash in light mode.
    final sheetBg = light ? const Color(0xFFE6EBF3) : c.bgPrimary;

    return Scaffold(
      backgroundColor: light ? const Color(0xFF0B1220) : c.bgPrimary,
      body: Stack(
        children: [
          if (_loading)
            Center(child: CircularProgressIndicator(color: c.primary))
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
                      following: _following,
                      onPlay: series.episodes.isEmpty ? null : _playFirst,
                      onFollow: _toggleFollow,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: sheetBg,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                          boxShadow: light
                              ? const [
                                  BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, -6)),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: light ? const Color(0x330F172A) : c.border,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            if (series.description?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                                child: Text(
                                  series.description!,
                                  style: TextStyle(
                                    color: light ? const Color(0xFF475569) : c.textSecondary,
                                    fontSize: 14,
                                    height: 1.55,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
                              child: Row(
                                children: [
                                  Text(
                                    t('shortFilms.episodes'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: light ? const Color(0xFF0F172A) : c.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: light ? const Color(0x1F0F172A) : c.primarySoft,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: light ? const Color(0xFF64748B) : c.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (series.episodes.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: EmptyState(icon: LucideIcons.film, text: t('shortFilms.emptySeries')),
                              )
                            else
                              Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, pad.bottom + 36),
                                child: Column(
                                  children: [
                                    for (var i = 0; i < series.episodes.length; i++) ...[
                                      if (i > 0) const SizedBox(height: 10),
                                      _EpisodeRow(
                                        episode: series.episodes[i],
                                        index: i + 1,
                                        onTap: () => _openEpisode(series.episodes[i]),
                                      ),
                                    ],
                                  ],
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
                color: _titleVisible ? sheetBg.withValues(alpha: 0.96) : Colors.transparent,
                border: _titleVisible
                    ? Border(bottom: BorderSide(color: (light ? const Color(0x140F172A) : c.border)))
                    : null,
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: light ? const Color(0xFF0F172A) : c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (series != null)
                    GlassIconButton(
                      icon: _following ? LucideIcons.bellRing : LucideIcons.bell,
                      onTap: _toggleFollow,
                      overlay: !_titleVisible,
                    )
                  else
                    const SizedBox(width: 48),
                  const SizedBox(width: 6),
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
  const _SeriesHero({required this.series, this.onPlay, this.onFollow, this.following = false});
  final FilmSeries series;
  final VoidCallback? onPlay;
  final VoidCallback? onFollow;
  final bool following;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    final cover = series.coverUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    final fallback = ColoredBox(
      color: const Color(0xFF111827),
      child: Center(child: Icon(LucideIcons.tv, size: 48, color: c.primary.withValues(alpha: 0.55))),
    );

    return SizedBox(
      height: top + 360,
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
          // Keep the poster cinematic — never fade into pale light-mode blue.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0x990B1220),
                  Color(0xFF0B1220),
                ],
                stops: [0, 0.32, 0.68, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 36,
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
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 10)],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (onPlay != null || onFollow != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    if (onPlay != null)
                      Expanded(
                        child: GradientButton(
                          label: t('shortFilms.watchFromStart'),
                          icon: LucideIcons.play,
                          height: 46,
                          onPressed: onPlay,
                        ),
                      ),
                    if (onPlay != null && onFollow != null) const SizedBox(width: 10),
                    if (onFollow != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onFollow,
                          icon: Icon(
                            following ? LucideIcons.bellRing : LucideIcons.bell,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: Text(
                            following ? t('shortFilms.followingSeries') : t('shortFilms.followSeries'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                  ]),
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
    final light = Theme.of(context).brightness == Brightness.light;
    final n = episode.episodeNumber ?? index;
    final label = t('shortFilms.episodeN').replaceAll('{n}', '$n');
    final duration = formatFilmDuration(episode.durationSeconds);
    final thumbUrl = episode.thumbnailUrl;
    final fallback = ColoredBox(
      color: light ? const Color(0xFFE8ECF2) : c.bgElevated,
      child: Icon(LucideIcons.film, size: 22, color: c.primary.withValues(alpha: 0.55)),
    );

    return Material(
      color: light ? const Color(0xFFEEF2F8) : c.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: light ? const Color(0x1F0F172A) : c.border.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 68,
                  height: 92,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumbUrl != null && thumbUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: Api.absoluteUrl(thumbUrl)!,
                          fit: BoxFit.cover,
                          memCacheWidth: 220,
                          errorWidget: (_, _, _) => fallback,
                        )
                      else
                        fallback,
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xCC0B1220),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$n',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: light ? const Color(0xFF0F172A) : c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (episode.title.isNotEmpty && episode.title != label) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: light ? const Color(0xFF64748B) : c.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (duration.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.clock,
                            size: 13,
                            color: light ? const Color(0xFF94A3B8) : c.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            duration,
                            style: TextStyle(
                              color: light ? const Color(0xFF94A3B8) : c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.primary, c.primaryHover],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: light ? 0.28 : 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.play, size: 16, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
