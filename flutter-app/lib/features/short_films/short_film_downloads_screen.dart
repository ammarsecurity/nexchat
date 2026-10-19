import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets.dart';
import 'short_film_downloads.dart';
import 'short_films_controller.dart';
import 'short_films_theme.dart';

class ShortFilmDownloadsScreen extends ConsumerStatefulWidget {
  const ShortFilmDownloadsScreen({super.key});

  @override
  ConsumerState<ShortFilmDownloadsScreen> createState() => _ShortFilmDownloadsScreenState();
}

class _ShortFilmDownloadsScreenState extends ConsumerState<ShortFilmDownloadsScreen> {
  List<ShortFilm> _films = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  bool _looksLikeId(String title) {
    final t = title.trim();
    return t.length >= 32 && RegExp(r'^[0-9a-fA-F-]{32,}$').hasMatch(t);
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    var films = await ShortFilmDownloads.instance.listFilms();
    final store = ref.read(shortFilmsProvider.notifier);
    final hydrated = <ShortFilm>[];
    for (final f in films) {
      if (!_looksLikeId(f.title) && (f.thumbnailUrl?.isNotEmpty ?? false)) {
        hydrated.add(f);
        continue;
      }
      try {
        final remote = await store.fetchById(f.id);
        if (remote != null) {
          await ShortFilmDownloads.instance.saveMeta(remote);
          hydrated.add(remote);
          continue;
        }
      } catch (_) {}
      hydrated.add(f);
    }
    if (!mounted) return;
    setState(() {
      _films = hydrated;
      _loading = false;
    });
  }

  void _open(ShortFilm f) {
    if (f.seriesId != null && f.seriesId!.isNotEmpty) {
      context.push('/short-films/watch?start=${f.id}&series=${f.seriesId}');
    } else {
      context.push('/short-films/watch?start=${f.id}');
    }
  }

  void _openMenu(ShortFilm f) {
    showDramaWaveSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        DramaWaveSheetAction(
          icon: LucideIcons.play,
          label: t('shortFilms.play'),
          onTap: () {
            Navigator.pop(ctx);
            _open(f);
          },
        ),
        DramaWaveSheetAction(
          icon: LucideIcons.trash2,
          label: t('shortFilms.removeDownload'),
          danger: true,
          onTap: () {
            Navigator.pop(ctx);
            _remove(f);
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Future<void> _remove(ShortFilm f) async {
    final ok = await confirmDialog(
      context,
      title: t('shortFilms.removeDownload'),
      message: t('shortFilms.removeDownloadConfirm'),
      confirm: t('common.delete'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok) return;
    await ShortFilmDownloads.instance.remove(f.id);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: DramaWave.bg,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, pad.top + 4, 8, 8),
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
                    t('shortFilms.downloads'),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: DramaWave.title(size: 17),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DramaWave.gold))
                : _films.isEmpty
                    ? RefreshIndicator(
                        color: DramaWave.gold,
                        backgroundColor: DramaWave.elevated,
                        onRefresh: _reload,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
                            DramaWaveEmpty(
                              icon: LucideIcons.download,
                              text: t('shortFilms.emptyDownloads'),
                              actionLabel: t('shortFilms.browseFilms'),
                              onAction: () => context.go('/short-films'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: DramaWave.gold,
                        backgroundColor: DramaWave.elevated,
                        onRefresh: _reload,
                        child: ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, pad.bottom + 28),
                          itemCount: _films.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final f = _films[i];
                            final title = _looksLikeId(f.title)
                                ? t('shortFilms.downloadedFilm')
                                : (f.isEpisode ? f.displaySubtitle : f.title);
                            final subtitle = f.isEpisode && !_looksLikeId(f.title) && f.title != f.displaySubtitle
                                ? f.title
                                : null;
                            final thumb = f.thumbnailUrl;
                            final fallback = ColoredBox(
                              color: DramaWave.elevated,
                              child: Icon(LucideIcons.film, size: 22, color: DramaWave.gold.withValues(alpha: 0.55)),
                            );

                            return Material(
                              color: DramaWave.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: DramaWave.hairline),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _open(f),
                                onLongPress: () => _openMenu(f),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(
                                          width: 64,
                                          height: 88,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (thumb != null && thumb.isNotEmpty)
                                                CachedNetworkImage(
                                                  imageUrl: Api.absoluteUrl(thumb)!,
                                                  fit: BoxFit.cover,
                                                  memCacheWidth: 240,
                                                  errorWidget: (_, _, _) => fallback,
                                                )
                                              else
                                                fallback,
                                              const DecoratedBox(
                                                decoration: BoxDecoration(gradient: DramaWave.cardFade),
                                              ),
                                              const Align(
                                                alignment: Alignment.bottomCenter,
                                                child: Padding(
                                                  padding: EdgeInsets.only(bottom: 8),
                                                  child: Icon(LucideIcons.play, size: 16, color: DramaWave.gold),
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
                                            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: DramaWave.title(size: 15)),
                                            if (subtitle != null) ...[
                                              const SizedBox(height: 4),
                                              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: DramaWave.body(size: 12)),
                                            ],
                                            const SizedBox(height: 10),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: DramaWave.goldSoft,
                                                borderRadius: BorderRadius.circular(99),
                                                border: Border.all(color: DramaWave.gold.withValues(alpha: 0.35)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(LucideIcons.check, size: 13, color: DramaWave.gold),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    t('shortFilms.downloaded'),
                                                    style: const TextStyle(
                                                      color: DramaWave.gold,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Material(
                                        color: DramaWave.elevated,
                                        borderRadius: BorderRadius.circular(12),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => _openMenu(f),
                                          child: const SizedBox(
                                            width: 40,
                                            height: 40,
                                            child: Icon(LucideIcons.ellipsisVertical, size: 18, color: DramaWave.muted),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
