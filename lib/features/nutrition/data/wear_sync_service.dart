import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class WearSyncService {
  static const MethodChannel _channel = MethodChannel('com.example.herculex/wear');

  static Function(String?, bool)? onWatchWorkoutStarted;
  static Function(String?)? onWatchWorkoutUpdated;
  static Function()? onWatchWorkoutEnded;
  static Function()? onRequestSync;

  WearSyncService() {
    initialize();
  }

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWatchWorkoutStarted':
          final sessionJson = call.arguments?['session_json'] as String?;
          final jumpToWorkout = call.arguments?['jump_to_workout'] as bool? ?? false;
          onWatchWorkoutStarted?.call(sessionJson, jumpToWorkout);
          break;
        case 'onWatchWorkoutUpdated':
          final sessionJson = call.arguments?['session_json'] as String?;
          onWatchWorkoutUpdated?.call(sessionJson);
          break;
        case 'onWatchWorkoutEnded':
          onWatchWorkoutEnded?.call();
          break;
        case 'onRequestSync':
          onRequestSync?.call();
          break;
      }
    });

    // Check if Android native host has a pending watch workout session
    _channel.invokeMethod('checkPendingWatchWorkout').catchError((_) {});
  }

  Future<void> syncMacros(int calories, int protein, {int carbs = 0, int fats = 0, String fasting = "0h 0m"}) async {
    try {
      await _channel.invokeMethod('syncMacros', {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fats': fats,
        'fasting': fasting,
      });
      debugPrint('Synced macros to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync macros to wear: ${e.message}');
    }
  }

  Future<void> syncWorkouts(String workoutsJson) async {
    try {
      await _channel.invokeMethod('syncWorkouts', {
        'workouts_json': workoutsJson,
      });
      debugPrint('Synced workouts JSON to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync workouts to wear: ${e.message}');
    }
  }

  Future<void> syncCatalog(String catalogJson) async {
    try {
      await _channel.invokeMethod('syncCatalog', {
        'catalog_json': catalogJson,
      });
      debugPrint('Synced catalog JSON to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync catalog to wear: ${e.message}');
    }
  }

  Future<void> syncActiveSession(String sessionJson, {bool isStart = false}) async {
    try {
      await _channel.invokeMethod('syncActiveSession', {
        'session_json': sessionJson,
        'is_start': isStart,
      });
      debugPrint('Synced active session to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync active session to wear: ${e.message}');
    }
  }

  Future<void> endWorkoutOnWatch() async {
    try {
      await _channel.invokeMethod('endWorkoutOnWatch');
      debugPrint('Ended workout on watch');
    } on PlatformException catch (e) {
      debugPrint('Failed to end workout on watch: ${e.message}');
    }
  }
}
