import '../../nutrition/data/wear_sync_contract.dart';
import '../../../data/local/database.dart';

Map<String, dynamic> fastingPayloadFromSession(FastingSessionData? session) {
  return {
    'hasActiveFast': session != null,
    'phoneSessionId': session?.id.toString(),
    'startedAtEpochMs': session?.startedAt.millisecondsSinceEpoch,
    'targetSeconds': session?.targetSeconds ?? 16 * 60 * 60,
    'endedAtEpochMs': session?.endedAt?.millisecondsSinceEpoch,
    'completed': session?.completed ?? false,
  };
}

String encodeFastingSnapshot({
  required FastingSessionData? session,
  required int revision,
}) {
  final entityId = session?.id.toString() ?? 'fasting';
  return WearSyncEnvelope.wrap(
    entity: wearSyncEntityFasting,
    entityId: entityId,
    revision: revision,
    origin: wearSyncOriginPhone,
    payload: fastingPayloadFromSession(session),
  ).encode();
}
