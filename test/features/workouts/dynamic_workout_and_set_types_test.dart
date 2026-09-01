import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
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
  });
}
