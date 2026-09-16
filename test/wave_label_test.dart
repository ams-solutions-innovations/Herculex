import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/wave_label.dart';

void main() {
  group('WaveLabel.compute', () {
    test(
      'A,A,B,B rotation: viewing week 1 (0-based) returns wave 1 of 2, weeks 0-1',
      () {
        final result = WaveLabel.compute(
          totalWeeks: 4,
          currentWeekIndex: 1,
          exerciseIdByWeek: const {0: 1, 1: 1, 2: 2, 3: 2},
        );
        expect(result, isNotNull);
        expect(result!.waveIndex, 1);
        expect(result.waveCount, 2);
        expect(result.waveStartWeek, 0);
        expect(result.waveEndWeek, 1);
      },
    );

    test(
      'A,A,B,B rotation: viewing week 2 (0-based) returns wave 2 of 2, weeks 2-3',
      () {
        final result = WaveLabel.compute(
          totalWeeks: 4,
          currentWeekIndex: 2,
          exerciseIdByWeek: const {0: 1, 1: 1, 2: 2, 3: 2},
        );
        expect(result, isNotNull);
        expect(result!.waveIndex, 2);
        expect(result.waveCount, 2);
        expect(result.waveStartWeek, 2);
        expect(result.waveEndWeek, 3);
      },
    );

    test(
      'single exercise for the whole 8-week block reports wave 1 of 1 for every week',
      () {
        final exerciseIdByWeek = {for (var w = 0; w < 8; w++) w: 7};
        for (var w = 0; w < 8; w++) {
          final result = WaveLabel.compute(
            totalWeeks: 8,
            currentWeekIndex: w,
            exerciseIdByWeek: exerciseIdByWeek,
          );
          expect(result, isNotNull, reason: 'week $w should resolve');
          expect(result!.waveIndex, 1, reason: 'week $w waveIndex');
          expect(result.waveCount, 1, reason: 'week $w waveCount');
          expect(result.waveStartWeek, 0, reason: 'week $w waveStartWeek');
          expect(result.waveEndWeek, 7, reason: 'week $w waveEndWeek');
        }
      },
    );

    test(
      'does not read past week 0 or the last week at a rotating block boundary',
      () {
        // A,A,A,B,B,B rotation over 6 weeks: week 0 is the first week of the
        // first wave; week 5 is the last week of the last wave.
        final exerciseIdByWeek = {0: 1, 1: 1, 2: 1, 3: 2, 4: 2, 5: 2};

        final first = WaveLabel.compute(
          totalWeeks: 6,
          currentWeekIndex: 0,
          exerciseIdByWeek: exerciseIdByWeek,
        );
        expect(first, isNotNull);
        expect(first!.waveIndex, 1);
        expect(first.waveCount, 2);
        expect(first.waveStartWeek, 0);
        expect(first.waveEndWeek, 2);

        final last = WaveLabel.compute(
          totalWeeks: 6,
          currentWeekIndex: 5,
          exerciseIdByWeek: exerciseIdByWeek,
        );
        expect(last, isNotNull);
        expect(last!.waveIndex, 2);
        expect(last.waveCount, 2);
        expect(last.waveStartWeek, 3);
        expect(last.waveEndWeek, 5);
      },
    );

    test('returns null when currentWeekIndex is negative', () {
      final result = WaveLabel.compute(
        totalWeeks: 4,
        currentWeekIndex: -1,
        exerciseIdByWeek: const {0: 1, 1: 1, 2: 2, 3: 2},
      );
      expect(result, isNull);
    });

    test('returns null when currentWeekIndex is >= totalWeeks', () {
      final result = WaveLabel.compute(
        totalWeeks: 4,
        currentWeekIndex: 4,
        exerciseIdByWeek: const {0: 1, 1: 1, 2: 2, 3: 2},
      );
      expect(result, isNull);
    });

    test(
      'returns null when the exercise-id map has no entry for currentWeekIndex',
      () {
        final result = WaveLabel.compute(
          totalWeeks: 4,
          currentWeekIndex: 2,
          exerciseIdByWeek: const {0: 1, 1: 1},
        );
        expect(result, isNull);
      },
    );
  });

  group('WaveLabel.selectAnchorSlot', () {
    ProgramDayData day({
      required int id,
      required String name,
      String? slotLabel,
      int orderIndex = 0,
    }) => ProgramDayData(
      id: id,
      programWeekId: 1,
      dayOfWeek: 1,
      name: name,
      orderIndex: orderIndex,
      slotLabel: slotLabel,
      isRest: false,
      stressRole: 'mixed',
    );

    ProgramExerciseSlotData slot({
      required int id,
      required String daySlotLabel,
      required int orderIndex,
      required String role,
    }) => ProgramExerciseSlotData(
      id: id,
      programId: 1,
      slotKey: 'slot-$id',
      daySlotLabel: daySlotLabel,
      orderIndex: orderIndex,
      role: role,
      trainingMethod: 'straight',
      fatigueBudget: 1,
      userLocked: false,
    );

    test(
      'returns the first main-role slot walking days in order then orderIndex within a day',
      () {
        final days = [
          day(id: 1, name: 'Squat Day'),
          day(id: 2, name: 'Bench Day'),
        ];
        final slots = [
          slot(
            id: 10,
            daySlotLabel: 'Squat Day',
            orderIndex: 0,
            role: 'accessory',
          ),
          slot(id: 11, daySlotLabel: 'Squat Day', orderIndex: 1, role: 'main'),
          slot(id: 12, daySlotLabel: 'Bench Day', orderIndex: 0, role: 'main'),
        ];

        final result = WaveLabel.selectAnchorSlot(
          daysInOrder: days,
          allSlots: slots,
        );

        expect(result, isNotNull);
        expect(result!.id, 11);
      },
    );

    test('returns null when no slot in the program has role main', () {
      final days = [day(id: 1, name: 'Accessory Day')];
      final slots = [
        slot(
          id: 10,
          daySlotLabel: 'Accessory Day',
          orderIndex: 0,
          role: 'accessory',
        ),
        slot(
          id: 11,
          daySlotLabel: 'Accessory Day',
          orderIndex: 1,
          role: 'isolation',
        ),
      ];

      final result = WaveLabel.selectAnchorSlot(
        daysInOrder: days,
        allSlots: slots,
      );

      expect(result, isNull);
    });

    test(
      'day order is the primary sort key: a main slot on a later day beats a '
      'non-main slot with a lower orderIndex on an earlier day',
      () {
        final days = [
          day(id: 1, name: 'Earlier Day'),
          day(id: 2, name: 'Later Day'),
        ];
        final slots = [
          slot(
            id: 10,
            daySlotLabel: 'Earlier Day',
            orderIndex: 0,
            role: 'accessory',
          ),
          slot(id: 11, daySlotLabel: 'Later Day', orderIndex: 0, role: 'main'),
        ];

        final result = WaveLabel.selectAnchorSlot(
          daysInOrder: days,
          allSlots: slots,
        );

        expect(result, isNotNull);
        expect(result!.id, 11);
      },
    );
  });
}
