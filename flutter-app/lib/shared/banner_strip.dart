import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/json.dart';
import '../core/network/api_client.dart';
import '../core/theme/app_colors.dart';

/// components/BannerStrip.vue — auto-scrolling promo banners for a placement.
class BannerStrip extends StatefulWidget {
  const BannerStrip({super.key, required this.placement, this.padding = const EdgeInsets.all(16)});
  final String placement;
  final EdgeInsets padding;

  @override
  State<BannerStrip> createState() => _BannerStripState();
}

class _BannerStripState extends State<BannerStrip> with SingleTickerProviderStateMixin {
  static const _speed = 0.8;
  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  List<Json> _banners = [];
  bool _interacting = false;
  Timer? _resume;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant BannerStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement) _fetch();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _resume?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    List<Json> list;
    try {
      list = asJsonList(await Api.get('banners', query: {'placement': widget.placement}, skipUnauthorized: true));
    } catch (_) {
      list = [];
    }
    if (!mounted) return;
    setState(() => _banners = list);
    if (_banners.length > 1) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration _) {
    if (_interacting || !_scroll.hasClients || _banners.length <= 1) return;
    final pos = _scroll.position;
    final half = (pos.maxScrollExtent + pos.viewportDimension) / 2;
    var next = pos.pixels + _speed;
    if (next >= half) next = 0;
    _scroll.jumpTo(next.clamp(0, pos.maxScrollExtent));
  }

  void _start() {
    _resume?.cancel();
    _interacting = true;
  }

  void _end() {
    _resume?.cancel();
    _resume = Timer(const Duration(milliseconds: 800), () => _interacting = false);
  }

  void _open(String? link) {
    if (link != null && link.startsWith('http')) launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final single = _banners.length == 1;
    final display = single ? _banners : [..._banners, ..._banners];
    return LayoutBuilder(builder: (context, box) {
      final vw = MediaQuery.sizeOf(context).width;
      final itemW = single
          ? (vw >= 480 ? 400.0 : 320.0).clamp(0.0, box.maxWidth - widget.padding.horizontal)
          : vw >= 480
              ? (vw * 0.42).clamp(240.0, 320.0)
              : (vw * 0.78).clamp(200.0, 280.0);
      final itemH = (itemW * 120 / 280).clamp(0.0, 140.0);
      final gap = (vw * 0.02).clamp(8.0, 14.0);
      Widget item(Json b) {
        final link = b.s('link');
        return GestureDetector(
          onTap: link == null || link.isEmpty ? null : () => _open(link),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: itemW,
              height: itemH,
              color: c.bgCard,
              child: CachedNetworkImage(imageUrl: Api.absoluteUrl(b.str('imageUrl')) ?? '', fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox()),
            ),
          ),
        );
      }

      return Padding(
        padding: widget.padding,
        child: single
            ? Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: item(display.first)))
            : Listener(
                onPointerDown: (_) => _start(),
                onPointerUp: (_) => _end(),
                onPointerCancel: (_) => _end(),
                child: SizedBox(
                  height: itemH + 8,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: ListView.separated(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: display.length,
                      separatorBuilder: (_, _) => SizedBox(width: gap),
                      itemBuilder: (_, i) => item(display[i]),
                    ),
                  ),
                ),
              ),
      );
    });
  }
}
