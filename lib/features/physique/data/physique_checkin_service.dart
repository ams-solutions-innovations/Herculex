import 'dart:typed_data';

import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

const _fallbackReason = "Herculex AI couldn't describe this comparison.";
const _quotaMessage =
    "You've used today's Herculex AI check-ins. Try again tomorrow, or save "
    'your photo without analysis.';
const _unavailableMessage =
    "Herculex AI isn't available right now. Save your photo without analysis "
    "and it will still count as this week's check-in.";

/// The only data about the user that leaves the device besides photos.
class PhysiqueCheckInContext {
  const PhysiqueCheckInContext({
    required this.phase,
    required this.weeksInPhase,
    this.weightTrendKgPerWeek,
  });

  final DietPhase phase;
  final int weeksInPhase;
  final double? weightTrendKgPerWeek;

  Map<String, dynamic> toWire() => {
    'phase': phase.name,
    'weeksInPhase': weeksInPhase,
    'weightTrendKgPerWeek': weightTrendKgPerWeek,
  };
}

class PhysiqueCheckInAnalysis {
  const PhysiqueCheckInAnalysis({
    required this.evidence,
    this.modelVersion,
    this.knowledgeVersion,
  });

  final CheckInEvidence evidence;
  final String? modelVersion;
  final String? knowledgeVersion;
}

enum PhysiqueCheckInFailure {
  consentRequired,
  invalidInput,
  quotaExhausted,
  unavailable,
  malformedResponse,
}

class PhysiqueCheckInException implements Exception {
  const PhysiqueCheckInException(this.kind, this.message);

  final PhysiqueCheckInFailure kind;
  final String message;

  @override
  String toString() => message;
}

/// Returns evidence only. It has no repository dependency: the AI never writes
/// to the database, and the verdict is computed elsewhere by the classifier.
class PhysiqueCheckInService {
  PhysiqueCheckInService(this._backend);

  final PhysiqueCheckInBackend _backend;

  Future<PhysiqueCheckInAnalysis> analyze({
    required List<Uint8List> baselineJpegs,
    required Uint8List currentJpeg,
    required PhysiqueCheckInContext context,
    required bool consentGranted,
    String? userNote,
  }) async {
    if (!consentGranted) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.consentRequired,
        'Confirm the photo privacy notice before starting the analysis.',
      );
    }
    if (baselineJpegs.isEmpty || currentJpeg.isEmpty) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.invalidInput,
        'A baseline photo and a current photo are required.',
      );
    }

    final baselines = baselineJpegs
        .where((b) => b.isNotEmpty)
        .take(PhysiqueTuning.maxCheckInBaselinePhotos)
        .map((b) => <String, dynamic>{'bytes': b, 'mimeType': 'image/jpeg'})
        .toList();
    if (baselines.isEmpty) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.invalidInput,
        'A baseline photo and a current photo are required.',
      );
    }

    final (Map<String, dynamic> result, Map<String, dynamic> provenance) raw;
    try {
      raw = await _backend.analyzePhysiqueCheckIn(
        baselineImages: baselines,
        currentImage: {'bytes': currentJpeg, 'mimeType': 'image/jpeg'},
        context: context.toWire(),
        userNote: userNote,
      );
    } catch (error) {
      final detail = error.toString();
      if (detail.contains('are used up')) {
        throw PhysiqueCheckInException(
          PhysiqueCheckInFailure.quotaExhausted,
          _quotaMessage,
        );
      }
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.unavailable,
        _unavailableMessage,
      );
    }

    final (result, provenance) = raw;
    final band = _parseBand(result['directionBand']);
    final reason = _stripPercentages(result['reason']);
    final evidence = CheckInEvidence(
      band: band,
      confidence: AssessmentConfidence.fromWire(result['confidence']),
      reason: reason.isEmpty ? _fallbackReason : reason,
      limitations: _parseLimitations(result['limitations']),
    );
    return PhysiqueCheckInAnalysis(
      evidence: evidence,
      modelVersion: _optionalString(provenance['modelVersion']),
      knowledgeVersion: _optionalString(provenance['knowledgeVersion']),
    );
  }
}

CheckInBand _parseBand(Object? raw) {
  if (raw is Map) {
    final low = raw['low'];
    final high = raw['high'];
    if (low is num && high is num) {
      try {
        return CheckInBand.clamped(low.toDouble(), high.toDouble());
      } on ArgumentError {
        // fall through to malformed
      }
    }
  }
  throw const PhysiqueCheckInException(
    PhysiqueCheckInFailure.malformedResponse,
    'Herculex AI returned an incomplete comparison.',
  );
}

List<String> _parseLimitations(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .take(3)
      .toList(growable: false);
}

String? _optionalString(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

final _percentNumber = RegExp(
  r'\d+(?:[.,]\d+)?\s*(?:%|percent|per\s*cent)',
  caseSensitive: false,
);

/// Defense in depth for D-11: no false-precision percentage reaches the UI,
/// even when the server predates its own normaliser.
String _stripPercentages(Object? raw) {
  if (raw is! String) return '';
  return raw
      .replaceAll(_percentNumber, '')
      .replaceAll('%', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
