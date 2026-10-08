import 'package:herculex/core/utils/units.dart';
import 'package:herculex/features/physique/domain/roadmap_schedule.dart';
import 'package:intl/intl.dart';

/// Text for a phase on the calendar, shared by every roadmap view so the
/// timeline and the update review never word the same numbers differently.

/// Last day a phase covers (its end date is the day after).
DateTime roadmapLastDay(ScheduledPhase p) =>
    DateTime(p.endDate.year, p.endDate.month, p.endDate.day - 1);

/// "Sep 2 – Nov 24, 2026".
String roadmapDateRange(ScheduledPhase p) {
  final start = p.startDate;
  final end = roadmapLastDay(p);
  final sameYear = start.year == end.year;
  final from = DateFormat(sameYear ? 'MMM d' : 'MMM d, y').format(start);
  return '$from – ${DateFormat('MMM d, y').format(end)}';
}

/// "80 → 74 kg", or just the end weight when the start is unknown; empty when
/// the phase names no weight.
String roadmapWeightRange(ScheduledPhase p, WeightFormat wf) {
  final start = p.startKg;
  final end = p.endKg;
  if (end == null) return '';
  if (start == null) return wf.format(end);
  return '${wf.formatValue(start)} → ${wf.format(end)}';
}

/// "−0.5 kg/wk"; empty for a phase that holds weight.
String roadmapPace(ScheduledPhase p, WeightFormat wf) {
  final weekly = p.weeklyKg;
  if (weekly == null) return '';
  final shown = double.parse(wf.toDisplay(weekly.abs()).toStringAsFixed(2));
  if (shown == 0) return '';
  final sign = weekly < 0 ? '−' : '+';
  final number = shown.truncateToDouble() == shown
      ? shown.toStringAsFixed(0)
      : shown.toString();
  return '$sign$number ${wf.suffix}/wk';
}
