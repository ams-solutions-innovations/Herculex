import 'package:drift/drift.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';

class FastingRepository {
  final AppDatabase _db;
  final Clock _clock;

  FastingRepository(this._db, this._clock);

  Future<int> startSession(int targetSeconds, {DateTime? customStartTime}) async {
    // Ensure we don't have another active session running. If we do, close it.
    final active = await (_db.select(
      _db.fastingSessions,
    )..where((t) => t.endedAt.isNull())).get();
    for (var i = 0; i < active.length; i++) {
      await endSession(completed: false);
    }

    return _db
        .into(_db.fastingSessions)
        .insert(
          FastingSessionsCompanion.insert(
            startedAt: customStartTime ?? _clock.now(),
            targetSeconds: targetSeconds,
            completed: const Value(false),
          ),
        );
  }

  Future<void> endSession({bool completed = true}) async {
    final active =
        await (_db.select(_db.fastingSessions)
              ..where((t) => t.endedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (active == null) return;

    await (_db.update(
      _db.fastingSessions,
    )..where((t) => t.id.equals(active.id))).write(
      FastingSessionsCompanion(
        endedAt: Value(_clock.now()),
        completed: Value(completed),
      ),
    );
  }

  Future<void> deleteSession(int id) async {
    await (_db.delete(_db.fastingSessions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateSessionStartTime(int id, DateTime newStartTime) async {
    await (_db.update(_db.fastingSessions)..where((t) => t.id.equals(id))).write(
      FastingSessionsCompanion(startedAt: Value(newStartTime)),
    );
  }

  Future<void> updateSessionTarget(int id, int targetSeconds) async {
    await (_db.update(_db.fastingSessions)..where((t) => t.id.equals(id))).write(
      FastingSessionsCompanion(targetSeconds: Value(targetSeconds)),
    );
  }

  Future<void> updateSessionCompletion(int id, bool completed, {DateTime? endedAt}) async {
    await (_db.update(_db.fastingSessions)..where((t) => t.id.equals(id))).write(
      FastingSessionsCompanion(
        completed: Value(completed),
        endedAt: endedAt == null ? const Value.absent() : Value(endedAt),
      ),
    );
  }

  Stream<FastingSessionData?> watchActiveSession() {
    return (_db.select(_db.fastingSessions)
          ..where((t) => t.endedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<FastingSessionData?> activeSession() {
    return (_db.select(_db.fastingSessions)
          ..where((t) => t.endedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<FastingSessionData>> watchHistory({int limit = 50}) {
    return (_db.select(_db.fastingSessions)
          ..where((t) => t.endedAt.isNotNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  Future<int> currentStreak() async {
    final completedSessions =
        await (_db.select(_db.fastingSessions)
              ..where((t) => t.completed.equals(true) & t.endedAt.isNotNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.endedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    if (completedSessions.isEmpty) return 0;

    int streak = 0;
    DateTime checkDate = _clock.now();

    // Normalise to date-only comparison
    DateTime today = DateTime(checkDate.year, checkDate.month, checkDate.day);

    // If the most recent completed fast ended before yesterday, streak is broken
    final mostRecentEnd = completedSessions.first.endedAt!;
    final daysSinceMostRecent = today
        .difference(
          DateTime(mostRecentEnd.year, mostRecentEnd.month, mostRecentEnd.day),
        )
        .inDays;
    if (daysSinceMostRecent > 1) {
      return 0;
    }

    for (final session in completedSessions) {
      final ended = session.endedAt!;
      final sessionDate = DateTime(ended.year, ended.month, ended.day);
      final diff = today.difference(sessionDate).inDays;

      if (diff == 0 || diff == 1) {
        streak++;
        // Shift our check date to yesterday relative to the current sessionDate to continue checking backward
        today = sessionDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }

  Future<double> averageEatingWindow(int days) async {
    final cutoff = _clock.now().subtract(Duration(days: days));
    final sessions =
        await (_db.select(_db.fastingSessions)
              ..where(
                (t) =>
                    t.endedAt.isNotNull() &
                    t.startedAt.isBiggerOrEqualValue(cutoff),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.asc,
                ),
              ]))
            .get();

    if (sessions.isEmpty) {
      return 8.0; // Standard default eating window (16:8)
    }

    if (sessions.length == 1) {
      final s = sessions.first;
      final fastDuration = s.endedAt!.difference(s.startedAt);
      final eatingHrs = 24.0 - (fastDuration.inSeconds / 3600.0);
      return eatingHrs.clamp(0.0, 24.0);
    }

    int totalEatingSeconds = 0;
    int count = 0;
    for (int i = 0; i < sessions.length - 1; i++) {
      final end = sessions[i].endedAt!;
      final nextStart = sessions[i + 1].startedAt;
      final diff = nextStart.difference(end);

      // Reasonable interval between fasts for an eating window (under 36h)
      if (diff.inHours > 0 && diff.inHours < 36) {
        totalEatingSeconds += diff.inSeconds;
        count++;
      }
    }

    if (count == 0) {
      double sum = 0;
      for (final s in sessions) {
        final fastDuration = s.endedAt!.difference(s.startedAt);
        sum += 24.0 - (fastDuration.inSeconds / 3600.0);
      }
      return (sum / sessions.length).clamp(0.0, 24.0);
    }

    return (totalEatingSeconds / count) / 3600.0;
  }

  // ── Auto-schedule (Phase 6) ──

  Stream<List<FastingScheduleData>> watchSchedules() {
    return (_db.select(_db.fastingSchedules)
          ..orderBy([
            (t) => OrderingTerm(expression: t.startTimeMinutes),
          ]))
        .watch();
  }

  Future<FastingScheduleData?> schedule(int id) {
    return (_db.select(
      _db.fastingSchedules,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> createSchedule({
    required String planName,
    int? customTargetSeconds,
    required int daysOfWeek,
    required int startTimeMinutes,
    bool enabled = true,
    bool autoStart = false,
  }) {
    return _db
        .into(_db.fastingSchedules)
        .insert(
          FastingSchedulesCompanion.insert(
            planName: planName,
            customTargetSeconds: Value(customTargetSeconds),
            daysOfWeek: daysOfWeek,
            startTimeMinutes: startTimeMinutes,
            enabled: Value(enabled),
            autoStart: Value(autoStart),
          ),
        );
  }

  Future<void> updateSchedule(
    int id, {
    required String planName,
    int? customTargetSeconds,
    required int daysOfWeek,
    required int startTimeMinutes,
    required bool enabled,
    required bool autoStart,
  }) {
    return (_db.update(_db.fastingSchedules)..where((t) => t.id.equals(id)))
        .write(
          FastingSchedulesCompanion(
            planName: Value(planName),
            customTargetSeconds: Value(customTargetSeconds),
            daysOfWeek: Value(daysOfWeek),
            startTimeMinutes: Value(startTimeMinutes),
            enabled: Value(enabled),
            autoStart: Value(autoStart),
          ),
        );
  }

  Future<void> setScheduleEnabled(int id, bool enabled) {
    return (_db.update(_db.fastingSchedules)..where((t) => t.id.equals(id)))
        .write(FastingSchedulesCompanion(enabled: Value(enabled)));
  }

  Future<void> deleteSchedule(int id) {
    return (_db.delete(
      _db.fastingSchedules,
    )..where((t) => t.id.equals(id))).go();
  }
}
