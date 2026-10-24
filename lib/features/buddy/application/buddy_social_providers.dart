import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/buddy/data/buddy_social_repository.dart';
import 'package:herculex/features/buddy/domain/gym_buddy_social.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';

enum BenchmarkLiftType {
  bench('Bench Press', 'bench', 'kg', Icons.fitness_center_rounded),
  squat('Squat', 'squat', 'kg', Icons.directions_run_rounded),
  deadlift('Deadlift', 'deadlift', 'kg', Icons.sports_gymnastics_rounded),
  ohp('Overhead Press', 'ohp', 'kg', Icons.arrow_upward_rounded),
  pullup('Pull-ups', 'pullup', 'reps', Icons.accessibility_new_rounded);

  final String label;
  final String key;
  final String unit;
  final IconData icon;
  const BenchmarkLiftType(this.label, this.key, this.unit, this.icon);
}

final buddySocialRepositoryProvider = Provider<BuddySocialRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = BuddySocialRepository(prefs);
  ref.onDispose(repo.dispose);
  return repo;
});

final savedBuddiesProvider = StreamProvider<List<GymBuddyProfile>>((ref) {
  return ref.watch(buddySocialRepositoryProvider).watchBuddies();
});

final buddyPrFeedProvider = StreamProvider<List<BuddyPrActivity>>((ref) {
  return ref.watch(buddySocialRepositoryProvider).watchPrActivities();
});

final comparisonExercisesProvider = StreamProvider<List<ComparisonExercise>>((
  ref,
) {
  return ref.watch(buddySocialRepositoryProvider).watchComparisonExercises();
});

/// Constructs the current user's live [GymBuddyProfile] from live state.
final userGymBuddyProfileProvider = Provider<GymBuddyProfile>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final levelProgress = ref.watch(levelProgressProvider).valueOrNull;
  final goalTarget = ref.watch(goalTargetProvider);
  final strengthAssessment = ref.watch(strengthAssessmentProvider).valueOrNull;
  final allPrs = ref.watch(allOneRmsProvider).valueOrNull ?? const [];

  final currentWeight = profile?.weightKg ?? 80.0;
  final targetWeight = goalTarget.targetKg ?? profile?.targetWeightKg ?? 75.0;

  // Calculate goal progress:
  double progress = 0.75;
  if (profile?.weightKg != null && targetWeight > 0) {
    final diff = (currentWeight - targetWeight).abs();
    // Progress is closer to 1.0 when diff is smaller
    progress = (1.0 - (diff / 15.0)).clamp(0.2, 0.98);
  }

  // Extract lifts:
  final lifts = <String, double>{};

  double findPr(String query) {
    for (final pr in allPrs) {
      if (pr.exerciseName.toLowerCase().contains(query)) {
        return pr.estimatedOneRmKg;
      }
    }
    return 0.0;
  }

  double getBenchmarkLift(
    StrengthLift lift,
    String fallbackQuery,
    double defVal,
  ) {
    final best = strengthAssessment?.bests[lift]?.best;
    if (best != null && best > 0) {
      return lift.measure == StrengthMeasure.bodyweightRatio
          ? (best * currentWeight)
          : best;
    }
    final pr = findPr(fallbackQuery);
    if (pr > 0) return pr;
    return defVal;
  }

  lifts['bench'] = getBenchmarkLift(StrengthLift.bench, 'bench', 100.0);
  lifts['squat'] = getBenchmarkLift(StrengthLift.squat, 'squat', 140.0);
  lifts['deadlift'] = getBenchmarkLift(
    StrengthLift.deadlift,
    'deadlift',
    180.0,
  );
  lifts['ohp'] = getBenchmarkLift(StrengthLift.overheadPress, 'overhead', 65.0);
  lifts['pullup'] = getBenchmarkLift(StrengthLift.pullUp, 'pull-up', 15.0);

  final repo = ref.watch(buddySocialRepositoryProvider);

  // Add any user-specified custom lift values or auto-match from logged PRs
  final customUserLifts = repo.getUserCustomLifts();
  for (final entry in customUserLifts.entries) {
    lifts[entry.key] = entry.value;
  }
  final comparisonExercises = repo.getComparisonExercises();
  for (final ex in comparisonExercises) {
    if (!lifts.containsKey(ex.key)) {
      final pr = findPr(ex.label.toLowerCase());
      if (pr > 0) {
        lifts[ex.key] = pr;
      } else {
        lifts[ex.key] = ex.unit == 'reps' ? 12.0 : 70.0;
      }
    }
  }

  return GymBuddyProfile(
    id: 'current_user',
    name: profile?.name?.trim().isNotEmpty == true ? profile!.name! : 'You',
    avatarId: profile?.avatarId,
    levelTitle: levelProgress?.level.title ?? 'Spartan I',
    levelNumber: levelProgress?.level.number ?? 3,
    goalPhase: goalTarget.phase?.label ?? profile?.goal.label ?? 'Cutting',
    currentWeightKg: currentWeight,
    targetWeightKg: targetWeight,
    goalProgressPercent: progress,
    benchmarkLifts: lifts,
    lastWorkout: 'Today',
    isUser: true,
    inviteCode: repo.myInviteCode,
  );
});

/// All buddies including current user at index 0 for side-by-side comparison.
final allBuddiesWithUserProvider = Provider<List<GymBuddyProfile>>((ref) {
  final user = ref.watch(userGymBuddyProfileProvider);
  final saved = ref.watch(savedBuddiesProvider).valueOrNull ?? const [];
  return [user, ...saved];
});
