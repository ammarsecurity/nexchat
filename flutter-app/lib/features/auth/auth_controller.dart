import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/storage/prefs.dart';
import '../../services/push_service.dart';
import '../short_films/short_film_cache.dart';

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

  Future<void> register(String name, String password, String gender, String birthDate) async {
    final data = await Api.post('/auth/register', {'name': name, 'password': password, 'gender': gender, 'birthDate': birthDate});
    await _setAuth(data as Map<String, dynamic>);
  }

  Future<void> login(String name, String password) async {
    final data = await Api.post('/auth/login', {'name': name, 'password': password});
    await _setAuth(data as Map<String, dynamic>);
  }

  Future<void> _setAuth(Map<String, dynamic> data) async {
    final user = AppUser(
      id: '${data['userId']}',
      name: '${data['name'] ?? ''}',
      gender: data['gender'] as String?,
      uniqueCode: data['uniqueCode'] as String?,
      isFeatured: data['isFeatured'] == true,
    );
    final needs = data['needsProfileContact'] == true;
    final p = Prefs.instance;
    await p.setToken(data['token'] as String?);
    await p.setString(Keys.user, jsonEncode(user.toJson()));
    await p.setString(Keys.needsProfileContact, needs ? '1' : '0');
    String? avatar = state.avatar;
    if (data.containsKey('avatar')) {
      avatar = data['avatar'] as String?;
      await p.setString(Keys.avatar, (avatar?.isEmpty ?? true) ? null : avatar);
    }
    state = AuthState(
      token: data['token'] as String?,
      user: user,
      avatar: (avatar?.isEmpty ?? true) ? null : avatar,
      needsProfileContact: needs,
      needsProfileContactRedirect: needs,
    );
    PushService.instance.init(user.id).then((granted) {
      if (!granted) PushService.promptNotifications.value = true;
    });
  }

  Future<void> setAvatar(String? value) async {
    await Prefs.instance.setString(Keys.avatar, value);
    state = value == null ? state.copyWith(clearAvatar: true) : state.copyWith(avatar: value);
    try {
      await Api.put('/user/avatar', {'avatar': value});
    } catch (_) {}
  }

  void updateUser(AppUser user) {
    Prefs.instance.setString(Keys.user, jsonEncode(user.toJson()));
    state = state.copyWith(user: user);
  }

  Future<void> logout() async {
    await PushService.instance.clear();
    await Hubs.stopAll();
    final p = Prefs.instance;
    await p.setToken(null);
    await p.setString(Keys.user, null);
    await p.setString(Keys.avatar, null);
    await p.setString(Keys.needsProfileContact, null);
    await p.setString(Keys.pendingInvite, null);
    unawaited(ShortFilmCache.instance.clear());
    state = const AuthState();
  }

  void setNeedsProfileContact(bool value) {
    Prefs.instance.setString(Keys.needsProfileContact, value ? '1' : '0');
    state = state.copyWith(needsProfileContact: value, needsProfileContactRedirect: false);
  }

  Future<void> fetchProfileContactStatus() async {
    if (!state.isLoggedIn) return;
    try {
      final me = await Api.get('/user/me') as Map<String, dynamic>;
      final needs = '${me['country'] ?? ''}'.isEmpty || '${me['phoneNumber'] ?? ''}'.isEmpty;
      Prefs.instance.setString(Keys.needsProfileContact, needs ? '1' : '0');
      String? avatar = state.avatar;
      if (me.containsKey('avatar') || me.containsKey('Avatar')) {
        avatar = (me['avatar'] ?? me['Avatar']) as String?;
        await Prefs.instance.setString(Keys.avatar, (avatar?.isEmpty ?? true) ? null : avatar);
      }
      state = state.copyWith(
        needsProfileContact: needs,
        avatar: (avatar?.isEmpty ?? true) ? null : avatar,
        clearAvatar: avatar == null || avatar.isEmpty,
      );
    } catch (_) {}
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
