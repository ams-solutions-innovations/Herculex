import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:intl/intl.dart';

/// Which minimum floors a logged entry just carried the day's intake over.
class MinimumCrossings {
  const MinimumCrossings({this.calories = false, this.protein = false});

  final bool calories;
  final bool protein;

  bool get any => calories || protein;
}

/// Pure crossing detection: a floor is crossed when intake was below it
/// before ([previous]) and is at or above it now ([next]). A floor that is
/// null (off, unset, or unresolvable) or already announced today
/// ([alreadyCalories] / [alreadyProtein]) never fires.
MinimumCrossings detectMinimumCrossings({
  required DailyTotals previous,
  required DailyTotals next,
  required int? minKcal,
  required int? minProteinG,
  bool alreadyCalories = false,
  bool alreadyProtein = false,
}) {
  bool crossed(double before, double after, int? floor, bool already) =>
      floor != null &&
      floor > 0 &&
      !already &&
      before < floor &&
      after >= floor;

  return MinimumCrossings(
    calories: crossed(previous.kcal, next.kcal, minKcal, alreadyCalories),
    protein: crossed(
      previous.proteinG,
      next.proteinG,
      minProteinG,
      alreadyProtein,
    ),
  );
}

String _kcalFlagKey(String iso) => 'min_kcal_notified_$iso';
String _proteinFlagKey(String iso) => 'min_protein_notified_$iso';

/// Drops the top pill once per day when today's intake first reaches the
/// minimum calories / protein floors from the Minimum targets tile.
///
/// Every logging path ends in [dailyTotalsProvider], so one listener covers
/// them all. The first emission and any loading state are ignored, so a cold
/// start with the floor already met stays quiet.
final minimumReachedControllerProvider = Provider<void>((ref) {
  final clock = ref.watch(clockProvider);
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  final iso = DateFormat('yyyy-MM-dd').format(today);

  ref.listen<AsyncValue<DailyTotals>>(dailyTotalsProvider(today), (
    previous,
    next,
  ) {
    // Day rolled over while the app stayed open: rebuild for the new day.
    final current = clock.now();
    if (DateTime(current.year, current.month, current.day) != today) {
      ref.invalidateSelf();
      return;
    }

    final before = previous?.valueOrNull;
    final after = next.valueOrNull;
    if (before == null || after == null) return;

    final minTargets = ref.read(minimumTargetsProvider);
    if (!minTargets.enabled) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final weightKg = ref.read(profileProvider).valueOrNull?.weightKg;
    final crossings = detectMinimumCrossings(
      previous: before,
      next: after,
      minKcal: minTargets.effectiveMinCaloriesKcal,
      minProteinG: minTargets.resolvedMinProteinG(weightKg),
      alreadyCalories: prefs.getBool(_kcalFlagKey(iso)) ?? false,
      alreadyProtein: prefs.getBool(_proteinFlagKey(iso)) ?? false,
    );
    if (!crossings.any) return;

    final notifier = ref.read(inAppNotificationControllerProvider.notifier);
    if (crossings.calories) {
      prefs.setBool(_kcalFlagKey(iso), true);
      notifier.show(
        InAppNotificationItem.minimumReached(
          isProtein: false,
          current: after.kcal,
          minimum: minTargets.effectiveMinCaloriesKcal!,
        ),
      );
    }
    if (crossings.protein) {
      prefs.setBool(_proteinFlagKey(iso), true);
      notifier.show(
        InAppNotificationItem.minimumReached(
          isProtein: true,
          current: after.proteinG,
          minimum: minTargets.resolvedMinProteinG(weightKg)!,
        ),
      );
    }
  });
});
