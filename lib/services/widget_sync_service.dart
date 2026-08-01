import 'package:flutter/services.dart';

/// Pushes nutrition and fitness data to the Android home-screen widgets.
///
/// Data is written to SharedPreferences via a MethodChannel so that each
/// [AppWidgetProvider] can read it synchronously in [onUpdate]. After writing,
/// the channel call also triggers [AppWidgetManager.updateAppWidget] for every
/// registered widget instance on the Kotlin side.
class WidgetSyncService {
  static const _channel = MethodChannel('com.ams.herculex/widget');

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
      });
    } on PlatformException catch (e) {
      debugPrint('[WidgetSync] syncRecovery failed: ${e.message}');
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
