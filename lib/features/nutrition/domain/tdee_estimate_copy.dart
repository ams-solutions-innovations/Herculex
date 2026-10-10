import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

/// "today", "yesterday" or "N days ago", by calendar day against [asOf].
String tdeeRelativeDay(DateTime at, DateTime asOf) {
  final days = DateTime(
    asOf.year,
    asOf.month,
    asOf.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

/// When an observed estimate was last measured; falls back to when it was
/// stored. Only differs from `estimatedAt` for a held (aging) estimate.
DateTime tdeeMeasuredAt(TdeeEstimateResult e) {
  final raw = e.inputs['measured_at'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  return parsed?.toLocal() ?? e.estimatedAt;
}

/// Days the observed data actually covers: the persisted measured span plus
/// one (both ends inclusive). Null when the span is missing or malformed;
/// the winning candidate window is a selection detail and is never shown.
int? tdeeObservedDays(TdeeEstimateResult e) {
  final span = e.inputs['span_days'];
  return span is num ? span.round() + 1 : null;
}

/// One sentence on how [e] was reached (28-UI-SPEC copy).
String tdeeMethodLine(TdeeEstimateResult e, DateTime asOf) {
  switch (e.method) {
    case TdeeMethod.observed:
      if (e.isHeld) {
        final when = tdeeRelativeDay(tdeeMeasuredAt(e), asOf);
        return 'Measured from your logs $when. Log again to refresh it.';
      }
      return 'Worked out from what you ate and how your weight trended.';
    case TdeeMethod.classifier:
      return 'Worked out from your daily activity and training.';
    case TdeeMethod.coldStart:
      return 'Using the activity level you chose at setup until there is '
          'enough data to measure.';
  }
}
