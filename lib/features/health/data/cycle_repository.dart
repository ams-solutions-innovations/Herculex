import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../domain/cycle_adjuster.dart';

class CycleRepository {
  final AppDatabase _db;

  CycleRepository(this._db);

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<CycleSettingData?> getSettings() {
    return (_db.select(_db.cycleSettings)..limit(1)).getSingleOrNull();
  }

  Stream<CycleSettingData?> watchSettings() {
    return (_db.select(_db.cycleSettings)..limit(1)).watchSingleOrNull();
  }

  Future<void> saveSettings({
    required int avgCycleDays,
    required int avgPeriodDays,
    required DateTime lastPeriodStart,
  }) async {
    await _db.into(_db.cycleSettings).insertOnConflictUpdate(
          CycleSettingsCompanion.insert(
            id: const Value(1),
            avgCycleDays: Value(avgCycleDays),
            avgPeriodDays: Value(avgPeriodDays),
            lastPeriodStart: lastPeriodStart,
          ),
        );
  }

  // ── Logs & Overrides ─────────────────────────────────────────────────────

  Future<void> logManualOverride({
    required DateTime date,
    required String phase,
    required int intensity,
  }) async {
    final dateStr = _formatDateIso(date);
    await _db.transaction(() async {
      await (_db.delete(_db.cycleLogs)..where((t) => t.dateIso.equals(dateStr))).go();
      await _db.into(_db.cycleLogs).insert(
            CycleLogsCompanion.insert(
              dateIso: dateStr,
              phase: phase,
              intensity: Value(intensity),
              manualOverride: const Value(true),
            ),
          );
    });
  }

  Future<void> clearManualOverride(DateTime date) async {
    final dateStr = _formatDateIso(date);
    await (_db.delete(_db.cycleLogs)..where((t) => t.dateIso.equals(dateStr))).go();
  }

  Future<CycleLogData?> getManualOverride(DateTime date) {
    final dateStr = _formatDateIso(date);
    return (_db.select(_db.cycleLogs)..where((t) => t.dateIso.equals(dateStr))).getSingleOrNull();
  }

  Stream<CycleLogData?> watchLogForDate(DateTime date) {
    final dateStr = _formatDateIso(date);
    return (_db.select(_db.cycleLogs)..where((t) => t.dateIso.equals(dateStr))).watchSingleOrNull();
  }

  Stream<List<CycleLogData>> watchRecentLogs({int limit = 60}) {
    return (_db.select(_db.cycleLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.dateIso)])
          ..limit(limit))
        .watch();
  }

  // ── Ingest Health / Flo Period Data ──────────────────────────────────────

  /// Ingests a list of period date timestamps obtained from Apple Health (HealthKit)
  /// or Health Connect (synced from Flo, Clue, or Apple Cycle Tracking).
  Future<void> ingestHealthPeriodDates(List<DateTime> periodDates) async {
    if (periodDates.isEmpty) return;

    // Sort ascending
    final sorted = List<DateTime>.from(periodDates)..sort((a, b) => a.compareTo(b));
    final latestPeriod = sorted.last;

    final currentSettings = await getSettings();
    final avgCycle = currentSettings?.avgCycleDays ?? 28;
    final avgPeriod = currentSettings?.avgPeriodDays ?? 5;

    await saveSettings(
      avgCycleDays: avgCycle,
      avgPeriodDays: avgPeriod,
      lastPeriodStart: latestPeriod,
    );

    // Save individual menstrual day logs into CycleLogs
    await _db.transaction(() async {
      for (final date in sorted) {
        final dateStr = _formatDateIso(date);
        await (_db.delete(_db.cycleLogs)..where((t) => t.dateIso.equals(dateStr))).go();
        await _db.into(_db.cycleLogs).insert(
              CycleLogsCompanion.insert(
                dateIso: dateStr,
                phase: 'menstrual',
                intensity: const Value(3),
                manualOverride: const Value(false),
              ),
            );
      }
    });
  }

  // ── Prediction & Adjustments ─────────────────────────────────────────────

  Future<CycleAdjustmentResult> getAdjustmentFor(DateTime date) async {
    final override = await getManualOverride(date);
    final settings = await getSettings();

    final lastStart = settings?.lastPeriodStart ?? date;
    final avgCycleDays = settings?.avgCycleDays ?? 28;
    final avgPeriodDays = settings?.avgPeriodDays ?? 5;

    final dayOfCycle = CyclePredictor.computeDayOfCycle(
      date: date,
      lastPeriodStart: lastStart,
      avgCycleDays: avgCycleDays,
    );

    final daysUntilNext = CyclePredictor.daysUntilNextPeriod(
      date: date,
      lastPeriodStart: lastStart,
      avgCycleDays: avgCycleDays,
    );

    if (override != null) {
      final phase = CyclePhase.fromId(override.phase);
      return CycleAwareAdjuster.suggest(
        phase: phase,
        dayOfCycle: dayOfCycle,
        totalCycleDays: avgCycleDays,
        daysUntilNextPeriod: daysUntilNext,
        isManualOverride: true,
      );
    }

    final predictedPhase = settings != null
        ? CyclePredictor.predictPhase(
            date: date,
            lastPeriodStart: lastStart,
            avgCycleDays: avgCycleDays,
            avgPeriodDays: avgPeriodDays,
          )
        : CyclePhase.follicular;

    return CycleAwareAdjuster.suggest(
      phase: predictedPhase,
      dayOfCycle: dayOfCycle,
      totalCycleDays: avgCycleDays,
      daysUntilNextPeriod: daysUntilNext,
      isManualOverride: false,
    );
  }

  Future<String> predictPhaseFor(DateTime date) async {
    final adjustment = await getAdjustmentFor(date);
    return adjustment.phase.id;
  }

  Future<double> getCycleMultiplierFor(DateTime date) async {
    final adjustment = await getAdjustmentFor(date);
    return adjustment.volumeFactor;
  }

  String _formatDateIso(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }
}
