import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';

/// A stored weekly report row, as plain values.
///
/// The JSON columns stay raw strings: a row pulled from another device is
/// untrusted text, and decoding (behind try/catch) is the caller's job, so a
/// malformed row can never crash a read here (T-29-26).
class WeeklyReportRecord {
  const WeeklyReportRecord({
    required this.id,
    required this.week,
    required this.weekStartIso,
    required this.generatedAt,
    required this.payloadVersion,
    required this.payloadJson,
    required this.narrativeJson,
    required this.narrativeAttempts,
    required this.knowledgeVersion,
    required this.modelVersion,
    required this.tdeeDecision,
    required this.tdeeDecisionKcal,
    required this.viewedAt,
  });

  factory WeeklyReportRecord.fromRow(WeeklyReportData row) {
    return WeeklyReportRecord(
      id: row.id,
      week: IsoWeek(row.isoYear, row.isoWeek),
      weekStartIso: row.weekStartIso,
      generatedAt: row.generatedAt,
      payloadVersion: row.payloadVersion,
      payloadJson: row.payloadJson,
      narrativeJson: row.narrativeJson,
      narrativeAttempts: row.narrativeAttempts,
      knowledgeVersion: row.knowledgeVersion,
      modelVersion: row.modelVersion,
      tdeeDecision: row.tdeeDecision,
      tdeeDecisionKcal: row.tdeeDecisionKcal,
      viewedAt: row.viewedAt,
    );
  }

  final int id;
  final IsoWeek week;
  final String weekStartIso;
  final DateTime generatedAt;
  final int payloadVersion;
  final String payloadJson;
  final String? narrativeJson;
  final int narrativeAttempts;
  final String? knowledgeVersion;
  final String? modelVersion;
  final String? tdeeDecision;
  final int? tdeeDecisionKcal;
  final DateTime? viewedAt;
}

/// The only code that touches `weekly_reports` (D-01, RPT-04).
///
/// A past week must never change, so the payload is written exactly once, in
/// [insertSnapshot], and no other method can rewrite it. The narrative and the
/// TDEE decision are write-once (`... IS NULL` guards). One report per ISO week
/// is enforced here, inside the insert transaction, because the table has no
/// unique key (a cross-device duplicate must be tolerated on pull, plan 05);
/// reads and mutators therefore all pick one winner via [_pickWinner]: most
/// decided state first (TDEE decision, then narrative), then earliest
/// generatedAt, then syncUuid, then id. Tombstoned rows are never deleted
/// locally so their remote delete can still be pushed.
class WeeklyReportRepository {
  WeeklyReportRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  static const Set<String> decisions = {'updated', 'kept'};
  static const int minDecisionKcal = 800;
  static const int maxDecisionKcal = 6000;

  $WeeklyReportsTable get _t => _db.weeklyReports;

  /// Get-or-create the frozen snapshot for [week]. A live row is returned
  /// untouched; a week that only has soft-deleted rows is regenerable: a fresh
  /// row is inserted next to the tombstones, which are kept so their remote
  /// delete can still be pushed.
  Future<WeeklyReportRecord> insertSnapshot({
    required IsoWeek week,
    required int payloadVersion,
    required String payloadJson,
  }) {
    return _db.transaction(() async {
      final existing = await _rowsForWeek(week).get();
      for (final row in existing) {
        if (row.deletedAt == null) return WeeklyReportRecord.fromRow(row);
      }
      final id = await _db
          .into(_t)
          .insert(
            WeeklyReportsCompanion(
              isoYear: Value(week.isoYear),
              isoWeek: Value(week.isoWeek),
              weekStartIso: Value(week.startIso),
              payloadVersion: Value(payloadVersion),
              payloadJson: Value(payloadJson),
              generatedAt: Value(_clock.now()),
            ),
          );
      final row = await (_db.select(
        _t,
      )..where((t) => t.id.equals(id))).getSingle();
      return WeeklyReportRecord.fromRow(row);
    });
  }

  Future<WeeklyReportRecord?> forWeek(IsoWeek week) async {
    final winner = _pickWinner(await _liveForWeek(week).get());
    return winner == null ? null : WeeklyReportRecord.fromRow(winner);
  }

  Stream<WeeklyReportRecord?> watchWeek(IsoWeek week) =>
      _liveForWeek(week).watch().map((rows) {
        final winner = _pickWinner(rows);
        return winner == null ? null : WeeklyReportRecord.fromRow(winner);
      });

  /// Newest week first; soft-deleted rows excluded; one record per week (the
  /// winner per [_pickWinner] when duplicates exist).
  Stream<List<WeeklyReportRecord>> watchHistory() {
    final query = _db.select(_t)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.isoYear),
        (t) => OrderingTerm.desc(t.isoWeek),
        (t) => OrderingTerm.asc(t.generatedAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return query.watch().map((rows) {
      final groups = <IsoWeek, List<WeeklyReportData>>{};
      for (final row in rows) {
        groups
            .putIfAbsent(IsoWeek(row.isoYear, row.isoWeek), () => [])
            .add(row);
      }
      // Rows arrive newest week first, and map keys keep insertion order.
      return [
        for (final group in groups.values)
          WeeklyReportRecord.fromRow(_pickWinner(group)!),
      ];
    });
  }

  /// Increments the attempt counter atomically and returns the new value (0
  /// when the week has no live row). Callers increment BEFORE firing the AI
  /// call so a crash mid-call cannot cause a free retry loop.
  Future<int> incrementNarrativeAttempts(IsoWeek week) {
    return _db.transaction(() async {
      final row = await _winnerLive(week);
      if (row == null) return 0;
      final next = row.narrativeAttempts + 1;
      await (_db.update(_t)..where((t) => t.id.equals(row.id))).write(
        WeeklyReportsCompanion(narrativeAttempts: Value(next)),
      );
      return next;
    });
  }

  /// Stores the narrative once. Returns false when it was already set (or the
  /// week has no live row). Writes only the narrative and its provenance.
  Future<bool> saveNarrative(
    IsoWeek week, {
    required String narrativeJson,
    String? knowledgeVersion,
    String? modelVersion,
  }) {
    return _db.transaction(() async {
      final row = await _winnerLive(week);
      if (row == null) return false;
      final changed =
          await (_db.update(_t)
                ..where((t) => t.id.equals(row.id) & t.narrativeJson.isNull()))
              .write(
                WeeklyReportsCompanion(
                  narrativeJson: Value(narrativeJson),
                  knowledgeVersion: Value(knowledgeVersion),
                  modelVersion: Value(modelVersion),
                ),
              );
      return changed > 0;
    });
  }

  /// Records the user's TDEE decision once. Vocabulary and range are checked
  /// before anything is written.
  Future<bool> recordTdeeDecision(
    IsoWeek week, {
    required String decision,
    int? kcal,
  }) {
    _validateDecision(decision, kcal);
    return _db.transaction(() async {
      final row = await _winnerLive(week);
      if (row == null) return false;
      final changed =
          await (_db.update(
            _t,
          )..where((t) => t.id.equals(row.id) & t.tdeeDecision.isNull())).write(
            WeeklyReportsCompanion(
              tdeeDecision: Value(decision),
              tdeeDecisionKcal: Value(kcal),
            ),
          );
      return changed > 0;
    });
  }

  static void _validateDecision(String decision, int? kcal) {
    if (!decisions.contains(decision)) {
      throw ArgumentError.value(
        decision,
        'decision',
        "must be 'updated'/'kept'",
      );
    }
    if (kcal != null && (kcal < minDecisionKcal || kcal > maxDecisionKcal)) {
      throw ArgumentError.value(
        kcal,
        'kcal',
        'must be in $minDecisionKcal..$maxDecisionKcal',
      );
    }
  }

  /// Records the TDEE decision and, in the SAME transaction, runs
  /// [beforeRecord] (the nutrition target write). This is the only atomic
  /// target-plus-decision path: callers pass the target write as
  /// [beforeRecord]. Returns false, having written nothing, when the week has
  /// no live row or already has a decision ([beforeRecord] is then never
  /// called). If the callback or the decision write fails, everything rolls
  /// back; a callback exception propagates unchanged.
  Future<bool> applyTdeeDecision(
    IsoWeek week, {
    required String decision,
    int? kcal,
    Future<void> Function()? beforeRecord,
  }) async {
    _validateDecision(decision, kcal);
    try {
      return await _db.transaction(() async {
        final row = await _winnerLive(week);
        if (row == null || row.tdeeDecision != null) return false;
        if (beforeRecord != null) await beforeRecord();
        final changed =
            await (_db.update(_t)
                  ..where((t) => t.id.equals(row.id) & t.tdeeDecision.isNull()))
                .write(
                  WeeklyReportsCompanion(
                    tdeeDecision: Value(decision),
                    tdeeDecisionKcal: Value(kcal),
                  ),
                );
        if (changed == 0) throw const _DecisionNotRecorded();
        return true;
      });
    } on _DecisionNotRecorded {
      return false;
    }
  }

  /// Sets viewedAt to now, only when it is still null.
  Future<void> markViewed(IsoWeek week) {
    return _db.transaction(() async {
      final row = await _winnerLive(week);
      if (row == null) return;
      await (_db.update(_t)
            ..where((t) => t.id.equals(row.id) & t.viewedAt.isNull()))
          .write(WeeklyReportsCompanion(viewedAt: Value(_clock.now())));
    });
  }

  /// All rows (live or tombstoned) for the week, earliest first.
  SimpleSelectStatement<$WeeklyReportsTable, WeeklyReportData> _rowsForWeek(
    IsoWeek week,
  ) {
    return _db.select(_t)
      ..where(
        (t) => t.isoYear.equals(week.isoYear) & t.isoWeek.equals(week.isoWeek),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.generatedAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
  }

  SimpleSelectStatement<$WeeklyReportsTable, WeeklyReportData> _liveForWeek(
    IsoWeek week,
  ) {
    return _db.select(_t)
      ..where(
        (t) =>
            t.isoYear.equals(week.isoYear) &
            t.isoWeek.equals(week.isoWeek) &
            t.deletedAt.isNull(),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.generatedAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
  }

  /// The one row every read and mutator agrees on among live duplicates.
  static WeeklyReportData? _pickWinner(List<WeeklyReportData> rows) {
    WeeklyReportData? best;
    for (final row in rows) {
      if (row.deletedAt != null) continue;
      if (best == null || _compare(row, best) < 0) best = row;
    }
    return best;
  }

  static int _compare(WeeklyReportData a, WeeklyReportData b) {
    final decided = (b.tdeeDecision != null ? 1 : 0).compareTo(
      a.tdeeDecision != null ? 1 : 0,
    );
    if (decided != 0) return decided;
    final narrated = (b.narrativeJson != null ? 1 : 0).compareTo(
      a.narrativeJson != null ? 1 : 0,
    );
    if (narrated != 0) return narrated;
    final byTime = a.generatedAt.compareTo(b.generatedAt);
    if (byTime != 0) return byTime;
    final byUuid = (a.syncUuid ?? '').compareTo(b.syncUuid ?? '');
    if (byUuid != 0) return byUuid;
    return a.id.compareTo(b.id);
  }

  Future<WeeklyReportData?> _winnerLive(IsoWeek week) async {
    return _pickWinner(await _liveForWeek(week).get());
  }
}

/// Thrown inside [WeeklyReportRepository.applyTdeeDecision] to roll the
/// transaction back when the guarded decision update changed no row.
class _DecisionNotRecorded implements Exception {
  const _DecisionNotRecorded();
}
