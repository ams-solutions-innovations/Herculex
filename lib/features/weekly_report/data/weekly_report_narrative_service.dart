import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

/// The single seam between the weekly report and the Herculex AI narrative
/// call (RPT-02, D-12).
///
/// House rule: the AI never writes to the database. This service has no
/// database dependency; it returns validated evidence and the caller saves it
/// through the repository after the user-visible flow completes. The client is
/// the authoritative gate on the model's answer: [WeeklyNarrative.fromJson]
/// enforces structure and the correlation-only wording guard.
final weeklyReportNarrativeServiceProvider =
    Provider<WeeklyReportNarrativeService>((ref) {
      return WeeklyReportNarrativeService(
        ref.watch(weeklyReportBackendProvider),
      );
    });

/// Why a narrative could not be produced. Per D-02 the caller treats every
/// kind the same way (row kept, "Narrative pending", user-initiated retry);
/// the kind only selects the copy variant.
enum NarrativeFailureKind {
  offline,
  unconfigured,
  quotaExhausted,
  rejected,
  unavailable,
}

/// A translated, user-facing failure from
/// [WeeklyReportNarrativeService.generate]. [message] is a fixed, user-safe
/// sentence per [kind] and never contains a raw technical exception string.
class WeeklyReportNarrativeException implements Exception {
  const WeeklyReportNarrativeException(this.kind, this.message);

  final NarrativeFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Substrings of the Edge Function's daily-quota 429 message (see
/// `HerculexAiBriefService`; there is no typed quota exception to catch).
const _quotaIndicators = <String>['used up', 'try again tomorrow'];

/// Substrings of the connection and timeout errors raised by
/// `SupabaseGeminiBackend._invoke`.
const _offlineIndicators = <String>['Cannot connect', 'timed out'];

const _unconfiguredIndicator = 'not configured';

const _messages = <NarrativeFailureKind, String>{
  NarrativeFailureKind.offline:
      "Herculex AI couldn't be reached. Check your connection and try again.",
  NarrativeFailureKind.unconfigured:
      'Herculex AI is not set up on this build, so there is no summary yet.',
  NarrativeFailureKind.quotaExhausted:
      "You've used today's Herculex AI summaries. Try again tomorrow.",
  NarrativeFailureKind.rejected:
      'Herculex AI returned a summary that could not be used. Try again.',
  NarrativeFailureKind.unavailable:
      "Herculex AI couldn't write this week's summary. Try again.",
};

class WeeklyReportNarrativeService {
  const WeeklyReportNarrativeService(this._backend);

  final WeeklyReportBackend _backend;

  /// Sends [facts] to the backend unchanged and strictly parses the answer.
  /// Throws [WeeklyReportNarrativeException] for every failure.
  Future<(WeeklyNarrative narrative, Map<String, dynamic> provenance)> generate(
    Map<String, dynamic> facts,
  ) async {
    final Map<String, dynamic> result;
    final Map<String, dynamic> provenance;
    try {
      (result, provenance) = await _backend.generateWeeklyReportNarrative(
        facts: facts,
      );
    } catch (error) {
      throw _translate(error);
    }

    try {
      return (WeeklyNarrative.fromJson(result), provenance);
    } on FormatException {
      // Structural failure and causal-wording rejection are the same outcome
      // (D-12): the text is discarded and the report shows "pending".
      throw _failure(NarrativeFailureKind.rejected);
    }
  }

  WeeklyReportNarrativeException _translate(Object error) {
    final detail = error.toString().replaceFirst('Exception: ', '').trim();
    if (_quotaIndicators.any(detail.contains)) {
      return _failure(NarrativeFailureKind.quotaExhausted);
    }
    if (_offlineIndicators.any(detail.contains)) {
      return _failure(NarrativeFailureKind.offline);
    }
    if (detail.contains(_unconfiguredIndicator)) {
      return _failure(NarrativeFailureKind.unconfigured);
    }
    return _failure(NarrativeFailureKind.unavailable);
  }

  WeeklyReportNarrativeException _failure(NarrativeFailureKind kind) =>
      WeeklyReportNarrativeException(kind, _messages[kind]!);
}
