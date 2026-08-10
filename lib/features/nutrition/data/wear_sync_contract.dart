import 'dart:convert';

const int wearSyncSchemaVersion = 1;
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
    final isEnvelope =
        decoded['schemaVersion'] is num &&
        decoded['entity'] is String &&
        payload is Map;

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

class WearRevisionAllocator {
  int _lastRevision = 0;

  int next() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _lastRevision) {
      _lastRevision += 1;
    } else {
      _lastRevision = now;
    }
    return _lastRevision;
  }
}

class WearDedupeState {
  final Map<String, ({int revision, int updatedAtEpochMs})> _latest = {};

  bool shouldAccept(WearSyncEnvelope envelope) {
    if (envelope.schemaVersion == 0 &&
        envelope.revision == 0 &&
        envelope.updatedAtEpochMs == 0) {
      return true;
    }
    final key = '${envelope.entity}:${envelope.entityId}:${envelope.origin}';
    final previous = _latest[key];
    if (previous != null) {
      if (envelope.revision < previous.revision) return false;
      if (envelope.revision == previous.revision &&
          envelope.updatedAtEpochMs <= previous.updatedAtEpochMs) {
        return false;
      }
    }
    _latest[key] = (
      revision: envelope.revision,
      updatedAtEpochMs: envelope.updatedAtEpochMs,
    );
    return true;
  }
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
