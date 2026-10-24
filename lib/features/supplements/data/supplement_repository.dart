import 'dart:async';
import 'dart:convert';

import 'package:herculex/features/labs/data/labs_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final _supplementsController = StreamController<List<Supplement>>.broadcast();
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
    final previous = loadSupplements();
    final labs = LabsRepository(_prefs);
    try {
      if (labs.consent.enabled &&
          labs.consent.categories.any((c) => c.name == 'supplements')) {
        final now = DateTime.now();
        await labs.put('definitions', now.microsecondsSinceEpoch.toString(), {
          'at': now.toIso8601String(),
          'before': previous.map((s) => s.toJson()).toList(),
          'after': supplements.map((s) => s.toJson()).toList(),
        });
      }
    } finally {
      await labs.changes.close();
    }
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
      await markTaken(id, false);
    }
  }

  // ── Daily taken set ────────────────────────────────────────────────────────

  static String takenKeyForDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return 'supplements_taken_$y-$m-$d';
  }

  static Set<String> loadTakenFromPrefs(
    SharedPreferences prefs, [
    DateTime? date,
  ]) {
    final raw = prefs.getString(takenKeyForDate(date ?? DateTime.now()));
    if (raw == null || raw.isEmpty) return {};
    try {
      return Set<String>.from(jsonDecode(raw) as List<dynamic>);
    } catch (_) {
      return {};
    }
  }

  static Future<Set<String>> markTakenInPrefs(
    SharedPreferences prefs,
    String id,
    bool taken, {
    DateTime? date,
  }) async {
    final set = loadTakenFromPrefs(prefs, date);
    if (taken) {
      set.add(id);
    } else {
      set.remove(id);
    }
    await prefs.setString(
      takenKeyForDate(date ?? DateTime.now()),
      jsonEncode(set.toList()),
    );
    await LabsRepository.recordIntake(prefs, id, taken, date ?? DateTime.now());
    return set;
  }

  Set<String> loadTakenToday() => loadTakenFromPrefs(_prefs);

  Set<String> loadTakenForDate(DateTime date) =>
      loadTakenFromPrefs(_prefs, date);

  Stream<Set<String>> watchTakenToday() {
    Future.microtask(() => _takenController.add(loadTakenToday()));
    return _takenController.stream;
  }

  Future<void> markTaken(String id, bool taken) async {
    final updated = await markTakenInPrefs(_prefs, id, taken);
    _takenController.add(updated);
  }

  Future<void> markTakenForDate(String id, bool taken, DateTime date) async {
    await markTakenInPrefs(_prefs, id, taken, date: date);
    // Broadcast today's taken set so all listeners (including history providers
    // that watch takenTodayProvider) refresh immediately.
    _takenController.add(loadTakenToday());
  }

  /// Loads the taken supplement IDs for each day in the trailing [days] window
  /// ending on [anchor] (defaults to today), keyed by `YYYY-MM-DD`.
  Map<String, Set<String>> loadHistory({required int days, DateTime? anchor}) {
    final now = anchor ?? DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final out = <String, Set<String>>{};
    for (int i = days - 1; i >= 0; i--) {
      final d = end.subtract(Duration(days: i));
      final iso = _isoDate(d);
      out[iso] = loadTakenFromPrefs(_prefs, d);
    }
    return out;
  }

  /// Finds the earliest date on which at least one supplement was marked taken,
  /// or null if no supplement has ever been logged.
  DateTime? findEarliestTrackedDate() {
    DateTime? earliest;
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('supplements_taken_')) continue;
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty || raw == '[]') continue;
      final datePart = key.replaceFirst('supplements_taken_', '');
      final parsed = DateTime.tryParse(datePart);
      if (parsed == null) continue;
      final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      if (earliest == null || dateOnly.isBefore(earliest)) {
        earliest = dateOnly;
      }
    }
    return earliest;
  }

  static String _isoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Removes taken-set keys older than 365 days to keep a full year of habit
  /// tracking history while avoiding unbounded prefs growth.
  void clearOldDays() {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
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
