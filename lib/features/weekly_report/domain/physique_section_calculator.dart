/// Physique card calculator for the weekly report (RPT-01, RPT-02).
///
/// Takes plain inputs so the domain layer holds no drift rows: the caller maps
/// `PhysiqueAssessments` rows of kind `checkin` and the bodyweight log into
/// [PhysiqueCheckInInput] and [BodyweightLog]. The verdict is the stored
/// deterministic one; this file never produces or interprets a verdict.
///
/// Pure Dart: no Flutter, drift, Riverpod or wall-clock reads.
library;

import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

/// One physique check-in (`kind == 'checkin'`) as stored.
class PhysiqueCheckInInput {
  const PhysiqueCheckInInput({
    required this.dateIso,
    this.verdict,
    this.confidence,
  });

  /// Local calendar day, `yyyy-MM-dd`.
  final String dateIso;

  /// Stored verdict text; anything outside the closed vocabulary is dropped.
  final String? verdict;

  /// Stored confidence text; anything outside the closed vocabulary is dropped.
  final String? confidence;
}

/// One bodyweight reading.
class BodyweightLog {
  const BodyweightLog({required this.dateIso, required this.kg});

  /// Local calendar day, `yyyy-MM-dd`.
  final String dateIso;
  final double kg;
}

abstract final class PhysiqueSectionCalculator {
  /// Closed verdict vocabulary (`CheckInVerdict.wireValue`).
  static const Set<String> verdicts = {'on_track', 'off_track', 'inconclusive'};

  /// Closed confidence vocabulary (`PhysiqueAssessments.confidence`).
  static const Set<String> confidences = {'low', 'medium', 'high', 'unknown'};

  /// Returns null when the week holds neither a check-in nor a bodyweight.
  ///
  /// The newest check-in is the one with the latest [PhysiqueCheckInInput
  /// .dateIso] inside the week; of equal dates the later list entry wins. The
  /// bodyweight is the latest reading inside the week and the delta is against
  /// the latest reading before the week (null when there is none).
  static PhysiqueSection? compute({
    required IsoWeek week,
    required List<PhysiqueCheckInInput> checkIns,
    required List<BodyweightLog> weights,
  }) {
    final start = week.startIso;
    final end = week.endIso;

    PhysiqueCheckInInput? checkIn;
    for (final c in checkIns) {
      if (!_inRange(c.dateIso, start, end)) continue;
      if (checkIn == null || c.dateIso.compareTo(checkIn.dateIso) >= 0) {
        checkIn = c;
      }
    }

    BodyweightLog? current;
    BodyweightLog? before;
    for (final w in weights) {
      if (!w.kg.isFinite || w.kg <= 0) continue;
      if (_inRange(w.dateIso, start, end)) {
        if (current == null || w.dateIso.compareTo(current.dateIso) >= 0) {
          current = w;
        }
      } else if (w.dateIso.compareTo(start) < 0) {
        if (before == null || w.dateIso.compareTo(before.dateIso) >= 0) {
          before = w;
        }
      }
    }

    if (checkIn == null && current == null) return null;

    final delta = (current != null && before != null)
        ? _round2(current.kg - before.kg)
        : null;

    final verdict = checkIn?.verdict;
    final confidence = checkIn?.confidence;
    return PhysiqueSection(
      checkInVerdict: verdict != null && verdicts.contains(verdict)
          ? verdict
          : null,
      checkInConfidence: confidence != null && confidences.contains(confidence)
          ? confidence
          : null,
      checkInDateIso: checkIn?.dateIso,
      bodyweightKg: current?.kg,
      bodyweightDeltaKg: delta,
    );
  }

  // yyyy-MM-dd compares correctly as a string.
  static bool _inRange(String dateIso, String start, String end) =>
      dateIso.compareTo(start) >= 0 && dateIso.compareTo(end) <= 0;

  static double _round2(double v) => (v * 100).round() / 100;
}
