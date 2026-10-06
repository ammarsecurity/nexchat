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
import 'short_film_engagement.dart';
import 'short_films_controller.dart';

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
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final sheet = light ? const Color(0xFFE6EBF3) : c.bgPrimary;
    final glassBg = light ? const Color(0xFFEEF2F8) : null;
    final glassBorder = light ? const Color(0x1F0F172A) : null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: sheet,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 8),
            child: Row(
              children: [
                GlassIconButton(
                  icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                  backgroundColor: glassBg,
                  borderColor: glassBorder,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/short-films');
                    }
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('shortFilms.myLibrary'),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: light ? const Color(0xFF0F172A) : c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 54),
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
                ? Center(child: CircularProgressIndicator(color: c.primary))
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
                      ),
                      _FilmList(
                        films: _downloads,
                        emptyText: t('shortFilms.emptyDownloads'),
                        emptyIcon: LucideIcons.download,
                        onOpen: _open,
                        onMenu: (f) => _menuFor(LibraryTab.downloads, f),
                        onRefresh: _reload,
                        offlineBadge: true,
                      ),
                      _FilmList(
                        films: _likes,
                        emptyText: t('shortFilms.emptyLikes'),
                        emptyIcon: LucideIcons.heart,
                        onOpen: _open,
                        onMenu: (f) => _menuFor(LibraryTab.likes, f),
                        onRefresh: _reload,
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
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final n = widget.labels.length;
    const gap = 4.0;
    final index = widget.controller.index.clamp(0, n - 1);
    final anim = (widget.controller.animation?.value ?? index.toDouble()).clamp(0.0, (n - 1).toDouble());
    final track = light ? const Color(0x140F172A) : c.bgElevated;
    final pill = light ? Colors.white : c.bgCard;
    final ink = light ? const Color(0xFF0F172A) : c.textPrimary;
    final muted = light ? const Color(0xFF64748B) : c.textMuted;
    final hairline = light ? const Color(0x1F0F172A) : c.border;

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
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
                  color: pill,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: light ? const Color(0x14000000) : c.shadow,
                      blurRadius: light ? 8 : 6,
                      offset: light ? const Offset(0, 2) : Offset.zero,
                    ),
                  ],
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
                            color: index == i ? ink : muted,
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
  });

  final List<ShortFilm> films;
  final String emptyText;
  final IconData emptyIcon;
  final void Function(ShortFilm) onOpen;
  final void Function(ShortFilm) onMenu;
  final Future<void> Function() onRefresh;
  final bool offlineBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final pad = MediaQuery.paddingOf(context);
    if (films.isEmpty) {
      return RefreshIndicator(
        color: c.primary,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            EmptyState(icon: emptyIcon, text: emptyText),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: c.primary,
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
            color: light ? const Color(0xFFDDE3EE) : c.bgElevated,
            child: Icon(LucideIcons.film, size: 22, color: c.primary.withValues(alpha: 0.55)),
          );
          return Material(
            color: light ? const Color(0xFFEEF2F8) : c.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: light ? const Color(0x1F0F172A) : c.border),
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
                            style: TextStyle(
                              color: light ? const Color(0xFF0F172A) : c.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (f.isEpisode && f.title != f.displaySubtitle) ...[
                            const SizedBox(height: 4),
                            Text(
                              f.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: light ? const Color(0xFF64748B) : c.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (offlineBadge) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(LucideIcons.check, size: 13, color: c.success),
                                const SizedBox(width: 4),
                                Text(
                                  t('shortFilms.downloaded'),
                                  style: TextStyle(color: c.success, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Material(
                      color: light ? const Color(0x140F172A) : c.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onMenu(f),
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
    );
  }
}
