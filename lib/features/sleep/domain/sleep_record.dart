// Domain model for sleep tracking and sleep stages.
// Pure Dart: no Flutter or Drift dependencies.

/// Standard physiological sleep stages tracked by wearable sensors and sleep logs.
enum SleepStage { deep, rem, light, awake }

/// Duration breakdown across sleep stages in minutes.
class SleepStageBreakdown {
  final double deepMinutes;
  final double remMinutes;
  final double lightMinutes;
  final double awakeMinutes;

  const SleepStageBreakdown({
    this.deepMinutes = 0.0,
    this.remMinutes = 0.0,
    this.lightMinutes = 0.0,
    this.awakeMinutes = 0.0,
  });

  /// Builds a breakdown from durations specified in hours.
  factory SleepStageBreakdown.fromHours({
    double deepHours = 0.0,
    double remHours = 0.0,
    double lightHours = 0.0,
    double awakeHours = 0.0,
  }) {
    return SleepStageBreakdown(
      deepMinutes: deepHours * 60.0,
      remMinutes: remHours * 60.0,
      lightMinutes: lightHours * 60.0,
      awakeMinutes: awakeHours * 60.0,
    );
  }

  /// Total actual sleep duration excluding awake time (deep + REM + light).
  double get totalSleepMinutes => deepMinutes + remMinutes + lightMinutes;

  /// Total actual sleep duration in hours.
  double get totalSleepHours => totalSleepMinutes / 60.0;

  /// Total time spent in bed, including nocturnal awakenings.
  double get totalTimeInBedMinutes => totalSleepMinutes + awakeMinutes;

  /// Total time spent in bed in hours.
  double get totalTimeInBedHours => totalTimeInBedMinutes / 60.0;

  /// Deep sleep as percentage of total actual sleep (0.0 to 100.0).
  double get deepPercentage =>
      totalSleepMinutes > 0 ? (deepMinutes / totalSleepMinutes) * 100.0 : 0.0;

  /// REM sleep as percentage of total actual sleep (0.0 to 100.0).
  double get remPercentage =>
      totalSleepMinutes > 0 ? (remMinutes / totalSleepMinutes) * 100.0 : 0.0;

  /// Light sleep as percentage of total actual sleep (0.0 to 100.0).
  double get lightPercentage =>
      totalSleepMinutes > 0 ? (lightMinutes / totalSleepMinutes) * 100.0 : 0.0;

  /// Awake time as percentage of total time in bed (0.0 to 100.0).
  double get awakePercentage => totalTimeInBedMinutes > 0
      ? (awakeMinutes / totalTimeInBedMinutes) * 100.0
      : 0.0;

  /// Shorthand aliases for stage percentages (0.0 to 100.0).
  double get deepPercent => deepPercentage;
  double get remPercent => remPercentage;
  double get lightPercent => lightPercentage;
  double get awakePercent => awakePercentage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepStageBreakdown &&
          runtimeType == other.runtimeType &&
          deepMinutes == other.deepMinutes &&
          remMinutes == other.remMinutes &&
          lightMinutes == other.lightMinutes &&
          awakeMinutes == other.awakeMinutes;

  @override
  int get hashCode =>
      Object.hash(deepMinutes, remMinutes, lightMinutes, awakeMinutes);

  @override
  String toString() =>
      'SleepStageBreakdown(deep: ${deepMinutes}m, rem: ${remMinutes}m, light: ${lightMinutes}m, awake: ${awakeMinutes}m)';
}

/// Nightly sleep summary record for a specific calendar date.
class SleepRecord {
  final String dateIso;
  final double totalHours;
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final SleepStageBreakdown? stages;
  final double? restingHr;
  final double targetHours;

  const SleepRecord({
    required this.dateIso,
    required this.totalHours,
    this.bedtime,
    this.wakeTime,
    this.stages,
    this.restingHr,
    this.targetHours = 8.0,
  });

  /// Accumulated sleep debt relative to target hours (minimum 0).
  double get sleepDebtHours {
    final debt = targetHours - totalHours;
    return debt > 0.0 ? debt : 0.0;
  }

  /// Sleep efficiency: ratio of actual sleep to time spent in bed (0.0 to 1.0).
  ///
  /// Typical healthy range is 0.85 to 0.95. If bed/wake intervals and stages
  /// are not recorded, defaults to 1.0.
  double get sleepEfficiency {
    if (stages != null && stages!.totalTimeInBedMinutes > 0) {
      final eff = stages!.totalSleepMinutes / stages!.totalTimeInBedMinutes;
      return eff.clamp(0.0, 1.0);
    }
    if (bedtime != null && wakeTime != null) {
      final inBedMinutes = wakeTime!.difference(bedtime!).inMinutes;
      if (inBedMinutes > 0) {
        final eff = (totalHours * 60.0) / inBedMinutes;
        return eff.clamp(0.0, 1.0);
      }
    }
    return 1.0;
  }

  /// Helper factory to build from hour durations.
  factory SleepRecord.fromHours({
    required String dateIso,
    required double totalHours,
    DateTime? bedtime,
    DateTime? wakeTime,
    double? deepHours,
    double? remHours,
    double? lightHours,
    double? awakeHours,
    double? restingHr,
    double targetHours = 8.0,
  }) {
    final hasStages =
        deepHours != null ||
        remHours != null ||
        lightHours != null ||
        awakeHours != null;

    final stageBreakdown = hasStages
        ? SleepStageBreakdown.fromHours(
            deepHours: deepHours ?? 0.0,
            remHours: remHours ?? 0.0,
            lightHours: lightHours ?? 0.0,
            awakeHours: awakeHours ?? 0.0,
          )
        : null;

    return SleepRecord(
      dateIso: dateIso,
      totalHours: totalHours,
      bedtime: bedtime,
      wakeTime: wakeTime,
      stages: stageBreakdown,
      restingHr: restingHr,
      targetHours: targetHours,
    );
  }

  /// Helper factory to build from raw health sample data.
  factory SleepRecord.fromSamples({
    required String dateIso,
    required double totalHours,
    DateTime? bedtime,
    DateTime? wakeTime,
    double? deepHours,
    double? remHours,
    double? lightHours,
    double? awakeHours,
    double? restingHr,
    double targetHours = 8.0,
  }) {
    return SleepRecord.fromHours(
      dateIso: dateIso,
      totalHours: totalHours,
      bedtime: bedtime,
      wakeTime: wakeTime,
      deepHours: deepHours,
      remHours: remHours,
      lightHours: lightHours,
      awakeHours: awakeHours,
      restingHr: restingHr,
      targetHours: targetHours,
    );
  }

  SleepRecord copyWith({
    String? dateIso,
    double? totalHours,
    DateTime? bedtime,
    DateTime? wakeTime,
    SleepStageBreakdown? stages,
    double? restingHr,
    double? targetHours,
  }) {
    return SleepRecord(
      dateIso: dateIso ?? this.dateIso,
      totalHours: totalHours ?? this.totalHours,
      bedtime: bedtime ?? this.bedtime,
      wakeTime: wakeTime ?? this.wakeTime,
      stages: stages ?? this.stages,
      restingHr: restingHr ?? this.restingHr,
      targetHours: targetHours ?? this.targetHours,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepRecord &&
          runtimeType == other.runtimeType &&
          dateIso == other.dateIso &&
          totalHours == other.totalHours &&
          bedtime == other.bedtime &&
          wakeTime == other.wakeTime &&
          stages == other.stages &&
          restingHr == other.restingHr &&
          targetHours == other.targetHours;

  @override
  int get hashCode => Object.hash(
    dateIso,
    totalHours,
    bedtime,
    wakeTime,
    stages,
    restingHr,
    targetHours,
  );

  @override
  String toString() =>
      'SleepRecord(date: $dateIso, hours: $totalHours, stages: $stages, rHr: $restingHr)';
}
