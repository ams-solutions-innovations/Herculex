import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// The 7-day check-in cap (D-13), in local calendar days so a DST change
/// cannot make day 7 early or late. The repository is the enforced gate.
abstract final class CheckInCapPolicy {
  static DateTime? nextEligibleDate(DateTime? lastCheckInAt) {
    if (lastCheckInAt == null) return null;
    return DateTime(
      lastCheckInAt.year,
      lastCheckInAt.month,
      lastCheckInAt.day + PhysiqueTuning.checkInWindowDays,
    );
  }

  static bool isEligible({required DateTime now, DateTime? lastCheckInAt}) {
    final next = nextEligibleDate(lastCheckInAt);
    if (next == null) return true;
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(next);
  }
}
