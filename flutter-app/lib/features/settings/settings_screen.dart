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
import '../discover/discover_opt_in.dart';
import 'avatar_picker_sheet.dart';
import 'bio_sheet.dart';
import 'birth_date_sheet.dart';
import 'profile_photos_sheet.dart';

/// views/SettingsView.vue — profile & preferences, aligned with app chrome.
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

  Future<void> _setDiscoverEnabled(bool value) async {
    final ok = await ref.read(discoverOptInProvider.notifier).setEnabled(value);
    if (!mounted) return;
    if (!ok) {
      showToast(context, t('common.error'), error: true);
      return;
    }
    final flags = ref.read(featureFlagsProvider).value ?? FeatureFlags.hiddenUntilLoaded;
    if (!value && !flags.randomChat && !flags.codeConnect && GoRouter.of(context).state.uri.path == '/home') {
      context.go('/conversations');
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
      final data = Json.from(await Api.get('/support/conversation') as Map);
      if (!mounted) return;
      final cid = data.s('conversationId');
      if (cid == null || cid.isEmpty) {
        showToast(context, t('common.error'), error: true);
        return;
      }
      context.push('/conversation/$cid');
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
    final saved = await showBirthDateSheet(context, initial: _profile?.s('birthDate'));
    if (saved != null && mounted) setState(() => _profile = {...?_profile, 'birthDate': saved});
  }

  Future<void> _openBio() async {
    final saved = await showBioSheet(context, initial: _profile?.s('bio'));
    if (saved != null && mounted) setState(() => _profile = {...?_profile, 'bio': saved});
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
    final discoverOpt = ref.watch(discoverOptInProvider);
    final update = ref.watch(appUpdateProvider);
    final cc = flags?.codeConnect == true;
    final discoverAdmin = flags?.discoverSwipe == true;
    final phone = _profile?.s('phoneNumber');
    final coverUrl = _profile?.s('coverImageUrl');
    final gender = user?.gender;
    final genderLabel = switch (gender) {
      'male' => t('gender.male'),
      'female' => t('gender.female'),
      'other' => t('gender.other'),
      _ => gender ?? '',
    };

    final avatarUrl = () {
      final a = auth.avatar;
      if (a != null && (a.startsWith('http') || a.startsWith('/'))) return a;
      final raw = _profile?['profilePhotos'] ?? _profile?['ProfilePhotos'];
      if (raw is List) {
        for (final e in raw) {
          final s = '$e'.trim();
          if (s.startsWith('http') || s.startsWith('/')) return s;
        }
      }
      return a;
    }();
    final bio = (_profile?.s('bio') ?? '').trim();
    final bioPreview = bio.isEmpty
        ? t('settings.bioNotSet')
        : (bio.length > 56 ? '${bio.substring(0, 56)}…' : bio);
    final featuredAccent = light ? const Color(0xFFFF7300) : const Color(0xFFFFD700);

    return Stack(children: [
      ModernPage(
        title: t('settings.title'),
        showBack: false,
        padding: EdgeInsets.fromLTRB(16, 0, 16, tabScrollPadding(context, extra: 20)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // —— Profile hero ——
          _Surface(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SizedBox(
                height: 132,
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: c.bgSecondary),
                  if (!_coverError && coverUrl != null && isImageAvatar(coverUrl))
                    CachedNetworkImage(
                      imageUrl: Api.absoluteUrl(coverUrl)!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Image.asset('assets/images/cover.jpg', fit: BoxFit.cover),
                    )
                  else
                    Image.asset('assets/images/cover.jpg', fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          c.bgPrimary.withValues(alpha: 0.05),
                          c.bgPrimary.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 12,
                    bottom: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: _uploadCover,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(LucideIcons.image, size: 15, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(t('settings.changeCover'),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Row(children: [
                  GestureDetector(
                    onTap: () async {
                      final saved = await showProfilePhotosSheet(context);
                      if (saved && mounted) await _loadProfile();
                    },
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: c.bgCard, width: 3),
                            boxShadow: [
                              BoxShadow(color: c.shadow, blurRadius: 16, offset: const Offset(0, 6)),
                              if (user?.isFeatured == true)
                                BoxShadow(color: featuredAccent.withValues(alpha: 0.35), blurRadius: 14),
                            ],
                          ),
                          foregroundDecoration: user?.isFeatured == true
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: featuredAccent.withValues(alpha: 0.75), width: 2),
                                )
                              : null,
                          child: UserAvatar(url: avatarUrl, name: user?.name ?? '', size: 66),
                        ),
                        if (user?.isFeatured == true)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Icon(LucideIcons.crown, size: 18, color: featuredAccent),
                          ),
                        PositionedDirectional(
                          bottom: 2,
                          end: 2,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.bgCard, width: 2),
                            ),
                            child: const Icon(LucideIcons.pencil, size: 11, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        user?.name ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25, color: c.textPrimary),
                      ),
                      if (genderLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _Pill(genderLabel),
                      ],
                    ]),
                  ),
                ]),
              ),
            ]),
          ),

          // —— Profile details (one grouped surface) ——
          _section(t('settings.profile')),
          _Surface(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (cc)
                _InfoRow(
                  icon: LucideIcons.hash,
                  title: t('settings.contactCode'),
                  value: user?.uniqueCode ?? '',
                  onTap: _copyCode,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _IconChip(
                      onTap: _copyCode,
                      child: _copied
                          ? Icon(LucideIcons.check, size: 16, color: c.success)
                          : Icon(LucideIcons.copy, size: 16, color: c.primary),
                    ),
                    const SizedBox(width: 8),
                    _IconChip(onTap: _shareInvite, child: Icon(LucideIcons.share2, size: 16, color: c.primary)),
                  ]),
                ),
              if (cc) _hairline(c),
              _InfoRow(
                icon: LucideIcons.globe,
                title: '${t('completeProfile.country')} & ${t('completeProfile.phone')}',
                value: (phone?.isNotEmpty ?? false) ? '+$phone' : t('completeProfile.selectCountry'),
                ltrValue: phone?.isNotEmpty ?? false,
                onTap: () async {
                  await context.push('/complete-profile?from=settings');
                  if (mounted) _loadProfile();
                },
              ),
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.calendar,
                title: t('settings.birthDate'),
                value: _formattedBirthDate ?? t('settings.birthDateNotSet'),
                onTap: _openBirthDate,
              ),
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.quote,
                title: t('settings.bio'),
                value: bioPreview,
                onTap: _openBio,
              ),
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.messageCircle,
                title: t('settings.supportChat'),
                value: t('settings.supportDesc'),
                onTap: _supportLoading ? null : _openSupport,
              ),
            ]),
          ),

          _section(t('settings.permissions')),
          _Surface(
            padding: EdgeInsets.zero,
            child: _InfoRow(
              icon: LucideIcons.camera,
              title: t('settings.cameraMicPermissions'),
              value: _mediaPermMessage.isNotEmpty ? _mediaPermMessage : t('settings.cameraMicDesc'),
              valueColor: _mediaPermMessage.isNotEmpty ? (_mediaPermSuccess ? c.success : c.danger) : null,
              onTap: _mediaPermLoading ? null : _requestMediaPerms,
            ),
          ),

          _section(t('settings.general')),
          _Surface(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _InfoRow(
                icon: LucideIcons.globe,
                title: t('settings.language'),
                onTap: () => ref.read(localeProvider.notifier).toggle(),
                trailing: _Pill(locale.languageCode == 'ar' ? 'عربي' : 'English'),
                showChevron: false,
              ),
              _hairline(c),
              _InfoRow(
                icon: light ? LucideIcons.moon : LucideIcons.sun,
                title: light ? t('settings.darkMode') : t('settings.lightMode'),
                onTap: () => ref.read(lightThemeProvider.notifier).toggle(),
                trailing: _Pill(light ? t('settings.dark') : t('settings.light')),
                showChevron: false,
              ),
              _hairline(c),
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
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.bellRing,
                title: t('settings.notificationCenter'),
                onTap: () => context.push('/notifications'),
              ),
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.phone,
                title: t('calls.title'),
                onTap: () => context.push('/calls'),
              ),
              if (cc) ...[
                _hairline(c),
                _InfoRow(
                  icon: LucideIcons.send,
                  title: t('connectionHistory.title'),
                  onTap: () => context.push('/connection-history'),
                ),
              ],
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.ban,
                title: t('blocked.title'),
                onTap: () => context.push('/blocked'),
              ),
              if (cc) ...[
                _hairline(c),
                _InfoRow(
                  icon: LucideIcons.bookmarkPlus,
                  title: t('home.savedCodes'),
                  onTap: () => context.push('/saved-codes'),
                ),
              ],
              _hairline(c),
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
              if (discoverAdmin) ...[
                _hairline(c),
                _ToggleBlock(
                  icon: LucideIcons.heartHandshake,
                  on: discoverOpt.enabled,
                  title: t('settings.discoverEnabled'),
                  hint: discoverOpt.enabled ? t('settings.discoverEnabledHintOn') : t('settings.discoverEnabledHintOff'),
                  desc: t('settings.discoverEnabledDesc'),
                  pill: discoverOpt.enabled ? t('settings.discoverEnabledOn') : t('settings.discoverEnabledOff'),
                  onLabel: t('settings.discoverEnabledOn'),
                  offLabel: t('settings.discoverEnabledOff'),
                  onColorSuccess: true,
                  onSelect: _setDiscoverEnabled,
                ),
              ],
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.shield,
                title: t('settings.privacyPolicy'),
                onTap: () => context.push('/privacy'),
              ),
              _hairline(c),
              _InfoRow(
                icon: LucideIcons.scrollText,
                title: t('settings.termsOfService'),
                onTap: () => context.push('/terms'),
              ),
            ]),
          ),

          _section(t('settings.app')),
          if (update?.hasUpdate == true && update?.downloadUrl != null) ...[
            _Surface(
              padding: EdgeInsets.zero,
              accent: const Color(0xFF00D4FF),
              child: _InfoRow(
                icon: LucideIcons.download,
                title: t('settings.updateAvailable'),
                value: t('settings.updateAvailableDesc'),
                iconColor: const Color(0xFF00D4FF),
                onTap: _openUpdateUrl,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _Surface(
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 48, width: 48, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NexChat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text(t('settings.tagline'), style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.35)),
                  const SizedBox(height: 8),
                  _Pill('v$_version'),
                ]),
              ),
            ]),
          ),

          _section(t('settings.account')),
          _DangerButton(icon: LucideIcons.logOut, label: t('home.logout'), filled: true, onTap: _confirmLogout),
          const SizedBox(height: 10),
          _DangerButton(icon: LucideIcons.trash2, label: t('settings.deleteAccount'), onTap: _openDelete),
        ]),
      ),
      LoaderOverlay(show: _uploadingCover, text: t('settings.uploadingCover')),
      LoaderOverlay(show: _deleting, text: t('settings.deletingAccount')),
      LoaderOverlay(show: _supportLoading, text: t('settings.openingSupport')),
    ]);
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: context.colors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            height: 1.2,
          ),
        ),
      );

  Widget _hairline(AppColors c) => Divider(height: 1, thickness: 1, color: c.border, indent: 66, endIndent: 14);
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16), this.accent});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent?.withValues(alpha: 0.28) ?? c.border),
        boxShadow: [
          BoxShadow(
            color: light ? const Color(0x0A0F172A) : c.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: Padding(padding: padding, child: child)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.trailing,
    this.ltrValue = false,
    this.showChevron = true,
    this.iconColor,
    this.valueColor,
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool ltrValue;
  final bool showChevron;
  final Color? iconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = iconColor ?? c.primary;
    final chevron = Icon(
      Directionality.of(context) == TextDirection.rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
      size: 18,
      color: c.textMuted,
    );
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null && trailing == null ? 0.65 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25, color: c.textPrimary)),
                if (value != null && value!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    value!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: ltrValue ? TextDirection.ltr : null,
                    style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w500, color: valueColor ?? c.textSecondary),
                  ),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!] else if (showChevron) chevron,
          ]),
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.primarySoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 36, height: 36, child: Center(child: child)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: on ? c.primary.withValues(alpha: 0.18) : c.danger.withValues(alpha: light ? 0.1 : 0.12),
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
