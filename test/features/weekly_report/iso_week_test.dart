import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';

void main() {
  group('IsoWeek.fromDate', () {
    final cases = <(DateTime, int, int)>[
      (DateTime(2026, 12, 31), 2026, 53),
      (DateTime(2027, 1, 1), 2026, 53),
      (DateTime(2027, 1, 4), 2027, 1),
      (DateTime(2024, 12, 30), 2025, 1),
      (DateTime(2021, 1, 3), 2020, 53),
      (DateTime(2026, 9, 28), 2026, 40),
      (DateTime(2026, 10, 4), 2026, 40),
      (DateTime(2026, 9, 27), 2026, 39),
    ];
    for (final c in cases) {
      test('${c.$1.toIso8601String()} -> ${c.$2}-W${c.$3}', () {
        expect(IsoWeek.fromDate(c.$1), IsoWeek(c.$2, c.$3));
      });
    }

    test('time of day does not change the week', () {
      expect(
        IsoWeek.fromDate(DateTime(2026, 10, 4, 23, 59)),
        const IsoWeek(2026, 40),
      );
      expect(
        IsoWeek.fromDate(DateTime(2026, 10, 5, 0, 0)),
        const IsoWeek(2026, 41),
      );
    });
  });

  group('IsoWeek.tryCreate / weeksInYear', () {
    test('accepts real weeks and rejects impossible ones', () {
      expect(IsoWeek.tryCreate(2026, 53), isNotNull);
      expect(IsoWeek.tryCreate(2027, 53), isNull);
      expect(IsoWeek.tryCreate(2026, 0), isNull);
      expect(IsoWeek.tryCreate(2026, 54), isNull);
      expect(IsoWeek.tryCreate(1999, 10), isNull);
      expect(IsoWeek.tryCreate(2101, 10), isNull);
      expect(IsoWeek.tryCreate(2026, 40), const IsoWeek(2026, 40));
    });

    test('weeksInYear', () {
      expect(IsoWeek.weeksInYear(2026), 53);
      expect(IsoWeek.weeksInYear(2027), 52);
      expect(IsoWeek.weeksInYear(2020), 53);
      expect(IsoWeek.weeksInYear(2025), 52);
    });
  });

  group('IsoWeek window', () {
    test('2026-W40 boundaries', () {
      const w = IsoWeek(2026, 40);
      expect(w.start, DateTime(2026, 9, 28));
      expect(w.endExclusive, DateTime(2026, 10, 5));
      expect(w.startIso, '2026-09-28');
      expect(w.endIso, '2026-10-04');
    });

    test('every 2026 and 2027 week starts and ends on local Monday 00:00', () {
      for (final year in [2026, 2027]) {
        for (var wk = 1; wk <= IsoWeek.weeksInYear(year); wk++) {
          final w = IsoWeek(year, wk);
          expect(w.start.weekday, DateTime.monday, reason: '$w start');
          expect(w.start.hour, 0, reason: '$w start hour');
          expect(w.start.minute, 0, reason: '$w start minute');
          expect(w.endExclusive.weekday, DateTime.monday, reason: '$w end');
          expect(w.endExclusive.hour, 0, reason: '$w end hour');
          expect(IsoWeek.fromDate(w.start), w, reason: '$w round trip');
        }
      }
    });

    test('consecutive weeks abut exactly', () {
      for (var wk = 1; wk < 53; wk++) {
        expect(
          IsoWeek(2026, wk).endExclusive,
          IsoWeek(2026, wk + 1).start,
          reason: 'W$wk',
        );
      }
      expect(IsoWeek(2026, 53).endExclusive, IsoWeek(2027, 1).start);
    });

    test('windowEnd clamps to now inside the week', () {
      const w = IsoWeek(2026, 40);
      final inside = DateTime(2026, 10, 1, 12);
      expect(w.windowEnd(inside), inside);
      expect(w.windowEnd(DateTime(2026, 10, 9)), w.endExclusive);
    });
  });

  group('IsoWeek navigation and identity', () {
    test('previous', () {
      expect(const IsoWeek(2026, 1).previous, const IsoWeek(2025, 52));
      expect(const IsoWeek(2021, 1).previous, const IsoWeek(2020, 53));
      expect(const IsoWeek(2026, 40).previous, const IsoWeek(2026, 39));
    });

    test('equality, hashCode, compareTo, isAfter, toString', () {
      expect(const IsoWeek(2026, 40), const IsoWeek(2026, 40));
      expect(
        const IsoWeek(2026, 40).hashCode,
        const IsoWeek(2026, 40).hashCode,
      );
      expect({const IsoWeek(2026, 40): 1}[const IsoWeek(2026, 40)], 1);
      expect(const IsoWeek(2026, 40).compareTo(const IsoWeek(2026, 41)), lessThan(0));
      expect(const IsoWeek(2027, 1).compareTo(const IsoWeek(2026, 53)), greaterThan(0));
      expect(const IsoWeek(2026, 40).compareTo(const IsoWeek(2026, 40)), 0);
      expect(const IsoWeek(2027, 1).isAfter(const IsoWeek(2026, 53)), isTrue);
      expect(const IsoWeek(2026, 40).isAfter(const IsoWeek(2026, 40)), isFalse);
      expect(const IsoWeek(2026, 40).toString(), '2026-W40');
      expect(const IsoWeek(2026, 5).toString(), '2026-W05');
    });
  });

  group('IsoWeek.forNotificationTap', () {
    test('Sunday 17:59 with 18:00 resolves to the previous week', () {
      expect(
        IsoWeek.forNotificationTap(DateTime(2026, 10, 4, 17, 59), '18:00'),
        const IsoWeek(2026, 39),
      );
    });

    test('Sunday 18:01 resolves to this week', () {
      expect(
        IsoWeek.forNotificationTap(DateTime(2026, 10, 4, 18, 1), '18:00'),
        const IsoWeek(2026, 40),
      );
    });

    test('Monday resolves to the week that just ended', () {
      expect(
        IsoWeek.forNotificationTap(DateTime(2026, 10, 5, 9), '18:00'),
        const IsoWeek(2026, 40),
      );
    });

    test('year boundary', () {
      expect(
        IsoWeek.forNotificationTap(DateTime(2027, 1, 1, 12), '18:00'),
        const IsoWeek(2026, 52),
      );
      expect(
        IsoWeek.forNotificationTap(DateTime(2027, 1, 3, 18, 30), '18:00'),
        const IsoWeek(2026, 53),
      );
    });

    test('invalid time string falls back to 18:00', () {
      for (final bad in ['', 'abc', '25:00', '18:99', '18', '-1:00']) {
        expect(
          IsoWeek.forNotificationTap(DateTime(2026, 10, 4, 17, 59), bad),
          const IsoWeek(2026, 39),
          reason: 'bad="$bad" before 18:00',
        );
        expect(
          IsoWeek.forNotificationTap(DateTime(2026, 10, 4, 18, 1), bad),
          const IsoWeek(2026, 40),
          reason: 'bad="$bad" after 18:00',
        );
      }
    });

    test('a custom time is honoured', () {
      expect(
        IsoWeek.forNotificationTap(DateTime(2026, 10, 4, 20, 30), '21:00'),
        const IsoWeek(2026, 39),
      );
      expect(
        IsoWeek.forNotificationTap(DateTime(2026, 10, 4, 21, 0), '21:00'),
        const IsoWeek(2026, 40),
      );
    });
  });
}
