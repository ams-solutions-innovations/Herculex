import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/wave_label.dart';

void main() {
  group('WaveLabelInfo.label', () {
    test('matches 19-UI-SPEC.md copy example verbatim', () {
      const info = WaveLabelInfo(
        waveIndex: 2,
        waveCount: 4,
        waveStartWeek: 2,
        waveEndWeek: 3,
      );
      expect(info.label, 'Exercise wave 2 of 4 · Weeks 3–4');
    });
  });

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

  group('WaveSegments.compute', () {
    test('no rotation anywhere is one wave covering every week', () {
      final waves = WaveSegments.compute(
        totalWeeks: 6,
        exerciseIdByWeekBySlot: const {
          1: {0: 5, 1: 5, 2: 5, 3: 5, 4: 5, 5: 5},
          2: {0: 7, 1: 7, 2: 7, 3: 7, 4: 7, 5: 7},
        },
      );

      expect(waves, [const WaveSegment(index: 1, startWeek: 0, endWeek: 5)]);
      expect(waves.single.weeksLabel, 'Weeks 1–6');
    });

    test('a three-week rotation gives waves of three weeks', () {
      final waves = WaveSegments.compute(
        totalWeeks: 9,
        exerciseIdByWeekBySlot: const {
          1: {0: 1, 1: 1, 2: 1, 3: 2, 4: 2, 5: 2, 6: 3, 7: 3, 8: 3},
          // A fixed main lift must not add boundaries of its own.
          2: {0: 9, 1: 9, 2: 9, 3: 9, 4: 9, 5: 9, 6: 9, 7: 9, 8: 9},
        },
      );

      expect(waves.map((w) => (w.startWeek, w.endWeek)), [
        (0, 2),
        (3, 5),
        (6, 8),
      ]);
      expect(waves.map((w) => w.index), [1, 2, 3]);
      expect(waves[1].contains(4), isTrue);
      expect(waves[1].contains(6), isFalse);
    });

    test(
      'a wave ends when ANY slot rotates, so offset slots split further',
      () {
        final waves = WaveSegments.compute(
          totalWeeks: 6,
          exerciseIdByWeekBySlot: const {
            1: {0: 1, 1: 1, 2: 2, 3: 2, 4: 2, 5: 2},
            2: {0: 5, 1: 5, 2: 5, 3: 5, 4: 6, 5: 6},
          },
        );

        expect(waves.map((w) => (w.startWeek, w.endWeek)), [
          (0, 1),
          (2, 3),
          (4, 5),
        ]);
      },
    );

    test('weeks a slot has no entry for do not invent boundaries', () {
      final waves = WaveSegments.compute(
        totalWeeks: 4,
        exerciseIdByWeekBySlot: const {
          1: {0: 1, 3: 1},
        },
      );

      expect(waves, hasLength(1));
    });

    test('a single week reads "Week N" and no weeks gives no waves', () {
      expect(
        const WaveSegment(index: 2, startWeek: 3, endWeek: 3).weeksLabel,
        'Week 4',
      );
      expect(
        WaveSegments.compute(totalWeeks: 0, exerciseIdByWeekBySlot: const {}),
        isEmpty,
      );
    });
  });
}
