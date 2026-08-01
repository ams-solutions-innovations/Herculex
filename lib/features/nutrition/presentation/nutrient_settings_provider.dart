import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/nutrient_definitions.dart';

class NutrientSettingsNotifier extends StateNotifier<Set<String>> {
  static const _prefsKey = 'nutrition_visible_nutrients_v1';
  final dynamic _prefs;

  NutrientSettingsNotifier(this._prefs) : super(_load(_prefs));

  static Set<String> _load(dynamic prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {'fiber', 'sodium', 'potassium', 'cholesterol'};
    try {
      final values = (jsonDecode(raw) as List).whereType<String>().toSet();
      return values.isEmpty
          ? {'fiber', 'sodium', 'potassium', 'cholesterol'}
          : values;
    } catch (_) {
      return {'fiber', 'sodium', 'potassium', 'cholesterol'};
    }
  }

  Future<void> toggle(String id, bool enabled) async {
    final next = {...state};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = next;
    await _prefs.setString(_prefsKey, jsonEncode(next.toList()));
  }
}

final visibleNutrientIdsProvider =
    StateNotifierProvider<NutrientSettingsNotifier, Set<String>>((ref) {
      return NutrientSettingsNotifier(ref.watch(sharedPreferencesProvider));
    });

/// Whether the food-logging form offers a time-of-day field (§3). Off by
/// default — most users only care which day a food landed on, and an extra
/// required decision slows down every single log.
class LogTimestampNotifier extends Notifier<bool> {
  static const _prefsKey = 'nutrition_log_timestamp_v1';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsKey) ?? false;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, enabled);
    state = enabled;
  }
}

final logTimestampEnabledProvider =
    NotifierProvider<LogTimestampNotifier, bool>(LogTimestampNotifier.new);

final nutrientDefinitionsByIdProvider =
    Provider<Map<String, NutrientDefinition>>((ref) {
      return {
        for (final definition in trackedNutrients) definition.id: definition,
      };
    });
