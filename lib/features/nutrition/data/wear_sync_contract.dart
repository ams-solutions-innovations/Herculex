import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const int wearSyncSchemaVersion = 2;
const String wearSyncOriginPhone = 'phone';
const String wearSyncOriginWatch = 'watch';
const String wearSyncEntityActiveWorkout = 'active_workout';
const String wearSyncEntityFasting = 'fasting';

class WearSyncEnvelope {
  const WearSyncEnvelope({
    required this.schemaVersion,
    required this.entity,
    required this.entityId,
    required this.revision,
    required this.origin,
    required this.updatedAtEpochMs,
    required this.payload,
  });

  final int schemaVersion;
  final String entity;
  final String entityId;
  final int revision;
  final String origin;
  final int updatedAtEpochMs;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'entity': entity,
      'entityId': entityId,
      'revision': revision,
      'origin': origin,
      'updatedAtEpochMs': updatedAtEpochMs,
      'payload': payload,
    };
  }

  String encode() => jsonEncode(toJson());

  static WearSyncEnvelope wrap({
    required String entity,
    required String entityId,
    required int revision,
    required String origin,
    required Map<String, dynamic> payload,
    int? updatedAtEpochMs,
  }) {
    return WearSyncEnvelope(
      schemaVersion: wearSyncSchemaVersion,
      entity: entity,
      entityId: entityId,
      revision: revision,
      origin: origin,
      updatedAtEpochMs:
          updatedAtEpochMs ?? DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    );
  }

  static WearSyncEnvelope decode(
    String jsonString, {
    required String fallbackEntity,
    required String fallbackEntityId,
    required String fallbackOrigin,
  }) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final payload = decoded['payload'];
    // origin/entityId are optional at decode time (the fallback below still
    // covers "absent") but must be the right type when present — a
    // wrong-typed value falls through to the legacy branch instead of
    // crashing or being silently coerced.
    final isEnvelope =
        decoded['schemaVersion'] is num &&
        decoded['entity'] is String &&
        payload is Map &&
        (decoded['origin'] == null || decoded['origin'] is String) &&
        (decoded['entityId'] == null || decoded['entityId'] is String);

    if (!isEnvelope) {
      return WearSyncEnvelope(
        schemaVersion: 0,
        entity: fallbackEntity,
        entityId: fallbackEntityId,
        revision: (decoded['revision'] as num?)?.toInt() ?? 0,
        origin: fallbackOrigin,
        updatedAtEpochMs:
            (decoded['updatedAtEpochMs'] as num?)?.toInt() ??
            (decoded['startedAtEpochMs'] as num?)?.toInt() ??
            0,
        payload: decoded,
      );
    }

    return WearSyncEnvelope(
      schemaVersion: (decoded['schemaVersion'] as num).toInt(),
      entity: decoded['entity'] as String,
      entityId: decoded['entityId'] as String? ?? fallbackEntityId,
      revision: (decoded['revision'] as num?)?.toInt() ?? 0,
      origin: decoded['origin'] as String? ?? fallbackOrigin,
      updatedAtEpochMs: (decoded['updatedAtEpochMs'] as num?)?.toInt() ?? 0,
      payload: Map<String, dynamic>.from(payload),
    );
  }
}

/// Issues revisions that never go backwards, even across a process restart.
///
/// The old in-memory-only version reset to 0 on every app restart, so a
/// revision issued before a restart could collide with (or beat) one issued
/// after it — see Phase 1 of
/// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md. [key]
/// namespaces the persisted high-water mark so independent entities (e.g.
/// workout vs. fasting) don't share — and corrupt — each other's sequence.
class WearRevisionAllocator {
  WearRevisionAllocator(this._prefs, String key) : _key = 'wear_sync_revision_$key';

  final SharedPreferences _prefs;
  final String _key;

  int next() {
    final persistedLast = _prefs.getInt(_key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = now > persistedLast ? now : persistedLast + 1;
    // shared_preferences updates its synchronous in-memory cache immediately
    // on setInt — the returned Future only tracks the async platform-channel
    // flush to disk, so a subsequent next() call in this process sees `next`
    // right away even though this call isn't awaited. Awaiting here would
    // make every sync call chain through disk I/O for no correctness gain.
    unawaited(_prefs.setInt(_key, next));
    return next;
  }
}

class WearDedupeState {
  final Map<String, ({int revision, int updatedAtEpochMs})> _latest = {};

  /// Pure check: would [envelope] be newer than the last envelope *committed*
  /// for its key? Does not mutate any state.
  ///
  /// Split from the combined check-and-commit that used to live here so a
  /// caller can gate on this *before* attempting to durably apply the
  /// envelope, then call [commit] only once that apply actually succeeds. The
  /// combined version committed on the check alone, so a failed apply (e.g. a
  /// Drift write that threw) still marked the revision "seen" and a retried
  /// delivery of the same envelope was then silently dropped forever — see
  /// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md Phase 2
  /// (ENG-07/10/12).
  ///
  /// The unenveloped-legacy shape is rejected (fail-closed) rather than
  /// always-accepted — see Phase 1c of the remediation plan. That bypass
  /// existed for pre-envelope watch builds; once both APKs move to
  /// schemaVersion 2 together there's no legitimate sender left for it.
  bool wouldAccept(WearSyncEnvelope envelope) {
    if (_isUnenvelopedLegacyPayload(envelope)) return false;
    final previous = _latest[_keyFor(envelope)];
    if (previous == null) return true;
    if (envelope.revision < previous.revision) return false;
    if (envelope.revision == previous.revision &&
        envelope.updatedAtEpochMs <= previous.updatedAtEpochMs) {
      return false;
    }
    return true;
  }

  /// Records [envelope] as applied. Call only after the corresponding
  /// durable write has succeeded.
  void commit(WearSyncEnvelope envelope) {
    if (_isUnenvelopedLegacyPayload(envelope)) return;
    _latest[_keyFor(envelope)] = (
      revision: envelope.revision,
      updatedAtEpochMs: envelope.updatedAtEpochMs,
    );
  }

  bool _isUnenvelopedLegacyPayload(WearSyncEnvelope envelope) =>
      envelope.schemaVersion == 0 &&
      envelope.revision == 0 &&
      envelope.updatedAtEpochMs == 0;

  String _keyFor(WearSyncEnvelope envelope) =>
      '${envelope.entity}:${envelope.entityId}:${envelope.origin}';
}

String normalizeWearSetType(String? raw) {
  switch ((raw ?? 'standard').trim().toLowerCase()) {
    case 'normal':
    case 'work':
    case 'working':
    case '':
      return 'standard';
    case 'warmup':
    case 'warm_up':
      return 'standard';
    case 'failure':
    case 'forced':
      return 'forced';
    default:
      return raw!.trim().toLowerCase();
  }
}

bool normalizeWearWarmup({String? setType, bool? isWarmup}) {
  final raw = (setType ?? '').trim().toLowerCase();
  return isWarmup == true || raw == 'warmup' || raw == 'warm_up';
}
