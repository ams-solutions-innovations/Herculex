import '../../nutrition/data/wear_sync_contract.dart';
import '../../../data/local/database.dart';

Map<String, dynamic> fastingPayloadFromSession(FastingSessionData? session, {FastingSessionData? lastSession}) {
  return {
    'hasActiveFast': session != null,
    'phoneSessionId': session?.id.toString(),
    'startedAtEpochMs': session?.startedAt.millisecondsSinceEpoch,
    'targetSeconds': session?.targetSeconds ?? 16 * 60 * 60,
    'endedAtEpochMs': session?.endedAt?.millisecondsSinceEpoch,
    'completed': session?.completed ?? false,
    'lastFastDurationSeconds': lastSession != null && lastSession.endedAt != null 
        ? lastSession.endedAt!.difference(lastSession.startedAt).inSeconds 
        : null,
  };
}

String encodeFastingSnapshot({
  required FastingSessionData? session,
  FastingSessionData? lastSession,
  required int revision,
}) {
  final entityId = session?.id.toString() ?? 'fasting';
  return WearSyncEnvelope.wrap(
    entity: wearSyncEntityFasting,
    entityId: entityId,
    revision: revision,
    origin: wearSyncOriginPhone,
    payload: fastingPayloadFromSession(session, lastSession: lastSession),
  ).encode();
}
