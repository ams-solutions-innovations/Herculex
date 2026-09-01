import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/presentation/equipment_icon.dart';
import 'package:herculex/features/workouts/presentation/exercise_artwork.dart';

void main() {
  group('EquipmentType.resolve', () {
    test('resolves core free weights and bars', () {
      expect(EquipmentType.resolve('Barbell'), EquipmentType.barbell);
      expect(EquipmentType.resolve('barbell'), EquipmentType.barbell);
      expect(EquipmentType.resolve('bb'), EquipmentType.barbell);
      expect(EquipmentType.resolve('Dumbbell'), EquipmentType.dumbbell);
      expect(EquipmentType.resolve('dumbbell'), EquipmentType.dumbbell);
      expect(EquipmentType.resolve('db'), EquipmentType.dumbbell);
      expect(EquipmentType.resolve('Kettlebell'), EquipmentType.kettlebell);
      expect(EquipmentType.resolve('kettlebell'), EquipmentType.kettlebell);
      expect(EquipmentType.resolve('kb'), EquipmentType.kettlebell);
      expect(EquipmentType.resolve('Swiss Bar'), EquipmentType.swissBar);
      expect(EquipmentType.resolve('swiss_bar'), EquipmentType.swissBar);
      expect(EquipmentType.resolve('Football Bar'), EquipmentType.swissBar);
      expect(EquipmentType.resolve('EZ Bar'), EquipmentType.ezBar);
      expect(EquipmentType.resolve('ez_bar'), EquipmentType.ezBar);
      expect(EquipmentType.resolve('Trap Bar'), EquipmentType.trapBar);
      expect(EquipmentType.resolve('Hex Bar'), EquipmentType.trapBar);
      expect(EquipmentType.resolve('Safety Bar'), EquipmentType.safetyBar);
      expect(
        EquipmentType.resolve('Safety Squat Bar'),
        EquipmentType.safetyBar,
      );
      expect(EquipmentType.resolve('SSB'), EquipmentType.safetyBar);
      expect(EquipmentType.resolve('Axle Bar'), EquipmentType.axleBar);
      expect(EquipmentType.resolve('Cambered Bar'), EquipmentType.camberedBar);
      expect(EquipmentType.resolve('Duffalo Bar'), EquipmentType.camberedBar);
    });

    test('resolves machines and cables', () {
      expect(EquipmentType.resolve('Smith Machine'), EquipmentType.smith);
      expect(EquipmentType.resolve('smith'), EquipmentType.smith);
      expect(EquipmentType.resolve('Cable'), EquipmentType.cable);
      expect(EquipmentType.resolve('cable'), EquipmentType.cable);
      expect(
        EquipmentType.resolve('Machine (Plate-Loaded)'),
        EquipmentType.machinePlate,
      );
      expect(
        EquipmentType.resolve('machine_plate'),
        EquipmentType.machinePlate,
      );
      expect(
        EquipmentType.resolve('Machine (Selectorized)'),
        EquipmentType.machineSelectorized,
      );
      expect(
        EquipmentType.resolve('machine_selectorized'),
        EquipmentType.machineSelectorized,
      );
      expect(
        EquipmentType.resolve('Machine'),
        EquipmentType.machineSelectorized,
      );
    });

    test('resolves bodyweight and accessories', () {
      expect(EquipmentType.resolve('Bodyweight'), EquipmentType.bodyweight);
      expect(EquipmentType.resolve('bodyweight'), EquipmentType.bodyweight);
      expect(EquipmentType.resolve('Weighted'), EquipmentType.weighted);
      expect(EquipmentType.resolve('weighted'), EquipmentType.weighted);
      expect(EquipmentType.resolve('Band'), EquipmentType.band);
      expect(EquipmentType.resolve('Band/Assist'), EquipmentType.band);
      expect(EquipmentType.resolve('band'), EquipmentType.band);
      expect(EquipmentType.resolve('Rings'), EquipmentType.rings);
      expect(EquipmentType.resolve('TRX'), EquipmentType.trx);
      expect(EquipmentType.resolve('Landmine'), EquipmentType.landmine);
      expect(EquipmentType.resolve('Plate'), EquipmentType.plate);
      expect(
        EquipmentType.resolve('Medicine Ball'),
        EquipmentType.medicineBall,
      );
      expect(EquipmentType.resolve('Sandbag'), EquipmentType.sandbag);
      expect(EquipmentType.resolve('Sled/Yoke'), EquipmentType.sled);
      expect(EquipmentType.resolve('Battle Ropes'), EquipmentType.battleRopes);
      expect(
        EquipmentType.resolve('Climbing Rope'),
        EquipmentType.climbingRope,
      );
      expect(EquipmentType.resolve('Jump Rope'), EquipmentType.jumpRope);
      expect(EquipmentType.resolve('Neck Harness'), EquipmentType.neckHarness);
    });

    test('resolves cardio machines', () {
      expect(EquipmentType.resolve('Treadmill'), EquipmentType.treadmill);
      expect(EquipmentType.resolve('Rower'), EquipmentType.rower);
      expect(EquipmentType.resolve('Air Bike'), EquipmentType.airBike);
      expect(
        EquipmentType.resolve('Stationary Bike'),
        EquipmentType.stationaryBike,
      );
      expect(EquipmentType.resolve('Ski Erg'), EquipmentType.skiErg);
      expect(EquipmentType.resolve('Elliptical'), EquipmentType.elliptical);
      expect(
        EquipmentType.resolve('Stair Climber'),
        EquipmentType.stairClimber,
      );
    });

    test('handles all catalog equipments without throwing', () {
      final raw = File('assets/data/exercises.json').readAsStringSync();
      final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final r in rows) {
        final eq = r['equipment'] as String?;
        final mod = r['modality'] as String?;
        final resolvedEq = EquipmentType.resolve(eq);
        final resolvedMod = EquipmentType.resolve(mod);
        expect(resolvedEq, isNotNull);
        expect(resolvedMod, isNotNull);
      }
    });
  });

  group('EquipmentGlyph & ExerciseArtwork widgets', () {
    testWidgets('EquipmentGlyph renders all equipment types without error', (
      tester,
    ) async {
      for (final type in EquipmentType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EquipmentGlyph(
                variant: type.name,
                size: 32,
                color: Colors.amber,
              ),
            ),
          ),
        );
        expect(find.byType(EquipmentGlyph), findsOneWidget);
      }
    });

    testWidgets('ExerciseArtwork renders fallback equipment glyph', (
      tester,
    ) async {
      const fakeExercise = ExerciseCatalogData(
        id: 9999,
        name: 'Swiss Bar Floor Press',
        primaryMuscle: 'Chest',
        equipment: 'Swiss Bar',
        mechanics: 'Compound',
        force: 'Push',
        plane: 'Sagittal',
        defaultRestSeconds: 90,
        category: 'strength',
        modality: 'barbell',
        cnsScore: 3,
        recoveryImpact: 3,
        loggingMetric: 'weight_reps',
        supportsWeightedBodyweight: false,
        isCustom: false,
        isReviewed: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseArtwork(exercise: fakeExercise, size: 48, radius: 12),
          ),
        ),
      );

      expect(find.byType(ExerciseArtwork), findsOneWidget);
      expect(find.byType(EquipmentGlyph), findsOneWidget);
    });
  });
}
