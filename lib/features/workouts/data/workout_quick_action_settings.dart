import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

class QuickLoadStepNotifier extends Notifier<double> {
  static const prefsKey = 'quick_load_step_kg';
  static const defaultKg = 2.5;

  @override
  double build() {
    return ref.watch(sharedPreferencesProvider).getDouble(prefsKey) ??
        defaultKg;
  }

  Future<void> set(double stepKg) async {
    final normalized = stepKg.clamp(0.25, 100.0);
    await ref.read(sharedPreferencesProvider).setDouble(prefsKey, normalized);
    state = normalized;
  }
}

final quickLoadStepProvider = NotifierProvider<QuickLoadStepNotifier, double>(
  QuickLoadStepNotifier.new,
);
