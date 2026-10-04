import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/storage/prefs.dart';
import '../../services/push_service.dart';
import '../../services/tiktok_analytics_service.dart';
import '../short_films/short_film_cache.dart';
import '../conversations/conversation_cache.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    this.gender,
    this.uniqueCode,
    this.isFeatured = false,
  });

  final String id;
  final String name;
  final String? gender;
  final String? uniqueCode;
  final bool isFeatured;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'gender': gender, 'uniqueCode': uniqueCode, 'isFeatured': isFeatured};

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        gender: j['gender'] as String?,
        uniqueCode: j['uniqueCode'] as String?,
        isFeatured: j['isFeatured'] == true,
      );
}

class AuthState {
  const AuthState({
    this.token,
    this.user,
    this.avatar,
    this.needsProfileContact = false,
    this.needsProfileContactRedirect = false,
  });

  final String? token;
  final AppUser? user;
  final String? avatar;
  final bool needsProfileContact;
  final bool needsProfileContactRedirect;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Color get avatarColor {
    const colors = [Color(0xFF6C63FF), Color(0xFFFF6584), Color(0xFF00D4FF), Color(0xFFFF8C42), Color(0xFFA8FF78)];
    final name = user?.name ?? '';
    if (name.isEmpty) return colors.first;
    return colors[name.codeUnitAt(0) % colors.length];
  }

  AuthState copyWith({
    String? token,
    AppUser? user,
    String? avatar,
    bool clearAvatar = false,
    bool? needsProfileContact,
    bool? needsProfileContactRedirect,
  }) =>
      AuthState(
        token: token ?? this.token,
        user: user ?? this.user,
        avatar: clearAvatar ? null : (avatar ?? this.avatar),
        needsProfileContact: needsProfileContact ?? this.needsProfileContact,
        needsProfileContactRedirect: needsProfileContactRedirect ?? this.needsProfileContactRedirect,
      );
}

/// Mirrors mobile-app/src/stores/auth.js.
class AuthController extends Notifier<AuthState> {
  int _authGeneration = 0;
  // Serialize persistence so an obsolete write cannot finish after a newer login.
  Future<void> _authWrites = Future.value();

  Future<void> _writeAuth(Future<void> Function() action) {
    final next = _authWrites.catchError((_) {}).then((_) => action());
    _authWrites = next;
    return next;
  }

  bool _isCurrent(int generation, String? account) =>
      generation == _authGeneration && state.user?.id == account;

  Options _pinnedAuth(String token) => Options(
    headers: {'Authorization': 'Bearer $token'},
    extra: {'preserveAuthorization': true},
  );
  @override
  AuthState build() {
    final p = Prefs.instance;
    final rawUser = p.getString(Keys.user);
    return AuthState(
      token: p.token,
      user: rawUser == null ? null : AppUser.fromJson(jsonDecode(rawUser) as Map<String, dynamic>),
      avatar: p.getString(Keys.avatar),
      needsProfileContact: p.getString(Keys.needsProfileContact) == '1',
    );
  }

  Future<void> register(
    String name,
    String password,
    String gender,
    String birthDate, {
    required String country,
    required String countryCode,
    required String phoneNumber,
    String? otpCode,
  }) async {
    final generation = ++_authGeneration;
    final body = <String, dynamic>{
      'name': name,
      'password': password,
      'gender': gender,
      'birthDate': birthDate,
      'country': country,
      'countryCode': countryCode,
      'phoneNumber': phoneNumber,
    };
    if (otpCode != null && otpCode.isNotEmpty) body['otpCode'] = otpCode;
    final data = await Api.post('/auth/register', body);
    if (generation != _authGeneration) return;
    await _setAuth(data as Map<String, dynamic>, isNewRegistration: true, generation: generation);
  }

  Future<void> login(String name, String password) async {
    final generation = ++_authGeneration;
    final data = await Api.post('/auth/login', {'name': name, 'password': password});
    if (generation != _authGeneration) return;
    await _setAuth(data as Map<String, dynamic>, isNewRegistration: false, generation: generation);
  }

  Future<void> _setAuth(Map<String, dynamic> data, {required bool isNewRegistration, required int generation}) async {
    final user = AppUser(
      id: '${data['userId']}',
      name: '${data['name'] ?? ''}',
      gender: data['gender'] as String?,
      uniqueCode: data['uniqueCode'] as String?,
      isFeatured: data['isFeatured'] == true,
    );
    final previousAvatar = state.user?.id == user.id ? state.avatar : null;
    state = const AuthState();
    final needs = data['needsProfileContact'] == true;
    await _writeAuth(() async {
      if (generation != _authGeneration) return;
      final p = Prefs.instance;
      await p.setToken(null);
      await Hubs.stopAll();
      if (generation != _authGeneration) return;
      await ConversationCache.removeLegacy();
      if (generation != _authGeneration) return;
      await p.setString(Keys.user, jsonEncode(user.toJson()));
      if (generation != _authGeneration) return;
      final avatar = data.containsKey('avatar') ? data['avatar'] as String? : previousAvatar;
      await p.setString(Keys.avatar, (avatar?.isEmpty ?? true) ? null : avatar);
      if (generation != _authGeneration) return;
      await p.setString(Keys.needsProfileContact, needs ? '1' : '0');
      if (generation != _authGeneration) return;
      await p.setToken(data['token'] as String?);
      if (generation != _authGeneration) return;
      state = AuthState(
        token: data['token'] as String?, user: user,
        avatar: (avatar?.isEmpty ?? true) ? null : avatar,
        needsProfileContact: needs, needsProfileContactRedirect: needs,
      );
    });
    if (!_isCurrent(generation, user.id)) return;
    PushService.instance.init(user.id).then((granted) {
      if (generation == _authGeneration && state.user?.id == user.id && !granted) PushService.promptNotifications.value = true;
    });
    final tiktok = TikTokAnalyticsService.instance;
    unawaited(tiktok.identify(userId: user.id, userName: user.name).then((_) async {
      if (isNewRegistration) {
        await tiktok.logCompleteRegistration();
      } else {
        await tiktok.logLogin();
      }
    }));
  }

  Future<void> setAvatar(String? value) async {
    final generation = _authGeneration;
    final account = state.user?.id;
    final token = state.token;
    if (account == null || token == null) return;
    await _writeAuth(() async {
      if (!_isCurrent(generation, account)) return;
      await Prefs.instance.setString(Keys.avatar, value);
      if (!_isCurrent(generation, account)) return;
      state = value == null ? state.copyWith(clearAvatar: true) : state.copyWith(avatar: value);
    });
    if (!_isCurrent(generation, account)) return;
    try {
      await Api.dio.put('user/avatar', data: {'avatar': value}, options: _pinnedAuth(token));
    } catch (_) {}
  }

  void updateUser(AppUser user) {
    final generation = _authGeneration;
    if (state.user?.id != user.id) return;
    state = state.copyWith(user: user);
    unawaited(_writeAuth(() async {
      if (_isCurrent(generation, user.id)) {
        await Prefs.instance.setString(Keys.user, jsonEncode(user.toJson()));
      }
    }));
  }

  Future<void> logout() async {
    ++_authGeneration;
    final pushCleanup = PushService.instance.clear();
    state = const AuthState();
    unawaited(TikTokAnalyticsService.instance.logout());
    final p = Prefs.instance;
    final stoppedHubs = Hubs.stopAll();
    final clearedToken = p.setToken(null);
    final localCleanup = _writeAuth(() async {
      try { await clearedToken; } catch (_) {}
      // Repeat inside the queue if an old secure write finished after revocation.
      try { await p.setToken(null); } catch (_) {}
      for (final key in [Keys.user, Keys.avatar, Keys.needsProfileContact, Keys.pendingInvite]) {
        try { await p.setString(key, null); } catch (_) {}
      }
      try { await ConversationCache.removeLegacy(); } catch (_) {}
      unawaited(ShortFilmCache.instance.clear());
    });
    // Never mutate local account state after waiting for remote/native cleanup.
    await localCleanup;
    try { await pushCleanup; } catch (_) {}
    try { await stoppedHubs; } catch (_) {}
  }

  void setNeedsProfileContact(bool value) {
    final generation = _authGeneration;
    final account = state.user?.id;
    state = state.copyWith(needsProfileContact: value, needsProfileContactRedirect: false);
    unawaited(_writeAuth(() async {
      if (_isCurrent(generation, account)) {
        await Prefs.instance.setString(Keys.needsProfileContact, value ? '1' : '0');
      }
    }));
  }

  Future<void> fetchProfileContactStatus() async {
    if (!state.isLoggedIn) return;
    final generation = _authGeneration;
    final account = state.user?.id;
    final token = state.token!;
    try {
      final response = await Api.dio.get('user/me', options: _pinnedAuth(token));
      final me = response.data as Map<String, dynamic>;
      if (!_isCurrent(generation, account)) return;
      await _writeAuth(() async {
        if (!_isCurrent(generation, account)) return;
        final needs = '${me['country'] ?? ''}'.isEmpty || '${me['phoneNumber'] ?? ''}'.isEmpty;
        await Prefs.instance.setString(Keys.needsProfileContact, needs ? '1' : '0');
        if (!_isCurrent(generation, account)) return;
        String? avatar = state.avatar;
        if (me.containsKey('avatar') || me.containsKey('Avatar')) {
          avatar = (me['avatar'] ?? me['Avatar']) as String?;
          await Prefs.instance.setString(Keys.avatar, (avatar?.isEmpty ?? true) ? null : avatar);
        }
        if (!_isCurrent(generation, account)) return;
        state = state.copyWith(
          needsProfileContact: needs,
          avatar: (avatar?.isEmpty ?? true) ? null : avatar,
          clearAvatar: avatar == null || avatar.isEmpty,
        );
      });
    } catch (_) {}
  }

}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
