import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/domain/meal_slots.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MealSlotsNotifier extends StateNotifier<List<MealSlot>> {
  static const _prefsKey = 'nutrition_meal_slots_v1';
  final SharedPreferences _prefs;

  MealSlotsNotifier(this._prefs) : super(_load(_prefs));

  static List<MealSlot> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return MealSlot.defaults;
    try {
      final decoded = jsonDecode(raw) as List;
      final slots = decoded
          .whereType<Map>()
          .map((item) => MealSlot.fromJson(item.cast<String, dynamic>()))
          .where((slot) => slot.key.isNotEmpty && slot.label.isNotEmpty)
          .toList();
      return slots.isEmpty ? MealSlot.defaults : slots;
    } catch (_) {
      return MealSlot.defaults;
    }
  }

  Future<void> _persist() => _prefs.setString(
    _prefsKey,
    jsonEncode([for (final slot in state) slot.toJson()]),
  );

  Future<void> add(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final base = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final key =
        'custom_${base.isEmpty ? 'meal' : base}_${DateTime.now().microsecondsSinceEpoch}';
    state = [...state, MealSlot(key: key, label: trimmed)];
    await _persist();
  }

  Future<void> addBuiltIn(MealSlot slot) async {
    if (state.any((s) => s.key == slot.key)) return;
    state = [...state, slot];
    await _persist();
  }

  Future<void> rename(String key, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    state = [
      for (final slot in state)
        slot.key == key ? MealSlot(key: slot.key, label: trimmed) : slot,
    ];
    await _persist();
  }

  Future<void> remove(String key) async {
    if (state.length <= 1) return;
    state = state.where((candidate) => candidate.key != key).toList();
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final items = [...state];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), item);
    state = items;
    await _persist();
  }
}

final mealSlotsProvider =
    StateNotifierProvider<MealSlotsNotifier, List<MealSlot>>((ref) {
      return MealSlotsNotifier(ref.watch(sharedPreferencesProvider));
    });
