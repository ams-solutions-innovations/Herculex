import 'dart:async';
import 'dart:convert';

import '../../nutrition/data/wear_sync_service.dart';
import '../domain/motion_sample.dart';
import '../domain/rep_detector.dart';
import '../domain/rep_features.dart';
import '../domain/rep_movement.dart';
import '../domain/rep_suggestion.dart';
import '../domain/rep_tracking_eligibility.dart';

/// One `/herculex/reps/samples` batch, ordered by [seq] before assembly.
class _Batch {
  const _Batch(this.seq, this.samples);

  final int seq;
  final List<MotionSample> samples;
}

/// Everything accumulated for one in-flight watch capture, keyed by
/// `captureId`. Raw samples live here — and nowhere else — for the duration
/// of the set (REP-04); [RepCaptureService] discards this entry the instant
/// detection finishes, success or failure.
class _CaptureState {
  _CaptureState({
    required this.exerciseSlug,
    required this.sensorType,
    required this.startedAtMs,
  });

  final String exerciseSlug;
  final String sensorType;
  final int startedAtMs;

  /// Keyed by `seq` so an out-of-order delivery still assembles correctly and
  /// a duplicate delivery of the same `seq` simply overwrites in place rather
  /// than duplicating samples.
  final Map<int, _Batch> batchesBySeq = {};

  int get sampleCount =>
      batchesBySeq.values.fold(0, (sum, b) => sum + b.samples.length);
}

/// Reassembles the watch's batched `/herculex/reps/*` traffic into a
/// [MotionTrace], runs the single authoritative [RepDetector] over it, and
/// emits an immutable [RepSuggestion] plus a [TrackerState] stream.
///
/// **REP-03 fence:** this file imports the nutrition bridge
/// (`wear_sync_service.dart`) and nothing under `lib/features/workouts/`.
/// `WorkoutsRepository`/`updateSet` are never referenced here or anywhere
/// else in `lib/features/reps/` — the tracker only ever proposes.
///
/// **REP-04:** raw samples exist in Dart memory for the duration of
/// detection only. [rawBufferSampleCount] exposes that as a tested property
/// rather than a comment: it is 0 for any `captureId` not currently mid
/// -detection, whether because nothing arrived, detection finished, or
/// detection threw.
class RepCaptureService {
  RepCaptureService({
    RepDetectionResult Function(MotionTrace trace, {RepDetectorConfig config})?
        detect,
  }) : _detect = detect ?? RepDetector.detect {
    WearSyncService.onWatchRepCaptureStart = _handleCaptureStart;
    WearSyncService.onWatchRepSamples = _handleSamples;
    WearSyncService.onWatchRepCaptureEnd = _handleCaptureEnd;
  }

  final RepDetectionResult Function(
    MotionTrace trace, {
    RepDetectorConfig config,
  }) _detect;

  final Map<String, _CaptureState> _captures = {};

  final StreamController<TrackerState> _stateController =
      StreamController<TrackerState>.broadcast();
  final StreamController<RepSuggestion> _suggestionController =
      StreamController<RepSuggestion>.broadcast();

  /// Non-null whenever the most recently emitted [TrackerState] is
  /// [TrackerState.manual] or [TrackerState.countOnly].
  String? get stateReason => _stateReason;
  String? _stateReason;

  Stream<TrackerState> get stateStream => _stateController.stream;
  Stream<RepSuggestion> get suggestions => _suggestionController.stream;

  /// Raw sample count still buffered for [captureId]. 0 for an id that never
  /// arrived, was never started, or has already finished detection — the
  /// tested proof that REP-04's "discarded at set end" property holds.
  int rawBufferSampleCount(String captureId) =>
      _captures[captureId]?.sampleCount ?? 0;

  /// Cancels an in-flight capture without waiting for `capture_end` — e.g. a
  /// user-initiated cancel from the review sheet, or a transport error the
  /// caller detects independently. Discards the buffer and emits
  /// [TrackerState.manual] with [reason].
  void abort(String captureId, {String reason = 'capture aborted'}) {
    _captures.remove(captureId);
    _emitManual(reason);
  }

  /// The `captureId` currently accumulating batches for [exerciseSlug], or
  /// null when nothing is in flight for it. 10-04's tracker panel uses this
  /// so a phone-side "Stop" tap can abort the matching wrist capture — the
  /// watch is the only device that can end a wrist capture normally, but the
  /// phone still needs a way to cancel one the user changed their mind about.
  String? activeCaptureIdFor(String exerciseSlug) {
    for (final entry in _captures.entries) {
      if (entry.value.exerciseSlug == exerciseSlug) return entry.key;
    }
    return null;
  }

  /// Builds a [RepSuggestion] from a phone-captured [trace] — the
  /// counterpart to the wrist bridge's `_handleCaptureEnd` above, added by
  /// 10-04 to answer the question 10-03b's summary left open ("how a
  /// phone-sourced trace reaches detection"). There is no on-device
  /// provisional count on this path (that only exists on the watch), so
  /// [RepSuggestion.provisionalCount] is always null and
  /// [RepSuggestion.provisionalDisagrees] is always false.
  ///
  /// Like the wrist path, this only ever proposes — it calls the same
  /// authoritative [RepDetector] and never touches anything under
  /// `lib/features/workouts/`.
  RepSuggestion buildPhoneSuggestion({
    required String captureId,
    required String exerciseSlug,
    required MotionTrace trace,
    required String placement,
    required String stoppedReason,
  }) {
    final movement = movementFor(exerciseSlug);
    if (movement == null || trace.samples.isEmpty) {
      return RepSuggestion(
        captureId: captureId,
        exerciseSlug: exerciseSlug,
        movement: movement ?? RepMovement.pullUp,
        source: 'phone',
        placement: placement,
        sensorType: trace.sensorType,
        proposedReps: 0,
        provisionalCount: null,
        provisionalDisagrees: false,
        setConfidence: 0,
        confidenceBand: ConfidenceBand.low,
        missedRepSuspected: false,
        missedBatches: 0,
        sampleCount: trace.samples.length,
        coverageRatio: 0,
        featuresJson: null,
        state: TrackerState.manual,
        stateReason: 'nothing captured — count not verified',
      );
    }

    final result =
        _detect(trace, config: RepDetectorConfig.forMovement(movement));
    var band = RepSuggestion.bandFor(result.setConfidence);
    // A cap-truncated (or otherwise non-'user'-ended) capture is incomplete,
    // the same treatment 10-03b's notes give a non-'user' stoppedReason on
    // the wrist path.
    final incomplete = stoppedReason != 'user';
    if (incomplete) band = band.lowerByOne();

    final isLowConfidence = band == ConfidenceBand.low;
    final state =
        isLowConfidence ? TrackerState.countOnly : TrackerState.tracking;
    final reason = isLowConfidence
        ? 'low confidence — reps proposed, no RPE suggestion'
        : (incomplete ? 'capture ended early ($stoppedReason)' : null);

    return RepSuggestion(
      captureId: captureId,
      exerciseSlug: exerciseSlug,
      movement: movement,
      source: 'phone',
      placement: placement,
      sensorType: trace.sensorType,
      proposedReps: result.repCount,
      provisionalCount: null,
      provisionalDisagrees: false,
      setConfidence: result.setConfidence,
      confidenceBand: band,
      missedRepSuspected: result.missedRepSuspected,
      missedBatches: 0,
      sampleCount: trace.samples.length,
      coverageRatio: 1.0,
      featuresJson: RepFeatures.fromResult(result).toJson(),
      state: state,
      stateReason: reason,
    );
  }

  void dispose() {
    WearSyncService.onWatchRepCaptureStart = null;
    WearSyncService.onWatchRepSamples = null;
    WearSyncService.onWatchRepCaptureEnd = null;
    _stateController.close();
    _suggestionController.close();
  }

  // ── Fake-bridge test entry points ────────────────────────────────────
  //
  // Production wiring goes through the three `WearSyncService.onWatchRep*`
  // setters assigned in the constructor above. These public aliases let a
  // test drive the exact same handlers directly — no plugin channel, no
  // device, no Gradle — while still exercising every line real traffic
  // would.

  /// Simulates one `/herculex/reps/capture_start` delivery.
  void handleCaptureStart(String? payloadJson) => _handleCaptureStart(payloadJson);

  /// Simulates one `/herculex/reps/samples` delivery.
  void handleSamples(String? payloadJson) => _handleSamples(payloadJson);

  /// Simulates one `/herculex/reps/capture_end` delivery.
  void handleCaptureEnd(String? payloadJson) => _handleCaptureEnd(payloadJson);

  // ── Bridge callbacks ──────────────────────────────────────────────────

  void _handleCaptureStart(String? payloadJson) {
    final payload = _decode(payloadJson);
    if (payload == null) return;
    final captureId = payload['captureId'] as String?;
    final exerciseSlug = payload['exerciseSlug'] as String?;
    final sensorType = payload['sensorType'] as String?;
    if (captureId == null || exerciseSlug == null || sensorType == null) {
      return;
    }
    _captures[captureId] = _CaptureState(
      exerciseSlug: exerciseSlug,
      sensorType: sensorType,
      startedAtMs: (payload['startedAtMs'] as num?)?.toInt() ?? 0,
    );
    _stateReason = null;
    _stateController.add(TrackerState.tracking);
  }

  void _handleSamples(String? payloadJson) {
    final payload = _decode(payloadJson);
    if (payload == null) return;
    final captureId = payload['captureId'] as String?;
    final seq = (payload['seq'] as num?)?.toInt();
    if (captureId == null || seq == null) return;
    final capture = _captures[captureId];
    if (capture == null) return;

    final rawSamples = payload['samples'] as List<dynamic>? ?? const [];
    final samples = <MotionSample>[
      for (final raw in rawSamples)
        if (raw is Map<String, dynamic>)
          MotionSample(
            ((raw['tMs'] as num?) ?? 0).toInt(),
            ((raw['x'] as num?) ?? 0).toDouble(),
            ((raw['y'] as num?) ?? 0).toDouble(),
            ((raw['z'] as num?) ?? 0).toDouble(),
          ),
    ];
    capture.batchesBySeq[seq] = _Batch(seq, samples);
  }

  void _handleCaptureEnd(String? payloadJson) {
    final payload = _decode(payloadJson);
    if (payload == null) return;
    final captureId = payload['captureId'] as String?;
    if (captureId == null) return;

    final batchCount = (payload['batchCount'] as num?)?.toInt() ?? 0;
    final stoppedReason = payload['stoppedReason'] as String?;
    final provisionalCount = (payload['provisionalCount'] as num?)?.toInt();

    final capture = _captures[captureId];

    // Nothing-captured vs zero reps: these are different facts (10-CONTEXT).
    // A watch that never reconnected, or a capture-end for an id this
    // service never saw a start for, must never produce a zero-rep
    // suggestion and must never fall back to the provisional count.
    if (capture == null || capture.batchesBySeq.isEmpty) {
      _captures.remove(captureId);
      _emitManual('watch was not connected — count not verified');
      return;
    }

    // A battery refusal reported from the watch mid-set is an incomplete
    // capture, not a confidently-proposed one — degrade to manual rather
    // than proposing off however many samples happened to arrive first.
    if (stoppedReason == 'battery') {
      _captures.remove(captureId);
      _emitManual('capture device battery too low — count not verified');
      return;
    }

    final movement = movementFor(capture.exerciseSlug);
    if (movement == null) {
      _captures.remove(captureId);
      _emitManual('unrecognised exercise for rep tracking — count not verified');
      return;
    }

    try {
      final orderedSeqs = capture.batchesBySeq.keys.toList()..sort();
      final maxSeq = orderedSeqs.last;
      var missedBatches = 0;
      for (var seq = 0; seq <= maxSeq; seq++) {
        if (!capture.batchesBySeq.containsKey(seq)) missedBatches++;
      }

      final samples = <MotionSample>[
        for (final seq in orderedSeqs) ...capture.batchesBySeq[seq]!.samples,
      ];
      final trace = MotionTrace(samples: samples, sensorType: capture.sensorType);

      // The single authoritative call. proposedReps is its output,
      // unconditionally — see the class doc and T-10-12.
      final result = _detect(trace, config: RepDetectorConfig.forMovement(movement));

      final provisionalDisagrees = provisionalCount != null &&
          (provisionalCount - result.repCount).abs() > 1;

      // Confidence is degraded — never proposedReps — by exactly one step
      // per independent reason it should be trusted less. Never averaged,
      // never substituted, never adjusted by any function of
      // provisionalCount other than this one-step-per-cause penalty.
      var band = RepSuggestion.bandFor(result.setConfidence);
      if (missedBatches > 0) band = band.lowerByOne();
      if (provisionalDisagrees) band = band.lowerByOne();

      final coverageRatio = batchCount <= 0
          ? (orderedSeqs.isNotEmpty ? 1.0 : 0.0)
          : (orderedSeqs.length / batchCount).clamp(0.0, 1.0);

      final isLowConfidence = band == ConfidenceBand.low;
      final state = isLowConfidence ? TrackerState.countOnly : TrackerState.tracking;
      final reason = isLowConfidence
          ? 'low confidence — reps proposed, no RPE suggestion'
          : null;

      final suggestion = RepSuggestion(
        captureId: captureId,
        exerciseSlug: capture.exerciseSlug,
        movement: movement,
        source: 'wrist',
        placement: null,
        sensorType: capture.sensorType,
        proposedReps: result.repCount,
        provisionalCount: provisionalCount,
        provisionalDisagrees: provisionalDisagrees,
        setConfidence: result.setConfidence,
        confidenceBand: band,
        missedRepSuspected: result.missedRepSuspected || missedBatches > 0,
        missedBatches: missedBatches,
        sampleCount: samples.length,
        coverageRatio: coverageRatio,
        featuresJson: RepFeatures.fromResult(result).toJson(),
        state: state,
        stateReason: reason,
      );

      _stateReason = reason;
      _suggestionController.add(suggestion);
      _stateController.add(state);
    } finally {
      // Cleared on every exit path, including an exception thrown by
      // _detect — REP-04's "discarded at set end" is enforced here, not
      // assumed.
      _captures.remove(captureId);
    }
  }

  void _emitManual(String reason) {
    _stateReason = reason;
    _stateController.add(TrackerState.manual);
  }

  Map<String, dynamic>? _decode(String? payloadJson) {
    if (payloadJson == null) return null;
    final decoded = jsonDecode(payloadJson);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
