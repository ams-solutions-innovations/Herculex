import 'dart:async';
import 'dart:convert';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/workout_xp_evaluator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small local, idempotent ledger. Session IDs make finishing a workout safe
/// to retry and keep historical finish screens from granting XP twice.
class XpLedgerRepository {
  XpLedgerRepository(this._preferences) {
    _entries = _read();
  }

  static const _key = 'gamification_xp_ledger_v1';
  final SharedPreferences _preferences;
  final _controller = StreamController<LevelProgress>.broadcast();
  late List<XpLedgerEntry> _entries;

  List<XpLedgerEntry> get entries => List.unmodifiable(_entries);
  LevelProgress get progress => LevelProgress(
    totalXp: _entries.fold(0, (sum, entry) => sum + entry.xp),
    completedWorkouts: _entries
        .where((entry) => entry.id.startsWith('workout:'))
        .length,
  );

  LevelProgress getProgressForActiveSessions(List<int>? activeSessionIds) {
    if (activeSessionIds == null) return progress;
    final activeSet = activeSessionIds.toSet();
    final activeEntries = _entries.where((entry) {
      if (!entry.id.startsWith('workout:')) return true;
      final sid = int.tryParse(entry.id.substring('workout:'.length));
      return sid == null || activeSet.contains(sid);
    }).toList();
    return LevelProgress(
      totalXp: activeEntries.fold(0, (sum, entry) => sum + entry.xp),
      completedWorkouts: activeEntries
          .where((entry) => entry.id.startsWith('workout:'))
          .length,
    );
  }

  Stream<LevelProgress> watch() async* {
    yield progress;
    yield* _controller.stream;
  }

  Future<bool> record({
    required String id,
    required DateTime awardedAt,
    required XpAward award,
  }) async {
    if (_entries.any((entry) => entry.id == id)) return false;
    _entries = [
      ..._entries,
      XpLedgerEntry(
        id: id,
        awardedAt: awardedAt,
        xp: award.xp,
        reasons: award.reasons,
      ),
    ];
    await _preferences.setString(
      _key,
      jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
    );
    _controller.add(progress);
    return true;
  }

  /// Reconciles the local ledger with completed workout sessions (e.g. pulled
  /// from cloud sync or loaded from the database).
  Future<bool> reconcileWithSessions({
    required List<WorkoutSessionData> sessions,
    required TrainingSnapshot? snapshot,
    required double? bodyweightKg,
  }) async {
    final completed =
        sessions.where((s) => s.endedAt != null && s.deletedAt == null).toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final missing = completed
        .where((s) => !_entries.any((e) => e.id == 'workout:${s.id}'))
        .toList();

    if (missing.isEmpty) return false;

    const evaluator = WorkoutXpEvaluator();
    final updatedEntries = List<XpLedgerEntry>.from(_entries);

    for (final session in missing) {
      final sessionSets =
          snapshot?.sets.where((s) => s.session.id == session.id).toList() ??
          const <ResolvedSet>[];

      final award = evaluator.evaluate(
        sessionSets: sessionSets,
        bodyweightKg: bodyweightKg,
        previousEntries: updatedEntries,
        completedAt: session.endedAt ?? session.startedAt,
      );

      updatedEntries.add(
        XpLedgerEntry(
          id: 'workout:${session.id}',
          awardedAt: session.endedAt ?? session.startedAt,
          xp: award.xp,
          reasons: award.reasons,
        ),
      );
    }

    _entries = updatedEntries;
    await _preferences.setString(
      _key,
      jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
    );
    _controller.add(progress);
    return true;
  }

  List<XpLedgerEntry> _read() {
    final raw = _preferences.getString(_key);
    if (raw == null) return [];
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      return values
          .whereType<Map<String, dynamic>>()
          .map(XpLedgerEntry.fromJson)
          .where((entry) => entry.xp > 0)
          .toList();
    } catch (_) {
      // A corrupted local-only reward record must never block a workout.
      return [];
    }
  }

  void dispose() => _controller.close();
}
