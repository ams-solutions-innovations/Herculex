import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';

enum _WatchEventType { started, updated, ended }

class _WatchEvent {
  const _WatchEvent(
    this.type, {
    this.sessionJson,
    this.jumpToWorkout = false,
    this.isDiscard = false,
    this.entityId,
  });

  final _WatchEventType type;
  final String? sessionJson;
  final bool jumpToWorkout;
  final bool isDiscard;
  final String? entityId;
}

class WearSyncService {
  static const String channelName = 'com.example.herculex/wear';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Function(String?, bool)? _onWatchWorkoutStarted;
  static Function(String?)? _onWatchWorkoutUpdated;
  static Function(String?, bool)? _onWatchWorkoutEnded;
  static Function(String?)? _onWatchWorkoutSavedAsTemplate;
  static Function(String?)? _onWatchFastingCommand;
  static Function(String?)? _onWatchQuickAddCommand;
  static Function(String?)? _onWatchMacroCommand;
  static Function()? onRequestSync;

  /// Watch events that arrived before the handlers below were registered.
  ///
  /// The native host fires these from `MainActivity.onResume` (notification
  /// tap) and from `checkPendingWatchWorkout` in [initialize], both of which
  /// run well before the first widget build constructs `WearWorkoutSyncService`
  /// and assigns the handlers. The old `?.call` dropped those payloads on the
  /// floor, so opening the app from the "workout started on watch" notification
  /// left the phone with no active session at all.
  static final List<_WatchEvent> _pendingWatchEvents = [];
  static final List<String?> _pendingFastingCommands = [];
  static final List<String?> _pendingQuickAddCommands = [];
  static final List<String?> _pendingMacroCommands = [];
  static final List<String?> _pendingRamblerCommands = [];

  static Function(String?)? _onWatchRamblerCommand;

  static set onWatchWorkoutStarted(Function(String?, bool)? handler) {
    _onWatchWorkoutStarted = handler;
    _drainPendingWatchEvents();
  }

  static set onWatchWorkoutUpdated(Function(String?)? handler) {
    _onWatchWorkoutUpdated = handler;
    _drainPendingWatchEvents();
  }

  static set onWatchWorkoutEnded(Function(String?, bool)? handler) {
    _onWatchWorkoutEnded = handler;
    _drainPendingWatchEvents();
  }

  static set onWatchWorkoutSavedAsTemplate(Function(String?)? handler) {
    _onWatchWorkoutSavedAsTemplate = handler;
  }

  static set onWatchFastingCommand(Function(String?)? handler) {
    _onWatchFastingCommand = handler;
    _drainPendingFastingCommands();
  }

  static set onWatchQuickAddCommand(Function(String?)? handler) {
    _onWatchQuickAddCommand = handler;
    _drainPendingQuickAddCommands();
  }

  static set onWatchMacroCommand(Function(String?)? handler) {
    _onWatchMacroCommand = handler;
    _drainPendingMacroCommands();
  }

  static set onWatchRamblerCommand(Function(String?)? handler) {
    _onWatchRamblerCommand = handler;
    _drainPendingRamblerCommands();
  }

  WearSyncService() {
    initialize();
  }

  static void initialize() {
    // The native side can emit several watch events back to back during
    // startup (the notification's intent extra, then the persisted copy).
    // Flutter's default per-channel buffer holds a single message and warns
    // on overflow, which would silently discard the first one.
    ServicesBinding.instance.channelBuffers.resize(channelName, 16);

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWatchWorkoutStarted':
          _deliver(
            _WatchEvent(
              _WatchEventType.started,
              sessionJson: call.arguments?['session_json'] as String?,
              jumpToWorkout:
                  call.arguments?['jump_to_workout'] as bool? ?? false,
            ),
          );
          break;
        case 'onWatchWorkoutUpdated':
          _deliver(
            _WatchEvent(
              _WatchEventType.updated,
              sessionJson: call.arguments?['session_json'] as String?,
            ),
          );
          break;
        case 'onWatchWorkoutEnded':
          final isDiscard = call.arguments?['isDiscard'] as bool? ?? false;
          final entityId = call.arguments?['entityId'] as String?;
          _deliver(
            _WatchEvent(
              _WatchEventType.ended,
              isDiscard: isDiscard,
              entityId: entityId,
            ),
          );
          break;
        case 'onWatchWorkoutSavedAsTemplate':
          _onWatchWorkoutSavedAsTemplate?.call(
            call.arguments?['entityId'] as String?,
          );
          break;
        case 'onWatchFastingCommand':
          _deliverFastingCommand(call.arguments?['command_json'] as String?);
          break;
        case 'onWatchQuickAddCommand':
          _deliverQuickAddCommand(call.arguments?['command_json'] as String?);
          break;
        case 'onWatchMacroCommand':
          _deliverMacroCommand(call.arguments?['command_json'] as String?);
          break;
        case 'onWatchRamblerCommand':
          _deliverRamblerCommand(call.arguments?['command_json'] as String?);
          break;
        case 'onRequestSync':
          onRequestSync?.call();
          break;
      }
    });

    // Check if Android native host has a pending watch workout session
    _channel.invokeMethod('checkPendingWatchWorkout').catchError((_) {});
  }

  /// Queues [event] behind anything already waiting so the watch's events are
  /// applied in the order they were emitted — a "started" that overtook an
  /// earlier "updated" would rewind the session to a stale snapshot.
  static void _deliver(_WatchEvent event) {
    if (_pendingWatchEvents.isEmpty && _dispatch(event)) return;
    _pendingWatchEvents.add(event);
  }

  static bool _dispatch(_WatchEvent event) {
    switch (event.type) {
      case _WatchEventType.started:
        final handler = _onWatchWorkoutStarted;
        if (handler == null) return false;
        handler(event.sessionJson, event.jumpToWorkout);
        return true;
      case _WatchEventType.updated:
        final handler = _onWatchWorkoutUpdated;
        if (handler == null) return false;
        handler(event.sessionJson);
        return true;
      case _WatchEventType.ended:
        final handler = _onWatchWorkoutEnded;
        if (handler == null) return false;
        handler(event.entityId, event.isDiscard);
        return true;
    }
  }

  static void _drainPendingWatchEvents() {
    while (_pendingWatchEvents.isNotEmpty &&
        _dispatch(_pendingWatchEvents.first)) {
      _pendingWatchEvents.removeAt(0);
    }
  }

  static void _deliverFastingCommand(String? commandJson) {
    final handler = _onWatchFastingCommand;
    if (handler == null) {
      _pendingFastingCommands.add(commandJson);
      return;
    }
    handler(commandJson);
  }

  static void _drainPendingFastingCommands() {
    final handler = _onWatchFastingCommand;
    if (handler == null) return;
    while (_pendingFastingCommands.isNotEmpty) {
      handler(_pendingFastingCommands.removeAt(0));
    }
  }

  static void _deliverQuickAddCommand(String? commandJson) {
    final handler = _onWatchQuickAddCommand;
    if (handler == null) {
      _pendingQuickAddCommands.add(commandJson);
      return;
    }
    handler(commandJson);
  }

  static void _drainPendingQuickAddCommands() {
    final handler = _onWatchQuickAddCommand;
    if (handler == null) return;
    while (_pendingQuickAddCommands.isNotEmpty) {
      handler(_pendingQuickAddCommands.removeAt(0));
    }
  }

  static void _deliverMacroCommand(String? commandJson) {
    final handler = _onWatchMacroCommand;
    if (handler == null) {
      _pendingMacroCommands.add(commandJson);
      return;
    }
    handler(commandJson);
  }

  static void _drainPendingMacroCommands() {
    final handler = _onWatchMacroCommand;
    if (handler == null) return;
    while (_pendingMacroCommands.isNotEmpty) {
      handler(_pendingMacroCommands.removeAt(0));
    }
  }

  static void _deliverRamblerCommand(String? commandJson) {
    final handler = _onWatchRamblerCommand;
    if (handler == null) {
      _pendingRamblerCommands.add(commandJson);
      return;
    }
    handler(commandJson);
  }

  static void _drainPendingRamblerCommands() {
    final handler = _onWatchRamblerCommand;
    if (handler == null) return;
    while (_pendingRamblerCommands.isNotEmpty) {
      handler(_pendingRamblerCommands.removeAt(0));
    }
  }

  /// Visible for tests — the handlers and queue are process-global statics.
  @visibleForTesting
  static void resetForTesting() {
    _onWatchWorkoutStarted = null;
    _onWatchWorkoutUpdated = null;
    _onWatchWorkoutEnded = null;
    _onWatchFastingCommand = null;
    _onWatchQuickAddCommand = null;
    _onWatchMacroCommand = null;
    _onWatchRamblerCommand = null;
    onRequestSync = null;
    _pendingWatchEvents.clear();
    _pendingFastingCommands.clear();
    _pendingQuickAddCommands.clear();
    _pendingMacroCommands.clear();
    _pendingRamblerCommands.clear();
  }

  /// Tells the native host the watch's session is now in the phone's database,
  /// so it can drop its persisted copy.
  ///
  /// Until this lands, the host keeps replaying that copy on every launch —
  /// that persistence is the only thing standing between a dropped platform
  /// message and a lost workout.
  Future<void> markWatchWorkoutApplied() async {
    try {
      await _channel.invokeMethod('markWatchWorkoutApplied');
    } catch (e) {
      debugPrint('Failed to ack watch workout: $e');
    }
  }

  Future<void> syncMacros(
    int calories,
    int protein, {
    int carbs = 0,
    int fats = 0,
    String fasting = "0h 0m",
    double weeklyTonnage = 0.0,
    int weeklySets = 0,
    String weeklyVolumeJson = "[]",
    String nutrientTrendsJson = "[]",
    int calorieGoal = 2000,
    int proteinGoal = 150,
    int carbsGoal = 200,
    int fatGoal = 65,
    int waterGoal = 2000,
  }) async {
    try {
      await _channel.invokeMethod('syncMacros', {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fats': fats,
        'fasting': fasting,
        'weekly_tonnage': weeklyTonnage,
        'weekly_sets': weeklySets,
        'weekly_volume_json': weeklyVolumeJson,
        'nutrient_trends_json': nutrientTrendsJson,
        'calorie_goal': calorieGoal,
        'protein_goal': proteinGoal,
        'carbs_goal': carbsGoal,
        'fat_goal': fatGoal,
        'water_goal': waterGoal,
      });
      debugPrint('Synced macros & goals to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync macros to wear: ${e.message}');
    }
  }

  Future<void> syncFastingSnapshot(String fastingJson) async {
    try {
      await _channel.invokeMethod('syncFastingSnapshot', {
        'fasting_json': fastingJson,
      });
      debugPrint('Synced fasting snapshot to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync fasting snapshot to wear: ${e.message}');
    }
  }

  Future<void> markWatchFastingCommandApplied(String commandId) async {
    try {
      await _channel.invokeMethod('markWatchFastingCommandApplied', {
        'command_id': commandId,
      });
    } catch (e) {
      debugPrint('Failed to ack watch fasting command: $e');
    }
  }

  Future<void> syncQuickAddFoods(String quickAddJson) async {
    try {
      await _channel.invokeMethod('syncQuickAddFoods', {
        'quickadd_json': quickAddJson,
      });
      debugPrint('Synced quick-add foods to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync quick-add foods to wear: ${e.message}');
    }
  }

  Future<void> markWatchQuickAddCommandApplied(String commandId) async {
    try {
      await _channel.invokeMethod('markWatchQuickAddCommandApplied', {
        'command_id': commandId,
      });
    } catch (e) {
      debugPrint('Failed to ack watch quick-add command: $e');
    }
  }

  Future<void> markWatchMacroCommandApplied(String commandId) async {
    try {
      await _channel.invokeMethod('markWatchMacroCommandApplied', {
        'command_id': commandId,
      });
    } catch (e) {
      debugPrint('Failed to ack watch macro command: $e');
    }
  }

  Future<void> markWatchRamblerCommandApplied(String commandId) async {
    try {
      await _channel.invokeMethod('markWatchRamblerCommandApplied', {
        'command_id': commandId,
      });
    } catch (e) {
      debugPrint('Failed to ack watch rambler command: $e');
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
      await _channel.invokeMethod('syncCatalog', {'catalog_json': catalogJson});
      debugPrint('Synced catalog JSON to wear');
    } on PlatformException catch (e) {
      debugPrint('Failed to sync catalog to wear: ${e.message}');
    }
  }

  Future<void> syncActiveSession(
    String sessionJson, {
    bool isStart = false,
  }) async {
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

  Future<void> syncMediaState(String mediaJson) async {
    try {
      await _channel.invokeMethod('syncMediaState', {'media_json': mediaJson});
    } on PlatformException catch (e) {
      debugPrint('Failed to sync media state to wear: ${e.message}');
    }
  }

  /// Native replacement for the `flutter_media_controller` plugin's
  /// `getMediaInfo` — that plugin queries `getActiveSessions()` against its
  /// own `AppWidgetProvider` class, which can never hold notification
  /// listener access, so it always throws and reports "no track playing".
  /// This queries the plugin's actual `MediaNotificationListener` service
  /// (already declared/grantable in AndroidManifest.xml) instead, and
  /// prefers a session that's actually playing over whatever
  /// `getActiveSessions()` happens to return first.
  Future<Map<String, dynamic>> getMediaInfoNative() async {
    try {
      final result = await _channel.invokeMethod<Map>('getMediaInfoNative');
      return result?.cast<String, dynamic>() ?? const {};
    } on PlatformException catch (e) {
      debugPrint('Failed to read native media info: ${e.message}');
      return const {};
    }
  }

  /// Native replacement for `flutter_media_controller`'s `mediaAction` —
  /// same wrong-ComponentName bug as [getMediaInfoNative].
  Future<void> sendMediaActionNative(String action) async {
    try {
      await _channel.invokeMethod('mediaActionNative', {'action': action});
    } on PlatformException catch (e) {
      debugPrint('Failed to send native media action: ${e.message}');
    }
  }

  Future<void> openMediaControlsPermission() async {
    try {
      await _channel.invokeMethod('openMediaControlsPermission');
    } on PlatformException catch (e) {
      debugPrint('Failed to open media controls permission: ${e.message}');
    }
  }

  Future<void> endWorkoutOnWatch(String entityId) async {
    try {
      await _channel.invokeMethod('endWorkoutOnWatch', {'entity_id': entityId});
      debugPrint('Ended workout on watch');
    } on PlatformException catch (e) {
      debugPrint('Failed to end workout on watch: ${e.message}');
    }
  }

  Future<void> sendAchievementNotification(InAppNotificationItem item) async {
    try {
      final jsonPayload = jsonEncode({
        'exerciseName': item.title,
        'prType': item.type.name,
        'headline': item.badgeText,
        'valueText': item.valueText,
        'subDetail': item.subtitle,
        'durationMs': item.duration.inMilliseconds,
      });
      await _channel.invokeMethod('sendAchievement', {
        'achievement_json': jsonPayload,
      });
      debugPrint('Sent achievement to watch: ${item.title}');
    } on PlatformException catch (e) {
      debugPrint('Failed to send achievement to watch: ${e.message}');
    }
  }
}
