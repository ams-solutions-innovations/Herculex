import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/buddy/data/buddy_social_repository.dart';
import 'package:herculex/features/buddy/domain/gym_buddy_social.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BuddySocialRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initializes with seed buddies and PR feed when empty', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = BuddySocialRepository(prefs);

      final buddies = repo.getBuddies();
      expect(buddies, isNotEmpty);
      expect(buddies.length, greaterThanOrEqualTo(3));
      expect(buddies.any((b) => b.name == 'Luka Novak'), isTrue);

      final prs = repo.getPrActivities();
      expect(prs, isNotEmpty);
      expect(prs.any((p) => p.exerciseName.contains('Deadlift')), isTrue);
    });

    test('addBuddy adds a new buddy profile', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = BuddySocialRepository(prefs);

      const newBuddy = GymBuddyProfile(
        id: 'buddy_custom',
        name: 'Test Buddy',
        levelTitle: 'Novice I',
        levelNumber: 1,
        goalPhase: 'Maintenance',
        goalProgressPercent: 0.5,
        benchmarkLifts: {'bench': 80.0, 'squat': 100.0, 'deadlift': 120.0},
        lastWorkout: 'Yesterday',
      );

      await repo.addBuddy(newBuddy);
      final buddies = repo.getBuddies();
      expect(buddies.any((b) => b.id == 'buddy_custom'), isTrue);
    });

    test('removeBuddy removes a buddy profile', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = BuddySocialRepository(prefs);

      await repo.removeBuddy('buddy_luka');
      final buddies = repo.getBuddies();
      expect(buddies.any((b) => b.id == 'buddy_luka'), isFalse);
    });

    test('addPrActivity and toggleReaction works', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = BuddySocialRepository(prefs);

      final act = BuddyPrActivity(
        id: 'pr_custom',
        buddyId: 'user_1',
        buddyName: 'Test User',
        exerciseName: 'Incline Dumbbell Press',
        weightKg: 40.0,
        achievedAt: DateTime.now(),
        reactions: {'🔥': 1},
      );

      await repo.addPrActivity(act);
      final prs = repo.getPrActivities();
      expect(prs.first.id, 'pr_custom');

      await repo.toggleReaction('pr_custom', '🔥');
      final updatedPrs = repo.getPrActivities();
      expect(updatedPrs.first.reactions['🔥'], 2);
    });

    test('addComparisonExercise and removeComparisonExercise work', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = BuddySocialRepository(prefs);

      final initialExercises = repo.getComparisonExercises();
      expect(initialExercises.length, 5); // default items

      const newEx = ComparisonExercise(
        key: 'incline_bench',
        label: 'Incline Bench Press',
        unit: 'kg',
        isCustom: true,
      );

      await repo.addComparisonExercise(newEx, userValue: 60.0);
      final exercisesAfterAdd = repo.getComparisonExercises();
      expect(exercisesAfterAdd.length, 6);
      expect(exercisesAfterAdd.any((e) => e.key == 'incline_bench'), isTrue);

      final userLifts = repo.getUserCustomLifts();
      expect(userLifts['incline_bench'], 60.0);

      // Verify buddies got estimated/scaled values for the new exercise
      final buddies = repo.getBuddies();
      expect(
        buddies.every((b) => b.benchmarkLifts.containsKey('incline_bench')),
        isTrue,
      );

      await repo.removeComparisonExercise('incline_bench');
      final exercisesAfterRemove = repo.getComparisonExercises();
      expect(exercisesAfterRemove.length, 5);
      expect(
        exercisesAfterRemove.any((e) => e.key == 'incline_bench'),
        isFalse,
      );
    });
  });
}
