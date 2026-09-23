import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// views/SavedCodesView.vue
class SavedCodesScreen extends StatefulWidget {
  const SavedCodesScreen({super.key});

  @override
  State<SavedCodesScreen> createState() => _SavedCodesScreenState();
}

class _SavedCodesScreenState extends State<SavedCodesScreen> {
  final List<void Function()> _offs = [];
  List<Json> _codes = [];
  bool _listLoading = false;
  bool _loading = false;
  bool _waitingForAccept = false;
  String _codeError = '';
  Timer? _connectionTimeout;

  @override
  void initState() {
    super.initState();
    Hubs.matching.start().catchError((_) {});
    final h = Hubs.matching;
    _offs.addAll([
      h.on('ConnectionRequestSent', (_) {
        if (mounted) setState(() => _waitingForAccept = true);
        _startTimeout();
      }),
      h.on('ConnectionDeclined', (_) => _fail(t('home.requestDeclined'))),
      h.on('CodeError', (a) => _fail(a.isNotEmpty && '${a.first}'.isNotEmpty ? '${a.first}' : t('home.connectionError'))),
      h.on('ConnectionCancelled', (_) {
        _clearTimeout();
        if (mounted) setState(() => _waitingForAccept = _loading = false);
      }),
      h.on('MatchFound', (_) {
        _clearTimeout();
        if (mounted) setState(() => _waitingForAccept = _loading = false);
      }),
    ]);
    _fetch();
  }

  @override
  void dispose() {
    for (final off in _offs) {
      off();
    }
    _clearTimeout();
    super.dispose();
  }

  void _fail(String msg) {
    _clearTimeout();
    if (!mounted) return;
    setState(() {
      _waitingForAccept = _loading = false;
      _codeError = msg;
    });
  }

  void _clearTimeout() {
    _connectionTimeout?.cancel();
    _connectionTimeout = null;
  }

  void _startTimeout() {
    _clearTimeout();
    _connectionTimeout = Timer(const Duration(seconds: 60), () {
      _connectionTimeout = null;
      _fail(t('home.timeoutError'));
      Hubs.matching.invoke('CancelConnectionRequest').catchError((_) => null);
    });
  }

  Future<void> _fetch() async {
    setState(() => _listLoading = true);
    try {
      final data = await Api.get('/user/saved-codes');
      if (mounted) setState(() => _codes = asJsonList(data));
    } catch (_) {
      if (mounted) setState(() => _codes = []);
    } finally {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _remove(String code) async {
    try {
      await Api.delete('/user/saved-codes/${Uri.encodeComponent(code)}');
      await _fetch();
    } catch (_) {}
  }

  Future<void> _connect(String code) async {
    setState(() {
      _codeError = '';
      _loading = true;
      _waitingForAccept = false;
    });
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('ConnectByCode', [code]);
    } catch (_) {
      _fail(t('home.connectionError'));
    }
  }

  Future<void> _cancelRequest() async {
    _clearTimeout();
    setState(() => _waitingForAccept = _loading = false);
    try {
      await Hubs.matching.invoke('CancelConnectionRequest');
    } catch (_) {}
  }

  Future<void> _openAdd() async {
    final added = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (_) => const _AddCodeDialog(),
    );
    if (added == true) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_listLoading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(t('common.loading'), style: TextStyle(color: c.textMuted))),
      );
    } else if (_codes.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(children: [
          Icon(LucideIcons.bookmarkPlus, size: 48, color: c.textMuted),
          const SizedBox(height: 12),
          Text(t('home.noSavedCodes'), style: TextStyle(fontSize: 15, color: c.textMuted)),
          const SizedBox(height: 6),
          Text(t('savedCodes.addFirstHint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary)),
          const SizedBox(height: 16),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: PillButton(label: t('home.addCode'), onPressed: _openAdd)),
        ]),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_codeError.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: const Color(0x1AF44336), borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Row(children: [
              Icon(LucideIcons.circleAlert, size: 16, color: c.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(_codeError, style: TextStyle(fontSize: 13, color: c.danger))),
            ]),
          ),
        for (final item in _codes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: c.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _connect(item.str('code')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.str('code'),
                            textDirection: TextDirection.ltr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                        if ((item.s('label') ?? '').isNotEmpty)
                          Text(item.str('label'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                      ]),
                    ),
                    _SquareBtn(icon: LucideIcons.phoneCall, size: 18, bg: c.primarySoft, fg: c.primary, onTap: () => _connect(item.str('code'))),
                    const SizedBox(width: 8),
                    _SquareBtn(icon: LucideIcons.trash2, size: 16, bg: const Color(0x1FFF6584), fg: c.danger, onTap: () => _remove(item.str('code'))),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    }

    return Stack(children: [
      ModernPage(
        title: t('home.savedCodes'),
        backTo: '/settings',
        actions: [GlassIconButton(icon: LucideIcons.bookmarkPlus, onTap: _openAdd)],
        body: body,
      ),
      LoaderOverlay(show: _loading, text: _waitingForAccept ? t('home.waitingForAccept') : t('home.connecting')),
      if (_waitingForAccept)
        Positioned(
          left: 0,
          right: 0,
          bottom: 48 + MediaQuery.paddingOf(context).bottom,
          child: Center(
            child: Material(
              color: const Color(0xB3000000),
              shape: const StadiumBorder(side: BorderSide(color: Color(0x33FFFFFF))),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _cancelRequest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(LucideIcons.phoneOff, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(t('home.cancelRequest'), style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _SquareBtn extends StatelessWidget {
  const _SquareBtn({required this.icon, required this.size, required this.bg, required this.fg, required this.onTap});
  final IconData icon;
  final double size;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: size, color: fg)),
        ),
      );
}

class _AddCodeDialog extends StatefulWidget {
  const _AddCodeDialog();

  @override
  State<_AddCodeDialog> createState() => _AddCodeDialogState();
}

class _AddCodeDialogState extends State<_AddCodeDialog> {
  final _code = TextEditingController();
  final _label = TextEditingController();
  String _error = '';
  bool _submitting = false;

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty || !code.startsWith('NX-') || code.length != 7) {
      setState(() => _error = t('home.codeFormatError'));
      return;
    }
    setState(() {
      _error = '';
      _submitting = true;
    });
    try {
      final label = _label.text.trim();
      await Api.post('/user/saved-codes', {'code': code, 'label': label.isEmpty ? null : label});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final m = Api.errorMessage(e);
      if (mounted) setState(() => _error = m.isNotEmpty ? m : t('common.error'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    InputDecoration deco(String hint) => InputDecoration(hintText: hint, counterText: '');
    return Dialog(
      backgroundColor: c.bgCard,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(t('savedCodes.addModalTitle'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3, color: c.textPrimary)),
              ),
              Material(
                color: c.bgElevated,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => Navigator.pop(context),
                  child: SizedBox(width: 36, height: 36, child: Icon(LucideIcons.x, size: 20, color: c.textSecondary)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(t('savedCodes.addCodeDesc'), style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              maxLength: 7,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase()))],
              onChanged: (_) => setState(() => _error = ''),
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700, letterSpacing: 1),
              decoration: deco(t('savedCodes.codePlaceholder')),
            ),
            const SizedBox(height: 10),
            TextField(controller: _label, maxLength: 50, style: TextStyle(color: c.textPrimary), decoration: deco(t('savedCodes.labelPlaceholder'))),
            const SizedBox(height: 12),
            PillButton(
              label: _submitting ? t('common.loading') : t('home.addCode'),
              onPressed: _submitting || _code.text.trim().isEmpty ? null : _submit,
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(LucideIcons.circleAlert, size: 14, color: c.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error, style: TextStyle(fontSize: 13, color: c.danger))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
