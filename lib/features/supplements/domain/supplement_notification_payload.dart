abstract final class SupplementNotificationActionIds {
  static const done = 'supplement_action_done';
  static const snooze30 = 'supplement_action_snooze_30';
  static const snooze60 = 'supplement_action_snooze_60';
}

const String _supplementPrefix = 'supplement:';

/// Builds the notification payload string for a supplement reminder.
String supplementNotificationPayload(String supplementId) =>
    '$_supplementPrefix$supplementId';

/// Extracts the supplement ID from a notification payload, or returns null
/// if [payload] does not belong to a supplement notification.
String? supplementIdFromPayload(String? payload) {
  if (payload == null || !payload.startsWith(_supplementPrefix)) return null;
  final id = payload.substring(_supplementPrefix.length);
  return id.isEmpty ? null : id;
}

/// Returns true if [payload] belongs to a supplement notification.
bool isSupplementPayload(String? payload) =>
    payload != null && payload.startsWith(_supplementPrefix);
