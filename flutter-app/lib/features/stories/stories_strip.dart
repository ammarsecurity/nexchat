import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../shared/video_poster.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'stories_controller.dart';

/// components/StoriesStrip.vue (variant="hero", inside the blue conversations card).
class StoriesStrip extends ConsumerStatefulWidget {
  const StoriesStrip({super.key});

  @override
  ConsumerState<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends ConsumerState<StoriesStrip> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(storiesProvider.notifier).fetchFeed());
  }

  void _openCreate() => context.push('/stories/create');

  void _openMine(StoriesState st) {
    final uid = ref.read(authProvider).user?.id;
    final mine = st.feed.where((r) => r.isMine).firstOrNull;
    if (uid != null && (mine?.slideCount ?? 0) > 0) {
      context.push('/stories/view/$uid');
      return;
    }
    _openCreate();
  }

  void _openRing(StoryRing ring) {
    if (ring.isMine && ring.slideCount == 0) {
      _openCreate();
      return;
    }
    context.push('/stories/view/${ring.userId}');
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storiesProvider);
    final auth = ref.watch(authProvider);
    return SizedBox(
      height: 70,
      child: st.loading
          ? const _Skeleton()
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
              children: [
                _Ring(
                  mine: true,
                  unseen: st.feed.any((r) => r.isMine && r.hasUnseen),
                  label: t('stories.yourStory'),
                  onTap: () => _openMine(st),
                  onPlus: _openCreate,
                  child: _mineThumb(st, auth.user?.name, auth.avatar),
                ),
                for (final ring in st.feed.where((r) => !r.isMine))
                  _Ring(
                    unseen: ring.hasUnseen,
                    label: ring.name,
                    onTap: () => _openRing(ring),
                    child: _ringThumb(ring),
                  ),
              ],
            ),
    );
  }

  Widget _face(String? url, String? name) =>
      UserAvatar(url: url, name: (name != null && name.isNotEmpty && name != '—') ? name : '?', size: 42);

  Widget _mineThumb(StoriesState st, String? name, String? avatarUrl) {
    final avatar = _face(avatarUrl, name);
    final thumb = st.feed.where((r) => r.isMine).firstOrNull?.latestThumbUrl;
    if (thumb == null || thumb.isEmpty) return avatar;
    if (isVideoUrl(thumb)) return VideoFramePoster(url: thumb, placeholder: avatar);
    return CachedNetworkImage(
      imageUrl: Api.absoluteUrl(thumb)!,
      fit: BoxFit.cover,
      memCacheWidth: _thumbPx,
      errorWidget: (_, _, _) => avatar,
      placeholder: (_, _) => avatar,
    );
  }

  Widget _ringThumb(StoryRing ring) {
    final avatar = _face(ring.avatar, ring.name);
    final thumb = ring.latestThumbUrl;
    if (thumb == null || thumb.isEmpty) return avatar;
    if (isVideoUrl(thumb)) return VideoFramePoster(url: thumb, placeholder: avatar);
    return CachedNetworkImage(
        imageUrl: Api.absoluteUrl(thumb)!,
        fit: BoxFit.cover,
        memCacheWidth: _thumbPx,
        errorWidget: (_, _, _) => avatar,
        placeholder: (_, _) => avatar);
  }

  static const _thumbPx = 240;
}

class _Ring extends StatelessWidget {
  const _Ring({required this.label, required this.onTap, required this.child, this.unseen = false, this.mine = false, this.onPlus});
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onPlus;
  final Widget child;
  final bool unseen;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      width: 42,
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mine ? Colors.white.withValues(alpha: 0.12) : const Color(0x33FFFFFF),
        border: mine ? null : Border.all(color: Colors.white.withValues(alpha: 0.92), width: 2),
      ),
      child: mine ? CustomPaint(foregroundPainter: _DashedCircle(), child: child) : child,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 54,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unseen ? null : Colors.white.withValues(alpha: 0.28),
                  gradient: unseen
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFFFFF), Color(0xFFBFDBFE), Color(0xFF60A5FA)],
                          stops: [0, 0.55, 1],
                        )
                      : null,
                ),
                child: inner,
              ),
              if (mine)
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: GestureDetector(
                    onTap: onPlus ?? onTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
                      ),
                      child: const Icon(LucideIcons.plus, size: 10, color: Color(0xFF2563EB)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.95), height: 1.2),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Offset.zero & size;
    const dashes = 14;
    const sweep = 6.283185307179586 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(1), i * sweep, sweep * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shade = Colors.white.withValues(alpha: 0.24);
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_ctrl),
      child: Row(children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, end: 10),
            child: SizedBox(
              width: 52,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: shade, shape: BoxShape.circle)),
                const SizedBox(height: 4),
                Container(width: 40, height: 8, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(6))),
              ]),
            ),
          ),
      ]),
    );
  }
}
