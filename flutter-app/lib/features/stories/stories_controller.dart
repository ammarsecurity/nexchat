import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../calls/css_filter.dart';
import 'story_overlay.dart';

export 'story_overlay.dart';

/// stores/stories.js ring.
class StoryRing {
  const StoryRing({
    required this.userId,
    required this.name,
    this.avatar,
    this.hasUnseen = false,
    this.latestThumbUrl,
    this.latestAt,
    this.slideCount = 0,
    this.isMine = false,
  });

  final String userId;
  final String name;
  final String? avatar;
  final bool hasUnseen;
  final String? latestThumbUrl;
  final String? latestAt;
  final int slideCount;
  final bool isMine;

  factory StoryRing.fromJson(Map r) => StoryRing(
        userId: r.str('userId'),
        name: r.s('name') ?? '—',
        avatar: r.s('avatar'),
        hasUnseen: r.b('hasUnseen'),
        latestThumbUrl: r.s('latestThumbUrl'),
        latestAt: r.s('latestAt'),
        slideCount: r.i('slideCount'),
        isMine: r.b('isMine'),
      );

  StoryRing copyWith({String? name, String? avatar, bool? hasUnseen, String? latestThumbUrl, String? latestAt, int? slideCount, bool? isMine}) =>
      StoryRing(
        userId: userId,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        hasUnseen: hasUnseen ?? this.hasUnseen,
        latestThumbUrl: latestThumbUrl ?? this.latestThumbUrl,
        latestAt: latestAt ?? this.latestAt,
        slideCount: slideCount ?? this.slideCount,
        isMine: isMine ?? this.isMine,
      );
}

class StoriesState {
  const StoriesState({this.feed = const [], this.loading = false, this.loaded = false});
  final List<StoryRing> feed;
  final bool loading;
  final bool loaded;

  int get unseenCount => feed.where((r) => !r.isMine && r.hasUnseen).length;

  StoriesState copyWith({List<StoryRing>? feed, bool? loading, bool? loaded}) =>
      StoriesState(feed: feed ?? this.feed, loading: loading ?? this.loading, loaded: loaded ?? this.loaded);
}

class StoriesController extends Notifier<StoriesState> {
  @override
  StoriesState build() => const StoriesState();

  StoriesState get current => state;

  Future<void> fetchFeed({bool force = false}) async {
    if (state.loading) return;
    if (state.loaded && !force) return;
    if (!NetworkStatus.online.value) {
      state = state.copyWith(loading: false, loaded: true);
      return;
    }
    state = state.copyWith(loading: true);
    try {
      final data = await Api.get('/stories/feed');
      state = state.copyWith(feed: asJsonList(data).map(StoryRing.fromJson).toList(), loaded: true);
    } catch (_) {
      if (!state.loaded) state = state.copyWith(feed: const []);
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  void applyStoryPublished(Map? payload) {
    final userId = payload?.s('userId');
    if (payload == null || userId == null) return;
    final feed = [...state.feed];
    final idx = feed.indexWhere((r) => r.userId == userId);
    final prev = idx >= 0 ? feed[idx] : null;
    final ring = StoryRing(
      userId: userId,
      name: payload.s('publisherName') ?? prev?.name ?? '—',
      avatar: payload.s('publisherAvatar') ?? payload.s('avatar') ?? prev?.avatar,
      hasUnseen: true,
      latestThumbUrl: payload.s('thumbUrl') ?? prev?.latestThumbUrl,
      latestAt: DateTime.now().toIso8601String(),
      slideCount: (prev?.slideCount ?? 0) + 1,
      isMine: false,
    );
    if (idx >= 0) {
      feed[idx] = ring;
    } else {
      feed.insert(0, ring);
    }
    feed.sort((a, b) => (b.isMine ? 1 : 0) - (a.isMine ? 1 : 0));
    state = state.copyWith(feed: feed);
  }

  void patchAvatar(String userId, String? avatar) {
    final feed = [...state.feed];
    final idx = feed.indexWhere((r) => r.userId == userId);
    if (idx < 0) return;
    feed[idx] = feed[idx].copyWith(avatar: avatar);
    state = state.copyWith(feed: feed);
  }

  void applyStoryDeleted(Map? payload) {
    final userId = payload?.s('userId');
    if (userId == null) return;
    final feed = [...state.feed];
    final idx = feed.indexWhere((r) => r.userId == userId);
    if (idx < 0) return;
    final r = feed[idx];
    if (r.slideCount <= 1) {
      feed.removeAt(idx);
    } else {
      feed[idx] = r.copyWith(slideCount: r.slideCount - 1);
    }
    state = state.copyWith(feed: feed);
  }

  void markRingSeen(String userId) {
    final idx = state.feed.indexWhere((r) => r.userId == userId);
    if (idx < 0) return;
    final feed = [...state.feed];
    feed[idx] = feed[idx].copyWith(hasUnseen: false);
    state = state.copyWith(feed: feed);
  }

  void invalidate() => state = state.copyWith(loaded: false);
}

final storiesProvider = NotifierProvider<StoriesController, StoriesState>(StoriesController.new);

/// A story slide as returned by `/stories/user/{id}` and `/stories/mine`.
class StorySlide {
  const StorySlide({
    required this.id,
    this.userId,
    this.mediaUrl,
    this.mediaType = 'image',
    this.caption,
    this.backgroundColor,
    this.filterId,
    this.videoDurationSeconds,
    this.viewCount = 0,
    this.likedByMe = false,
    this.likeCount = 0,
    this.overlayJson,
  });

  final String id;
  final String? userId;
  final String? mediaUrl;
  final String mediaType;
  final String? caption;
  final String? backgroundColor;
  final String? filterId;
  final num? videoDurationSeconds;
  final int viewCount;
  final bool likedByMe;
  final int likeCount;
  final String? overlayJson;

  bool get isVideo => mediaType == 'video';
  bool get isText => mediaType == 'text';

  StorySlide copyWith({bool? likedByMe, int? likeCount}) => StorySlide(
        id: id,
        userId: userId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        caption: caption,
        backgroundColor: backgroundColor,
        filterId: filterId,
        videoDurationSeconds: videoDurationSeconds,
        viewCount: viewCount,
        likedByMe: likedByMe ?? this.likedByMe,
        likeCount: likeCount ?? this.likeCount,
        overlayJson: overlayJson,
      );

  factory StorySlide.fromJson(Map s) => StorySlide(
        id: s.str('id'),
        userId: s.s('userId'),
        mediaUrl: s.s('mediaUrl'),
        mediaType: (s.s('mediaType') ?? 'image').toLowerCase(),
        caption: s.s('caption'),
        backgroundColor: s.s('backgroundColor'),
        filterId: s.s('filterId'),
        videoDurationSeconds: s.v('videoDurationSeconds') as num?,
        viewCount: s.i('viewCount'),
        likedByMe: s.b('likedByMe'),
        likeCount: s.i('likeCount'),
        overlayJson: storyOverlayAsString(s.v('overlayJson')),
      );
}

bool isVideoUrl(String? url) {
  if (url == null) return false;
  return RegExp(r'\.(mp4|mov|webm|m4v)(\?|$)', caseSensitive: false).hasMatch(url);
}

/// Same CSS filter strings as StoryViewerView / StoryEditorCanvas.
List<double>? storyFilterMatrix(String? id) {
  switch (id) {
    case 'grayscale':
      return CssFilter.grayscale(1).matrix;
    case 'sepia':
      return CssFilter.sepia(0.8).matrix;
    case 'vintage':
      return CssFilter.sepia(0.4).then(CssFilter.contrast(1.1)).matrix;
    case 'warm':
      return CssFilter.sepia(0.3).then(CssFilter.hueRotate(-10)).matrix;
    case 'cool':
      return CssFilter.hueRotate(180).then(CssFilter.saturate(0.85)).matrix;
    case 'vivid':
      return CssFilter.saturate(1.4).then(CssFilter.contrast(1.05)).matrix;
  }
  return null;
}

Widget applyStoryFilter(String? id, Widget child) {
  final m = storyFilterMatrix(id);
  return m == null ? child : ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
}

const defaultStoryBackground = 'linear-gradient(135deg,#2563eb 0%,#60a5fa 100%)';

/// Parses the CSS backgrounds stories store (`#hex` or `linear-gradient(<deg>deg, #a [p%], #b [p%])`).
BoxDecoration storyBackgroundDecoration(String? css, {BorderRadius? radius}) {
  final v = (css ?? '').trim();
  Color? hex(String s) {
    var h = s.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length != 6) return null;
    final n = int.tryParse(h, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }

  if (v.startsWith('linear-gradient')) {
    final deg = double.tryParse(RegExp(r'(-?\d+(?:\.\d+)?)deg').firstMatch(v)?.group(1) ?? '') ?? 135;
    final stops = RegExp(r'#([0-9a-fA-F]{3,6})\s*(\d+(?:\.\d+)?%)?').allMatches(v).toList();
    final colors = <Color>[];
    final positions = <double>[];
    for (final m in stops) {
      final c = hex(m.group(1)!);
      if (c == null) continue;
      colors.add(c);
      final p = m.group(2);
      positions.add(p == null ? double.nan : double.parse(p.replaceAll('%', '')) / 100);
    }
    if (colors.length >= 2) {
      final rad = (deg - 90) * math.pi / 180;
      final dx = math.cos(rad), dy = math.sin(rad);
      final hasAll = positions.every((p) => !p.isNaN);
      return BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: colors,
          stops: hasAll ? positions : null,
        ),
      );
    }
  }
  final solid = v.startsWith('#') ? hex(v) : null;
  if (solid != null) return BoxDecoration(color: solid, borderRadius: radius);
  return storyBackgroundDecoration('linear-gradient(135deg,#6c63ff,#ff6584)', radius: radius);
}

void paintStoryBackground(Canvas canvas, Size size, String? css) {
  final dec = storyBackgroundDecoration(css);
  final rect = Offset.zero & size;
  if (dec.gradient is LinearGradient) {
    canvas.drawRect(rect, Paint()..shader = (dec.gradient as LinearGradient).createShader(rect));
    return;
  }
  canvas.drawRect(rect, Paint()..color = dec.color ?? const Color(0xFF2563EB));
}