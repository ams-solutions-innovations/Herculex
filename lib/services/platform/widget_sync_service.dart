import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';

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

  /// Sync recovery to the Recovery widget.
  ///
  /// [scorePct] is the average recovery across all muscle groups (0–100), or
  /// -1 when there's nothing to score yet. [muscles] are the most fatigued
  /// groups, worst first, as (name, recovery score 0–100).
  Future<void> syncRecovery({
    required int scorePct,
    List<(String, int)> muscles = const [],
  }) async {
    try {
      await _channel.invokeMethod('syncRecovery', {
        'scorePct': scorePct,
        'muscles': [
          for (final (name, score) in muscles) {'name': name, 'score': score},
        ],
        'epochDay': _epochDay,
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncRecovery failed: ${e.message}');
    }
  }

  /// Sync the running fast to the Fasting widget. The widget computes the
  /// clock itself, so this only needs to run when the session changes.
  ///
  /// Pass a null [startedAt] when no fast is running, and a null
  /// [targetSeconds] for a Quick Fast. [planLabel] is the badge, e.g. "16:8".
  Future<void> syncFasting({
    required DateTime? startedAt,
    required int? targetSeconds,
    required String? planLabel,
  }) async {
    try {
      await _channel.invokeMethod('syncFasting', {
        'startedAtMs': startedAt?.millisecondsSinceEpoch,
        'targetSeconds': targetSeconds,
        'planLabel': planLabel,
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncFasting failed: ${e.message}');
    }
  }

  /// Last payload sent per [syncWidgetData] key, so unchanged rebuilds
  /// don't redraw every widget.
  static final _lastData = <String, String>{};

  /// Push the payload for one of the training/body/habit widgets. [key]
  /// names the widget (see `HxWidgetProvider.DATA_PROVIDERS`); values are
  /// display-ready strings, so units and locale formatting stay in Dart.
  /// A null [data] clears it back to the widget's empty state.
  Future<void> syncWidgetData(String key, Map<String, Object?>? data) async {
    final encoded = jsonEncode(data);
    if (_lastData[key] == encoded) return;
    try {
      await _channel.invokeMethod('syncWidgetData', {'key': key, 'data': data});
      _lastData[key] = encoded;
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncWidgetData($key) failed: ${e.message}');
    }
  }

  /// Sync the selected app theme so the widgets draw with the same
  /// [HxColors]. Both palettes are sent so a `system` [mode] can follow the
  /// device's dark setting without the app running.
  Future<void> syncTheme({
    required ThemeMode mode,
    required HxColors dark,
    required HxColors light,
  }) async {
    Map<String, int> palette(HxColors c) => {
      'surface': c.surfaceContainerLowest.toARGB32(),
      'surfaceVariant': c.surfaceVariant.toARGB32(),
      'outlineVariant': c.outlineVariant.toARGB32(),
      'onSurface': c.onSurface.toARGB32(),
      'secondary': c.secondary.toARGB32(),
      'primary': c.primary.toARGB32(),
      'onPrimary': c.onPrimary.toARGB32(),
      'kcal': c.macroKcal.toARGB32(),
      'protein': c.macroProtein.toARGB32(),
      'carbs': c.macroCarbs.toARGB32(),
      'fat': c.macroFat.toARGB32(),
      'success': c.success.toARGB32(),
      'warning': c.warning.toARGB32(),
      'danger': c.danger.toARGB32(),
      'recovery': c.domainRecovery.toARGB32(),
      'fasting': c.domainFasting.toARGB32(),
      'nutrition': c.domainNutrition.toARGB32(),
    };

    try {
      await _channel.invokeMethod('syncTheme', {
        'mode': switch (mode) {
          ThemeMode.dark => 'dark',
          ThemeMode.light => 'light',
          ThemeMode.system => 'system',
        },
        'dark': palette(dark),
        'light': palette(light),
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncTheme failed: ${e.message}');
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
