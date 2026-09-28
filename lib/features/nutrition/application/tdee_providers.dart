import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

// NOTE: this file must not import nutrition_providers.dart. That file imports
// this one for `baselineTargetsProvider`, so the reverse would be a cycle.

/// History repository for the adaptive maintenance estimate.
final tdeeEstimatesRepositoryProvider = Provider<TdeeEstimatesRepository>((
  ref,
) {
  return TdeeEstimatesRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  );
});

/// Newest persisted estimate, live. Deliberately not `autoDispose`: many
/// widgets read the baseline, and disposing would re-query on every rebuild.
final latestTdeeEstimateProvider = StreamProvider<TdeeEstimateResult?>((ref) {
  return ref.watch(tdeeEstimatesRepositoryProvider).watchLatest();
});

/// The estimate the app should use right now.
///
/// Null only when the profile lacks weight, height or age. On an empty table,
/// a loading stream, a stream error, or a stored cold-start row, this
/// synthesizes a cold-start estimate from the live profile seed (D-08: never
/// blank, never an error). A stored cold-start row's kcal is deliberately
/// ignored so a manual ActivityLevel reset (D-14) takes effect at once; an
/// observed or classifier row is returned as stored (D-15).
final tdeeEstimateProvider = Provider<TdeeEstimateResult?>((ref) {
  final profile = ref.watch(profileProvider).asData?.value;
  if (profile == null) return null;
  final seed = MacroTargets.seedMaintenanceKcal(profile);
  if (seed == null) return null;

  final stored = ref.watch(latestTdeeEstimateProvider).asData?.value;
  if (stored != null && stored.method != TdeeMethod.coldStart) return stored;

  return TdeeEstimateResult(
    kcal: seed.round(),
    method: TdeeMethod.coldStart,
    confidence: TdeeConfidence.low,
    windowDays: 0,
    observedQualified: false,
    inputs: {
      'onboarding_level': profile.activityLevel.label,
      'activity_factor': MacroTargets.multiplierFor(profile.activityLevel),
    },
    estimatedAt: ref.watch(clockProvider).now(),
  );
});

/// PURE maintenance calories (no goal delta). Maintenance-labelled UI reads
/// this; targets go through `baselineTargetsProvider`.
final maintenanceKcalProvider = Provider<int?>((ref) {
  return ref.watch(tdeeEstimateProvider)?.kcal;
});
