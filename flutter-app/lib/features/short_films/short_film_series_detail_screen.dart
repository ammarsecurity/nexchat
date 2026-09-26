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
import 'short_films_hub_screen.dart';

class ShortFilmSeriesDetailScreen extends ConsumerStatefulWidget {
  const ShortFilmSeriesDetailScreen({super.key, required this.seriesId});
  final String seriesId;

  @override
  ConsumerState<ShortFilmSeriesDetailScreen> createState() => _ShortFilmSeriesDetailScreenState();
}

class _ShortFilmSeriesDetailScreenState extends ConsumerState<ShortFilmSeriesDetailScreen> {
  FilmSeries? _series;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
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

  void _openEpisode(ShortFilm ep) {
    context.push('/short-films/watch?start=${ep.id}&series=${widget.seriesId}');
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
    final series = _series;
    return ModernPage(
      title: series?.title ?? t('shortFilms.series'),
      backTo: '/short-films',
      scroll: true,
      actions: [
        if (series != null && series.episodes.isNotEmpty)
          GlassIconButton(icon: LucideIcons.share2, onTap: _shareSeries),
        GlassIconButton(icon: LucideIcons.refreshCw, onTap: _loading ? null : _load),
      ],
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          : series == null
              ? EmptyState(icon: LucideIcons.tv, text: t('shortFilms.emptySeries'))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (series.coverUrl != null && series.coverUrl!.isNotEmpty)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: Api.absoluteUrl(series.coverUrl)!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => ColoredBox(
                          color: c.bgCard,
                          child: Icon(LucideIcons.tv, size: 40, color: c.primary.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(series.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary)),
                      const SizedBox(height: 6),
                      Text(
                        t('shortFilms.episodesCount').replaceAll('{n}', '${series.episodesCount}'),
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                      if (series.description?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 10),
                        Text(series.description!, style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.45)),
                      ],
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Text(t('shortFilms.episodes'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  ),
                  if (series.episodes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: EmptyState(icon: LucideIcons.film, text: t('shortFilms.emptySeries')),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: series.episodes.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 9 / 14,
                        ),
                        itemBuilder: (_, i) {
                          final ep = series.episodes[i];
                          return FilmCard(
                            film: ep,
                            small: true,
                            onTap: () => _openEpisode(ep),
                          );
                        },
                      ),
                    ),
                ]),
    );
  }
}
