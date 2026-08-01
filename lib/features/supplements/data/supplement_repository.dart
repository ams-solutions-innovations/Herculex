import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/supplement.dart';

/// Persists the user's supplement definitions and daily taken-set in
/// SharedPreferences. No Drift migration required.
///
/// Keys used:
///   - `supplements_config_v1`           → JSON list of [Supplement]s
///   - `supplements_taken_YYYY-MM-DD`    → JSON list of taken supplement ids
class SupplementRepository {
  static const _configKey = 'supplements_config_v1';

  final SharedPreferences _prefs;

  // In-memory stream controllers so UI reacts to changes immediately.
  final _supplementsController =
      StreamController<List<Supplement>>.broadcast();
  final _takenController = StreamController<Set<String>>.broadcast();

  SupplementRepository(this._prefs);

  void dispose() {
    _supplementsController.close();
    _takenController.close();
  }

  // ── Supplement list ────────────────────────────────────────────────────────

  List<Supplement> loadSupplements() {
    final raw = _prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return Supplement.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Stream<List<Supplement>> watchSupplements() {
    // Seed with current value, then broadcast future changes.
    Future.microtask(() => _supplementsController.add(loadSupplements()));
    return _supplementsController.stream;
  }

  Future<void> saveSupplements(List<Supplement> supplements) async {
    await _prefs.setString(_configKey, Supplement.listToJson(supplements));
    _supplementsController.add(supplements);
  }

  Future<void> addSupplement(Supplement supplement) async {
    final list = [...loadSupplements(), supplement];
    await saveSupplements(list);
  }

  Future<void> updateSupplement(Supplement supplement) async {
    final list = loadSupplements()
        .map((s) => s.id == supplement.id ? supplement : s)
        .toList();
    await saveSupplements(list);
  }

  Future<void> deleteSupplement(String id) async {
    final list = loadSupplements().where((s) => s.id != id).toList();
    await saveSupplements(list);
    // Also remove from today's taken set if present.
    final taken = loadTakenToday();
    if (taken.contains(id)) {
      taken.remove(id);
      await _saveTakenToday(taken);
    }
  }

  // ── Daily taken set ────────────────────────────────────────────────────────

  String _takenKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return 'supplements_taken_$y-$m-$d';
  }

  Set<String> loadTakenToday() {
    final raw = _prefs.getString(_takenKey(DateTime.now()));
    if (raw == null || raw.isEmpty) return {};
    try {
      return Set<String>.from(jsonDecode(raw) as List<dynamic>);
    } catch (_) {
      return {};
    }
  }

  Stream<Set<String>> watchTakenToday() {
    Future.microtask(() => _takenController.add(loadTakenToday()));
    return _takenController.stream;
  }

  Future<void> markTaken(String id, bool taken) async {
    final set = loadTakenToday();
    if (taken) {
      set.add(id);
    } else {
      set.remove(id);
    }
    await _saveTakenToday(set);
  }

  Future<void> _saveTakenToday(Set<String> ids) async {
    await _prefs.setString(_takenKey(DateTime.now()), jsonEncode(ids.toList()));
    _takenController.add(ids);
  }

  /// Removes taken-set keys older than 7 days to avoid prefs bloat.
  void clearOldDays() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('supplements_taken_')) continue;
      final datePart = key.replaceFirst('supplements_taken_', '');
      final date = DateTime.tryParse(datePart);
      if (date != null && date.isBefore(cutoff)) {
        _prefs.remove(key);
      }
    }
  }
}
