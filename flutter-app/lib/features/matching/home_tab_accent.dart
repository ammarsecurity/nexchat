import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-tab chrome for `/home`: Discover red vs Instant violet.
enum HomeTabAccent { discover, instant, neutral }

class HomeTabAccentNotifier extends Notifier<HomeTabAccent> {
  @override
  HomeTabAccent build() => HomeTabAccent.neutral;

  void set(HomeTabAccent value) => state = value;
}

final homeTabAccentProvider = NotifierProvider<HomeTabAccentNotifier, HomeTabAccent>(HomeTabAccentNotifier.new);
