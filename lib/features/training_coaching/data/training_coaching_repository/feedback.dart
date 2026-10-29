part of '../training_coaching_repository.dart';

class CoachingTrialFeedback {
  const CoachingTrialFeedback(this.sessionId, this.before, this.after);
  final int sessionId;
  final ReportContext before, after;
  bool? get fatigueBefore =>
      before.reason == ReportReason.fatigue ? true : before.unusualFatigue;
  bool? get fatigueAfter =>
      after.reason == ReportReason.fatigue ? true : after.unusualFatigue;
  bool get pain => after.pain == true || after.reason == ReportReason.pain;
}

extension CoachingFeedback on TrainingCoachingRepository {
  /// Health context stays in the existing private local reports.
  Future<CoachingTrialFeedback?> _feedback(int id) async {
    final proposal = await (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.id.equals(id))).getSingle();
    final overrides = await (db.select(
      db.trainingCoachingOverrides,
    )..where((o) => o.proposalId.equals(id))).get();
    final schedules =
        await (db.select(db.scheduledWorkouts)
              ..where(
                (s) =>
                    s.id.isIn(overrides.map((o) => o.scheduleId)) &
                    s.completedSessionId.isNotNull() &
                    s.deletedAt.isNull(),
              )
              ..orderBy([(s) => OrderingTerm.desc(s.dateIso)]))
            .get();
    for (final schedule in schedules) {
      final session =
          await (db.select(db.workoutSessions)..where(
                (s) =>
                    s.id.equals(schedule.completedSessionId!) &
                    s.endedAt.isNotNull() &
                    s.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (session == null) continue;
      final reports = WorkoutReportRepository(db, clock);
      final before = proposal.sourceSessionId == null
          ? const ReportContext()
          : await reports.contextFor(proposal.sourceSessionId!);
      return CoachingTrialFeedback(
        session.id,
        before,
        await reports.contextFor(session.id),
      );
    }
    return null;
  }

  Future<void> _saveFeedback(
    int id, {
    required bool tiring,
    bool pain = false,
  }) async {
    final current = await feedback(id);
    if (current == null)
      throw StateError('Complete a trial workout before adding feedback.');
    final old = current.after;
    await WorkoutReportRepository(db, clock).saveContext(
      current.sessionId,
      ReportContext(
        reason: old.reason,
        ateBefore: old.ateBefore,
        stressed: old.stressed,
        unusualFatigue: tiring,
        pain: pain || old.pain == true,
        techniqueChanged: old.techniqueChanged,
      ),
    );
  }

  /// Creates a draft only. Applying the revised trial still requires a preview
  /// and confirmation, and supersedes the previous trial atomically.
  Future<int> _adjustTrial(int id, {int? targetSets}) async {
    final old = await (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.id.equals(id))).getSingle();
    if (old.status != 'review')
      throw StateError('Review a completed trial before revising it.');
    if ((await feedback(id))?.pain == true)
      throw StateError(
        'Review the provoking movement before prescribing another trial.',
      );
    final raw = Map<String, dynamic>.from(jsonDecode(old.payloadJson) as Map);
    final signalJson = Map<String, dynamic>.from(raw['signal'] as Map);
    if (targetSets != null) {
      final original =
          (signalJson['exercise'] as Map?)?['planned'] as int? ?? 0;
      if (targetSets < 1 || targetSets >= original)
        throw StateError(
          'Choose a smaller working-set target than the original prescription.',
        );
      signalJson['targetSets'] = targetSets;
    }
    final key = 'adjustment:${old.syncUuid}:${const Uuid().v4()}';
    return db
        .into(db.trainingCoachingProposals)
        .insert(
          TrainingCoachingProposalsCompanion.insert(
            programId: Value(old.programId),
            sourceSessionId: Value(old.sourceSessionId),
            kind: old.kind,
            proposalKey: key,
            payloadJson: jsonEncode({
              'signal': signalJson,
              'manualAdjustment': true,
              'adjusts': old.syncUuid,
            }),
            createdAt: clock.now(),
          ),
        );
  }
}
