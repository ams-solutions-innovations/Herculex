import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workout_report/domain/workout_report_engine.dart';

ReportSet set(
  int reps, {
  double load = 50,
  double? rpe = 8,
  int? max,
  double? target,
}) => ReportSet(
  load: load,
  reps: reps,
  rpe: rpe,
  targetMax: max,
  targetRpe: target,
);
WorkoutReport evaluate({
  List<ReportSet>? sets,
  List<List<ReportSet>> previous = const [],
  ReportContext context = const ReportContext(),
  bool changed = false,
  bool rep = true,
  int planned = 1,
  int original = 1,
  double? sleep,
  bool known = true,
}) => WorkoutReportEngine.evaluate(
  ReportInput(
    exercises: [
      ReportExercise(
        name: 'Bench',
        muscle: 'Chest',
        sets: sets ?? [set(10)],
        previous: previous,
        newSetup: changed,
        repBased: rep,
        plannedSets: planned,
      ),
    ],
    plannedSets: planned,
    originalSets: original,
    minutes: 45,
    context: context,
    muscleChanges: const {},
    changes: const [],
    sleepHours: sleep,
    planKnown: known,
  ),
);
bool has(WorkoutReport report, String id) =>
    report.findings.any((f) => f.ruleId == id);

void main() {
  test('one lower result is not a plateau or CNS diagnosis', () {
    final r = evaluate(
      sets: [set(8)],
      previous: [
        [set(10)],
      ],
    );
    expect(has(r, 'PERFORMANCE-DOWN'), isTrue);
    expect(has(r, 'PROGRESSION-PLATEAU-02'), isFalse);
    expect(has(r, 'RECOVERY-ADJUST-01'), isFalse);
  });
  test('intentional shorter plan is successful when completed', () {
    final r = evaluate(planned: 1, original: 3);
    expect(has(r, 'PLAN-COMPLETE'), isTrue);
    expect(r.findings.first.title, 'Adjusted workout completed');
    expect(has(r, 'PLAN-PARTIAL'), isFalse);
  });
  test('missing RPE cannot become a comparable performance claim', () {
    final r = evaluate(
      sets: [set(12, rpe: null)],
      previous: [
        [set(10)],
      ],
    );
    expect(has(r, 'PERFORMANCE-UP'), isFalse);
    expect(has(r, 'DATA-NO-BASELINE'), isTrue);
  });
  test('different load does not imply decline at same load', () {
    expect(
      has(
        evaluate(
          sets: [set(8, load: 55)],
          previous: [
            [set(10)],
          ],
        ),
        'PERFORMANCE-DOWN',
      ),
      isFalse,
    );
  });
  test('changed setup prevents comparison and progression', () {
    final r = evaluate(
      changed: true,
      previous: [
        [set(12)],
      ],
    );
    expect(has(r, 'COMPARISON-CHANGED'), isTrue);
    expect(has(r, 'PERFORMANCE-DOWN'), isFalse);
  });
  test('three descending exposures produce a review', () {
    expect(
      has(
        evaluate(
          sets: [set(8)],
          previous: [
            [set(10)],
            [set(12)],
          ],
        ),
        'PERFORMANCE-REPEATED',
      ),
      isTrue,
    );
  });
  test('plateau requires at least three comparable observations', () {
    expect(
      has(
        evaluate(
          previous: [
            [set(10)],
          ],
        ),
        'PROGRESSION-PLATEAU-02',
      ),
      isFalse,
    );
    expect(
      has(
        evaluate(
          previous: [
            [set(10)],
            [set(10)],
          ],
        ),
        'PROGRESSION-PLATEAU-02',
      ),
      isTrue,
    );
  });
  test('two complete target exposures enable load review', () {
    final r = evaluate(
      sets: [set(12, max: 12, target: 8)],
      previous: [
        [set(12, max: 12, target: 8)],
      ],
    );
    expect(has(r, 'PROGRESSION-DOUBLE-01'), isTrue);
  });
  test('missing technique context does not make progression unconditional', () {
    final r = evaluate(
      sets: [set(12, max: 12, target: 8)],
      previous: [
        [set(12, max: 12, target: 8)],
      ],
    );
    expect(
      r.findings
          .singleWhere((f) => f.ruleId == 'PROGRESSION-DOUBLE-01')
          .nextStep,
      contains('If technique'),
    );
  });
  test('unknown context does not invent sleep food or stress explanations', () {
    final r = evaluate();
    expect(r.findings.where((f) => f.ruleId.startsWith('CONTEXT')), isEmpty);
  });
  test('short sleep is a possible contribution without exact capacity', () {
    final r = evaluate(sleep: 5.5);
    expect(
      r.findings.singleWhere((f) => f.ruleId == 'CONTEXT-SLEEP').support,
      ReportSupport.possible,
    );
  });
  test('reported fasting is not glycogen diagnosis', () {
    final r = evaluate(context: const ReportContext(ateBefore: false));
    expect(
      r.findings.singleWhere((f) => f.ruleId == 'CONTEXT-FUEL').detail,
      contains('does not establish'),
    );
  });
  test('pain precedes every performance message', () {
    final r = evaluate(
      context: const ReportContext(pain: true),
      previous: [
        [set(8)],
      ],
    );
    expect(r.findings.first.ruleId, 'SAFETY-PAIN-03');
  });
  test('non-rep work does not create lifting progression', () {
    final r = evaluate(
      rep: false,
      previous: [
        [set(8)],
      ],
    );
    expect(has(r, 'METRIC-SPECIFIC'), isTrue);
    expect(has(r, 'PERFORMANCE-UP'), isFalse);
  });
  test('no historical plan is scored as incomplete', () {
    expect(has(evaluate(known: false, planned: 8), 'PLAN-PARTIAL'), isFalse);
  });
  test('report round trip preserves rule provenance and confidence', () {
    final report = evaluate(sleep: 6);
    expect(WorkoutReport.decode(report.encode()).encode(), report.encode());
    expect(
      () => WorkoutReport.decode('{"payloadVersion":99}'),
      throwsFormatException,
    );
  });
}
