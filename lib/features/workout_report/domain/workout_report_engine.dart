import 'package:herculex/features/workout_report/domain/workout_report.dart';

/// Deterministic facts and explicitly qualified coaching hypotheses.
/// No neural models, network calls, or mutation of the user's program.
abstract final class WorkoutReportEngine {
  static WorkoutReport evaluate(ReportInput input) {
    final facts = <ReportFinding>[];
    void add(
      String id,
      String title,
      String detail,
      String next, {
      ReportSupport support = ReportSupport.recorded,
      ReportTone tone = ReportTone.neutral,
      String? exercise,
      int chapter = 53,
    }) {
      facts.add(
        ReportFinding(
          ruleId: id,
          title: title,
          detail: detail,
          nextStep: next,
          support: support,
          tone: tone,
          exerciseName: exercise,
          chapter: chapter,
        ),
      );
    }

    final completed = input.exercises.fold<int>(0, (n, e) => n + e.sets.length);
    final context = input.context;
    if (context.pain == true || context.reason == ReportReason.pain) {
      add(
        'SAFETY-PAIN-03',
        'Pain deserves attention',
        'You reported pain. A performance or recovery score cannot explain its cause.',
        'Avoid the provoking movement. Seek qualified assessment if pain persists, worsens or radiates.',
        tone: ReportTone.caution,
        chapter: 35,
      );
    }
    if (input.planKnown && completed >= input.plannedSets && completed > 0) {
      add(
        'PLAN-COMPLETE',
        input.plannedSets < input.originalSets
            ? 'Adjusted workout completed'
            : 'Planned work completed',
        '$completed working sets completed against ${input.plannedSets} in the session plan.',
        'Keep the next session stable unless a repeated pattern calls for a change.',
        tone: ReportTone.positive,
        chapter: 52,
      );
    } else if (input.planKnown && completed < input.plannedSets) {
      add(
        'PLAN-PARTIAL',
        'Some planned work was left out',
        '$completed of ${input.plannedSets} working sets completed. Omitted work is not automatically failed work.',
        'Review which priorities remain covered; do not cram every missed set into the next workout.',
        chapter: 29,
      );
    } else if (!input.planKnown) {
      add(
        'DATA-PLAN-UNKNOWN',
        'Original plan unavailable',
        'This workout predates plan capture or has no fixed prescription. Completion cannot be scored against an original plan.',
        'Use the recorded work as a benchmark for future comparable sessions.',
        support: ReportSupport.unknown,
        chapter: 52,
      );
    }
    if (input.plannedSets < input.originalSets) {
      add(
        'VOLUME-REDUCED',
        'Volume was intentionally edited',
        '${input.originalSets - input.plannedSets} working sets were removed from the captured plan.',
        context.reason == ReportReason.fatigue
            ? 'A smaller session may reduce fatigue. Reassess at the next comparable exposure before restoring all optional work.'
            : 'Check muscle coverage below. A single shorter session does not require a full program redesign.',
        chapter: 9,
      );
    }
    if (context.reason == ReportReason.time) {
      add(
        'CONSTRAINT-TIME',
        'Time shaped this session',
        'You identified time as a reason for the changes.',
        'Keep priority lifts and adequate rest; trim lower-priority accessories or distribute work across visits.',
        chapter: 34,
      );
    }
    if (context.reason == ReportReason.equipment ||
        context.reason == ReportReason.preference) {
      add(
        'EXERCISE-EQUIPMENT-02',
        'A substitution can preserve the goal',
        'Your reported reason was ${context.reason!.name}. Loads on different machines or movements are not directly equivalent.',
        'Keep the intended muscle and movement role; establish the replacement’s own benchmark.',
        chapter: 54,
      );
    }
    var declines = 0;
    var progress = 0;
    for (final exercise in input.exercises) {
      final sets = exercise.sets;
      if (sets.isEmpty) continue;
      void finding(
        String id,
        String title,
        String detail,
        String next, {
        ReportSupport support = ReportSupport.recorded,
        ReportTone tone = ReportTone.neutral,
        int chapter = 53,
      }) => add(
        id,
        title,
        detail,
        next,
        support: support,
        tone: tone,
        exercise: exercise.name,
        chapter: chapter,
      );
      if (!exercise.repBased) {
        finding(
          'METRIC-SPECIFIC',
          'Use the movement’s own metric',
          'This movement is measured by time, distance or machine calories, rather than repetition tonnage.',
          'Compare the same duration, distance and setup; a lifting e1RM does not apply.',
          chapter: 51,
        );
        continue;
      }
      if (sets.any(
        (s) => !s.load.isFinite || s.load < 0 || s.reps <= 0 || s.reps > 1000,
      )) {
        finding(
          'DATA-INVALID',
          'Check the logged values',
          'Some set values are unsuitable for a strength comparison.',
          'Correct units or incomplete entries before drawing a performance conclusion.',
          support: ReportSupport.unknown,
        );
        continue;
      }
      if (context.techniqueChanged == true || exercise.newSetup) {
        finding(
          'COMPARISON-CHANGED',
          'A new benchmark is needed',
          'The setup, exercise or your reported technique changed. The prior result is not a like-for-like comparison.',
          'Repeat the new setup consistently before judging progression.',
          support: ReportSupport.unknown,
          chapter: 54,
        );
        continue;
      }
      final straight = sets.where((s) => s.standard).toList();
      if (straight.length != sets.length) {
        finding(
          'METHOD-NOT-EQUIVALENT',
          'Method affects comparison',
          'Advanced sets were recorded. A drop set or mini-set sequence is not an exact number of straight sets.',
          'Compare the same method separately and retain a straight-set benchmark.',
          chapter: 26,
        );
      }
      if (straight.isEmpty) continue;
      final first = straight.first;
      if (straight.length > 1 && first.reps > 0) {
        final last = straight.last;
        if (_sameLoad(first.load, last.load) && last.reps <= first.reps * 0.7) {
          finding(
            'SET-DROP-OFF',
            'Repetitions fell within the exercise',
            '${first.reps} repetitions on the first straight set and ${last.reps} on the last at comparable load. This alone does not identify a cause.',
            'Check actual rest and first-set effort before adding more sets.',
            support: ReportSupport.possible,
            chapter: 11,
          );
        }
      }
      if (first.rpe != null && first.rpe! >= 9.5) {
        finding(
          'EFFORT-EARLY-FAILURE',
          'High effort on the first set',
          'You logged the first straight set near maximal effort. That can affect later-set output.',
          'Test leaving a little more reserve while keeping load and setup comparable.',
          support: ReportSupport.possible,
          chapter: 10,
        );
      }
      if (straight.any(
        (s) =>
            s.targetRpe != null && s.rpe != null && s.rpe! > s.targetRpe! + 1,
      )) {
        finding(
          'EFFORT-ABOVE-PLAN',
          'Effort exceeded the target',
          'At least one recorded RPE was more than a point above its prescribed target.',
          'Review the loading increment and effort estimate; avoid increasing load and sets together.',
          chapter: 10,
        );
      }
      if (straight.any((s) => s.targetMin != null && s.reps < s.targetMin!)) {
        finding(
          'REPS-BELOW-TARGET',
          'Below the prescribed rep range',
          'At least one straight set ended below its planned lower rep boundary.',
          'Check load, setup and rest. One exposure is not a plateau.',
          chapter: 12,
        );
      }
      if (exercise.superset) {
        finding(
          'ORDER-SUPERSET',
          'Superset context matters',
          'This exercise was paired with other work. The log does not measure actual inter-set rest.',
          'If output keeps falling, test a noncompeting pairing or more rest.',
          support: ReportSupport.possible,
          chapter: 11,
        );
      }
      final benchmark = _best(straight, first.load);
      if (benchmark == null) continue;
      final comparable = exercise.previous
          .map(
            (p) => _best(p.where((s) => s.standard).toList(), benchmark.load),
          )
          .whereType<ReportSet>()
          .where((p) => _effortComparable(p, benchmark))
          .take(3)
          .toList();
      if (comparable.isEmpty) {
        finding(
          'DATA-NO-BASELINE',
          'First comparable benchmark',
          'There is no recent session with matching equipment, gym, setup, load and recorded effort.',
          'Keep this setup for future comparisons; avoid interpreting different machine loads as lost strength.',
          support: ReportSupport.unknown,
        );
      } else {
        final delta = benchmark.reps - comparable.first.reps;
        if (delta > 0) {
          progress++;
          finding(
            'PERFORMANCE-UP',
            'More repetitions at comparable load',
            '${benchmark.reps} repetitions versus ${comparable.first.reps} previously, with comparable recorded effort.',
            'Keep progressing within the rep range before taking the smallest practical load step.',
            support: ReportSupport.pattern,
            tone: ReportTone.positive,
          );
        } else if (delta <= -2) {
          declines++;
          final repeated =
              comparable.length >= 2 &&
              benchmark.reps < comparable[0].reps &&
              comparable[0].reps < comparable[1].reps;
          finding(
            repeated ? 'PERFORMANCE-REPEATED' : 'PERFORMANCE-DOWN',
            repeated
                ? 'A repeated decline is worth reviewing'
                : 'Fewer repetitions this time',
            '${benchmark.reps} versus ${comparable.first.reps} repetitions at comparable load and effort.',
            repeated
                ? 'Review sleep, food, rest and accumulated work. Test one change and reassess over the next one to three exposures.'
                : 'One lower result is ordinary variability. Recheck the next comparable session before changing the program.',
            support: repeated ? ReportSupport.pattern : ReportSupport.recorded,
          );
        } else if (comparable.length >= 2 &&
            comparable.every((p) => p.reps == benchmark.reps)) {
          finding(
            'PROGRESSION-PLATEAU-02',
            'A stable result needs context',
            'The benchmark is unchanged across at least three comparable exposures.',
            'Check adherence, setup, rest and recovery before adding local volume.',
            support: ReportSupport.pattern,
            chapter: 12,
          );
        }
        final allAtTop =
            straight.length >= exercise.plannedSets &&
            exercise.plannedSets > 0 &&
            straight.every(
              (s) =>
                  s.targetMax != null &&
                  s.reps >= s.targetMax! &&
                  s.rpe != null &&
                  s.targetRpe != null &&
                  s.rpe! <= s.targetRpe!,
            );
        final previous = exercise.previous.firstOrNull;
        if (allAtTop &&
            previous != null &&
            previous.length >= exercise.plannedSets &&
            previous.every(
              (s) =>
                  s.standard &&
                  _sameLoad(s.load, first.load) &&
                  s.targetMax != null &&
                  s.reps >= s.targetMax! &&
                  s.rpe != null &&
                  s.targetRpe != null &&
                  s.rpe! <= s.targetRpe!,
            )) {
          finding(
            'PROGRESSION-DOUBLE-01',
            'Ready to review the next load',
            'All prescribed sets reached the top of the range within the RPE target on two comparable exposures.',
            'If technique and range stayed consistent, use the smallest practical increase; repetitions may return toward the lower range.',
            support: ReportSupport.pattern,
            tone: ReportTone.positive,
            chapter: 12,
          );
        }
      }
    }
    if (declines >= 2 && context.unusualFatigue == true) {
      add(
        'RECOVERY-ADJUST-01',
        'Several benchmarks and fatigue align',
        'Multiple comparable exercises declined and you reported unusual fatigue. This does not diagnose CNS fatigue or overtraining.',
        'Consider a lower-stress session, then review sleep, nutrition and total work before restoring optional sets.',
        support: ReportSupport.possible,
        chapter: 28,
      );
    }
    if (declines > 0 && progress > 0) {
      add(
        'PERFORMANCE-LOCAL',
        'The change is not uniform',
        'Some comparable exercises improved while others declined.',
        'Check the affected exercise’s order, setup and overlap before increasing volume everywhere.',
        support: ReportSupport.pattern,
        chapter: 12,
      );
    }
    if (input.sleepHours != null &&
        (input.sleepHours! < 7 ||
            (input.usualSleepHours != null &&
                input.sleepHours! < input.usualSleepHours! - 1))) {
      add(
        'CONTEXT-SLEEP',
        'Shorter sleep is relevant context',
        '${input.sleepHours!.toStringAsFixed(1)} hours were recorded for the night before training. This cannot determine today’s strength or CNS percentage.',
        declines > 0
            ? 'Sleep may have contributed. Protect the next night and compare the next equivalent exposure.'
            : 'Keep the actual performance in view; one shorter night does not require cancelling the next workout.',
        support: ReportSupport.possible,
        chapter: 28,
      );
    }
    if (context.ateBefore == false) {
      add(
        'CONTEXT-FUEL',
        'No pre-workout meal was reported',
        'You reported not eating before training. That does not establish low glycogen or a carbohydrate deficiency.',
        input.minutes >= 60 || completed >= 20
            ? 'For a longer or higher-volume session, test a familiar pre-workout meal and compare under similar conditions.'
            : 'Review regular meals if you felt underfueled; a short session does not automatically require extra carbohydrate.',
        support: ReportSupport.possible,
        chapter: 31,
      );
    }
    if (context.stressed == true) {
      add(
        'CONTEXT-STRESS',
        'Unusual stress was reported',
        'Life stress is part of the session context, not a proven explanation for a particular set.',
        'Favor a manageable next session and change one variable at a time.',
        support: ReportSupport.possible,
        chapter: 27,
      );
    }
    for (final entry in input.priorMuscleSets.entries) {
      if (entry.value > 18) {
        add(
          'VOLUME-GUARD-03',
          '${entry.key}: review recent workload',
          '${entry.value} direct/primary working sets were logged before this session in the preceding seven days. Eighteen is a review heuristic, not a biological ceiling.',
          'Review recovery and comparable performance before adding more work.',
          support: ReportSupport.possible,
          chapter: 9,
        );
      }
    }
    if (completed == 0) {
      add(
        'DATA-EMPTY',
        'No working sets recorded',
        'There is no completed working-set performance to analyze.',
        'Check whether the session was a rest, technique-only session or has missing entries.',
        support: ReportSupport.unknown,
      );
    }
    // Safety first, then meaningful trends, positives, facts, contextual hypotheses.
    facts.sort((a, b) => _priority(a).compareTo(_priority(b)));
    return WorkoutReport(
      completedSets: completed,
      plannedSets: input.plannedSets,
      originalSets: input.originalSets,
      minutes: input.minutes,
      findings: facts,
      muscleChanges: input.muscleChanges,
      changes: input.changes,
      revision: input.revision,
    );
  }

  static bool _sameLoad(double a, double b) =>
      (a - b).abs() <= (a.abs() * .01).clamp(.01, 1);
  static bool _effortComparable(ReportSet a, ReportSet b) =>
      a.rpe != null && b.rpe != null && (a.rpe! - b.rpe!).abs() <= 1;
  static ReportSet? _best(List<ReportSet> sets, double load) {
    final eligible =
        sets
            .where((s) => _sameLoad(s.load, load) && s.reps > 0 && s.reps <= 20)
            .toList()
          ..sort((a, b) => b.reps.compareTo(a.reps));
    return eligible.firstOrNull;
  }

  static int _priority(ReportFinding f) {
    if (f.ruleId.startsWith('SAFETY')) return 0;
    if (f.ruleId == 'PERFORMANCE-REPEATED' ||
        f.ruleId == 'RECOVERY-ADJUST-01') {
      return 1;
    }
    if (f.tone == ReportTone.positive) return 2;
    if (f.ruleId.startsWith('PLAN') || f.ruleId == 'VOLUME-REDUCED') return 3;
    if (f.support == ReportSupport.pattern) return 4;
    if (f.ruleId.startsWith('CONTEXT')) return 5;
    return 6;
  }
}
