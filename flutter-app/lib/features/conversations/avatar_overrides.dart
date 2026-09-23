import 'package:flutter_riverpod/flutter_riverpod.dart';

/// stores/userAvatarOverrides.js — live avatar changes pushed over SignalR (`UserAvatarUpdated`).
class AvatarOverridesController extends Notifier<Map<String, String?>> {
  @override
  Map<String, String?> build() => {};

  void set(String userId, String? avatar) => state = {...state, userId: avatar};
}

final avatarOverridesProvider = NotifierProvider<AvatarOverridesController, Map<String, String?>>(AvatarOverridesController.new);
