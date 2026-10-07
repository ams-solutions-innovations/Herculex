import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/analytics/application/muscle_volume_providers.dart';
import 'package:herculex/features/analytics/domain/muscle_volume_details.dart';
import 'package:herculex/features/analytics/presentation/views/muscle_volume_detail_view.dart';
import 'package:herculex/features/analytics/presentation/views/muscle_volume_overview_view.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyOverviewData = MuscleVolumeOverviewData(
    timeframe: VolumeTimeframe.thisWeek,
    startDate: DateTime(2026, 8, 17),
    endDate: DateTime(2026, 8, 22),
    totalTonnageKg: 12500,
    totalSets: 36,
    totalWorkouts: 4,
    totalExercises: 8,
    groups: [
      const MuscleGroupOverviewItem(
        muscle: 'Chest',
        region: MuscleRegion.upper,
        tonnageKg: 4500,
        sets: 12,
        rawSets: 12,
        exerciseCount: 3,
        workoutCount: 2,
        lastTrained: null,
        percentageOfMax: 1.0,
      ),
      const MuscleGroupOverviewItem(
        muscle: 'Quads',
        region: MuscleRegion.lower,
        tonnageKg: 3500,
        sets: 10,
        rawSets: 10,
        exerciseCount: 2,
        workoutCount: 1,
        lastTrained: null,
        percentageOfMax: 0.77,
      ),
      const MuscleGroupOverviewItem(
        muscle: 'Abs',
        region: MuscleRegion.core,
        tonnageKg: 0,
        sets: 0,
        rawSets: 0,
        exerciseCount: 0,
        workoutCount: 0,
        lastTrained: null,
        percentageOfMax: 0.0,
      ),
    ],
  );

  final dummyDetailData = MuscleGroupDetailData(
    muscle: 'Chest',
    region: MuscleRegion.upper,
    timeframe: VolumeTimeframe.thisWeek,
    startDate: DateTime(2026, 8, 17),
    endDate: DateTime(2026, 8, 22),
    totalTonnageKg: 4500,
    totalSets: 12,
    rawSetsCount: 12,
    totalReps: 96,
    workoutsCount: 2,
    distinctExercisesCount: 3,
    topExercise: 'Barbell Bench Press',
    workouts: [
      MuscleWorkoutSessionItem(
        sessionId: 42,
        sessionName: 'Chest & Triceps Hypertrophy',
        date: DateTime(2026, 8, 21, 15, 30),
        sessionRpe: 8,
        muscleTonnageKg: 2500,
        muscleSets: 6,
        rawSetsCount: 6,
        exercises: [
          const MuscleWorkoutExerciseItem(
            exerciseId: 101,
            exerciseName: 'Barbell Bench Press',
            role: 'primary',
            roleWeight: 1.0,
            equipmentVariant: 'barbell',
            exerciseTonnageKg: 2500,
            exerciseSetsCount: 2,
            sets: [
              MuscleSetItem(
                setId: 1,
                setIndex: 0,
                weightKg: 100,
                reps: 8,
                effectiveKg: 100,
                tonnageKg: 800,
                rpeX10: 80,
                setType: SetType.standard,
                completedAt: null,
                accessoryNames: [],
              ),
              MuscleSetItem(
                setId: 2,
                setIndex: 1,
                weightKg: 100,
                reps: 8,
                effectiveKg: 100,
                tonnageKg: 800,
                rpeX10: 85,
                setType: SetType.standard,
                completedAt: null,
                accessoryNames: [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  testWidgets(
    'MuscleVolumeOverviewView renders headline metrics and muscle items',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            muscleVolumeOverviewProvider.overrideWith(
              (ref) => dummyOverviewData,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const MuscleVolumeOverviewView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Volume Breakdown'), findsOneWidget);
      expect(find.text('TOTAL VOLUME'), findsOneWidget);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('Quads'), findsOneWidget);
      expect(find.text('Abs'), findsOneWidget);
    },
  );

  testWidgets('MuscleVolumeDetailView renders muscle stats and exercise logs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          muscleVolumeDetailProvider(
            'Chest',
          ).overrideWith((ref) => dummyDetailData),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const MuscleVolumeDetailView(muscle: 'Chest'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Chest Volume'), findsOneWidget);
    expect(find.text('Chest & Triceps Hypertrophy • 15:30'), findsOneWidget);
    expect(
      find.text('Barbell Bench Press'),
      findsNWidgets(2),
    ); // Most frequent tag + exercise item
    expect(find.text('Primary (100%)'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });
}
