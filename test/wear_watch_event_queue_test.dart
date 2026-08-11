import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';

/// The watch -> phone handoff is a race by construction: the native host emits
/// the session from `MainActivity.onResume` (notification tap) and from
/// `main()` via `checkPendingWatchWorkout`, both of which run before the first
/// widget build constructs `WearWorkoutSyncService` and registers the handlers.
/// These tests pin the buffering that keeps the workout from being dropped in
/// that window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  final binding = TestDefaultBinaryMessengerBinding.instance;

  Future<void> emit(String method, [Object? arguments]) {
    return binding.defaultBinaryMessenger.handlePlatformMessage(
      WearSyncService.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  setUp(() {
    WearSyncService.resetForTesting();
    WearSyncService.initialize();
  });

  tearDown(WearSyncService.resetForTesting);

  test('a start that arrives before the handler is registered is replayed', () async {
    await emit('onWatchWorkoutStarted', <String, Object?>{
      'session_json': '{"exercises":[]}',
      'jump_to_workout': true,
    });

    String? seenJson;
    var seenJump = false;
    var calls = 0;
    WearSyncService.onWatchWorkoutStarted = (json, jump) {
      calls++;
      seenJson = json;
      seenJump = jump;
    };

    expect(calls, 1, reason: 'the queued start must fire on registration');
    expect(seenJson, '{"exercises":[]}');
    expect(seenJump, isTrue, reason: 'jump_to_workout must survive the queue');
  });

  test('queued watch events replay in the order they were emitted', () async {
    await emit('onWatchWorkoutStarted', <String, Object?>{
      'session_json': 'start',
      'jump_to_workout': false,
    });
    await emit('onWatchWorkoutUpdated', <String, Object?>{
      'session_json': 'update',
    });
    await emit('onWatchWorkoutEnded');

    final order = <String>[];
    WearSyncService.onWatchWorkoutStarted = (json, _) => order.add('start:$json');
    // Nothing can drain past the start until every earlier handler exists, so
    // registering out of order must not let a later event overtake it.
    WearSyncService.onWatchWorkoutEnded = (_, _) => order.add('end');
    expect(order, <String>['start:start']);

    WearSyncService.onWatchWorkoutUpdated = (json) => order.add('update:$json');

    expect(order, <String>['start:start', 'update:update', 'end']);
  });

  test('events arriving after registration dispatch immediately', () async {
    final seen = <String?>[];
    WearSyncService.onWatchWorkoutUpdated = seen.add;

    await emit('onWatchWorkoutUpdated', <String, Object?>{
      'session_json': 'live',
    });

    expect(seen, <String?>['live']);
  });

  test('a later event never overtakes one still waiting for its handler', () async {
    await emit('onWatchWorkoutStarted', <String, Object?>{
      'session_json': 'start',
      'jump_to_workout': false,
    });

    final seen = <String?>[];
    WearSyncService.onWatchWorkoutUpdated = seen.add;

    await emit('onWatchWorkoutUpdated', <String, Object?>{
      'session_json': 'update',
    });

    expect(
      seen,
      isEmpty,
      reason: 'the update must stay queued behind the undelivered start',
    );

    WearSyncService.onWatchWorkoutStarted = (_, _) {};
    expect(seen, <String?>['update']);
  });
}
