import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';

void main() {
  test('null last check-in has no next date and is eligible', () {
    expect(CheckInCapPolicy.nextEligibleDate(null), isNull);
    expect(CheckInCapPolicy.isEligible(now: DateTime(2026, 10, 1)), isTrue);
  });

  test('next eligible is local midnight 7 days later', () {
    expect(
      CheckInCapPolicy.nextEligibleDate(DateTime(2026, 10, 5, 14, 30)),
      DateTime(2026, 10, 12),
    );
  });

  test('eligibility boundary', () {
    final last = DateTime(2026, 10, 5, 14, 30);
    expect(
      CheckInCapPolicy.isEligible(
        now: DateTime(2026, 10, 12, 0, 0),
        lastCheckInAt: last,
      ),
      isTrue,
    );
    expect(
      CheckInCapPolicy.isEligible(
        now: DateTime(2026, 10, 11, 23, 59),
        lastCheckInAt: last,
      ),
      isFalse,
    );
  });

  test('DST window still 7 calendar days', () {
    expect(
      CheckInCapPolicy.nextEligibleDate(DateTime(2026, 3, 25, 9)),
      DateTime(2026, 4, 1),
    );
    expect(
      CheckInCapPolicy.nextEligibleDate(DateTime(2026, 3, 25, 23, 30)),
      DateTime(2026, 4, 1),
    );
  });

  test('month and year rollover', () {
    expect(
      CheckInCapPolicy.nextEligibleDate(DateTime(2026, 12, 28, 10)),
      DateTime(2027, 1, 4),
    );
  });
}
