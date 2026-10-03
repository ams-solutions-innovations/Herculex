/// Static payload carried by the weekly report notification.
///
/// A repeating `dayOfWeekAndTime` schedule has exactly one payload for every
/// fire, so unlike the fasting helper this is a constant rather than an
/// id-carrying prefix. The target week is resolved at tap time with
/// `IsoWeek.forNotificationTap`.
const String weeklyReportNotificationPayload = 'weekly_report';

/// True only for the exact weekly report payload.
bool isWeeklyReportPayload(String? payload) =>
    payload == weeklyReportNotificationPayload;
