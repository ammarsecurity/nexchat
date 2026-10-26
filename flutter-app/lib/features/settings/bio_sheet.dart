import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import '../discover/discover_theme.dart';

Future<String?> showBioSheet(BuildContext context, {String? initial, Color? accent}) =>
    showAppSheet<String>(context, builder: (_) => BioSheet(initial: initial, accent: accent));

class BioSheet extends StatefulWidget {
  const BioSheet({super.key, this.initial, this.accent});
  final String? initial;
  final Color? accent;

  @override
  State<BioSheet> createState() => _BioSheetState();
}

class _BioSheetState extends State<BioSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String _error = '';

  static const _max = 160;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final text = _ctrl.text.trim();
      final res = await Api.put('/user/bio', {'bio': text.isEmpty ? null : text});
      final bio = res is Map ? (res['bio'] ?? res['Bio'])?.toString() : text;
      if (mounted) Navigator.pop(context, bio ?? text);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = widget.accent ?? c.primary;
    final len = _ctrl.text.characters.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t('settings.editBio'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text(t('settings.bioHint'), style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.35)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLength: _max,
            maxLines: 4,
            minLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('settings.bioPlaceholder'),
              counterText: '$len / $_max',
              filled: true,
              fillColor: c.bgElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 1.5)),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: TextStyle(color: c.danger, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          PillButton(
            label: _saving ? t('common.loading') : t('common.save'),
            color: accent == DiscoverTheme.red ? DiscoverTheme.red : accent,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
