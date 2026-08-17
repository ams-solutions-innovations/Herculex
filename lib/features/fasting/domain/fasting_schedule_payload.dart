const String _prefix = 'fasting_schedule:';

/// Notification payload for a fasting-schedule "notify to start" reminder —
/// just the row id, prefixed so the app-wide notification dispatcher in
/// `workout_notification_service.dart` can route a default tap here instead
/// of down the workout path, without importing fasting types.
String fastingSchedulePayload(int scheduleId) => '$_prefix$scheduleId';

/// Inverse of [fastingSchedulePayload]. Returns null for any other payload
/// shape (including null/empty), so the dispatcher can treat that as "not a
/// fasting-schedule notification" and fall through to its other paths.
int? fastingScheduleIdFromPayload(String? payload) {
  if (payload == null || !payload.startsWith(_prefix)) return null;
  return int.tryParse(payload.substring(_prefix.length));
}
