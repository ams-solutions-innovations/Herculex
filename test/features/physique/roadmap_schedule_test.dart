import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/roadmap_schedule.dart';

void main() {
  final anchor = DateTime(2026, 10, 7);

  RoadmapSchedule proposal() => RoadmapScheduleCalculator.build(
    anchor: anchor,
    now: anchor,
    startWeightKg: 80,
    phases: const [
      SchedulePhaseInput(
        phase: DietPhase.cut,
        plannedWeeks: 12,
        targetWeightKg: 74,
        targetBfPercent: 12,
      ),
      SchedulePhaseInput(
        phase: DietPhase.maintain,
        plannedWeeks: 2,
        targetWeightKg: 74,
      ),
      SchedulePhaseInput(
        phase: DietPhase.maingain,
        plannedWeeks: 38,
        targetWeightKg: 78.2,
      ),
    ],
  );

  group('RoadmapScheduleCalculator', () {
    test('places a proposal back to back from the anchor', () {
      final s = proposal();
      expect(s.phases[0].startDate, DateTime(2026, 10, 7));
      expect(s.phases[0].endDate, DateTime(2026, 12, 30));
      expect(s.phases[1].startDate, s.phases[0].endDate);
      expect(s.phases[2].startDate, s.phases[1].endDate);
      expect(s.totalWeeks, 52);
      expect(s.endDate, DateTime(2027, 10, 6));
      expect(s.totalMonths, 12);
    });

    test('chains start and end weights, and names the dream weight', () {
      final s = proposal();
      expect(s.phases.map((p) => p.startKg), [80, 74, 74]);
      expect(s.phases.map((p) => p.endKg), [74, 74, 78.2]);
      expect(s.startWeightKg, 80);
      expect(s.dreamWeightKg, 78.2);
      expect(s.phases[0].weeklyKg, closeTo(-0.5, 1e-9));
      expect(s.phases[1].weeklyKg, 0);
    });

    test('a phase without a target ends where it started', () {
      final s = RoadmapScheduleCalculator.build(
        anchor: anchor,
        now: anchor,
        startWeightKg: 80,
        phases: const [
          SchedulePhaseInput(phase: DietPhase.recomp, plannedWeeks: 8),
        ],
      );
      expect(s.phases.single.endKg, 80);
      expect(s.dreamWeightKg, 80);
    });

    test('unknown start weight leaves the weights null', () {
      final s = RoadmapScheduleCalculator.build(
        anchor: anchor,
        now: anchor,
        phases: const [
          SchedulePhaseInput(phase: DietPhase.maintain, plannedWeeks: 4),
        ],
      );
      expect(s.phases.single.startKg, isNull);
      expect(s.phases.single.weeklyKg, isNull);
      expect(s.dreamWeightKg, isNull);
    });

    test('uses recorded dates for started phases and never plans in the '
        'past', () {
      final s = RoadmapScheduleCalculator.build(
        anchor: DateTime(2026, 1, 1),
        now: DateTime(2026, 10, 7),
        startWeightKg: 80,
        phases: [
          SchedulePhaseInput(
            phase: DietPhase.cut,
            plannedWeeks: 12,
            targetWeightKg: 74,
            status: 'done',
            startedAt: DateTime(2026, 1, 1),
            completedAt: DateTime(2026, 3, 20),
          ),
          SchedulePhaseInput(
            phase: DietPhase.maintain,
            plannedWeeks: 2,
            targetWeightKg: 74,
            status: 'current',
            startedAt: DateTime(2026, 3, 20),
          ),
          const SchedulePhaseInput(
            phase: DietPhase.maingain,
            plannedWeeks: 10,
            targetWeightKg: 76,
          ),
        ],
      );
      expect(s.phases[0].endDate, DateTime(2026, 3, 20));
      expect(s.phases[1].startDate, DateTime(2026, 3, 20));
      expect(s.phases[1].endDate, DateTime(2026, 4, 3));
      // The running phase is long overdue, so the next one is shown from today.
      expect(s.phases[2].startDate, DateTime(2026, 10, 7));
      expect(s.current!.phase, DietPhase.maintain);
    });

    test('weightAt interpolates inside a phase', () {
      final s = proposal();
      expect(s.weightAt(DateTime(2026, 10, 7)), 80);
      expect(s.weightAt(DateTime(2026, 1, 1)), 80);
      // Halfway through the 12-week cut (42 of 84 days).
      expect(s.weightAt(DateTime(2026, 11, 18)), closeTo(77, 1e-9));
      expect(s.weightAt(DateTime(2027, 12, 1)), 78.2);
    });
  });
}
