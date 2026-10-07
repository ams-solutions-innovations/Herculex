import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';

/// Database-backed source of [DreamPhysiqueAnalysisSummary] (the model the
/// existing Dream Physique consumers read), built from the physique tables.
///
/// Not wired into any provider yet; the providers are switched together with
/// the Dream Physique save path so the view never writes SharedPreferences
/// while providers read the database.
class PhysiqueSummaryBridge {
  PhysiqueSummaryBridge(this._db);

  final AppDatabase _db;

  JoinedSelectStatement<HasResultSet, dynamic> _query({
    bool activeOnly = false,
  }) {
    final a = _db.physiqueAssessments;
    final g = _db.physiqueGoals;
    final q = _db.select(a).join([innerJoin(g, g.id.equalsExp(a.goalId))]);
    var where =
        a.kind.equals('analysis') & a.deletedAt.isNull() & g.deletedAt.isNull();
    if (activeOnly) where = where & g.status.equals('active');
    q
      ..where(where)
      ..orderBy([OrderingTerm.desc(a.assessedAt), OrderingTerm.desc(a.id)]);
    return q;
  }

  DreamPhysiqueAnalysisSummary? _map(TypedResult row) {
    final a = row.readTable(_db.physiqueAssessments);
    final g = row.readTable(_db.physiqueGoals);
    final json = a.summaryJson;
    if (json != null) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is! Map) return null;
        return DreamPhysiqueAnalysisSummary.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      } catch (_) {
        return null;
      }
    }
    final months = g.estimatedMonths;
    final target = g.targetBfPercent;
    if (months == null || target == null) return null;
    return DreamPhysiqueAnalysisSummary(
      schemaVersion: DreamPhysiqueAnalysisSummary.currentSchemaVersion,
      analyzedAt: a.assessedAt.toUtc(),
      targetAestheticStyle: g.targetAestheticStyle,
      timeframeRange: g.timeframeRange,
      estimatedMonths: months,
      targetBfPercent: target,
      currentEstimatedBf: a.currentBfPercent ?? 0,
      weightChangeKg: 0,
      currentPhotoCount: 0,
      targetPhotoCount: 0,
    );
  }

  List<DreamPhysiqueAnalysisSummary> _mapAll(List<TypedResult> rows) => [
    for (final r in rows) ?_map(r),
  ];

  /// Newest analysis of the active goal, or null.
  Stream<DreamPhysiqueAnalysisSummary?> watchCurrent() =>
      _query(activeOnly: true).watch().map((rows) {
        final all = _mapAll(rows);
        return all.isEmpty ? null : all.first;
      });

  /// Every analysis across all goals, newest first.
  Stream<List<DreamPhysiqueAnalysisSummary>> watchHistory() =>
      _query().watch().map(_mapAll);
}
