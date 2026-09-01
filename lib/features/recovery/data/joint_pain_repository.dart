import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../domain/joint_model.dart';

/// A joint's current flagged/resolved state, derived from its most recent
/// [JointPainLogs] rows.
class JointPainStatus {
  final String joint;

  /// 0 = not flagged. 1–3 = mild/moderate/severe.
  final int severity;

  /// Start of the current contiguous flagged streak — null when not
  /// flagged. Distinct from when the joint was first *ever* flagged: a
  /// resolve-then-reflag starts a new streak.
  final DateTime? flaggedSince;
  final String? note;

  const JointPainStatus({
    required this.joint,
    required this.severity,
    this.flaggedSince,
    this.note,
  });

  bool get isFlagged => severity > 0;
}

/// Event log of joint-pain status changes — see [JointPainLogs]'s doc
/// comment for why this is insert-only rather than update-in-place. Shaped
/// like [CycleRepository]: a thin Drift wrapper, no business logic beyond
/// deriving "current status" from history.
class JointPainRepository {
  final AppDatabase _db;

  JointPainRepository(this._db);

  Future<void> setStatus({
    required String joint,
    required int severity,
    String? note,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    await _db
        .into(_db.jointPainLogs)
        .insert(
          JointPainLogsCompanion.insert(
            dateIso: _formatDateIso(now),
            loggedAt: Value(now),
            joint: joint,
            severity: Value(severity),
            note: Value(note),
          ),
        );
  }

  Future<void> clear(String joint, {DateTime? at}) =>
      setStatus(joint: joint, severity: 0, at: at);

  Stream<Map<String, JointPainStatus>> watchCurrentStatuses() {
    final query = _db.select(_db.jointPainLogs)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.loggedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query.watch().map(_deriveStatuses);
  }

  Map<String, JointPainStatus> _deriveStatuses(List<JointPainLogData> rows) {
    // `rows` is newest-first across every joint; grouping preserves that
    // relative order within each joint's own history.
    final byJoint = <String, List<JointPainLogData>>{};
    for (final row in rows) {
      byJoint.putIfAbsent(row.joint, () => []).add(row);
    }
    return {
      for (final joint in JointModel.joints)
        joint: _statusFor(joint, byJoint[joint] ?? const []),
    };
  }

  JointPainStatus _statusFor(String joint, List<JointPainLogData> history) {
    if (history.isEmpty || history.first.severity == 0) {
      return JointPainStatus(joint: joint, severity: 0);
    }
    // Walk backward through the contiguous run of non-zero rows to find
    // where the current streak started.
    var since = history.first.loggedAt;
    for (var i = 1; i < history.length && history[i].severity != 0; i++) {
      since = history[i].loggedAt;
    }
    return JointPainStatus(
      joint: joint,
      severity: history.first.severity,
      flaggedSince: since,
      note: history.first.note,
    );
  }

  String _formatDateIso(DateTime dt) =>
      "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
}
