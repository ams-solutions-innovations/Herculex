part of '../health_service.dart';

/// Every sleep type we read, and what it means for [SleepAnalyzer].
///
/// Each platform supports a different subset (Health Connect has no
/// `SLEEP_IN_BED`, HealthKit has no `SLEEP_SESSION`), and the plugin throws
/// for a type its platform lacks — so [_SleepSync._readSleep] asks for them one
/// at a time and skips the ones that throw. Permission is per record class on
/// both platforms, so these need no extra grants beyond the sync types.
const Map<HealthDataType, SleepStage> _sleepStages = {
  HealthDataType.SLEEP_SESSION: SleepStage.inBed,
  HealthDataType.SLEEP_IN_BED: SleepStage.inBed,
  HealthDataType.SLEEP_ASLEEP: SleepStage.asleep,
  HealthDataType.SLEEP_LIGHT: SleepStage.light,
  HealthDataType.SLEEP_DEEP: SleepStage.deep,
  HealthDataType.SLEEP_REM: SleepStage.rem,
  HealthDataType.SLEEP_AWAKE: SleepStage.awake,
  HealthDataType.SLEEP_AWAKE_IN_BED: SleepStage.awake,
  HealthDataType.SLEEP_OUT_OF_BED: SleepStage.awake,
};

/// Sleep reading and persistence for [HealthService], split out so the main
/// file does not grow past the line limit.
extension _SleepSync on HealthService {
  /// Reads last night (and any naps since) and reduces it to a [SleepSummary].
  ///
  /// The window opens at 18:00 yesterday: late enough that yesterday's nap is
  /// not mistaken for tonight's sleep, early enough to catch a night that began
  /// in the early evening. Health Connect returns every record that overlaps
  /// the window, so a night straddling 18:00 is still whole.
  Future<HealthRead<SleepSummary>> _readSleep(
    DateTime midnight,
    DateTime endTime,
  ) async {
    final types = _sleepStages.keys.toList();
    final points = <HealthDataPoint>[];
    Object? firstError;
    var anyTypeRead = false;
    for (final type in types) {
      try {
        points.addAll(
          await _health.getHealthDataFromTypes(
            types: [type],
            startTime: midnight.subtract(const Duration(hours: 6)),
            endTime: endTime,
          ),
        );
        anyTypeRead = true;
      } catch (error) {
        // A type this platform lacks throws; that must not sink the others.
        firstError ??= error;
      }
    }
    if (!anyTypeRead) {
      return _failedRead<SleepSummary>(firstError!, types, endTime);
    }

    final summary = SleepAnalyzer.summarize([
      for (final p in points)
        SleepInterval(
          stage: _sleepStages[p.type]!,
          from: p.dateFrom,
          to: p.dateTo,
          source: p.sourceName.isNotEmpty
              ? p.sourceName
              : (p.sourceId.isNotEmpty ? p.sourceId : 'default'),
        ),
    ]);
    if (summary == null) {
      return HealthRead<SleepSummary>.empty(
        readAt: endTime,
        dataTypes: _typeNames(types),
      );
    }
    return HealthRead<SleepSummary>.available(
      value: summary,
      readAt: endTime,
      dataTypes: _typeNames(types),
    );
  }

  /// The headline hours (actual sleep) of a sleep read, status carried over.
  HealthRead<double> _sleepHoursOf(HealthRead<SleepSummary> read) {
    return HealthRead<double>(
      status: read.status,
      readAt: read.readAt,
      value: read.value?.asleepHours,
      dataTypes: read.dataTypes,
      platform: read.platform,
      message: read.message,
      error: read.error,
    );
  }

  /// Persists the stage / time-in-bed rows that ride along with `sleep_hours`.
  /// Mirrors [HealthService._applyMetricRead]: a trusted read replaces them
  /// (dropping any the new night lacks), an empty read clears them, and denied
  /// / failed reads leave the last trusted night alone.
  Future<void> _applySleepDetail(
    String dateIso,
    HealthReadStatus status,
    SleepSummary? detail,
  ) async {
    if (status == HealthReadStatus.available && detail != null) {
      final rows = detail.toSamples();
      for (final kind in SleepSummary.detailKinds) {
        await _deleteMetric(dateIso, kind);
        final value = rows[kind];
        if (value == null) continue;
        await _db
            .into(_db.healthSamples)
            .insert(
              HealthSamplesCompanion.insert(
                dateIso: dateIso,
                kind: kind,
                value: value,
              ),
            );
      }
    } else if (status == HealthReadStatus.empty) {
      for (final kind in SleepSummary.detailKinds) {
        await _deleteMetric(dateIso, kind);
      }
    }
  }

  /// Quietly re-reads sleep so recovery sees last night without the user
  /// opening the Health screen first — [HealthService.runDailySync] otherwise
  /// only runs from that screen.
  ///
  /// Throttled to once per [minGap] per session, never prompts for permission
  /// (no grant means no-op), and only ever *adds* a trusted night: an empty or
  /// failed read leaves what is stored alone, since a watch that has not synced
  /// to Health Connect yet is not evidence that last night did not happen.
  Future<void> _refreshSleep(Duration minGap) async {
    final now = _clock.now();
    final last = _lastSleepRefresh;
    if (last != null && now.difference(last) < minGap) return;
    _lastSleepRefresh = now;
    try {
      if (!await checkHasPermissions()) return;
      final sleep = await _readSleep(
        DateTime(now.year, now.month, now.day),
        now.add(const Duration(minutes: 15)),
      );
      if (sleep.status != HealthReadStatus.available) return;
      final dateIso = _formatDateIso(now);
      await _db.transaction(() async {
        await _applyMetricRead(
          dateIso,
          SleepSummary.kindAsleepHours,
          _sleepHoursOf(sleep),
        );
        await _applySleepDetail(dateIso, sleep.status, sleep.value);
      });
    } catch (_) {
      // Best effort: the manual sync on the Health screen still reports errors.
    }
  }
}
