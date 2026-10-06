import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'short_film_downloads.dart';
import 'short_films_controller.dart';

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
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        SheetAction(
          icon: LucideIcons.play,
          label: t('shortFilms.play'),
          onTap: () {
            Navigator.pop(ctx);
            _open(f);
          },
        ),
        SheetAction(
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
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    final light = Theme.of(context).brightness == Brightness.light;

    return ModernPage(
      title: t('shortFilms.downloads'),
      backTo: '/short-films',
      scroll: false,
      padding: EdgeInsets.zero,
      body: ColoredBox(
        color: light ? const Color(0xFFF7F8FA) : c.bgPrimary,
        child: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : _films.isEmpty
              ? EmptyState(icon: LucideIcons.download, text: t('shortFilms.emptyDownloads'))
              : RefreshIndicator(
                  color: c.primary,
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, pad.bottom + 28),
                    itemCount: _films.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                        color: light ? const Color(0xFFE8ECF2) : c.bgElevated,
                        child: Icon(LucideIcons.film, size: 22, color: c.primary.withValues(alpha: 0.55)),
                      );

                      return Material(
                        color: light ? Colors.white : c.bgCard,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: light ? const Color(0x140F172A) : c.border.withValues(alpha: 0.7),
                          ),
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
                                  borderRadius: BorderRadius.circular(14),
                                  child: SizedBox(
                                    width: 72,
                                    height: 96,
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
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [Color(0x00000000), Color(0x66000000)],
                                            ),
                                          ),
                                        ),
                                        const Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Padding(
                                            padding: EdgeInsets.only(bottom: 8),
                                            child: Icon(LucideIcons.play, size: 18, color: Colors.white),
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
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: light ? const Color(0xFF0F172A) : c.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          height: 1.3,
                                        ),
                                      ),
                                      if (subtitle != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: light ? const Color(0xFF64748B) : c.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: c.success.withValues(alpha: light ? 0.12 : 0.18),
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(LucideIcons.check, size: 13, color: c.success),
                                            const SizedBox(width: 4),
                                            Text(
                                              t('shortFilms.downloaded'),
                                              style: TextStyle(
                                                color: c.success,
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
                                const SizedBox(width: 4),
                                Material(
                                  color: light ? const Color(0x0F0F172A) : c.bgElevated,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _openMenu(f),
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Icon(
                                        LucideIcons.ellipsisVertical,
                                        size: 18,
                                        color: light ? const Color(0xFF64748B) : c.textSecondary,
                                      ),
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
    );
  }
}
