import 'dart:convert';

enum ReportReason { time, fatigue, pain, equipment, preference }

enum ReportSupport { recorded, pattern, possible, unknown }

enum ReportTone { positive, neutral, caution }

class ReportContext {
  const ReportContext({
    this.reason,
    this.ateBefore,
    this.stressed,
    this.unusualFatigue,
    this.pain,
    this.techniqueChanged,
  });
  final ReportReason? reason;
  final bool? ateBefore, stressed, unusualFatigue, pain, techniqueChanged;
  Map<String, Object?> toJson() => {
    'reason': reason?.name,
    'ateBefore': ateBefore,
    'stressed': stressed,
    'unusualFatigue': unusualFatigue,
    'pain': pain,
    'techniqueChanged': techniqueChanged,
  };
  factory ReportContext.fromJson(Map<String, dynamic> json) => ReportContext(
    reason: ReportReason.values
        .where((r) => r.name == json['reason'])
        .firstOrNull,
    ateBefore: json['ateBefore'] as bool?,
    stressed: json['stressed'] as bool?,
    unusualFatigue: json['unusualFatigue'] as bool?,
    pain: json['pain'] as bool?,
    techniqueChanged: json['techniqueChanged'] as bool?,
  );
}

class ReportFinding {
  const ReportFinding({
    required this.ruleId,
    required this.title,
    required this.detail,
    required this.nextStep,
    required this.support,
    this.tone = ReportTone.neutral,
    this.exerciseName,
    this.chapter = 53,
  });
  final String ruleId, title, detail, nextStep;
  final String? exerciseName;
  final ReportSupport support;
  final ReportTone tone;
  final int chapter;
  Map<String, Object?> toJson() => {
    'ruleId': ruleId,
    'title': title,
    'detail': detail,
    'nextStep': nextStep,
    'support': support.name,
    'tone': tone.name,
    'exerciseName': exerciseName,
    'chapter': chapter,
  };
  factory ReportFinding.fromJson(Map<String, dynamic> j) => ReportFinding(
    ruleId: j['ruleId'] as String,
    title: j['title'] as String,
    detail: j['detail'] as String,
    nextStep: j['nextStep'] as String,
    support: ReportSupport.values.byName(j['support'] as String),
    tone: ReportTone.values.byName(j['tone'] as String),
    exerciseName: j['exerciseName'] as String?,
    chapter: j['chapter'] as int,
  );
}

class WorkoutReport {
  const WorkoutReport({
    required this.completedSets,
    required this.plannedSets,
    required this.originalSets,
    required this.minutes,
    required this.findings,
    required this.muscleChanges,
    required this.changes,
    this.revision = 1,
    this.engineVersion = '1',
    this.rulesVersion = 'blueprint-2-report-1',
  });
  final int completedSets, plannedSets, originalSets, minutes, revision;
  final String engineVersion, rulesVersion;
  final List<ReportFinding> findings;
  final Map<String, int> muscleChanges;
  final List<String> changes;
  List<ReportFinding> get highlights => findings.take(3).toList();
  bool get hasPerformanceDecline => findings.any(
    (f) => f.ruleId == 'PERFORMANCE-DOWN' || f.ruleId == 'PERFORMANCE-REPEATED',
  );
  String encode() => jsonEncode({
    'payloadVersion': 1,
    'completedSets': completedSets,
    'plannedSets': plannedSets,
    'originalSets': originalSets,
    'minutes': minutes,
    'revision': revision,
    'engineVersion': engineVersion,
    'rulesVersion': rulesVersion,
    'findings': findings.map((f) => f.toJson()).toList(),
    'muscleChanges': muscleChanges,
    'changes': changes,
  });
  static WorkoutReport decode(String value) {
    final j = jsonDecode(value) as Map<String, dynamic>;
    if (j['payloadVersion'] != 1) {
      throw const FormatException('Unknown report version');
    }
    return WorkoutReport(
      completedSets: j['completedSets'] as int,
      plannedSets: j['plannedSets'] as int,
      originalSets: j['originalSets'] as int,
      minutes: j['minutes'] as int,
      revision: j['revision'] as int,
      engineVersion: j['engineVersion'] as String,
      rulesVersion: j['rulesVersion'] as String,
      findings: (j['findings'] as List)
          .map(
            (f) => ReportFinding.fromJson(Map<String, dynamic>.from(f as Map)),
          )
          .toList(),
      muscleChanges: Map<String, int>.from(j['muscleChanges'] as Map),
      changes: List<String>.from(j['changes'] as List),
    );
  }
}

class ReportSet {
  const ReportSet({
    required this.load,
    required this.reps,
    this.rpe,
    this.targetMin,
    this.targetMax,
    this.targetRpe,
    this.standard = true,
  });
  final double load;
  final int reps;
  final double? rpe, targetRpe;
  final int? targetMin, targetMax;
  final bool standard;
}

class ReportExercise {
  const ReportExercise({
    required this.name,
    required this.muscle,
    required this.sets,
    required this.previous,
    this.repBased = true,
    this.newSetup = false,
    this.superset = false,
    this.plannedSets = 0,
  });
  final String name, muscle;
  final List<ReportSet> sets;

  /// Comparable sessions, newest first, always before the current session.
  final List<List<ReportSet>> previous;
  final bool repBased, newSetup, superset;
  final int plannedSets;
}

class ReportInput {
  const ReportInput({
    required this.exercises,
    required this.plannedSets,
    required this.originalSets,
    required this.minutes,
    required this.context,
    required this.muscleChanges,
    required this.changes,
    this.sleepHours,
    this.usualSleepHours,
    this.priorMuscleSets = const {},
    this.planKnown = true,
    this.revision = 1,
  });
  final List<ReportExercise> exercises;
  final int plannedSets, originalSets, minutes, revision;
  final bool planKnown;
  final ReportContext context;
  final double? sleepHours, usualSleepHours;
  final Map<String, int> priorMuscleSets, muscleChanges;
  final List<String> changes;
}
