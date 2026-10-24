part of '../weekly_adaptation_repository.dart';

extension _ProposalInputs on WeeklyAdaptationRepository {
  Future<Map<String, String>> _musclePriorities(int programId) async {
    final brief =
        await (_db.select(_db.herculexAiProgramBriefs)
              ..where(
                (b) =>
                    b.programId.equals(programId) &
                    b.active.equals(true) &
                    b.deletedAt.isNull(),
              )
              ..orderBy([(b) => OrderingTerm.desc(b.confirmedAt)])
              ..limit(1))
            .getSingleOrNull();
    final profile =
        await (_db.select(_db.physiqueProgrammingProfiles)
              ..where((p) => p.active.equals(true) & p.deletedAt.isNull())
              ..orderBy([(p) => OrderingTerm.desc(p.confirmedAt)])
              ..limit(1))
            .getSingleOrNull();
    try {
      final raw = jsonDecode(
        brief?.briefJson ?? profile?.prioritiesJson ?? '{}',
      );
      final list = raw is Map ? raw['musclePriorities'] : null;
      if (list is! List) {
        return {};
      }
      return {
        for (final p in list.whereType<Map>())
          if (p['muscleId'] is String && p['priority'] is String)
            (p['muscleId'] as String).toLowerCase().replaceAll(
              RegExp('[^a-z]'),
              '',
            ): p['priority'] as String,
      };
    } on FormatException {
      return {};
    }
  }

  double _exercisePriority(
    PlannedExerciseSnapshot exercise,
    Map<String, double> credit,
    String goal,
    Map<String, String> priorities,
  ) {
    final main = exercise.slotRole == 'main';
    final secondary = exercise.slotRole == 'secondary';
    final role = switch (goal) {
      'strength' =>
        main
            ? 3.0
            : secondary
            ? 2.0
            : 0.8,
      'powerbuilding' || 'athletic' =>
        main
            ? 2.5
            : secondary
            ? 1.5
            : 1.0,
      _ => main ? 1.25 : 1.0,
    };
    var muscleWeight = 1.0;
    for (final muscle in credit.keys) {
      final priority =
          priorities[muscle.toLowerCase().replaceAll(RegExp('[^a-z]'), '')];
      muscleWeight = math.max(muscleWeight, switch (priority) {
        'high' || 'prioritize' || 'focus' => 3.0,
        'medium' => 2.0,
        _ => 1.0,
      });
    }
    return role * muscleWeight;
  }

  Future<void> _expireOtherProposals(
    int sourceId,
    AdaptationTrigger trigger,
    String fingerprint,
  ) async {
    await (_db.update(_db.adaptationProposals)..where(
          (p) =>
              p.sourceScheduleId.equals(sourceId) &
              p.trigger.equals(trigger.name) &
              p.decision.equals('proposed') &
              p.inputFingerprint.equals(fingerprint).not() &
              p.deletedAt.isNull(),
        ))
        .write(
          AdaptationProposalsCompanion(
            decision: const Value('expired'),
            decidedAt: Value(_clock.now()),
          ),
        );
  }

  Future<void> _revalidateProposal(int id) async {
    final row = await (_db.select(
      _db.adaptationProposals,
    )..where((p) => p.id.equals(id))).getSingle();
    if (row.decision == AdaptationDecision.accepted.name) {
      return;
    }
    if (row.decision != AdaptationDecision.proposed.name) {
      throw const AdaptationStaleException();
    }
    if (row.deletedAt != null || row.sourceScheduleId == null) {
      throw const AdaptationStaleException();
    }
    if (row.trigger == AdaptationTrigger.lowRecovery.name) {
      final source = await (_db.select(
        _db.scheduledWorkouts,
      )..where((s) => s.id.equals(row.sourceScheduleId!))).getSingleOrNull();
      if (source == null) {
        throw const AdaptationStaleException();
      }
      final plan = await PlannedSessionResolver(
        _db,
      ).resolveScheduledWorkout(source);
      if (!row.inputFingerprint.endsWith(_adaptedPlan(plan).encode())) {
        throw const AdaptationStaleException();
      }
      return;
    }
    final fresh = await _propose(
      scheduleId: row.sourceScheduleId!,
      trigger: AdaptationTrigger.values.byName(row.trigger),
      sourceSessionId: row.sourceSessionId,
    );
    if (fresh == null || fresh.id != id) {
      await (_db.update(
        _db.adaptationProposals,
      )..where((p) => p.id.equals(id))).write(
        AdaptationProposalsCompanion(
          decision: const Value('expired'),
          decidedAt: Value(_clock.now()),
        ),
      );
      throw const AdaptationStaleException();
    }
  }
}
