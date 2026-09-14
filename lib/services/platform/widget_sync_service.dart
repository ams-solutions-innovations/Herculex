import 'package:flutter/services.dart';
import 'package:herculex/core/utils/clock.dart';

/// Pushes nutrition and fitness data to the Android home-screen widgets.
///
/// Data is written to SharedPreferences via a MethodChannel so that each
/// [AppWidgetProvider] can read it synchronously in [onUpdate]. After writing,
/// the channel call also triggers [AppWidgetManager.updateAppWidget] for every
/// registered widget instance on the Kotlin side.
class WidgetSyncService {
  WidgetSyncService({Clock clock = const SystemClock()}) : _clock = clock;

  final Clock _clock;

  static const _channel = MethodChannel('com.ams.herculex/widget');

  /// Local day number the data being pushed belongs to.
  ///
  /// Stored alongside every payload so the Kotlin providers can tell "synced
  /// today" from "left over from yesterday" and render their `—` placeholder
  /// instead of stale numbers. Goes through [Clock] so tests can pin the day.
  /// Built via [DateTime.utc] so the result is the plain calendar-date day
  /// number, independent of the device's UTC offset. The Kotlin side derives
  /// the same number from a local midnight plus its zone/DST offset.
  int get _epochDay {
    final now = _clock.now();
    return DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  /// Sync full nutrition data (calories goal, food, exercise, remaining, and macros)
  /// to the home-screen widgets.
  Future<void> syncNutrition({
    required int baseGoalKcal,
    required int foodKcal,
    required int exerciseKcal,
    required int remainingKcal,
    required int carbsCurrent,
    required int carbsTarget,
    required int fatCurrent,
    required int fatTarget,
    required int proteinCurrent,
    required int proteinTarget,
  }) async {
    try {
      await _channel.invokeMethod('syncNutrition', {
        'baseGoalKcal': baseGoalKcal,
        'foodKcal': foodKcal,
        'exerciseKcal': exerciseKcal,
        'remainingKcal': remainingKcal,
        'carbsCurrent': carbsCurrent,
        'carbsTarget': carbsTarget,
        'fatCurrent': fatCurrent,
        'fatTarget': fatTarget,
        'proteinCurrent': proteinCurrent,
        'proteinTarget': proteinTarget,
        'epochDay': _epochDay,
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncNutrition failed: ${e.message}');
    }
  }

  /// Sync macro data (carbs, fat, protein) to the three macro pill widgets.
  Future<void> syncMacros({
    required int carbsCurrent,
    required int carbsTarget,
    required int fatCurrent,
    required int fatTarget,
    required int proteinCurrent,
    required int proteinTarget,
  }) async {
    try {
      await _channel.invokeMethod('syncMacros', {
        'carbsCurrent': carbsCurrent,
        'carbsTarget': carbsTarget,
        'fatCurrent': fatCurrent,
        'fatTarget': fatTarget,
        'proteinCurrent': proteinCurrent,
        'proteinTarget': proteinTarget,
        'epochDay': _epochDay,
      });
    } on PlatformException catch (e) {
      // Widget sync is non-critical — log and continue.
      debugPrint('[WidgetSync] syncMacros failed: ${e.message}');
    }
  }

  /// Sync CNS readiness data to the CNS pill widget.
  Future<void> syncCns({
    required int readinessPct,
    required String status,
  }) async {
    try {
      await _channel.invokeMethod('syncCns', {
        'readinessPct': readinessPct,
        'status': status,
        'epochDay': _epochDay,
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncCns failed: ${e.message}');
    }
  }

  /// Sync overall recovery score to the recovery pill widget.
  ///
  /// [scorePct] is the average recovery across all muscle groups (0–100).
  Future<void> syncRecovery({required int scorePct}) async {
    try {
      await _channel.invokeMethod('syncRecovery', {
        'scorePct': scorePct,
        'epochDay': _epochDay,
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncRecovery failed: ${e.message}');
    }
  }

  /// Sync today's planned workout and up to 4 supplements to the Training
  /// home-screen widget.
  ///
  /// [title] is null when nothing is scheduled today. [week] is the program
  /// week number, or null when unknown. The four supplement lists are always
  /// the same (already-capped) length; [supplementTaken] is parallel to them.
  Future<void> syncTraining({
    required String? title,
    required int? week,
    required int exerciseCount,
    required List<String> supplementNames,
    required List<String> supplementDoses,
    required List<String> supplementTimes,
    required List<bool> supplementTaken,
    required int supplementTakenCount,
    required int supplementTotalCount,
  }) async {
    try {
      await _channel.invokeMethod('syncTraining', {
        'title': title,
        'week': week ?? -1,
        'exerciseCount': exerciseCount,
        'supplementNames': supplementNames,
        'supplementDoses': supplementDoses,
        'supplementTimes': supplementTimes,
        'supplementTaken': supplementTaken,
        'supplementTakenCount': supplementTakenCount,
        'supplementTotalCount': supplementTotalCount,
        'epochDay': _epochDay,
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncTraining failed: ${e.message}');
    }
  }
}

// Lightweight debug helper that avoids importing dart:developer.
void debugPrint(String message) {
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}
