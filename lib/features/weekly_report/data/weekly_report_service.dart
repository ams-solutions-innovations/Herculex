import 'dart:convert';

import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_inputs_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_narrative_service.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/nutrition_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/physique_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/recovery_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/tdee_shift_calculator.dart';
import 'package:herculex/features/weekly_report/domain/training_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_facts.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';

/// Which way a [WeeklyReportService.generateNarrative] call ended.
enum NarrativeOutcomeStatus { saved, alreadySaved, notEligible, failed }

/// Result of [WeeklyReportService.generateNarrative]. Every non-saved state
/// leaves the report row exactly as it was, apart from the attempt counter.
class NarrativeOutcome {
  const NarrativeOutcome._(this.status, [this.failure]);

  /// A narrative was produced and stored.
  static const saved = NarrativeOutcome._(NarrativeOutcomeStatus.saved);

  /// The row already holds a narrative; nothing was called or counted.
  static const alreadySaved = NarrativeOutcome._(
    NarrativeOutcomeStatus.alreadySaved,
  );

  /// No row, an unreadable payload, or a week with nothing for the AI to say.
  static const notEligible = NarrativeOutcome._(
    NarrativeOutcomeStatus.notEligible,
  );

  /// The backend call failed; [failure] selects the copy variant (D-02).
  const NarrativeOutcome.failed(NarrativeFailureKind kind)
    : this._(NarrativeOutcomeStatus.failed, kind);

  final NarrativeOutcomeStatus status;
  final NarrativeFailureKind? failure;

  bool get isSaved => status == NarrativeOutcomeStatus.saved;
  bool get isFailed => status == NarrativeOutcomeStatus.failed;
}

/// Turns an ISO week into a frozen report row and, separately, a stored
/// narrative.
///
/// Order of guarantees:
/// * D-01 / RPT-04: an existing row is returned untouched, never recomputed.
/// * D-02: the measured snapshot is persisted before any AI work starts.
/// * D-04 / D-05: the window is Monday through `min(now, week end)`, and the
///   running week is persisted only once due (week over, or Sunday at/after
///   the weekly-report time), so a mid-week open freezes nothing.

/// * D-06: a week with nothing logged inside it, or a future week, creates no
///   row.
/// * House rule: the AI never writes. [generateNarrative] only passes facts
///   out and stores the validated answer in the narrative columns, through
///   the repository's write-once method.
///
/// Time comes only from the injected [Clock]. Programmer errors are not
/// swallowed here; the controller that calls this is the fail-soft layer.
class WeeklyReportService {
  WeeklyReportService({
    required WeeklyReportRepository repository,
    required WeeklyReportInputsRepository inputs,
    required WeeklyReportNarrativeService narrative,
    required Clock clock,
    required Future<MacroTargets?> Function(DateTime day) targetForDay,
    String Function()? reportTimeHHMM,
  }) : _reportTimeHHMM = reportTimeHHMM ?? _defaultReportTime,
       _repository = repository,
       _inputs = inputs,
       _narrative = narrative,
       _clock = clock,
       _targetForDay = targetForDay;

  final WeeklyReportRepository _repository;
  final WeeklyReportInputsRepository _inputs;
  final WeeklyReportNarrativeService _narrative;
  final Clock _clock;
  final Future<MacroTargets?> Function(DateTime day) _targetForDay;
  final String Function() _reportTimeHHMM;

  static String _defaultReportTime() => '18:00';

  /// Whether [week] may be persisted right now (see [IsoWeek.isSnapshotDue]).
  bool canSnapshot(IsoWeek week) =>
      week.isSnapshotDue(_clock.now(), _reportTimeHHMM());

  /// Returns the stored report for [week], creating it first if this is the
  /// first time the week is opened. Null when the week is in the future or
  /// holds no signal.
  Future<WeeklyReportRecord?> generate(IsoWeek week) async {
    final existing = await _repository.forWeek(week);
    if (existing != null) return existing;

    final now = _clock.now();
    if (week.start.isAfter(now)) return null;
    if (!canSnapshot(week)) return null;
    final windowEnd = week.windowEnd(now);

    final inputs = await _inputs.load(week: week, windowEnd: windowEnd);

    final targetByDate = <String, ({int kcal, int proteinG})>{};
    final days = inputs.nutrition.loggedDays.toList()..sort();
    for (final iso in days) {
      final target = await _targetForDay(DateTime.parse(iso));
      if (target != null) {
        targetByDate[iso] = (kcal: target.kcal, proteinG: target.proteinG);
      }
    }

    final payload = WeeklyReportPayload(
      isoYear: week.isoYear,
      isoWeek: week.isoWeek,
      weekStartIso: week.startIso,
      weekEndIso: week.endIso,
      windowEnd: windowEnd,
      nutrition: NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs.nutrition.copyWith(targetByDate: targetByDate),
      ),
      training: TrainingSectionCalculator.compute(
        week: week,
        windowEnd: windowEnd,
        sets: inputs.snapshot.sets,
      ),
      recovery: RecoverySectionCalculator.compute(
        week: week,
        windowEnd: windowEnd,
        weekHealth: inputs.weekHealth,
        trailingHealth: inputs.trailingHealth,
        snapshot: inputs.snapshot,
      ),
      physique: PhysiqueSectionCalculator.compute(
        week: week,
        checkIns: inputs.checkIns,
        weights: inputs.weights,
      ),
      tdee: TdeeShiftCalculator.compute(
        newest: inputs.tdeeNewest,
        before: inputs.tdeeBefore,
      ),
    );

    // hasSignal looks at in-window sections only, so TDEE history alone can
    // never persist a row for an empty week.
    if (!payload.hasSignal) return null;

    return _repository.insertSnapshot(
      week: week,
      payloadVersion: payload.payloadVersion,
      payloadJson: jsonEncode(payload.toJson()),
    );
  }

  /// The single narrative path, used by both the automatic first-open call and
  /// the manual retry. It never touches anything but the attempt counter and
  /// the narrative columns.
  Future<NarrativeOutcome> generateNarrative(IsoWeek week) async {
    final record = await _repository.forWeek(week);
    if (record == null) return NarrativeOutcome.notEligible;
    if (record.narrativeJson != null) return NarrativeOutcome.alreadySaved;

    final payload = WeeklyReportPayload.tryDecode(record.payloadJson);
    if (payload == null || !payload.hasNarrativeSignal) {
      return NarrativeOutcome.notEligible;
    }

    final facts = WeeklyReportFacts.fromPayload(payload);

    // Count the attempt first: a crash or timeout mid-call must not become a
    // free retry loop against the daily quota.
    await _repository.incrementNarrativeAttempts(week);

    final (WeeklyNarrative, Map<String, dynamic>) result;
    try {
      result = await _narrative.generate(facts);
    } on WeeklyReportNarrativeException catch (error) {
      return NarrativeOutcome.failed(error.kind);
    } catch (_) {
      return const NarrativeOutcome.failed(NarrativeFailureKind.unavailable);
    }

    final (narrative, provenance) = result;
    final stored = await _repository.saveNarrative(
      week,
      narrativeJson: jsonEncode(narrative.toJson()),
      knowledgeVersion: _text(provenance['knowledgeVersion']),
      modelVersion: _text(provenance['modelVersion']),
    );
    // False means another call stored one first; the row is complete either way.
    return stored ? NarrativeOutcome.saved : NarrativeOutcome.alreadySaved;
  }

  static String? _text(Object? value) => value is String ? value : null;
}
