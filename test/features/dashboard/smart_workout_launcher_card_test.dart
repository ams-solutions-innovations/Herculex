import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/smart_workout_launcher_card.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestClock implements Clock {
  final DateTime _time;
  _TestClock(this._time);
  @override
  DateTime now() => _time;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  final todayDate = DateTime(2026, 10, 25, 12, 0); // Sunday

  TodaysScheduledWorkout createMockWorkout({
    required String title,
    required String dateIso,
    int exerciseCount = 6,
    String status = ScheduleStatus.planned,
  }) {
    final schedule = ScheduledWorkoutData(
      id: 101,
      programDayId: 1,
      dateIso: dateIso,
      status: status,
      orderIndex: 0,
      occurrenceIndex: 0,
      updatedAt: DateTime(2026, 10, 20),
    );
    final programDay = ProgramDayData(
      id: 1,
      programWeekId: 1,
      dayOfWeek: 2,
      name: title,
      isRest: false,
      stressRole: 'mixed',
      orderIndex: 0,
      updatedAt: DateTime(2026, 10, 20),
    );
    return TodaysScheduledWorkout(
      schedule: schedule,
      programDay: programDay,
      exerciseCount: exerciseCount,
    );
  }

  testWidgets('displays Today\'s Plan and Today badge when workout is today', (tester) async {
    final workout = createMockWorkout(
      title: 'Upper',
      dateIso: '2026-10-25',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(_TestClock(todayDate)),
          nextScheduledWorkoutProvider.overrideWith((ref) => Stream.value(workout)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SmartWorkoutLauncherCard(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Today's Plan"), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Upper'), findsOneWidget);
    expect(find.text('6 exercises planned'), findsOneWidget);
    expect(find.text('Start Upper?'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('displays Next Workout and Tuesday badge when workout is planned on Tuesday', (tester) async {
    final workout = createMockWorkout(
      title: 'Upper',
      dateIso: '2026-10-27', // Tuesday
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(_TestClock(todayDate)),
          nextScheduledWorkoutProvider.overrideWith((ref) => Stream.value(workout)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SmartWorkoutLauncherCard(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next Workout'), findsOneWidget);
    expect(find.text('Tuesday, Oct 27'), findsOneWidget);
    expect(find.text('Upper'), findsOneWidget);
    expect(find.text('6 exercises planned'), findsOneWidget);
    expect(find.text('Start Upper?'), findsOneWidget);
  });

  testWidgets('displays Next Workout with No upcoming workouts scheduled when null', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(_TestClock(todayDate)),
          nextScheduledWorkoutProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SmartWorkoutLauncherCard(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next Workout'), findsOneWidget);
    expect(find.text('No upcoming workouts scheduled.'), findsOneWidget);
  });
}
