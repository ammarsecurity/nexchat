import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../conversations/avatar_overrides.dart';
import '../conversations/conversations_list_controller.dart';
import '../conversations/open_private.dart';
import '../settings/avatar_picker_sheet.dart';

/// views/UserProfileView.vue
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, required this.userId, this.conversationId});
  final String userId;
  final String? conversationId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  Json? _profile;
  bool _loading = true;
  bool _error = false;
  bool _copiedCode = false;
  bool _copiedPhone = false;
  bool _startingChat = false;
  bool _addingContact = false;
  bool _codeConnect = true;

  bool get _isOwn => ref.read(authProvider).user?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    ref.read(featureFlagsProvider.future).then((f) {
      if (mounted) setState(() => _codeConnect = f.codeConnect);
    }).catchError((_) {});
    _fetch();
  }

  @override
  void didUpdateWidget(UserProfileScreen old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      if (_isOwn) {
        _profile = {...Json.from(await Api.get('/user/me') as Map), 'isContact': true};
      } else {
        _profile = Json.from(await Api.get('/user/profile/${widget.userId}') as Map);
      }
    } catch (_) {
      if (_isOwn) {
        final me = ref.read(authProvider).user;
        if (me != null) {
          _profile = {'id': me.id, 'name': me.name, 'uniqueCode': me.uniqueCode, 'isContact': true};
          _error = false;
        } else {
          _profile = null;
          _error = true;
        }
      } else {
        final fromList = ref.read(conversationsListProvider).where((c) => c.str('partnerId') == widget.userId).firstOrNull;
        if (fromList != null) {
          _profile = {
            'id': widget.userId,
            'name': fromList.s('partnerName'),
            'avatar': fromList.s('partnerAvatar'),
            'uniqueCode': fromList.s('partnerUniqueCode'),
            'isOnline': fromList.b('partnerIsOnline'),
          };
          _error = false;
        } else {
          _profile = null;
          _error = true;
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String? get _formattedPhone {
    final phone = _profile?.s('phoneNumber');
    if (phone == null) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length <= 4) return '+$digits';
    final rest = digits.substring(3).replaceAllMapped(RegExp(r'(\d{3})(?=\d)'), (m) => '${m[1]} ').trim();
    return '+${digits.substring(0, 3)} $rest';
  }

  bool get _isContact => _profile?.b('isContact') ?? false;

  void _goBack() {
    if (_isOwn) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
      return;
    }
    context.go(widget.conversationId != null ? '/conversation/${widget.conversationId}' : '/conversations');
  }

  void _flash(void Function(bool) set) {
    set(true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) set(false);
    });
  }

  void _copyCode() {
    final code = _profile?.s('uniqueCode');
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    _flash((v) => setState(() => _copiedCode = v));
  }

  void _copyPhone() {
    final phone = _profile?.s('phoneNumber');
    if (phone == null) return;
    Clipboard.setData(ClipboardData(text: phone.startsWith('+') ? phone : '+$phone'));
    _flash((v) => setState(() => _copiedPhone = v));
  }

  void _afterOpen(String? conversationId) {
    if (!mounted) return;
    if (conversationId != null) {
      context.go('/conversation/$conversationId');
    } else {
      ref.read(pendingRequestsProvider.notifier).fetch();
      goToMessageRequestsOutgoingNotice(context);
    }
  }

  Future<void> _openChat() async {
    if (widget.conversationId != null) {
      context.go('/conversation/${widget.conversationId}');
      return;
    }
    final id = _profile?.s('id');
    if (id == null) return;
    if (_isContact) {
      if (!NetworkStatus.online.value) {
        if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
        return;
      }
      setState(() => _startingChat = true);
      try {
        _afterOpen(await createPrivateConversationOrRequest(id));
      } catch (e) {
        if (mounted) showToast(context, errorText(e), error: true);
      } finally {
        if (mounted) setState(() => _startingChat = false);
      }
      return;
    }
    final contactAdded = await showAppSheet<bool>(context, builder: (_) => _ChatGateSheet(userId: id, onContactAdded: _markContact));
    if (contactAdded == true) _markContact();
  }

  void _markContact() {
    if (mounted) setState(() => _profile = {...?_profile, 'isContact': true});
  }

  Future<void> _addAsContact() async {
    if (!NetworkStatus.online.value) {
      if (mounted) showToast(context, t('noConnection.actionFailed'), error: true);
      return;
    }
    setState(() => _addingContact = true);
    try {
      await Api.post('/contacts/by-user/${widget.userId}');
      if (!mounted) return;
      setState(() => _profile = {...?_profile, 'isContact': true});
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    }
    if (mounted) setState(() => _addingContact = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = ref.watch(authProvider);
    final overrides = ref.watch(avatarOverridesProvider);
    final p = _profile;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    final pid = p?.s('id') ?? widget.userId;
    final avatar = _isOwn ? (auth.avatar ?? overrides[pid] ?? p?.s('avatar')) : (overrides[pid] ?? p?.s('avatar'));
    final cover = p?.s('coverImageUrl');
    final featured = p?.b('isFeatured') ?? false;
    final gender = p?.s('gender')?.toLowerCase();
    final genderLabel = switch (gender) {
      'male' => t('profile.genderMale'),
      'female' => t('profile.genderFemale'),
      'other' => t('profile.genderOther'),
      _ => p?.s('gender') ?? '—',
    };
    final phone = _formattedPhone;

    final hero = Column(children: [
      SizedBox(
        height: 168,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Color(0xFF1E3A8A)),
          if (cover != null && isImageAvatar(cover))
            CachedNetworkImage(
              imageUrl: Api.absoluteUrl(cover)!,
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
                stops: const [0, 0.22, 0.48, 1],
                colors: [const Color(0x85000000), const Color(0x47000000), const Color(0x1F0F172A), c.bgPrimary],
              ),
            ),
          ),
          Positioned(
            top: pad.top + 8,
            left: 16,
            right: 16,
            child: Row(children: [
              GlassIconButton(icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft, onTap: _goBack, overlay: true),
              Expanded(
                child: Text(
                  t('profile.title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)), Shadow(color: Color(0xBF000000), blurRadius: 10)],
                  ),
                ),
              ),
              const SizedBox(width: 44),
            ]),
          ),
        ]),
      ),
      if (_loading)
        Transform.translate(
          offset: const Offset(0, -56),
          child: Column(children: [
            _Shimmer(width: 112, height: 112, circle: true),
            const SizedBox(height: 16),
            _Shimmer(width: 160, height: 22),
          ]),
        )
      else if (_error || p == null)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: EmptyState(
            icon: LucideIcons.userX,
            text: t('profile.notFound'),
            action: SizedBox(width: 240, child: PillButton(label: t('common.back'), onPressed: _goBack)),
          ),
        )
      else
        Transform.translate(
          offset: const Offset(0, -56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              GestureDetector(
                onTap: _isOwn ? () => showAvatarPicker(context) : null,
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.primary,
                        border: Border.all(color: featured ? const Color(0xFFE5B82E) : c.bgPrimary, width: 4),
                        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: UserAvatar(url: avatar, name: p.s('name') ?? '?', size: 104),
                    ),
                    if (featured)
                      const PositionedDirectional(
                        bottom: 4,
                        end: -4,
                        child: Icon(LucideIcons.crown, size: 22, color: Color(0xFFE5B82E)),
                      ),
                    if (_isOwn)
                      PositionedDirectional(
                        bottom: 2,
                        end: 2,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.bgPrimary, width: 2),
                            boxShadow: const [BoxShadow(color: Color(0x732563EB), blurRadius: 10, offset: Offset(0, 2))],
                          ),
                          child: const Icon(LucideIcons.pencil, size: 13, color: Colors.white),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(p.s('name') ?? '—', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const SizedBox(height: 4),
              Text(
                '$genderLabel · ${p.b('isOnline') ? t('profile.online') : t('profile.offline')}',
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 16, runSpacing: 6, alignment: WrapAlignment.center, children: [
                if (phone != null) _MetaItem(icon: LucideIcons.phone, text: phone),
                if (_codeConnect && p.s('uniqueCode') != null) _MetaItem(icon: LucideIcons.hash, text: p.s('uniqueCode')!),
              ]),
            ]),
          ),
        ),
    ]);

    final showBody = !_loading && p != null && !_error;
    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: pad.bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          hero,
          if (showBody)
            Transform.translate(
              offset: const Offset(0, -48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_isOwn)
                    PillButton(label: t('home.settings'), onPressed: () => context.go('/settings'))
                  else ...[
                    Row(children: [
                      Expanded(
                        child: PillButton(
                          label: _startingChat
                              ? t('common.loading')
                              : (widget.conversationId != null ? t('profile.openChat') : t('profile.startChat')),
                          onPressed: _startingChat ? null : _openChat,
                        ),
                      ),
                      if (!_isContact) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: SoftButton(
                            icon: LucideIcons.userPlus,
                            label: _addingContact ? t('common.loading') : t('profile.addAsContact'),
                            color: c.primary,
                            onPressed: _addingContact ? null : _addAsContact,
                          ),
                        ),
                      ],
                    ]),
                    if (_isContact)
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.success.withValues(alpha: 0.12),
                            border: Border.all(color: c.success.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(LucideIcons.check, size: 16, color: c.success),
                            const SizedBox(width: 6),
                            Text(t('profile.addedToContacts'), style: TextStyle(color: c.success, fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  if (_codeConnect) ...[
                    _SectionTitle(t('settings.contactCode')),
                    _InfoCard(value: p.s('uniqueCode') ?? '—', copied: _copiedCode, onTap: _copyCode),
                    const SizedBox(height: 16),
                  ],
                  _SectionTitle(t('profile.phone')),
                  if (phone != null)
                    _InfoCard(value: phone, copied: _copiedPhone, onTap: _copyPhone, ltr: true)
                  else
                    _InfoCard(value: t('profile.phoneNotSet'), muted: true),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: c.textMuted),
      const SizedBox(width: 4),
      Text(text, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, color: c.textSecondary)),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textMuted)),
      );
}

/// `.modern-info-card`
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.value, this.onTap, this.copied = false, this.muted = false, this.ltr = false});
  final String value;
  final VoidCallback? onTap;
  final bool copied;
  final bool muted;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: c.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Text(
                value,
                textDirection: ltr ? TextDirection.ltr : null,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
                  letterSpacing: muted ? 0 : 0.5,
                  color: muted ? c.textMuted : c.textPrimary,
                ),
              ),
            ),
            if (onTap != null)
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(10)),
                child: copied
                    ? Text(t('common.copiedShort'), style: TextStyle(fontSize: 11, color: c.success, fontWeight: FontWeight.w600))
                    : Icon(LucideIcons.copy, size: 18, color: c.primary),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.width, required this.height, this.circle = false});
  final double width;
  final double height;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.colors.bgElevated,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(8),
        ),
      );
}

/// Chat-gate modal: add as contact then chat, or send a message request only.
class _ChatGateSheet extends ConsumerStatefulWidget {
  const _ChatGateSheet({required this.userId, required this.onContactAdded});
  final String userId;
  final VoidCallback onContactAdded;

  @override
  ConsumerState<_ChatGateSheet> createState() => _ChatGateSheetState();
}

class _ChatGateSheetState extends ConsumerState<_ChatGateSheet> {
  bool _busy = false;
  String _error = '';

  String _msg(Object e) => errorText(e);

  void _done(String? conversationId) {
    final router = GoRouter.of(context);
    Navigator.pop(context, true);
    if (conversationId != null) {
      router.go('/conversation/$conversationId');
    } else {
      ref.read(pendingRequestsProvider.notifier).fetch();
      router.go('/conversations?tab=requests&notice=outgoing-wait');
    }
  }

  Future<void> _addAndChat() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await Api.post('/contacts/by-user/${widget.userId}', {});
      widget.onContactAdded();
      final id = await createPrivateConversationOrRequest(widget.userId);
      if (mounted) _done(id);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestOnly() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await Api.post(
        '/message-requests',
        {'targetUserId': widget.userId},
        Options(validateStatus: (s) => s != null && ((s >= 200 && s < 300) || s == 409)),
      );
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context, false);
      ref.read(pendingRequestsProvider.notifier).fetch();
      router.go('/conversations?tab=requests&notice=outgoing-wait');
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('profile.chatGateMessage'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: c.textPrimary)),
        const SizedBox(height: 16),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.danger)),
          ),
        PillButton(label: _busy ? t('common.loading') : t('profile.chatGateAddAndChat'), onPressed: _busy ? null : _addAndChat),
        const SizedBox(height: 10),
        SoftButton(label: t('profile.chatGateSendRequestOnly'), color: c.primary, onPressed: _busy ? null : _requestOnly),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('common.cancel'), style: TextStyle(color: c.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
