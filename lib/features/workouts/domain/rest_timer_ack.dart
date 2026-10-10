import 'dart:convert';

/// The watch's answer to a rest timer it was sent: did it really arm an alert
/// that will fire on time?
///
/// Transport success (`MessageClient.sendMessage` completing) only proves the
/// message reached the watch's radio, not that the watch will buzz. The phone
/// therefore keeps its own end-of-rest notification until it has read an ack
/// with [armed] set, and only then withdraws it.
class RestTimerAck {
  const RestTimerAck({
    required this.endsAtEpochMs,
    required this.armed,
    required this.reason,
    this.rev,
  });

  /// Revision of the rest timer message this answers; null from a watch build
  /// that predates revisions.
  final int? rev;
  final int endsAtEpochMs;

  /// True only when an exact alarm is set and notifications are allowed.
  final bool armed;

  /// Why the watch is or is not armed (`exact`, `inexact`,
  /// `notifications_denied`, `alarm_failed`), for logs.
  final String reason;

  /// Returns null for anything that is not a well-formed ack, so a corrupt or
  /// unrelated payload can never withdraw a notification.
  static RestTimerAck? tryParse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      final endsAt = decoded['endsAtEpochMs'];
      final armed = decoded['armed'];
      if (endsAt is! num || armed is! bool) return null;
      final rev = decoded['rev'];
      return RestTimerAck(
        endsAtEpochMs: endsAt.toInt(),
        armed: armed,
        reason: decoded['reason'] as String? ?? '',
        rev: rev is num && rev > 0 ? rev.toInt() : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Whether the phone should drop its own "rest is over" notification now.
///
/// Every condition must hold, and each guards a distinct way of losing the
/// alert altogether:
///  * [alertEnabled] and [watchFollowsWorkout]: the user wants the alert and
///    the watch is part of this workout, so it is not merely a connected
///    stranger.
///  * `ack.armed`: the watch can really deliver it, on time.
///  * the ack answers the timer that is running *now* ([sentRev] when both
///    sides have a revision, otherwise the end time). An ack for a rest that
///    was since skipped or extended says nothing about the current one.
///  * [now] is before the end: an ack that arrives after the phone's own alert
///    is due would only remove a notification the user may not have seen yet.
bool shouldWithdrawPhoneRestAlert({
  required RestTimerAck ack,
  required int? sentRev,
  required int? sentEndsAtMs,
  required bool alertEnabled,
  required bool watchFollowsWorkout,
  required DateTime now,
}) {
  if (!alertEnabled || !watchFollowsWorkout || !ack.armed) return false;
  if (sentEndsAtMs == null || sentEndsAtMs <= 0) return false;
  final answersCurrentTimer = ack.rev != null && sentRev != null
      ? ack.rev == sentRev
      : ack.endsAtEpochMs == sentEndsAtMs;
  if (!answersCurrentTimer) return false;
  return now.millisecondsSinceEpoch < sentEndsAtMs;
}
