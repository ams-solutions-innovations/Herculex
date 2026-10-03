/// The frozen, versioned snapshot stored in `weekly_reports.payload_json`
/// (D-01, D-06, RPT-01).
///
/// A null section means "No data this week". The payload is parsed strictly:
/// an unknown or missing `payloadVersion`, a missing required key or a
/// wrong-typed value throws [FormatException], which the UI maps to the
/// "Couldn't load this report" state. Remote-pulled JSON is never trusted, so
/// there are no `!` casts and nothing defaults silently.
///
/// Pure Dart: no Flutter, drift or wall-clock reads.
library;

import 'dart:convert';

import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

class WeeklyReportPayload {
  const WeeklyReportPayload({
    required this.isoYear,
    required this.isoWeek,
    required this.weekStartIso,
    required this.weekEndIso,
    required this.windowEnd,
    this.payloadVersion = currentVersion,
    this.nutrition,
    this.training,
    this.recovery,
    this.physique,
    this.tdee,
  });

  /// The only payload version this build writes and reads.
  static const int currentVersion = 1;

  factory WeeklyReportPayload.fromJson(Map<String, dynamic> json) {
    final version = json['payloadVersion'];
    if (version is! int || version != currentVersion) {
      throw FormatException(
        'Unsupported weekly report payloadVersion: $version',
      );
    }
    final isoYear = ReportJson.requiredInt(json, 'isoYear');
    final isoWeek = ReportJson.requiredInt(json, 'isoWeek');
    if (IsoWeek.tryCreate(isoYear, isoWeek) == null) {
      throw FormatException('Impossible ISO week $isoYear-W$isoWeek.');
    }
    final windowEndText = json['windowEnd'];
    final windowEnd = windowEndText is String
        ? DateTime.tryParse(windowEndText)
        : null;
    if (windowEnd == null) {
      throw const FormatException('Weekly report windowEnd is not a date.');
    }
    return WeeklyReportPayload(
      payloadVersion: version,
      isoYear: isoYear,
      isoWeek: isoWeek,
      weekStartIso: ReportJson.requiredString(json, 'weekStartIso'),
      weekEndIso: ReportJson.requiredString(json, 'weekEndIso'),
      windowEnd: windowEnd,
      nutrition: _section(json, 'nutrition', NutritionSection.fromJson),
      training: _section(json, 'training', TrainingSection.fromJson),
      recovery: _section(json, 'recovery', RecoverySection.fromJson),
      physique: _section(json, 'physique', PhysiqueSection.fromJson),
      tdee: _section(json, 'tdee', TdeeSection.fromJson),
    );
  }

  /// Parses stored text; throws [FormatException] on any problem.
  factory WeeklyReportPayload.fromJsonString(String text) {
    // jsonDecode itself throws FormatException on malformed text.
    return WeeklyReportPayload.fromJson(
      ReportJson.map(jsonDecode(text), 'payload'),
    );
  }

  /// Soft variant of [fromJsonString]: null on any failure.
  static WeeklyReportPayload? tryDecode(String text) {
    try {
      return WeeklyReportPayload.fromJsonString(text);
    } catch (_) {
      return null;
    }
  }

  final int payloadVersion;
  final int isoYear;
  final int isoWeek;

  /// Monday, `yyyy-MM-dd`.
  final String weekStartIso;

  /// Sunday, `yyyy-MM-dd`.
  final String weekEndIso;

  /// The effective end of the data window the calculators read.
  final DateTime windowEnd;

  final NutritionSection? nutrition;
  final TrainingSection? training;
  final RecoverySection? recovery;
  final PhysiqueSection? physique;
  final TdeeSection? tdee;

  IsoWeek get week => IsoWeek(isoYear, isoWeek);

  /// True when any section describing data logged inside the week exists
  /// (nutrition, training, recovery or physique); this decides whether a row is
  /// persisted at all (D-06).
  ///
  /// [tdee] is deliberately excluded: the TDEE section is derived from
  /// `tdee_estimates` history (earlier estimates), not from anything logged in
  /// the week, so counting it would persist a row for an empty week whenever
  /// two earlier estimates exist.
  bool get hasSignal =>
      nutrition != null ||
      training != null ||
      recovery != null ||
      physique != null;

  /// True when nutrition, training or recovery has data, i.e. there is enough
  /// for the AI to say something. A weight-only or physique-only week gets a
  /// row but no AI call (A2 interpretation of D-06).
  bool get hasNarrativeSignal =>
      nutrition != null || training != null || recovery != null;

  Map<String, dynamic> toJson() => {
    'payloadVersion': payloadVersion,
    'isoYear': isoYear,
    'isoWeek': isoWeek,
    'weekStartIso': weekStartIso,
    'weekEndIso': weekEndIso,
    'windowEnd': windowEnd.toIso8601String(),
    'nutrition': nutrition?.toJson(),
    'training': training?.toJson(),
    'recovery': recovery?.toJson(),
    'physique': physique?.toJson(),
    'tdee': tdee?.toJson(),
  };

  String toJsonString() => jsonEncode(toJson());
}

T? _section<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parse,
) {
  final raw = json[key];
  if (raw == null) return null;
  return parse(ReportJson.map(raw, '"$key" section'));
}
