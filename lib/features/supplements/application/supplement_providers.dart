import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/app/providers.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_habit_stats.dart';
import 'package:herculex/features/supplements/domain/supplement_intake.dart';

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

  const SupplementDayState({required this.supplements, required this.takenIds});

  int get takenCount =>
      supplements.where((s) => takenIds.contains(s.id)).length;

  int get totalCount => supplements.length;

  double get progress => totalCount == 0 ? 0.0 : takenCount / totalCount;

  bool isTaken(String id) => takenIds.contains(id);
}

final supplementDayStateProvider = Provider<AsyncValue<SupplementDayState>>((
  ref,
) {
  final supplements = ref.watch(supplementsProvider);
  final taken = ref.watch(takenTodayProvider);

  return supplements.whenData(
    (supps) => SupplementDayState(
      supplements: supps,
      takenIds: taken.valueOrNull ?? {},
    ),
  );
});

// ── Selected date & Habit Tracking analytics ──────────────────────────────────

/// Selected date on the Supplements page (defaults to today). Allows inspecting
/// or toggling missed doses on past days via the 7-day strip or heatmap.
final supplementSelectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Selected timeframe (in days: 7, 30, or 90) for the habit consistency charts.
final supplementHabitRangeDaysProvider = StateProvider<int>((ref) => 30);

/// State for the currently selected date on `SupplementsView`.
final supplementSelectedDayStateProvider =
    Provider<AsyncValue<SupplementDayState>>((ref) {
      final supplements = ref.watch(supplementsProvider);
      // Watch takenTodayProvider so any markTaken / markTakenForDate broadcast
      // triggers an immediate recompute.
      ref.watch(takenTodayProvider);
      final selectedDate = ref.watch(supplementSelectedDateProvider);
      final repo = ref.watch(supplementRepositoryProvider);

      return supplements.whenData(
        (supps) => SupplementDayState(
          supplements: supps,
          takenIds: repo.loadTakenForDate(selectedDate),
        ),
      );
    });

/// The Monday–Sunday week containing the selected date, one point per day, for
/// the strip at the top of the page. Unlike the 28-day heatmap this follows the
/// selection, so it keeps working when the user scrolls back months.
final supplementWeekPointsProvider = Provider<List<SupplementDayPoint>>((ref) {
  final supplements = ref.watch(supplementsProvider).valueOrNull ?? const [];
  // Recompute whenever any taken set changes.
  ref.watch(takenTodayProvider);
  final selected = ref.watch(supplementSelectedDateProvider);
  final repo = ref.watch(supplementRepositoryProvider);

  final ids = {for (final s in supplements) s.id};
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = DateTime(
          selected.year,
          selected.month,
          selected.day - (selected.weekday - 1) + i,
        );
        final taken = repo.loadTakenForDate(d);
        return SupplementDayPoint(
          date: d,
          dateIso: SupplementHabitStats.isoForDate(d),
          takenIds: taken,
          takenCount: taken.intersection(ids).length,
          totalCount: ids.length,
        );
      }(),
  ];
});

/// Computed habit-tracking statistics (streaks, consistency %, daily chart
/// points, 28-day heatmap, and per-supplement adherence).
final supplementHabitStatsProvider = Provider<SupplementHabitStats>((ref) {
  final supplements = ref.watch(supplementsProvider).valueOrNull ?? const [];
  // Recompute whenever taken state changes.
  ref.watch(takenTodayProvider);
  final rangeDays = ref.watch(supplementHabitRangeDaysProvider);
  final repo = ref.watch(supplementRepositoryProvider);

  final historyDays = rangeDays > 90 ? rangeDays : 90;
  final history = repo.loadHistory(days: historyDays);
  final earliest = repo.findEarliestTrackedDate();

  return SupplementHabitStats.compute(
    supplements: supplements,
    historyByIso: history,
    rangeDays: rangeDays,
    earliestTrackedDate: earliest,
  );
});

// ── Micronutrients contributed by today's supplements (§4) ────────────────────

/// What today's ticked supplements add to the diary's micronutrient totals.
/// Past days remain available for up to 365 days.
final supplementIntakeTodayProvider = Provider<SupplementIntake>((ref) {
  final state = ref.watch(supplementDayStateProvider).asData?.value;
  if (state == null) return SupplementIntake.empty;
  return SupplementIntake.forDay(
    supplements: state.supplements,
    takenIds: state.takenIds,
  );
});
