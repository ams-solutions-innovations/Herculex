import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../data/cycle_repository.dart';
import '../domain/cycle_adjuster.dart';
import 'health_providers.dart';

/// Database repository for menstrual cycle settings and logs.
final cycleRepositoryProvider = Provider<CycleRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CycleRepository(db);
});

/// Reactive stream of the user's cycle settings (cycle length, period length, start date).
final cycleSettingsStreamProvider = StreamProvider<CycleSettingData?>((ref) {
  final repo = ref.watch(cycleRepositoryProvider);
  return repo.watchSettings();
});

/// Legacy alias for compatibility.
final cycleSettingsProvider = FutureProvider<CycleSettingData?>((ref) async {
  final asyncVal = ref.watch(cycleSettingsStreamProvider);
  return asyncVal.valueOrNull;
});

/// Reactive stream of today's manual override log, if any.
final todayOverrideProvider = StreamProvider<CycleLogData?>((ref) {
  final repo = ref.watch(cycleRepositoryProvider);
  return repo.watchLogForDate(DateTime.now());
});

/// Reactive stream of recent cycle logs (period logs and overrides).
final recentCycleLogsProvider = StreamProvider<List<CycleLogData>>((ref) {
  final repo = ref.watch(cycleRepositoryProvider);
  return repo.watchRecentLogs();
});

/// Comprehensive physiological adjustment recommendation for today.
final cycleAdjustmentProvider = FutureProvider<CycleAdjustmentResult>((ref) async {
  final repo = ref.watch(cycleRepositoryProvider);
  // Recompute automatically when settings or today's override change
  ref.watch(cycleSettingsStreamProvider);
  ref.watch(todayOverrideProvider);

  return repo.getAdjustmentFor(DateTime.now());
});

/// Current predicted or overridden cycle phase string.
final predictedPhaseProvider = FutureProvider<String>((ref) async {
  final adjustment = await ref.watch(cycleAdjustmentProvider.future);
  return adjustment.phase.id;
});

/// Training volume multiplier for today (e.g. 0.8 for menstrual, 1.1 for follicular).
final cycleMultiplierProvider = FutureProvider<double>((ref) async {
  final adjustment = await ref.watch(cycleAdjustmentProvider.future);
  return adjustment.volumeFactor;
});

/// State of cycle syncing operations.
class CycleSyncState {
  final bool isSyncingHealth;
  final String? syncMessage;
  final DateTime? lastHealthSync;

  const CycleSyncState({
    this.isSyncingHealth = false,
    this.syncMessage,
    this.lastHealthSync,
  });

  CycleSyncState copyWith({
    bool? isSyncingHealth,
    String? syncMessage,
    DateTime? lastHealthSync,
  }) {
    return CycleSyncState(
      isSyncingHealth: isSyncingHealth ?? this.isSyncingHealth,
      syncMessage: syncMessage,
      lastHealthSync: lastHealthSync ?? this.lastHealthSync,
    );
  }
}

class CycleSyncNotifier extends StateNotifier<CycleSyncState> {
  final Ref _ref;

  CycleSyncNotifier(this._ref) : super(const CycleSyncState());

  CycleRepository get _repo => _ref.read(cycleRepositoryProvider);

  Future<void> saveSettings({
    required int avgCycleDays,
    required int avgPeriodDays,
    required DateTime lastPeriodStart,
  }) async {
    await _repo.saveSettings(
      avgCycleDays: avgCycleDays,
      avgPeriodDays: avgPeriodDays,
      lastPeriodStart: lastPeriodStart,
    );
  }

  Future<void> setManualOverride({
    required DateTime date,
    required CyclePhase phase,
    required int intensity,
  }) async {
    await _repo.logManualOverride(
      date: date,
      phase: phase.id,
      intensity: intensity,
    );
  }

  Future<void> clearManualOverride(DateTime date) async {
    await _repo.clearManualOverride(date);
  }

  /// Pulls menstrual flow logs from Apple Health (HealthKit) / Health Connect (including Flo & Clue).
  Future<bool> syncFromHealthApps() async {
    state = state.copyWith(isSyncingHealth: true, syncMessage: 'Querying health platforms...');
    try {
      final healthService = _ref.read(healthServiceProvider);
      final periodDays = await healthService.readPeriodDays(lookbackDays: 90);

      if (periodDays.isEmpty) {
        state = state.copyWith(
          isSyncingHealth: false,
          syncMessage: 'No period records found in Apple Health / Health Connect.',
          lastHealthSync: DateTime.now(),
        );
        return false;
      }

      await _repo.ingestHealthPeriodDates(periodDays);

      state = state.copyWith(
        isSyncingHealth: false,
        syncMessage: 'Successfully synced ${periodDays.length} period entries from Health / Flo.',
        lastHealthSync: DateTime.now(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSyncingHealth: false,
        syncMessage: 'Failed to sync: $e',
      );
      return false;
    }
  }
}

final cycleSyncNotifierProvider =
    StateNotifierProvider<CycleSyncNotifier, CycleSyncState>((ref) {
  return CycleSyncNotifier(ref);
});
