import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/network/api_client.dart';

/// utils/videoPoster.js — shows the first frame (≈0.1s) of a remote video as a still cover.
class VideoFramePoster extends StatefulWidget {
  const VideoFramePoster({super.key, required this.url, this.fit = BoxFit.cover, this.placeholder});
  final String url;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  State<VideoFramePoster> createState() => _VideoFramePosterState();
}

class _VideoFramePosterState extends State<VideoFramePoster> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoFramePoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _c?.dispose();
      _c = null;
      _ready = false;
      _load();
    }
  }

  Future<void> _load() async {
    final src = Api.absoluteUrl(widget.url);
    if (src == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(src), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.seekTo(const Duration(milliseconds: 100));
      if (mounted && _c == c) setState(() => _ready = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (!_ready || c == null) return widget.placeholder ?? const ColoredBox(color: Color(0xFF111111));
    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      ),
    );
  }
}
