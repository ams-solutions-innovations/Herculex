import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Applies a control tapped in the bubble's popup. Same `(actionId, sessionId,
/// setId)` shape as [WorkoutNotificationService.onNotificationAction], because
/// both surfaces send the same shared `WorkoutNotificationActionIds`.
/// Applies a control tapped or value edited in the bubble's popup.
typedef WorkoutBubbleActionHandler =
    Future<void> Function(
      String actionId,
      int? sessionId,
      int? setId,
      String? value,
    );

/// Drives the Workout Bubble — the floating chat head that sits over other apps
/// while a workout is running and expands into a live workout card.
///
/// Android only. iOS has no equivalent OS capability, so every method is a
/// no-op there rather than a thrown `MissingPluginException`.
///
/// The native side renders and reports taps; it never derives workout state.
/// [show] pushes the same `OngoingWorkoutSurfaceSnapshot` values that drive the
/// ongoing notification, and control taps come back through [onAction].
class WorkoutBubbleService {
  WorkoutBubbleService._();
  static final WorkoutBubbleService instance = WorkoutBubbleService._();

  static const channelName = 'com.ams.herculex/workout_bubble';
  static const MethodChannel _channel = MethodChannel(channelName);

  /// Set by the app root before any bubble is shown. Static to match
  /// `WorkoutNotificationService`'s callback style.
  static WorkoutBubbleActionHandler? onAction;

  /// Whether the platform can host a bubble at all. Guards every call so the
  /// rest of the app can stay platform-agnostic.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Starts listening for popup control taps. Call once at startup.
  void init() {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onBubbleAction') return null;
      final args = (call.arguments as Map?)?.cast<Object?, Object?>();
      final actionId = args?['actionId'] as String?;
      if (actionId == null || actionId.isEmpty) return null;
      await onAction?.call(
        actionId,
        (args?['sessionId'] as num?)?.toInt(),
        (args?['setId'] as num?)?.toInt(),
        args?['value'] as String?,
      );
      return null;
    });
  }

  /// Whether "Display over other apps" is currently granted.
  ///
  /// Read natively rather than through `permission_handler` so this can never
  /// disagree with the `Settings.canDrawOverlays` check the native controller
  /// itself makes before drawing. Requesting the permission still goes through
  /// `permission_handler`, which knows how to open the system screen and wait
  /// for the user to come back.
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return await _guard<bool>(
          () => _channel.invokeMethod<bool>('canDrawOverlays'),
        ) ??
        false;
  }

  /// Shows the bubble, or refreshes an already-visible one — safe and cheap to
  /// call on every workout change, which is how the open popup stays live.
  Future<void> show({
    required int sessionId,
    required int startedAtEpochMs,
    required String exerciseName,
    required String subtitle,
    required String setNumber,
    required String weight,
    required String reps,
    required String rpe,
    required String totalSetsText,
    required String tonnageText,
    required List<Map<String, Object?>> actions,
    int? targetSetId,
    String? lastSetText,
    bool isWarmup = false,
  }) async {
    if (!isSupported) return;
    await _guard<void>(
      () => _channel.invokeMethod<void>('show', <String, Object?>{
        'sessionId': sessionId,
        'startedAtEpochMs': startedAtEpochMs,
        'exerciseName': exerciseName,
        'subtitle': subtitle,
        'setNumber': setNumber,
        'weight': weight,
        'reps': reps,
        'rpe': rpe,
        'totalSetsText': totalSetsText,
        'tonnageText': tonnageText,
        'lastSetText': lastSetText,
        'targetSetId': targetSetId,
        'isWarmup': isWarmup,
        'actions': actions,
      }),
    );
  }

  Future<void> hide() async {
    if (!isSupported) return;
    await _guard<void>(() => _channel.invokeMethod<void>('hide'));
  }

  /// Runs a channel call, swallowing platform failures so a revoked permission
  /// or an OEM window policy can never throw into the UI. Mirrors
  /// `WorkoutNotificationService._guard`; errors are logged in debug only.
  Future<T?> _guard<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WorkoutBubbleService: bubble call skipped ($e)');
      }
      return null;
    }
  }
}
