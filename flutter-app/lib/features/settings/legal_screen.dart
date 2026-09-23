import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// views/PrivacyPolicyView.vue + views/TermsOfServiceView.vue
class LegalScreen extends StatefulWidget {
  const LegalScreen.privacy({super.key})
      : contentKey = 'privacy_policy',
        titleKey = 'settings.privacyPolicy',
        loadingKey = 'settings.privacyLoading',
        emptyKey = 'settings.privacyEmpty',
        errorKey = 'common.error';
  const LegalScreen.terms({super.key})
      : contentKey = 'terms_of_service',
        titleKey = 'terms.title',
        loadingKey = 'terms.loading',
        emptyKey = 'terms.empty',
        errorKey = 'terms.loadError';

  final String contentKey;
  final String titleKey;
  final String loadingKey;
  final String emptyKey;
  final String errorKey;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  String _content = '';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('SiteContent/${widget.contentKey}', skipUnauthorized: true);
      if (!mounted) return;
      final raw = data is Map ? (data['content'] ?? data['Content']) : null;
      final s = raw?.toString() ?? '';
      setState(() {
        _content = s.isNotEmpty ? s : t(widget.emptyKey);
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _content = t(widget.errorKey);
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ModernPage(
      title: t(widget.titleKey),
      backTo: null,
      scroll: !_loading,
      body: _loading
          ? PageLoader(text: t(widget.loadingKey))
          : _HtmlPlain(text: _content, style: TextStyle(color: _failed ? c.danger : c.textSecondary, fontSize: 14, height: 1.7)),
    );
  }
}

/// Lightweight HTML/plain renderer (newlines → breaks, a few block/inline tags).
class _HtmlPlain extends StatefulWidget {
  const _HtmlPlain({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_HtmlPlain> createState() => _HtmlPlainState();
}

class _HtmlPlainState extends State<_HtmlPlain> {
  final _links = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _links) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _links) {
      r.dispose();
    }
    _links.clear();
    final blocks = _blocks(widget.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks)
          Padding(
            padding: EdgeInsets.only(bottom: b.heading ? 10 : 8, top: b.heading ? 8 : 0),
            child: Text.rich(TextSpan(style: widget.style, children: _inline(b.text, b.heading))),
          ),
      ],
    );
  }

  List<TextSpan> _inline(String raw, bool heading) {
    final style = heading ? widget.style.copyWith(fontWeight: FontWeight.w700, fontSize: (widget.style.fontSize ?? 14) + 2) : widget.style;
    final spans = <TextSpan>[];
    final re = RegExp(r'<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)</a>|<b>(.*?)</b>|<strong>(.*?)</strong>|<i>(.*?)</i>|<em>(.*?)</em>', caseSensitive: false, dotAll: true);
    var last = 0;
    for (final m in re.allMatches(raw)) {
      if (m.start > last) spans.add(TextSpan(text: _decode(_strip(raw.substring(last, m.start))), style: style));
      if (m.group(1) != null) {
        final href = m.group(1)!;
        final rec = TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        _links.add(rec);
        spans.add(TextSpan(
          text: _decode(_strip(m.group(2) ?? href)),
          style: style.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
          recognizer: rec,
        ));
      } else {
        final bold = m.group(3) ?? m.group(4);
        final italic = m.group(5) ?? m.group(6);
        spans.add(TextSpan(
          text: _decode(_strip(bold ?? italic ?? '')),
          style: style.copyWith(fontWeight: bold != null ? FontWeight.w700 : style.fontWeight, fontStyle: italic != null ? FontStyle.italic : style.fontStyle),
        ));
      }
      last = m.end;
    }
    if (last < raw.length) spans.add(TextSpan(text: _decode(_strip(raw.substring(last))), style: style));
    return spans;
  }
}

class _Block {
  const _Block(this.text, {this.heading = false});
  final String text;
  final bool heading;
}

List<_Block> _blocks(String raw) {
  var s = raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ');
  final out = <_Block>[];
  final headingRe = RegExp(r'<h[1-3][^>]*>([\s\S]*?)</h[1-3]>', caseSensitive: false);
  var last = 0;
  for (final m in headingRe.allMatches(s)) {
    _pushParagraphs(out, s.substring(last, m.start));
    out.add(_Block(_strip(m.group(1) ?? ''), heading: true));
    last = m.end;
  }
  _pushParagraphs(out, s.substring(last));
  return out.isEmpty ? [const _Block('')] : out;
}

void _pushParagraphs(List<_Block> out, String chunk) {
  for (final p in chunk.split(RegExp(r'\n{2,}'))) {
    final t = _strip(p.replaceAll('\n', ' ')).trim();
    if (t.isNotEmpty) out.add(_Block(t));
  }
}

String _strip(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

String _decode(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
