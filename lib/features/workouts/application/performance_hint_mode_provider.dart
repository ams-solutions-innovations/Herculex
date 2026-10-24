import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';

/// Whether the exercise card's performance hint shows last session's numbers
/// or a forward-looking suggested target (item 2). Mutually exclusive.
enum PerformanceHintMode { last, next }

class PerformanceHintModeNotifier extends Notifier<PerformanceHintMode> {
  static const prefsKey = 'performance_hint_mode';

  @override
  PerformanceHintMode build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    return raw == 'last' ? PerformanceHintMode.last : PerformanceHintMode.next;
  }

  Future<void> set(PerformanceHintMode mode) async {
    await ref.read(sharedPreferencesProvider).setString(prefsKey, mode.name);
    state = mode;
  }
}

final performanceHintModeProvider =
    NotifierProvider<PerformanceHintModeNotifier, PerformanceHintMode>(
      PerformanceHintModeNotifier.new,
    );
