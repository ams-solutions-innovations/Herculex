import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_payload.dart';

void main() {
  test('round-trips a schedule id through the payload string', () {
    final payload = fastingSchedulePayload(42);
    expect(fastingScheduleIdFromPayload(payload), 42);
  });

  test('returns null for null, empty, and unrelated payloads', () {
    expect(fastingScheduleIdFromPayload(null), isNull);
    expect(fastingScheduleIdFromPayload(''), isNull);
    expect(fastingScheduleIdFromPayload('workout:1:2'), isNull);
  });

  test('returns null for a malformed id after the prefix', () {
    expect(fastingScheduleIdFromPayload('fasting_schedule:not_a_number'), isNull);
  });
}
