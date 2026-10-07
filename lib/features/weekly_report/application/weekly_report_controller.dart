import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/nutrition/domain/meal.dart' show dateIso;
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_narrative_service.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_service.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/narrative_status.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: imported only by the weekly report views and tests. The persisted
// "dismissed empty week" marker lives under the SharedPreferences key
// `weekly_report_dismissed_week` (see weeklyReportDismissedWeekKey).

/// How [WeeklyReportController.open] ended.
sealed class WeeklyReportOpenResult {
  const WeeklyReportOpenResult();
}

/// The report row exists and can be shown. The narrative, if one is due, is
/// running in the background; the screen watches [narrativeUiStateProvider].
final class WeeklyReportReady extends WeeklyReportOpenResult {
  const WeeklyReportReady(this.record);

  final WeeklyReportRecord record;
}

/// Nothing was logged in the week, or the week is in the future (D-06). No row
/// was created.
final class WeeklyReportNoData extends WeeklyReportOpenResult {
  const WeeklyReportNoData();
}

/// The running week is not due yet (before Sunday at the configured report
/// time), so no snapshot was taken: no row, no narrative, no dismissed marker
/// (RPT-04, WR-07).
final class WeeklyReportInProgress extends WeeklyReportOpenResult {
  const WeeklyReportInProgress();
}

/// The opt-in is off and the week has no stored report (D-07).
final class WeeklyReportDisabled extends WeeklyReportOpenResult {
  const WeeklyReportDisabled();
}

/// Reading or generating the report threw. The UI shows its error state.
final class WeeklyReportFailed extends WeeklyReportOpenResult {
  const WeeklyReportFailed();
}

/// What the narrative card needs to know that is not in the database: whether
/// a call is running right now and how the last one failed. Lives in memory
/// only, so a restart shows "pending" with Retry rather than a stale error.
class NarrativeUiState {
  const NarrativeUiState({
    this.inFlight = false,
    this.failure,
    this.quotaDayIso,
  });

  final bool inFlight;
  final NarrativeFailureKind? failure;

  /// Calendar day (`yyyy-MM-dd`, from the injected Clock) on which the quota
  /// failure happened.
  final String? quotaDayIso;

  @override
  bool operator ==(Object other) =>
      other is NarrativeUiState &&
      other.inFlight == inFlight &&
      other.failure == failure &&
      other.quotaDayIso == quotaDayIso;

  @override
  int get hashCode => Object.hash(inFlight, failure, quotaDayIso);
}

/// Per-week narrative UI state. Deliberately not `autoDispose`: leaving the
/// screen mid-call must not lose the in-flight flag.
final narrativeUiStateProvider =
    StateProvider.family<NarrativeUiState, IsoWeek>(
      (ref, week) => const NarrativeUiState(),
    );

/// What the narrative card renders.
class NarrativeCardModel {
  const NarrativeCardModel({
    required this.status,
    this.narrative,
    this.retryEnabled = false,
  });

  final NarrativeStatus status;

  /// Set only for [NarrativeStatus.ready].
  final WeeklyNarrative? narrative;
  final bool retryEnabled;
}

/// Pure mapping from stored row plus transient UI state to the narrative card.
/// Returns null when the card must not be shown at all ("skipped", D-06).
///
/// * A saved narrative is decoded without re-running the wording guard.
/// * `loading` comes only from [NarrativeUiState.inFlight], never from
///   `narrativeAttempts == 0`: a call that was never started (opt-in off) or
///   was cut short by a killed app shows "pending" with Retry, not a skeleton.
/// * Quota exhaustion blocks Retry for the rest of the same calendar day of
///   [now] only. From the next day it reads as plain pending with Retry on.
NarrativeCardModel? narrativeStatusFor({
  required WeeklyReportRecord record,
  required WeeklyReportPayload? payload,
  required NarrativeUiState ui,
  required DateTime now,
}) {
  if (record.narrativeJson != null) {
    final narrative = WeeklyNarrative.tryDecodeStored(record.narrativeJson);
    if (narrative != null) {
      return NarrativeCardModel(
        status: NarrativeStatus.ready,
        narrative: narrative,
      );
    }
    // Stored but unreadable: the backend is never called again for this row,
    // so offering Retry would be a dead button.
    return const NarrativeCardModel(status: NarrativeStatus.pending);
  }
  if (payload == null || !payload.hasNarrativeSignal) return null;

  if (ui.inFlight) {
    return const NarrativeCardModel(status: NarrativeStatus.loading);
  }

  switch (ui.failure) {
    case NarrativeFailureKind.offline:
      return const NarrativeCardModel(
        status: NarrativeStatus.offline,
        retryEnabled: true,
      );
    case NarrativeFailureKind.quotaExhausted:
      if (ui.quotaDayIso == dateIso(now)) {
        return const NarrativeCardModel(status: NarrativeStatus.quotaExhausted);
      }
      return const NarrativeCardModel(
        status: NarrativeStatus.pending,
        retryEnabled: true,
      );
    case NarrativeFailureKind.unconfigured:
    case NarrativeFailureKind.rejected:
    case NarrativeFailureKind.unavailable:
    case null:
      return const NarrativeCardModel(
        status: NarrativeStatus.pending,
        retryEnabled: true,
      );
  }
}

/// Opens weekly reports ("generated on open", RPT-03) with exactly-once
/// narrative semantics.
///
/// * Concurrent [open] calls for one week share a future, and concurrent
///   narrative calls for one week share a future, so a rebuild, a double tap or
///   a notification race costs at most one quota unit (D-03).
/// * The snapshot row is persisted before the narrative starts, and [open]
///   returns without waiting for it (D-02).
/// * The narrative fires automatically only on a week's first open (no saved
///   narrative, zero attempts, narrative signal). After any failure only an
///   explicit [retryNarrative] fires again (D-02, RPT-04).
/// * With the opt-in off nothing is generated (D-07).
/// * The running week is not snapshotted before it is due: [open] returns
///   [WeeklyReportInProgress] and writes nothing (RPT-04, WR-07).
/// * Fail-soft, like the TDEE recalibrator: errors become state, never throw.
///
/// Time comes only from the injected [Clock].
class WeeklyReportController {
  WeeklyReportController({
    required WeeklyReportService service,
    required WeeklyReportRepository repository,
    required Clock clock,
    required SharedPreferences prefs,
    required bool Function() isEnabled,
    required void Function(IsoWeek week, NarrativeUiState state) writeUiState,
    required void Function(String weekKey) onDismissedWeek,
  }) : _service = service,
       _repository = repository,
       _clock = clock,
       _prefs = prefs,
       _isEnabled = isEnabled,
       _writeUi = writeUiState,
       _onDismissedWeek = onDismissedWeek;

  final WeeklyReportService _service;
  final WeeklyReportRepository _repository;
  final Clock _clock;
  final SharedPreferences _prefs;
  final bool Function() _isEnabled;
  final void Function(IsoWeek, NarrativeUiState) _writeUi;
  final void Function(String) _onDismissedWeek;

  final Map<IsoWeek, Future<WeeklyReportOpenResult>> _opening = {};
  final Map<IsoWeek, Future<NarrativeOutcome>> _narrating = {};

  /// The running narrative call for [week], or null when none is in flight.
  Future<NarrativeOutcome>? narrationInFlight(IsoWeek week) => _narrating[week];

  /// Gets or creates the report for [week] and starts its first narrative.
  Future<WeeklyReportOpenResult> open(IsoWeek week) {
    final running = _opening[week];
    if (running != null) return running;
    // Block body on purpose: `remove` returns the very future being completed,
    // and an arrow would make whenComplete wait on itself.
    final future = _open(week).whenComplete(() {
      _opening.remove(week);
    });
    _opening[week] = future;
    return future;
  }

  Future<WeeklyReportOpenResult> _open(IsoWeek week) async {
    try {
      if (!_isEnabled()) {
        final existing = await _repository.forWeek(week);
        if (existing == null) return const WeeklyReportDisabled();
        return WeeklyReportReady(await _viewed(week, existing));
      }

      // The running week is frozen only once it is due (RPT-04). Before that,
      // an existing row is still shown, but nothing is created and the week is
      // not marked as dismissed.
      if (week == IsoWeek.fromDate(_clock.now()) &&
          !_service.canSnapshot(week)) {
        final existing = await _repository.forWeek(week);
        if (existing == null) return const WeeklyReportInProgress();
      }

      final generated = await _service.generate(week);
      if (generated == null) {
        await _dismissEmptyWeek(week);
        return const WeeklyReportNoData();
      }

      final record = await _viewed(week, generated);
      if (record.narrativeJson == null && record.narrativeAttempts == 0) {
        final payload = WeeklyReportPayload.tryDecode(record.payloadJson);
        if (payload != null && payload.hasNarrativeSignal) {
          // Deliberately not awaited: the screen must not block on the AI call.
          // _narrate flips the in-flight flag synchronously, so the first frame
          // after open() already shows "loading".
          _narrate(week);
        }
      }
      return WeeklyReportReady(record);
    } catch (_) {
      return const WeeklyReportFailed();
    }
  }

  /// Stamps the row viewed and returns it with the stamp, falling back to the
  /// row the caller already has.
  Future<WeeklyReportRecord> _viewed(
    IsoWeek week,
    WeeklyReportRecord record,
  ) async {
    await _repository.markViewed(week);
    return await _repository.forWeek(week) ?? record;
  }

  Future<void> _dismissEmptyWeek(IsoWeek week) async {
    final key = weeklyReportWeekKey(week);
    await _prefs.setString(weeklyReportDismissedWeekKey, key);
    _onDismissedWeek(key);
  }

  /// User-initiated retry. The only way to call the backend again after a
  /// failure.
  Future<NarrativeOutcome> retryNarrative(IsoWeek week) async {
    final running = _narrating[week];
    if (running != null) return running;
    try {
      final record = await _repository.forWeek(week);
      if (record?.narrativeJson != null) return NarrativeOutcome.alreadySaved;
    } catch (_) {
      return const NarrativeOutcome.failed(NarrativeFailureKind.unavailable);
    }
    return _narrate(week);
  }

  /// Starts (or joins) the narrative call for [week]. Everything up to the
  /// first await runs synchronously, including the in-flight flag.
  Future<NarrativeOutcome> _narrate(IsoWeek week) {
    final running = _narrating[week];
    if (running != null) return running;
    _writeUi(week, const NarrativeUiState(inFlight: true));
    final future = _runNarrative(week);
    _narrating[week] = future;
    return future;
  }

  Future<NarrativeOutcome> _runNarrative(IsoWeek week) async {
    var outcome = NarrativeOutcome.notEligible;
    try {
      outcome = await _service.generateNarrative(week);
    } catch (_) {
      outcome = const NarrativeOutcome.failed(NarrativeFailureKind.unavailable);
    } finally {
      _narrating.remove(week);
      final kind = outcome.failure;
      _writeUi(
        week,
        outcome.isFailed && kind != null
            ? NarrativeUiState(
                failure: kind,
                quotaDayIso: kind == NarrativeFailureKind.quotaExhausted
                    ? dateIso(_clock.now())
                    : null,
              )
            : const NarrativeUiState(),
      );
    }
    return outcome;
  }
}

/// App-lifetime on purpose (not `autoDispose`): the in-flight maps must
/// survive the user leaving the report screen while the 45 s client call is
/// still running.
final weeklyReportControllerProvider = Provider<WeeklyReportController>((ref) {
  return WeeklyReportController(
    service: ref.watch(weeklyReportServiceProvider),
    repository: ref.watch(weeklyReportRepositoryProvider),
    clock: ref.watch(clockProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    isEnabled: () => ref.read(weeklyReportEnabledProvider),
    writeUiState: (week, state) =>
        ref.read(narrativeUiStateProvider(week).notifier).state = state,
    onDismissedWeek: (key) =>
        ref.read(weeklyReportDismissedWeekProvider.notifier).state = key,
  );
});
