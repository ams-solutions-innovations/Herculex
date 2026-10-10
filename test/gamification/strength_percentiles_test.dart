import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_percentiles.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/profile/domain/profile.dart';

StrengthAssessment _assess(
  Map<StrengthLift, LiftBest> bests, {
  BiologicalSex? sex = BiologicalSex.male,
}) => StrengthAssessment(tier: LevelBand.novice, bests: bests, sex: sex);

void main() {
  group('lifterTopPct', () {
    test('every rank threshold lands on its anchor, for both sexes', () {
      const expected = {
        LevelBand.intermediate: 50.0,
        LevelBand.advanced: 20.0,
        LevelBand.elite: 5.0,
      };
      for (final standard in strengthStandards) {
        for (final sex in BiologicalSex.values) {
          for (final MapEntry(key: band, value: pct) in expected.entries) {
            final threshold = standard.listedThreshold(band, sex);
            if (threshold == null) continue;
            expect(
              StrengthPercentiles.lifterTopPct(standard.lift, threshold, sex),
              closeTo(pct, 1e-9),
              reason: '${standard.lift} $sex $band',
            );
          }
        }
      }
    });

    test('interpolates between anchors', () {
      // Male squat: 1.25 → 50 %, 1.75 → 20 %; halfway is 35 %.
      expect(
        StrengthPercentiles.lifterTopPct(
          StrengthLift.squat,
          1.5,
          BiologicalSex.male,
        ),
        closeTo(35, 1e-9),
      );
    });

    test('is monotonic: more is never worse', () {
      for (final lift in StrengthLift.values) {
        var last = 101.0;
        for (var v = 0.0; v <= 80; v += 0.05) {
          final pct = StrengthPercentiles.lifterTopPct(
            lift,
            v,
            BiologicalSex.female,
          );
          expect(pct, lessThanOrEqualTo(last), reason: '$lift at $v');
          last = pct;
        }
      }
    });

    test('edges: zero is 100 %, far past Elite bottoms out', () {
      expect(
        StrengthPercentiles.lifterTopPct(StrengthLift.bench, 0, null),
        100,
      );
      expect(
        StrengthPercentiles.lifterTopPct(StrengthLift.bench, 5, null),
        0.5,
      );
    });

    test('sex picks the matching row; null falls back to men', () {
      // 1.3 × BW squat is Advanced for women, below Intermediate+ for men.
      final f = StrengthPercentiles.lifterTopPct(
        StrengthLift.squat,
        1.3,
        BiologicalSex.female,
      );
      final m = StrengthPercentiles.lifterTopPct(
        StrengthLift.squat,
        1.3,
        BiologicalSex.male,
      );
      expect(f, closeTo(20, 1e-9));
      expect(m, greaterThan(40));
      expect(
        StrengthPercentiles.lifterTopPct(StrengthLift.squat, 1.3, null),
        m,
      );
    });
  });

  group('evaluate', () {
    test('only logged values count; best first; world is smaller', () {
      final result = StrengthPercentiles.evaluate(
        _assess({
          StrengthLift.squat: const LiftBest(
            lift: StrengthLift.squat,
            logged: 1.75,
          ),
          StrengthLift.bench: const LiftBest(
            lift: StrengthLift.bench,
            logged: 1.0,
          ),
          StrengthLift.pullUp: const LiftBest(
            lift: StrengthLift.pullUp,
            reported: 20,
          ),
        }),
      );
      expect(result.map((p) => p.lift), [
        StrengthLift.squat,
        StrengthLift.bench,
      ]);
      expect(result.first.lifterTopPct, closeTo(20, 1e-9));
      expect(result.first.worldTopPct, closeTo(3, 1e-9));
    });

    test('never shows less than the floor', () {
      final result = StrengthPercentiles.evaluate(
        _assess({
          StrengthLift.muscleUp: const LiftBest(
            lift: StrengthLift.muscleUp,
            logged: 30,
          ),
        }),
      );
      expect(result.single.worldTopPct, StrengthPercentiles.minTopPct);
    });
  });

  group('highlight', () {
    final strong = [
      for (final (lift, pct) in [
        (StrengthLift.squat, 10.0),
        (StrengthLift.pullUp, 30.0),
        (StrengthLift.bench, 70.0),
      ])
        LiftPercentile(
          lift: lift,
          value: 1,
          lifterTopPct: pct,
          worldTopPct: pct / 10,
        ),
    ];

    test('rotates daily through the top half only', () {
      final day = DateTime(2026, 10, 9);
      final picks = {
        for (var d = 0; d < 6; d++)
          StrengthPercentiles.highlight(
            strong,
            day.add(Duration(days: d)),
          )!.lift,
      };
      expect(picks, {StrengthLift.squat, StrengthLift.pullUp});
    });

    test('stable within a day', () {
      final a = StrengthPercentiles.highlight(strong, DateTime(2026, 10, 9, 1));
      final b = StrengthPercentiles.highlight(
        strong,
        DateTime(2026, 10, 9, 23),
      );
      expect(a!.lift, b!.lift);
    });

    test('falls back to the best lift when none is in the top half', () {
      final weak = [strong.last];
      expect(
        StrengthPercentiles.highlight(weak, DateTime(2026))!.lift,
        StrengthLift.bench,
      );
      expect(StrengthPercentiles.highlight(const [], DateTime(2026)), isNull);
    });
  });

  test('formatTopPct', () {
    expect(formatTopPct(12.4), '12%');
    expect(formatTopPct(3), '3%');
    expect(formatTopPct(0.46), '0.5%');
  });
}
