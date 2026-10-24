import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/presentation/dialogs/full_screen_rpe_picker.dart';
import 'package:herculex/features/workouts/presentation/widgets/set_type_menu.dart';

void main() {
  group('SetType cheat and forced reps tests', () {
    test('SetType.cheat is registered properly with factors and metaKeys', () {
      final cheat = SetType.fromId('cheat');
      expect(cheat, equals(SetType.cheat));
      expect(cheat.id, equals('cheat'));
      expect(cheat.label, equals('Cheat Reps'));
      expect(cheat.volumeFactor, equals(0.85));
      expect(cheat.cnsFactor, equals(1.25));
      expect(cheat.metaKeys, contains('extraReps'));
      expect(cheat.metaKeys, contains('cheatReps'));
    });

    test('SetType.forced metaKeys contain extraReps and forcedReps', () {
      final forced = SetType.fromId('forced');
      expect(forced, equals(SetType.forced));
      expect(forced.metaKeys, contains('extraReps'));
      expect(forced.metaKeys, contains('forcedReps'));
    });

    test('SetTypeInfo and badge contains SetType.cheat', () {
      final cheatInfo = SetTypeInfo.all.firstWhere(
        (info) => info.type == SetType.cheat,
      );
      expect(cheatInfo.badge, equals('CR'));
      expect(cheatInfo.label, equals('Cheat Reps'));
      expect(SetTypeMenu.badge(SetType.cheat), equals('CR'));
      expect(SetTypeMenu.badge(SetType.forced), equals('F'));
    });

    test('normalizeWearSetType handles cheat and forced', () {
      expect(normalizeWearSetType('cheat'), equals('cheat'));
      expect(normalizeWearSetType('forced'), equals('forced'));
      expect(normalizeWearSetType('failure'), equals('forced'));
      expect(normalizeWearSetType('myo_reps'), equals('myo_reps'));
    });

    test('Extra reps JSON encoding and decoding for forced and cheat reps', () {
      final meta = <String, dynamic>{
        'extraReps': [2, 1],
      };
      final encoded = jsonEncode(meta);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final raw = decoded['extraReps'];
      final List<int> extraItems = raw is List ? raw.cast<int>() : [];
      expect(extraItems, equals([2, 1]));

      // Adding an extra rep chip
      extraItems.add(3);
      decoded['extraReps'] = extraItems;
      expect(decoded['extraReps'], equals([2, 1, 3]));

      // Removing a chip
      extraItems.removeAt(0);
      decoded['extraReps'] = extraItems;
      expect(decoded['extraReps'], equals([1, 3]));
    });
  });

  group('Superset Round-Robin Alternating Logic', () {
    test(
      'Calculates next exercise in cyclic order within the superset group',
      () {
        // Suppose group has exercise IDs [10, 20, 30] in order
        final groupExerciseIds = [10, 20, 30];

        // Starting at index 0 (Ex 10)
        var currentIdx = 0;
        var nextIdx = (currentIdx + 1) % groupExerciseIds.length;
        expect(groupExerciseIds[nextIdx], equals(20));

        // Starting at index 1 (Ex 20)
        currentIdx = 1;
        nextIdx = (currentIdx + 1) % groupExerciseIds.length;
        expect(groupExerciseIds[nextIdx], equals(30));

        // Starting at index 2 (Ex 30) -> should wrap around to Ex 10
        currentIdx = 2;
        nextIdx = (currentIdx + 1) % groupExerciseIds.length;
        expect(groupExerciseIds[nextIdx], equals(10));
      },
    );
  });

  group('Active exercise detection logic', () {
    test('Finds first exercise with incomplete sets', () {
      final exercises = [
        {'id': 1, 'name': 'Squat'},
        {'id': 2, 'name': 'Bench Press'},
        {'id': 3, 'name': 'Deadlift'},
      ];

      final setsByExercise = {
        1: [
          {'id': 101, 'isCompleted': true},
          {'id': 102, 'isCompleted': true},
        ],
        2: [
          {'id': 201, 'isCompleted': true},
          {'id': 202, 'isCompleted': false},
        ],
        3: [
          {'id': 301, 'isCompleted': false},
        ],
      };

      int targetIdx = -1;
      for (int i = 0; i < exercises.length; i++) {
        final sets = setsByExercise[exercises[i]['id']] ?? [];
        final hasIncomplete = sets.any((s) => s['isCompleted'] == false);
        if (hasIncomplete) {
          targetIdx = i;
          break;
        }
      }

      expect(targetIdx, equals(1)); // Exercise 2 (Bench Press) has pending set
    });

    test('If all exercises completed, targetIdx is -1', () {
      final exercises = [
        {'id': 1, 'name': 'Squat'},
        {'id': 2, 'name': 'Bench Press'},
      ];

      final setsByExercise = {
        1: [
          {'id': 101, 'isCompleted': true},
        ],
        2: [
          {'id': 201, 'isCompleted': true},
        ],
      };

      int targetIdx = -1;
      for (int i = 0; i < exercises.length; i++) {
        final sets = setsByExercise[exercises[i]['id']] ?? [];
        final hasIncomplete = sets.any((s) => s['isCompleted'] == false);
        if (hasIncomplete) {
          targetIdx = i;
          break;
        }
      }

      expect(targetIdx, equals(-1));
    });
  });

  group('Watch Crown Wheel step calculations', () {
    test('Continuous drag steps calculate properly with step multiplier', () {
      const pixelsPerStep = 13.0;
      const step = 0.5;
      var value = 80.0;

      // Drag up by 52 pixels -> 4 steps
      var dragAccumulator = 52.0;
      final steps = (dragAccumulator / pixelsPerStep).truncate();
      expect(steps, equals(4));

      value += steps * step;
      expect(value, equals(82.0));
    });

    test('Integer mode rounding for reps', () {
      const step = 1.0;
      var reps = 10.0;
      // Drag down by 2 steps
      reps += (-2) * step;
      final rounded = reps.roundToDouble();
      expect(rounded, equals(8.0));
      expect(rounded.toInt(), equals(8));
    });

    test('Flick discrete step changes exactly one rep at a time', () {
      const flickThreshold = 22.0;
      var reps = 5;

      // Flick up (+25px displacement)
      final deltaUp = 25.0;
      if (deltaUp >= flickThreshold) {
        reps += 1;
      }
      expect(reps, equals(6));

      // Flick down (-30px displacement)
      final deltaDown = -30.0;
      if (deltaDown <= -flickThreshold) {
        reps -= 1;
      }
      expect(reps, equals(5));
    });
  });

  group('Full-Screen RPE picker options tests', () {
    test('FullScreenRpePicker defines valid scale from 10.0 to 5.0 (<6)', () {
      final values = FullScreenRpePicker.options
          .map((o) => o.valueX10)
          .toList();
      expect(values, equals([100, 95, 90, 85, 80, 75, 70, 65, 60, 50]));
      expect(FullScreenRpePicker.options.first.label, equals('10'));
      expect(FullScreenRpePicker.options.first.rir, equals('0 RIR'));
      expect(FullScreenRpePicker.options.last.label, equals('<6'));
    });

    test('RPE scale provides clear RIR descriptions for all options', () {
      for (final option in FullScreenRpePicker.options) {
        expect(option.label, isNotEmpty);
        expect(option.rir, contains('RIR'));
        expect(option.description, isNotEmpty);
      }
    });
  });

  group('Full-Screen Rest Timer Countdown tests', () {
    test('Seconds formatting formats mm:ss correctly', () {
      String fmt(int totalSeconds) {
        if (totalSeconds < 0) totalSeconds = 0;
        final minutes = totalSeconds ~/ 60;
        final seconds = totalSeconds % 60;
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      }

      expect(fmt(120), equals('02:00'));
      expect(fmt(95), equals('01:35'));
      expect(fmt(9), equals('00:09'));
      expect(fmt(0), equals('00:00'));
      expect(fmt(-5), equals('00:00'));
    });

    test('Progress calculation remains clamped between 0.0 and 1.0', () {
      double calcProgress(int remaining, int target) {
        if (target <= 0) return 0.0;
        final raw = 1.0 - (remaining / target);
        return raw.clamp(0.0, 1.0);
      }

      expect(calcProgress(120, 120), equals(0.0));
      expect(calcProgress(60, 120), equals(0.5));
      expect(calcProgress(0, 120), equals(1.0));
      expect(calcProgress(150, 120), equals(0.0)); // Over target
      expect(calcProgress(-10, 120), equals(1.0)); // Past expiry
    });
  });
}
