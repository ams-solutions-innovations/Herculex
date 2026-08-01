import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/supplement_repository.dart';
import '../domain/supplement.dart';
import '../domain/supplement_intake.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final supplementRepositoryProvider = Provider<SupplementRepository>((ref) {
  final repo = SupplementRepository(ref.watch(sharedPreferencesProvider));
  ref.onDispose(repo.dispose);
  repo.clearOldDays();
  return repo;
});

// ── Supplement list ───────────────────────────────────────────────────────────

final supplementsProvider = StreamProvider<List<Supplement>>((ref) {
  return ref.watch(supplementRepositoryProvider).watchSupplements();
});

// ── Today's taken set ─────────────────────────────────────────────────────────

final takenTodayProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(supplementRepositoryProvider).watchTakenToday();
});

// ── Combined state for the widget ─────────────────────────────────────────────

class SupplementDayState {
  final List<Supplement> supplements;
  final Set<String> takenIds;

  const SupplementDayState({
    required this.supplements,
    required this.takenIds,
  });

  int get takenCount =>
      supplements.where((s) => takenIds.contains(s.id)).length;

  int get totalCount => supplements.length;

  double get progress =>
      totalCount == 0 ? 0.0 : takenCount / totalCount;

  bool isTaken(String id) => takenIds.contains(id);
}

final supplementDayStateProvider =
    Provider<AsyncValue<SupplementDayState>>((ref) {
  final supplements = ref.watch(supplementsProvider);
  final taken = ref.watch(takenTodayProvider);

  return supplements.whenData(
    (supps) => SupplementDayState(
      supplements: supps,
      takenIds: taken.valueOrNull ?? {},
    ),
  );
});

// ── Micronutrients contributed by today's supplements (§4) ────────────────────

/// What today's ticked supplements add to the diary's micronutrient totals.
/// Only today is available because the taken-set is stored per day and pruned
/// after a week; past days fall back to food-only totals.
final supplementIntakeTodayProvider = Provider<SupplementIntake>((ref) {
  final state = ref.watch(supplementDayStateProvider).asData?.value;
  if (state == null) return SupplementIntake.empty;
  return SupplementIntake.forDay(
    supplements: state.supplements,
    takenIds: state.takenIds,
  );
});
