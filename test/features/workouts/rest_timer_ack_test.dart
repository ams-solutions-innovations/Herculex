import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/workouts/domain/rest_timer_ack.dart';

/// The phone used to withdraw its own "rest is over" notification as soon as
/// the message to the watch was handed to the radio. These tests pin the
/// replacement rule: only a watch that says it armed the alert, for the rest
/// that is running now, may take the phone's notification away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.fromMillisecondsSinceEpoch(1_000_000);
  final endsAt = now.millisecondsSinceEpoch + 60_000;

  String ackJson({
    int? endsAtMs,
    int? rev = 7,
    Object? armed = true,
    String reason = 'exact',
  }) => jsonEncode({
    'endsAtEpochMs': endsAtMs ?? endsAt,
    'rev': ?rev,
    'armed': armed,
    'reason': reason,
  });

  bool withdraw(
    RestTimerAck ack, {
    int? sentRev = 7,
    int? sentEndsAt,
    bool alert = true,
    bool follows = true,
    DateTime? at,
  }) => shouldWithdrawPhoneRestAlert(
    ack: ack,
    sentRev: sentRev,
    sentEndsAtMs: sentEndsAt ?? endsAt,
    alertEnabled: alert,
    watchFollowsWorkout: follows,
    now: at ?? now,
  );

  group('RestTimerAck.tryParse', () {
    test('reads a well-formed ack', () {
      final ack = RestTimerAck.tryParse(ackJson())!;

      expect(ack.armed, isTrue);
      expect(ack.rev, 7);
      expect(ack.endsAtEpochMs, endsAt);
      expect(ack.reason, 'exact');
    });

    test('an ack from a build without revisions has no rev', () {
      expect(RestTimerAck.tryParse(ackJson(rev: null))!.rev, isNull);
    });

    test('rejects anything that is not an ack', () {
      expect(RestTimerAck.tryParse(null), isNull);
      expect(RestTimerAck.tryParse(''), isNull);
      expect(RestTimerAck.tryParse('not json'), isNull);
      expect(RestTimerAck.tryParse('[1,2]'), isNull);
      expect(RestTimerAck.tryParse('{"armed":true}'), isNull);
      expect(RestTimerAck.tryParse(ackJson(armed: 'yes')), isNull);
    });
  });

  group('shouldWithdrawPhoneRestAlert', () {
    test('withdraws when the watch is armed for the current rest', () {
      expect(withdraw(RestTimerAck.tryParse(ackJson())!), isTrue);
    });

    test('keeps the phone alert when the watch is not armed', () {
      for (final reason in [
        'inexact',
        'notifications_denied',
        'alarm_failed',
      ]) {
        final ack = RestTimerAck.tryParse(
          ackJson(armed: false, reason: reason),
        )!;
        expect(withdraw(ack), isFalse, reason: reason);
      }
    });

    test('keeps the phone alert when the user switched alerts off', () {
      expect(
        withdraw(RestTimerAck.tryParse(ackJson())!, alert: false),
        isFalse,
      );
    });

    test('keeps the phone alert when the watch is not following the '
        'workout', () {
      expect(
        withdraw(RestTimerAck.tryParse(ackJson())!, follows: false),
        isFalse,
      );
    });

    test('an ack for an earlier rest does not withdraw the current one', () {
      // The user extended the rest: the ack still in flight answers rev 7, the
      // running timer is rev 8.
      final stale = RestTimerAck.tryParse(ackJson(rev: 7))!;

      expect(withdraw(stale, sentRev: 8), isFalse);
    });

    test('without revisions the end time identifies the rest', () {
      final legacy = RestTimerAck.tryParse(ackJson(rev: null))!;

      expect(withdraw(legacy), isTrue);
      expect(withdraw(legacy, sentEndsAt: endsAt + 30_000), isFalse);
    });

    test('nothing to withdraw after a skip', () {
      final ack = RestTimerAck.tryParse(ackJson())!;

      expect(withdraw(ack, sentEndsAt: 0), isFalse);
    });

    test('a late ack never removes a notification that is already due', () {
      final ack = RestTimerAck.tryParse(ackJson())!;

      expect(
        withdraw(ack, at: DateTime.fromMillisecondsSinceEpoch(endsAt - 1)),
        isTrue,
      );
      expect(
        withdraw(ack, at: DateTime.fromMillisecondsSinceEpoch(endsAt)),
        isFalse,
      );
    });
  });

  group('WearSyncService delivery', () {
    const codec = StandardMethodCodec();

    setUp(() {
      WearSyncService.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(WearSyncService.channelName),
            (call) async => null,
          );
      WearSyncService.initialize();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(WearSyncService.channelName),
            null,
          );
      WearSyncService.resetForTesting();
    });

    Future<void> deliver(String json) {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            WearSyncService.channelName,
            codec.encodeMethodCall(
              MethodCall('onWatchRestTimerAck', {'ack_json': json}),
            ),
            (_) {},
          );
    }

    test('the native ack reaches the registered handler', () async {
      String? received;
      WearSyncService.onWatchRestTimerAck = (json) => received = json;

      await deliver(ackJson());

      expect(received, ackJson());
    });

    test('an ack with no handler registered is dropped, not queued', () async {
      await deliver(ackJson());

      String? received;
      WearSyncService.onWatchRestTimerAck = (json) => received = json;
      await Future<void>.delayed(Duration.zero);

      expect(received, isNull);
    });

    test('resetForTesting clears the handler', () async {
      var calls = 0;
      WearSyncService.onWatchRestTimerAck = (_) => calls++;

      WearSyncService.resetForTesting();
      await deliver(ackJson());

      expect(calls, 0);
    });
  });
}
