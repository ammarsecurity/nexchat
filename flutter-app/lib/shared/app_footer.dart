import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/feature_flags.dart';
import '../core/json.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/layout.dart';

const _lucideSvg = {
  'twitter': '<path d="M22 4s-.7 2.1-2 3.4c1.6 10-9.4 17.3-18 11.6 2.2.1 4.4-.6 6-2C3 15.5.5 9.6 3 5c2.2 2.6 5.6 4.1 9 4-.9-4.2 4-6.6 7-3.8 1.1 0 3-1.2 3-1.2z"/>',
  'instagram':
      '<rect width="20" height="20" x="2" y="2" rx="5" ry="5"/><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/><line x1="17.5" x2="17.51" y1="6.5" y2="6.5"/>',
  'facebook': '<path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/>',
  'tiktok': '<path d="m16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.87a.5.5 0 0 0-.752-.432L16 10.5"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
  'youtube':
      '<path d="M2.5 17a24.12 24.12 0 0 1 0-10 2 2 0 0 1 1.4-1.4 49.56 49.56 0 0 1 16.2 0A2 2 0 0 1 21.5 7a24.12 24.12 0 0 1 0 10 2 2 0 0 1-1.4 1.4 49.55 49.55 0 0 1-16.2 0A2 2 0 0 1 2.5 17"/><path d="m10 15 5-3-5-3z"/>',
  'linkedin':
      '<path d="M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-2-2 2 2 0 0 0-2 2v7h-4v-7a6 6 0 0 1 6-6z"/><rect width="4" height="12" x="2" y="9"/><circle cx="4" cy="4" r="2"/>',
  'whatsapp': '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
  'telegram': '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>',
};

/// components/AppFooter.vue — brand + social links from `sitecontent/social_links`.
class AppFooter extends StatefulWidget {
  const AppFooter({super.key});

  @override
  State<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends State<AppFooter> {
  List<Json> _links = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await fetchSiteContent('social_links');
    if (content == null || '$content'.isEmpty) return;
    try {
      final list = asJsonList(jsonDecode('$content'));
      if (mounted) setState(() => _links = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + tabBarClearance(context)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
        child: Column(children: [
          Text('NexChat', style: TextStyle(color: c.primary, fontSize: 15, fontWeight: FontWeight.w700)),
          if (_links.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
              for (final l in _links)
                Material(
                  color: c.bgCard,
                  shape: StadiumBorder(side: BorderSide(color: c.border)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () {
                      final url = l.s('url');
                      if (url != null && url.startsWith('http')) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SvgPicture.string(
                          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
                          'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${_lucideSvg[l.str('platform')] ?? _lucideSvg['telegram']}</svg>',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(c.textSecondary, BlendMode.srcIn),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
