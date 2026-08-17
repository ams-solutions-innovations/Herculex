import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/macro_card_config.dart';

/// Persists which macro tiles show on the dashboard grid, and their order.
class MacroCardPrefsNotifier extends Notifier<MacroCardConfig> {
  static const _prefsKey = 'dashboard_macro_cards_v1';

  @override
  MacroCardConfig build() {
    return MacroCardConfig.decode(
      ref.watch(sharedPreferencesProvider).getString(_prefsKey),
    );
  }

  void toggle(DashboardMacro macro, bool visible) {
    state = state.toggle(macro, visible);
    ref.read(sharedPreferencesProvider).setString(_prefsKey, state.encode());
  }

  void reorder(int oldIndex, int newIndex) {
    state = state.reorder(oldIndex, newIndex);
    ref.read(sharedPreferencesProvider).setString(_prefsKey, state.encode());
  }
}

final macroCardPrefsProvider =
    NotifierProvider<MacroCardPrefsNotifier, MacroCardConfig>(
  MacroCardPrefsNotifier.new,
);
