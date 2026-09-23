import 'package:flutter/material.dart';

/// Poster for a video URL when the API did not send a thumbnail.
/// `video_thumbnail` cannot build on AGP 9 (it still calls `jcenter()`), so cards
/// use [placeholder] instead of holding a live decoder per tile.
class VideoFramePoster extends StatelessWidget {
  const VideoFramePoster({super.key, required this.url, this.fit = BoxFit.cover, this.placeholder});
  final String url;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) => placeholder ?? const ColoredBox(color: Color(0xFF111111));
}
