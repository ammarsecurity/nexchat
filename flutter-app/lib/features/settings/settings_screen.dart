import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/share_links.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../services/media.dart';
import '../../services/push_service.dart';
import '../../services/update_check.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_widgets.dart';
import '../chat/chat_session.dart';
import 'avatar_picker_sheet.dart';

const _violet = Color(0xFF6C63FF);

/// views/SettingsView.vue
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Json? _profile;
  bool _coverError = false;
  bool _uploadingCover = false;
  bool _deleting = false;
  bool _supportLoading = false;
  bool _copied = false;
  bool _showOnline = true;
  bool _showOnlineSaving = false;
  bool _notificationsEnabled = true;
  bool _mediaPermLoading = false;
  String _mediaPermMessage = '';
  bool _mediaPermSuccess = true;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _notificationsEnabled = PushService.instance.enabled;
    _loadProfile();
    unawaited(ref.read(appUpdateProvider.notifier).refresh());
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    });
    unawaited(ref.read(featureFlagsProvider.notifier).refresh());
  }

  Future<void> _loadProfile() async {
    try {
      final data = await Api.get('/user/me');
      if (!mounted || data is! Map) return;
      final j = Json.from(data);
      setState(() {
        _profile = j;
        _coverError = false;
        _showOnline = j.v('showOnlineStatusToOthers') != false;
      });
    } catch (_) {}
  }

  Future<void> _uploadCover() async {
    if (!_requireOnline()) return;
    final file = await pickImage();
    if (file == null) return;
    setState(() => _uploadingCover = true);
    try {
      final url = await uploadFile('/media/upload', file.path, filename: file.name);
      await Api.put('/user/cover', {'coverImageUrl': url});
      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, 'coverImageUrl': url};
        _coverError = false;
      });
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _requestMediaPerms() async {
    setState(() {
      _mediaPermLoading = true;
      _mediaPermMessage = '';
    });
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();
      final ok = statuses.values.every((s) => s.isGranted || s.isLimited);
      _mediaPermMessage = t(ok ? 'settings.permissionsVerified' : 'settings.permissionsFailed');
      _mediaPermSuccess = ok;
    } catch (_) {
      _mediaPermMessage = t('settings.permissionsFailed');
      _mediaPermSuccess = false;
    }
    if (!mounted) return;
    setState(() => _mediaPermLoading = false);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _mediaPermMessage = '');
    });
  }

  Future<void> _enableNotifications() async {
    final user = ref.read(authProvider).user;
    if (user != null) await PushService.instance.init(user.id);
    await PushService.instance.optIn();
    if (mounted) setState(() => _notificationsEnabled = true);
  }

  void _disableNotifications() {
    PushService.instance.optOut();
    setState(() => _notificationsEnabled = false);
  }

  Future<void> _setShowOnline(bool value) async {
    if (_showOnlineSaving || _showOnline == value) return;
    setState(() => _showOnlineSaving = true);
    try {
      await Api.put('/user/privacy', {'showOnlineStatusToOthers': value});
      if (!mounted) return;
      setState(() {
        _showOnline = value;
        _profile = {...?_profile, 'showOnlineStatusToOthers': value};
      });
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _showOnlineSaving = false);
    }
  }

  void _copyCode() {
    final code = ref.read(authProvider).user?.uniqueCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _shareInvite() async {
    final user = ref.read(authProvider).user;
    final msg = await shareInviteCode(user?.uniqueCode, inviterName: user?.name);
    if (msg != null && mounted) showToast(context, msg);
  }

  bool _requireOnline() {
    if (NetworkStatus.online.value) return true;
    if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
    return false;
  }

  Future<void> _openSupport() async {
    if (!_requireOnline()) return;
    setState(() => _supportLoading = true);
    try {
      final data = Json.from(await Api.get('/support/session') as Map);
      if (!mounted) return;
      final sid = data.s('sessionId');
      if (sid == null || sid.isEmpty) {
        showToast(context, t('common.error'), error: true);
        return;
      }
      final partner = data.v('partner') is Map ? Json.from(data.v('partner') as Map) : null;
      ref.read(chatSessionProvider.notifier).setSession(sid, partner);
      context.push('/chat/$sid?support=1', extra: {'partner': partner});
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _supportLoading = false);
    }
  }

  Future<void> _confirmLogout() async {
    final c = context.colors;
    final ok = await _dialog<bool>(
      (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(LucideIcons.logOut, size: 48, color: c.primary),
        const SizedBox(height: 8),
        _dialogTitle(t('home.logoutConfirm')),
        _dialogText(t('home.logoutConfirmText')),
        _dialogActions(ctx, confirm: t('home.logout'), onConfirm: () => Navigator.pop(ctx, true)),
      ]),
    );
    if (ok != true || !mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  Future<void> _openDelete() async {
    final c = context.colors;
    final proceed = await _dialog<bool>(
      (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: Text('⚠️', style: TextStyle(fontSize: 48))),
        const SizedBox(height: 8),
        Center(child: _dialogTitle(t('settings.deleteAccountWarning'))),
        _dialogText(t('settings.deleteAccountText')),
        for (final k in ['deleteAccountList1', 'deleteAccountList2', 'deleteAccountList3'])
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
            child: Text('•  ${t('settings.$k')}', style: TextStyle(color: c.textMuted, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        Center(
          child: Text(t('settings.deleteAccountConfirm'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.danger)),
        ),
        const SizedBox(height: 16),
        _dialogActions(ctx, confirm: t('settings.yesDelete'), onConfirm: () => Navigator.pop(ctx, true)),
      ]),
    );
    if (proceed != true || !mounted) return;
    await _dialog<void>((ctx) => _DeletePasswordDialog(onDeleting: (v) {
          if (mounted) setState(() => _deleting = v);
        }));
  }

  Future<void> _openBirthDate() async {
    final saved = await showAppSheet<String>(context, builder: (_) => _BirthDateSheet(initial: _profile?.s('birthDate')));
    if (saved != null && mounted) setState(() => _profile = {...?_profile, 'birthDate': saved});
  }

  Future<void> _openUpdateUrl() async {
    final url = ref.read(appUpdateProvider)?.downloadUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) => showDialog<T>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: ctx.colors.bgCard,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: ctx.colors.border)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(padding: const EdgeInsets.all(16), child: builder(ctx)),
          ),
        ),
      );

  Widget _dialogTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(s, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );

  Widget _dialogText(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(s, style: TextStyle(fontSize: 14, height: 1.5, color: context.colors.textSecondary)),
      );

  Widget _dialogActions(BuildContext ctx, {required String confirm, required VoidCallback? onConfirm, bool busy = false}) =>
      _DialogActions(confirm: confirm, onConfirm: onConfirm, busy: busy);

  String? get _formattedBirthDate {
    final b = _profile?.s('birthDate');
    if (b == null || b.isEmpty) return null;
    final p = b.split('T').first.split('-').map(int.tryParse).toList();
    if (p.length < 3) return null;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final light = ref.watch(lightThemeProvider);
    final locale = ref.watch(localeProvider);
    final flags = ref.watch(featureFlagsProvider).value;
    final update = ref.watch(appUpdateProvider);
    final cc = flags?.codeConnect == true;
    final phone = _profile?.s('phoneNumber');
    final coverUrl = _profile?.s('coverImageUrl');
    final gender = user?.gender;
    final genderLabel = switch (gender) {
      'male' => t('gender.male'),
      'female' => t('gender.female'),
      'other' => t('gender.other'),
      _ => gender ?? '',
    };

    return Stack(children: [
      ModernPage(
        title: t('settings.title'),
        showBack: false,
        padding: EdgeInsets.fromLTRB(16, 0, 16, tabScrollPadding(context, extra: 16)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Profile card
          _Card(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SizedBox(
                height: 120,
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Color(0xFF1E3A8A)),
                  if (!_coverError && coverUrl != null && isImageAvatar(coverUrl))
                    CachedNetworkImage(
                      imageUrl: Api.absoluteUrl(coverUrl)!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Image.asset('assets/images/cover.jpg', fit: BoxFit.cover),
                    )
                  else
                    Image.asset('assets/images/cover.jpg', fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x260F172A), Color(0x730F172A)],
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 12,
                    bottom: 10,
                    child: GestureDetector(
                      onTap: _uploadCover,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0x8C0F172A), borderRadius: BorderRadius.circular(999)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(LucideIcons.image, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(t('settings.changeCover'),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => showAvatarPicker(context),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: c.border, width: 2),
                            boxShadow: user?.isFeatured == true
                                ? [BoxShadow(color: (light ? const Color(0xFFFF7300) : const Color(0xFFFFD700)).withValues(alpha: 0.3), blurRadius: 12)]
                                : null,
                          ),
                          foregroundDecoration: user?.isFeatured == true
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: (light ? const Color(0xFFFF7300) : const Color(0xFFFFD700)).withValues(alpha: 0.6), width: 2))
                              : null,
                          child: UserAvatar(url: auth.avatar, name: user?.name ?? '', size: 52),
                        ),
                        if (user?.isFeatured == true)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Icon(LucideIcons.crown, size: 18, color: light ? const Color(0xFFFF7300) : const Color(0xFFFFD700)),
                          ),
                        PositionedDirectional(
                          bottom: 0,
                          end: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                            child: const Icon(LucideIcons.pencil, size: 11, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user?.name ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _violet.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                        child: Text(genderLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primary)),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          if (cc) ...[
            _gap,
            _InfoCard(
              icon: LucideIcons.hash,
              title: t('settings.contactCode'),
              value: user?.uniqueCode ?? '',
              onTap: _copyCode,
              trailing: [
                _SquareBtn(
                  onTap: _copyCode,
                  child: _copied
                      ? Text(t('common.copiedShort'), style: TextStyle(color: c.success, fontSize: 11, fontWeight: FontWeight.w600))
                      : Icon(LucideIcons.copy, size: 16, color: c.primary),
                ),
                const SizedBox(width: 10),
                _SquareBtn(onTap: _shareInvite, child: Icon(LucideIcons.share2, size: 16, color: c.primary)),
              ],
            ),
          ],
          _gap,
          _InfoCard(
            icon: LucideIcons.globe,
            title: '${t('completeProfile.country')} & ${t('completeProfile.phone')}',
            value: (phone?.isNotEmpty ?? false) ? '+$phone' : t('completeProfile.selectCountry'),
            ltrValue: phone?.isNotEmpty ?? false,
            onTap: () async {
              await context.push('/complete-profile?from=settings');
              if (mounted) _loadProfile();
            },
            trailing: [_arrow(c, 18)],
          ),
          _gap,
          _InfoCard(
            icon: LucideIcons.calendar,
            title: t('settings.birthDate'),
            value: _formattedBirthDate ?? t('settings.birthDateNotSet'),
            onTap: _openBirthDate,
            trailing: [_arrow(c, 18)],
          ),
          if (cc) ...[
            _gap,
            _BigRowCard(
              icon: LucideIcons.messageCircle,
              title: t('settings.supportChat'),
              desc: t('settings.supportDesc'),
              onTap: _supportLoading ? null : _openSupport,
            ),
          ],
          _section(t('settings.permissions')),
          _Card(
            padding: EdgeInsets.zero,
            child: _LinkRow(
              onTap: _mediaPermLoading ? null : _requestMediaPerms,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: _violet.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Stack(children: [
                  Center(child: Icon(LucideIcons.camera, size: 18, color: c.primary)),
                  Positioned(bottom: 3, right: 3, child: Icon(LucideIcons.mic, size: 12, color: c.primary)),
                ]),
              ),
              title: t('settings.cameraMicPermissions'),
              desc: t('settings.cameraMicDesc'),
              trailing: _mediaPermMessage.isNotEmpty
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(_mediaPermMessage,
                          style: TextStyle(fontSize: 11, color: _mediaPermSuccess ? c.success : c.danger)),
                    )
                  : _arrow(c, 16),
            ),
          ),
          _section(t('settings.general')),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _LinkRow(
                onTap: () => ref.read(localeProvider.notifier).toggle(),
                icon: LucideIcons.globe,
                title: t('settings.language'),
                trailing: _Badge(locale.languageCode == 'ar' ? 'عربي' : 'English'),
              ),
              _LinkRow(
                onTap: () => ref.read(lightThemeProvider.notifier).toggle(),
                icon: light ? LucideIcons.moon : LucideIcons.sun,
                title: light ? t('settings.darkMode') : t('settings.lightMode'),
                trailing: _Badge(light ? t('settings.dark') : t('settings.light')),
              ),
              _ToggleBlock(
                icon: LucideIcons.bell,
                on: _notificationsEnabled,
                title: t('settings.notifications'),
                hint: _notificationsEnabled ? t('settings.notificationsStatusOn') : t('settings.notificationsStatusOff'),
                pill: _notificationsEnabled ? t('settings.statusOn') : t('settings.statusOff'),
                onLabel: t('settings.enable'),
                offLabel: t('settings.disable'),
                onSelect: (v) => v ? _enableNotifications() : _disableNotifications(),
              ),
              _LinkRow(onTap: () => context.push('/notifications'), icon: LucideIcons.bell, title: t('settings.notificationCenter'), trailing: _arrow(c, 16)),
              _LinkRow(onTap: () => context.push('/calls'), icon: LucideIcons.phone, title: t('calls.title'), trailing: _arrow(c, 16)),
              if (cc)
                _LinkRow(
                    onTap: () => context.push('/connection-history'),
                    icon: LucideIcons.send,
                    title: t('connectionHistory.title'),
                    trailing: _arrow(c, 16)),
              _LinkRow(onTap: () => context.push('/blocked'), icon: LucideIcons.ban, title: t('blocked.title'), trailing: _arrow(c, 16)),
              if (cc)
                _LinkRow(
                    onTap: () => context.push('/saved-codes'),
                    icon: LucideIcons.bookmarkPlus,
                    title: t('home.savedCodes'),
                    trailing: _arrow(c, 16)),
              _ToggleBlock(
                icon: LucideIcons.eye,
                on: _showOnline,
                saving: _showOnlineSaving,
                title: t('settings.showOnlineStatus'),
                hint: _showOnline ? t('settings.onlineStatusVisible') : t('settings.onlineStatusHidden'),
                desc: t('settings.showOnlineStatusDesc'),
                pill: _showOnline ? t('settings.showOnlineStatusOn') : t('settings.showOnlineStatusOff'),
                onLabel: t('settings.showOnlineStatusOn'),
                offLabel: t('settings.showOnlineStatusOff'),
                onColorSuccess: true,
                onSelect: _setShowOnline,
              ),
              _LinkRow(onTap: () => context.push('/privacy'), icon: LucideIcons.shield, title: t('settings.privacyPolicy'), trailing: _arrow(c, 16)),
              _LinkRow(
                  onTap: () => context.push('/terms'), icon: LucideIcons.scrollText, title: t('settings.termsOfService'), trailing: _arrow(c, 16)),
            ]),
          ),
          _section(t('settings.app')),
          if (update?.hasUpdate == true && update?.downloadUrl != null) ...[
            _BigRowCard(
              icon: LucideIcons.download,
              title: t('settings.updateAvailable'),
              desc: t('settings.updateAvailableDesc'),
              accent: const Color(0xFF00D4FF),
              onTap: _openUpdateUrl,
            ),
            _gap,
          ],
          _Card(
            child: Row(children: [
              Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('NexChat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(t('settings.tagline'), style: TextStyle(fontSize: 13, color: c.textMuted)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: _violet.withValues(alpha: 0.15),
                      border: Border.all(color: _violet.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('v$_version', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primary)),
                  ),
                ]),
              ),
            ]),
          ),
          _section(t('settings.account')),
          _DangerButton(icon: LucideIcons.logOut, label: t('home.logout'), filled: true, onTap: _confirmLogout),
          _gap,
          _DangerButton(icon: LucideIcons.trash2, label: t('settings.deleteAccount'), onTap: _openDelete),
        ]),
      ),
      LoaderOverlay(show: _uploadingCover, text: t('settings.uploadingCover')),
      LoaderOverlay(show: _deleting, text: t('settings.deletingAccount')),
      LoaderOverlay(show: _supportLoading, text: t('settings.openingSupport')),
    ]);
  }

  static const _gap = SizedBox(height: 8);

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(color: context.colors.textMuted, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
      );

  Widget _arrow(AppColors c, double size) =>
      Icon(Directionality.of(context) == TextDirection.rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: size, color: c.textMuted);
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16), this.tint = false, this.accent});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tint;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = accent ?? _violet;
    return Container(
      decoration: BoxDecoration(
        color: tint ? null : c.bgCard,
        gradient: tint
            ? LinearGradient(colors: [
                Color.alphaBlend(a.withValues(alpha: 0.08), c.bgCard),
                Color.alphaBlend(a.withValues(alpha: 0.02), c.bgCard),
              ])
            : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tint ? a.withValues(alpha: 0.25) : c.border),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: Padding(padding: padding, child: child)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.value, required this.onTap, this.trailing = const [], this.ltrValue = false});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final List<Widget> trailing;
  final bool ltrValue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Card(
      tint: true,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: _violet.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(icon, size: 18, color: c.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 1),
                Text(value,
                    textDirection: ltrValue ? TextDirection.ltr : null,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1, color: c.primary)),
              ]),
            ),
            ...trailing,
          ]),
        ),
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  const _SquareBtn({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _violet.withValues(alpha: 0.15),
            border: Border.all(color: _violet.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: child,
        ),
      );
}

class _BigRowCard extends StatelessWidget {
  const _BigRowCard({required this.icon, required this.title, required this.desc, required this.onTap, this.accent});
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = accent ?? _violet;
    return _Card(
      tint: true,
      accent: a,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: a.withValues(alpha: accent == null ? 0.2 : 0.25), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, size: 22, color: accent ?? c.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(fontSize: 13, color: c.textMuted)),
                ]),
              ),
              Icon(Directionality.of(context) == TextDirection.rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                  size: 20, color: c.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.onTap, required this.title, this.icon, this.leading, this.desc, this.trailing});
  final VoidCallback? onTap;
  final String title;
  final IconData? icon;
  final Widget? leading;
  final String? desc;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            leading ?? Icon(icon, size: 18, color: c.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: desc == null
                  ? Text(title, style: TextStyle(fontSize: 14, color: c.textSecondary))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                      const SizedBox(height: 1),
                      Text(desc!, style: TextStyle(fontSize: 11, height: 1.35, color: c.textMuted)),
                    ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _violet.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(color: context.colors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// `.setting-toggle-block` — icon + title + status pill + segmented on/off.
class _ToggleBlock extends StatelessWidget {
  const _ToggleBlock({
    required this.icon,
    required this.on,
    required this.title,
    required this.hint,
    required this.pill,
    required this.onLabel,
    required this.offLabel,
    required this.onSelect,
    this.desc,
    this.saving = false,
    this.onColorSuccess = false,
  });
  final IconData icon;
  final bool on;
  final String title;
  final String hint;
  final String pill;
  final String onLabel;
  final String offLabel;
  final ValueChanged<bool> onSelect;
  final String? desc;
  final bool saving;
  final bool onColorSuccess;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final offRed = light ? const Color(0xFFDC2626) : const Color(0xFFF87171);
    final onGreen = const Color(0xFF4ADE80);

    Widget segment(bool value, String label) {
      final active = on == value;
      Color bg = Colors.transparent;
      Color fg = c.textSecondary;
      Border? border;
      List<BoxShadow>? shadow;
      if (active && value) {
        bg = onColorSuccess ? c.success : c.primary;
        fg = Colors.white;
        shadow = [BoxShadow(color: (onColorSuccess ? const Color(0x5934D399) : const Color(0x6660A5FA)), blurRadius: 12, offset: const Offset(0, 2))];
      } else if (active && !value) {
        bg = (light ? const Color(0xFFEF4444) : const Color(0xFFF87171)).withValues(alpha: light ? 0.12 : 0.2);
        fg = light ? const Color(0xFFDC2626) : const Color(0xFFFCA5A5);
        border = Border.all(color: offRed.withValues(alpha: 0.38));
      }
      return Expanded(
        child: GestureDetector(
          onTap: saving ? null : () => onSelect(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 42),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: border, boxShadow: shadow),
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          ),
        ),
      );
    }

    return Opacity(
      opacity: saving ? 0.72 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: on ? _violet.withValues(alpha: 0.18) : c.danger.withValues(alpha: light ? 0.1 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: on ? c.primary : c.danger),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3, color: c.textPrimary)),
                const SizedBox(height: 4),
                Text(hint, style: TextStyle(fontSize: 12, height: 1.45, color: c.textMuted)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: on ? const Color(0x2622C55E) : offRed.withValues(alpha: light ? 0.1 : 0.14),
                border: Border.all(color: on ? const Color(0x5922C55E) : offRed.withValues(alpha: light ? 0.25 : 0.32)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(pill, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? onGreen : offRed)),
            ),
          ]),
          if (desc != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 52, top: 12),
              child: Text(desc!, style: TextStyle(fontSize: 12, height: 1.45, color: c.textMuted)),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.primarySoft,
              border: Border.all(color: c.primaryMuted),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [segment(true, onLabel), const SizedBox(width: 6), segment(false, offLabel)]),
          ),
        ]),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const pink = Color(0xFFFF6584);
    return Material(
      color: filled ? pink.withValues(alpha: 0.1) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: pink.withValues(alpha: filled ? 0.2 : 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: c.danger),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: c.danger, fontSize: filled ? 15 : 14, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.confirm, required this.onConfirm, this.busy = false});
  final String confirm;
  final VoidCallback? onConfirm;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Expanded(
        child: SizedBox(
          height: 44,
          child: TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: c.textSecondary,
              side: BorderSide(color: c.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text(t('common.cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: busy ? null : onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: c.danger,
              disabledBackgroundColor: c.danger.withValues(alpha: 0.6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text(confirm, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    ]);
  }
}

class _DeletePasswordDialog extends ConsumerStatefulWidget {
  const _DeletePasswordDialog({required this.onDeleting});
  final ValueChanged<bool> onDeleting;

  @override
  ConsumerState<_DeletePasswordDialog> createState() => _DeletePasswordDialogState();
}

class _DeletePasswordDialogState extends ConsumerState<_DeletePasswordDialog> {
  final _ctrl = TextEditingController();
  String _error = '';
  bool _deleting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_ctrl.text.isEmpty) {
      setState(() => _error = t('settings.enterPassword'));
      return;
    }
    setState(() {
      _deleting = true;
      _error = '';
    });
    widget.onDeleting(true);
    try {
      await Api.delete('/user/account', {'password': _ctrl.text});
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.go('/login');
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('settings.deleteFailed')));
    } finally {
      widget.onDeleting(false);
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('settings.confirmDelete'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Text(t('settings.enterPasswordToDelete'), style: TextStyle(fontSize: 14, height: 1.5, color: c.textSecondary)),
      const SizedBox(height: 12),
      AuthField(controller: _ctrl, hint: t('settings.password'), password: true, onSubmitted: (_) => _confirm()),
      if (_error.isNotEmpty) ...[const SizedBox(height: 10), AuthError(_error)],
      const SizedBox(height: 16),
      _DialogActions(
        confirm: _deleting ? t('settings.deleting') : t('settings.deletePermanently'),
        onConfirm: _confirm,
        busy: _deleting,
      ),
    ]);
  }
}

class _BirthDateSheet extends StatefulWidget {
  const _BirthDateSheet({this.initial});
  final String? initial;

  @override
  State<_BirthDateSheet> createState() => _BirthDateSheetState();
}

class _BirthDateSheetState extends State<_BirthDateSheet> {
  int? _d, _m, _y;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final b = widget.initial?.split('T').first;
    if (b != null && b.isNotEmpty) {
      final p = b.split('-').map(int.tryParse).toList();
      if (p.length >= 3) {
        _y = p[0];
        _m = p[1];
        _d = p[2];
      }
    }
  }

  int get _daysInMonth {
    final m = _m, y = _y;
    if (m == null) return 31;
    final leap = y != null && (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
    return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
  }

  String? get _dateStr {
    if (_d == null || _m == null || _y == null) return null;
    return '$_y-${'$_m'.padLeft(2, '0')}-${'$_d'.padLeft(2, '0')}';
  }

  void _clampDay() {
    if (_d != null && _d! > _daysInMonth) _d = _daysInMonth;
  }

  Future<void> _save() async {
    final s = _dateStr;
    if (s == null) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await Api.put('/user/birth-date', {'birthDate': s});
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final year = DateTime.now().year;
    final years = [for (var y = year - 18; y >= year - 120; y--) y];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('settings.editBirthDate'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 2,
            child: DateSelect(
              hint: t('register.day'),
              value: _d,
              items: [for (var i = 1; i <= _daysInMonth; i++) i],
              onChanged: (v) => setState(() => _d = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: DateSelect(
              hint: t('register.month'),
              value: _m,
              items: [for (var i = 1; i <= 12; i++) i],
              onChanged: (v) => setState(() {
                _m = v;
                _clampDay();
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DateSelect(
              hint: t('register.year'),
              value: _y,
              items: years,
              onChanged: (v) => setState(() {
                _y = v;
                _clampDay();
              }),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(t('register.birthDateHint'), style: TextStyle(fontSize: 12, color: c.textMuted)),
        if (_error.isNotEmpty) ...[const SizedBox(height: 12), AuthError(_error)],
        const SizedBox(height: 12),
        PillButton(
          label: _saving ? t('common.loading') : t('settings.saveBirthDate'),
          onPressed: _saving || _dateStr == null ? null : _save,
        ),
      ]),
    );
  }
}
