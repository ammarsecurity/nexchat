import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets.dart';
import 'short_film_downloads.dart';
import 'short_film_engagement.dart';
import 'short_films_controller.dart';
import 'short_films_theme.dart';

enum LibraryTab { watchLater, downloads, likes }

class ShortFilmLibraryScreen extends ConsumerStatefulWidget {
  const ShortFilmLibraryScreen({super.key, this.initialTab = LibraryTab.watchLater});
  final LibraryTab initialTab;

  @override
  ConsumerState<ShortFilmLibraryScreen> createState() => _ShortFilmLibraryScreenState();
}

class _ShortFilmLibraryScreenState extends ConsumerState<ShortFilmLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<ShortFilm> _watchLater = const [];
  List<ShortFilm> _likes = const [];
  List<ShortFilm> _downloads = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.index.clamp(0, 2),
    );
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final (later, likes, offline) = await (
        ShortFilmEngagementApi.instance.watchLaterList(),
        ShortFilmEngagementApi.instance.likesList(),
        ShortFilmDownloads.instance.listFilms(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _watchLater = later;
        _likes = likes;
        _downloads = offline;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _open(ShortFilm f) {
    if (f.seriesId != null && f.seriesId!.isNotEmpty) {
      context.push('/short-films/watch?start=${f.id}&series=${f.seriesId}');
    } else {
      context.push('/short-films/watch?start=${f.id}');
    }
  }

  Future<void> _removeWatchLater(ShortFilm f) async {
    await ShortFilmEngagementApi.instance.setWatchLater(f.id, false);
    if (mounted) setState(() => _watchLater = _watchLater.where((x) => x.id != f.id).toList());
  }

  Future<void> _removeLike(ShortFilm f) async {
    await ShortFilmEngagementApi.instance.setLiked(f.id, false);
    if (mounted) setState(() => _likes = _likes.where((x) => x.id != f.id).toList());
  }

  Future<void> _removeDownload(ShortFilm f) async {
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
    if (mounted) setState(() => _downloads = _downloads.where((x) => x.id != f.id).toList());
  }

  void _menuFor(LibraryTab tab, ShortFilm f) {
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
          label: switch (tab) {
            LibraryTab.watchLater => t('shortFilms.removeWatchLater'),
            LibraryTab.likes => t('shortFilms.removeLike'),
            LibraryTab.downloads => t('shortFilms.removeDownload'),
          },
          danger: true,
          onTap: () {
            Navigator.pop(ctx);
            switch (tab) {
              case LibraryTab.watchLater:
                _removeWatchLater(f);
              case LibraryTab.likes:
                _removeLike(f);
              case LibraryTab.downloads:
                _removeDownload(f);
            }
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: DramaWave.bg,
      body: Column(
        children: [
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
                    t('shortFilms.myLibrary'),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _LibrarySegmentedTabs(
              controller: _tabs,
              labels: [
                t('shortFilms.watchLater'),
                t('shortFilms.downloads'),
                t('shortFilms.liked'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DramaWave.gold))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _FilmList(
                        films: _watchLater,
                        emptyText: t('shortFilms.emptyWatchLater'),
                        emptyIcon: LucideIcons.bookmark,
                        onOpen: _open,
                        onMenu: (f) => _menuFor(LibraryTab.watchLater, f),
                        onRefresh: _reload,
                        onBrowse: () => context.go('/short-films'),
                      ),
                      _FilmList(
                        films: _downloads,
                        emptyText: t('shortFilms.emptyDownloads'),
                        emptyIcon: LucideIcons.download,
                        onOpen: _open,
                        onMenu: (f) => _menuFor(LibraryTab.downloads, f),
                        onRefresh: _reload,
                        offlineBadge: true,
                        onBrowse: () => context.go('/short-films'),
                      ),
                      _FilmList(
                        films: _likes,
                        emptyText: t('shortFilms.emptyLikes'),
                        emptyIcon: LucideIcons.heart,
                        onOpen: _open,
                        onMenu: (f) => _menuFor(LibraryTab.likes, f),
                        onRefresh: _reload,
                        onBrowse: () => context.go('/short-films'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control matching conversations tabs (even spacing, no TabBar edge clash).
class _LibrarySegmentedTabs extends StatefulWidget {
  const _LibrarySegmentedTabs({required this.controller, required this.labels});
  final TabController controller;
  final List<String> labels;

  @override
  State<_LibrarySegmentedTabs> createState() => _LibrarySegmentedTabsState();
}

class _LibrarySegmentedTabsState extends State<_LibrarySegmentedTabs> {
  @override
  void initState() {
    super.initState();
    widget.controller.animation?.addListener(_onTick);
    widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _LibrarySegmentedTabs old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.animation?.removeListener(_onTick);
      old.controller.removeListener(_onTick);
      widget.controller.animation?.addListener(_onTick);
      widget.controller.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.controller.animation?.removeListener(_onTick);
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    const gap = 4.0;
    final index = widget.controller.index.clamp(0, n - 1);
    final anim = (widget.controller.animation?.value ?? index.toDouble()).clamp(0.0, (n - 1).toDouble());

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DramaWave.elevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DramaWave.hairline),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final tabW = (box.maxWidth - gap * (n - 1)) / n;
        return Stack(
          children: [
            PositionedDirectional(
              start: anim * (tabW + gap),
              width: tabW,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DramaWave.goldSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DramaWave.gold.withValues(alpha: 0.45)),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (widget.controller.index != i) widget.controller.animateTo(i);
                      },
                      child: Center(
                        child: Text(
                          widget.labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            fontWeight: index == i ? FontWeight.w800 : FontWeight.w600,
                            color: index == i ? DramaWave.gold : DramaWave.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _FilmList extends StatelessWidget {
  const _FilmList({
    required this.films,
    required this.emptyText,
    required this.emptyIcon,
    required this.onOpen,
    required this.onMenu,
    required this.onRefresh,
    this.offlineBadge = false,
    this.onBrowse,
  });

  final List<ShortFilm> films;
  final String emptyText;
  final IconData emptyIcon;
  final void Function(ShortFilm) onOpen;
  final void Function(ShortFilm) onMenu;
  final Future<void> Function() onRefresh;
  final bool offlineBadge;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    if (films.isEmpty) {
      return RefreshIndicator(
        color: DramaWave.gold,
        backgroundColor: DramaWave.elevated,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
            DramaWaveEmpty(
              icon: emptyIcon,
              text: emptyText,
              actionLabel: onBrowse == null ? null : t('shortFilms.browseFilms'),
              onAction: onBrowse,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: DramaWave.gold,
      backgroundColor: DramaWave.elevated,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 4, 16, pad.bottom + 24),
        itemCount: films.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final f = films[i];
          final title = f.isEpisode ? f.displaySubtitle : f.title;
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
              onTap: () => onOpen(f),
              onLongPress: () => onMenu(f),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 88,
                        child: thumb != null && thumb.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: Api.absoluteUrl(thumb)!,
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
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DramaWave.title(size: 15),
                          ),
                          if (f.isEpisode && f.title != f.displaySubtitle) ...[
                            const SizedBox(height: 4),
                            Text(
                              f.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DramaWave.body(size: 12),
                            ),
                          ],
                          if (offlineBadge) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(LucideIcons.check, size: 13, color: DramaWave.gold),
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
                          ],
                        ],
                      ),
                    ),
                    Material(
                      color: DramaWave.elevated,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onMenu(f),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            LucideIcons.ellipsisVertical,
                            size: 18,
                            color: DramaWave.muted,
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
    );
  }
}
