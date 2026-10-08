import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';
import 'package:herculex/features/physique/presentation/widgets/active_phase_card.dart';
import 'package:herculex/features/physique/presentation/widgets/goal_header_card.dart';
import 'package:herculex/features/physique/presentation/widgets/roadmap_timeline_card.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_database.dart';

const _id = 1;

PhysiqueGoalData _goal({
  bool accepted = true,
  String status = 'active',
  String style = 'Lean athletic',
  double? targetBf = 12,
  double? startWeight,
  int? estimatedMonths,
}) => PhysiqueGoalData(
  id: _id,
  status: status,
  source: 'ai_analysis',
  targetAestheticStyle: style,
  timeframeRange: '6 months',
  targetBfPercent: targetBf,
  startWeightKg: startWeight,
  estimatedMonths: estimatedMonths,
  startedAt: DateTime(2026, 9, 1),
  roadmapAcceptedAt: accepted ? DateTime(2026, 9, 2) : null,
);

PhysiqueRoadmapPhaseData _row(
  int id,
  DietPhase phase,
  int weeks, {
  String status = 'upcoming',
  double? rate,
  double? targetWeight,
  double? targetBf,
}) => PhysiqueRoadmapPhaseData(
  id: id,
  goalId: _id,
  orderIndex: id - 1,
  phaseType: phase.name,
  plannedWeeks: weeks,
  targetWeightKg: targetWeight,
  targetBfPercent: targetBf,
  weeklyRateKg: rate,
  tempoCapped: false,
  status: status,
  startedAt: status == 'upcoming' ? null : DateTime(2026, 9, 2),
);

PhysiquePhaseStatus _status(
  List<PhysiqueRoadmapPhaseData> phases, {
  bool offer = false,
  bool proposal = false,
  bool hint = false,
  bool metWeight = false,
  int week = 3,
}) {
  final idx = phases.indexWhere((p) => p.status == 'current');
  final current = idx < 0 ? null : phases[idx];
  final next = phases
      .skip(idx < 0 ? 0 : idx + 1)
      .where((p) => p.status == 'upcoming')
      .firstOrNull;
  ExitEvaluation? eval;
  if (current != null) {
    eval = ExitEvaluation(
      criteria: [
        if (current.targetWeightKg != null)
          ExitCriterionStatus(
            kind: ExitCriterionKind.weight,
            met: metWeight,
            target: current.targetWeightKg,
          ),
        if (current.targetBfPercent != null)
          ExitCriterionStatus(
            kind: ExitCriterionKind.bodyFat,
            met: false,
            target: current.targetBfPercent,
          ),
        ExitCriterionStatus(
          kind: ExitCriterionKind.duration,
          met: false,
          target: current.plannedWeeks.toDouble(),
        ),
      ],
      weekInPhase: week,
      plannedWeeks: current.plannedWeeks,
      targetReached: metWeight,
      durationElapsed: false,
    );
  }
  return PhysiquePhaseStatus(
    current: current,
    next: next,
    position: idx + 1,
    total: phases.length,
    evaluation: eval,
    offerAdvance: offer,
    proposalPending: proposal,
    bfReading: PhysiqueBfReading.none,
    logMeasurementsHint: hint,
  );
}

final _cutThenMaintain = [
  _row(
    1,
    DietPhase.cut,
    12,
    status: 'current',
    rate: 0.5,
    targetWeight: 82,
    targetBf: 15,
  ),
  _row(2, DietPhase.maintain, 4, rate: 0),
];

class _Harness {
  _Harness({
    required this.phases,
    PhysiqueGoalData? goal,
    PhysiquePhaseStatus? status,
    this.repo,
    this.eligibility = const PhaseEligibility.unrestricted(),
  }) : goal = goal ?? _goal(),
       status = status ?? _status(phases);

  final List<PhysiqueRoadmapPhaseData> phases;
  final PhysiqueGoalData goal;
  final PhysiquePhaseStatus status;
  final PhysiqueRoadmapRepository? repo;
  final PhaseEligibility eligibility;
  Object? lastExtra;

  Widget build({
    ThemeData? theme,
    double textScale = 1,
    List<Widget> cards = const [],
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: cards.isEmpty
                    ? [ActivePhaseCard(goalId: _id)]
                    : cards,
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.nutritionTargets,
          builder: (_, s) {
            lastExtra = s.extra;
            return Scaffold(body: Text('NT ${s.extra}'));
          },
        ),
        GoRoute(
          path: AppRoutes.measurements,
          builder: (_, _) => const Scaffold(body: Text('MEASUREMENTS')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 1, 9))),
        weightFormatProvider.overrideWithValue(
          const WeightFormat(MeasurementUnit.metric),
        ),
        physiqueWeightLogsProvider.overrideWith(
          (ref) => Stream.value(const <WeightLog>[]),
        ),
        physiqueGoalProvider(_id).overrideWith((ref) => Stream.value(goal)),
        physiqueRoadmapPhasesProvider(
          _id,
        ).overrideWith((ref) => Stream.value(phases)),
        physiquePhaseStatusProvider(_id).overrideWith((ref) => status),
        physiqueRoadmapEligibilityProvider(
          _id,
        ).overrideWith((ref) => eligibility),
        ?(repo == null
            ? null
            : physiqueRoadmapRepositoryProvider.overrideWithValue(repo!)),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => InAppNotificationHost(
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(w);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  for (final entry in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    group('ActivePhaseCard (${entry.key})', () {
      testWidgets('names phase, position, week, tempo and exit criteria', (
        tester,
      ) async {
        final h = _Harness(phases: _cutThenMaintain);
        await _pump(tester, h.build(theme: entry.value));
        expect(find.text('Cut'), findsOneWidget);
        expect(find.text('Phase 1 of 2'), findsOneWidget);
        expect(find.text('Week 3 of 12'), findsOneWidget);
        expect(find.text('About 0.5 kg per week'), findsOneWidget);
        expect(find.text('Exit when'), findsOneWidget);
        expect(find.text('Reach 82.0 kg'), findsOneWidget);
        expect(find.text('Reach about 15% body fat'), findsOneWidget);
        expect(find.text('Or finish the planned 12 weeks'), findsOneWidget);
        expect(find.textContaining('kcal'), findsNothing);
        expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsWidgets);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, closeTo(2 / 12, 1e-9));
        expect(find.text('Edit roadmap'), findsOneWidget);
        expect(find.text('Review nutrition targets'), findsOneWidget);
        expect(find.text('Ready for the next phase?'), findsNothing);
      });

      testWidgets('a met exit criterion uses the success check', (
        tester,
      ) async {
        final h = _Harness(
          phases: _cutThenMaintain,
          status: _status(_cutThenMaintain, metWeight: true),
        );
        await _pump(tester, h.build(theme: entry.value));
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      });
    });
  }

  group('tempo lines', () {
    for (final (phase, line) in [
      (DietPhase.maintain, 'Hold your weight steady'),
      (DietPhase.recomp, 'Weight stays flat while body composition shifts'),
    ]) {
      testWidgets('${phase.name} never shows a rate or kcal', (tester) async {
        final phases = [_row(1, phase, 8, status: 'current', rate: 0)];
        await _pump(tester, _Harness(phases: phases).build());
        expect(find.text(line), findsOneWidget);
        expect(find.textContaining('kg per week'), findsNothing);
        expect(find.textContaining('kcal'), findsNothing);
      });
    }
  });

  group('advance prompt (D-02)', () {
    testWidgets('hidden when offerAdvance is false', (tester) async {
      await _pump(tester, _Harness(phases: _cutThenMaintain).build());
      expect(find.text('Move to Maintenance'), findsNothing);
      expect(find.text('Not yet'), findsNothing);
    });

    testWidgets('shown with copy and a single filled button', (tester) async {
      final h = _Harness(
        phases: _cutThenMaintain,
        status: _status(_cutThenMaintain, offer: true, metWeight: true),
      );
      await _pump(tester, h.build());
      expect(find.text('Ready for the next phase?'), findsOneWidget);
      expect(
        find.text(
          "You've met this phase's goal. Maintenance is next. Nothing changes "
          'until you set new targets.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Move to Maintenance'), findsOneWidget);
      expect(find.text('Not yet'), findsOneWidget);
    });

    testWidgets('hidden for an archived goal, with no actions at all', (
      tester,
    ) async {
      final h = _Harness(
        phases: _cutThenMaintain,
        goal: _goal(status: 'archived'),
        status: _status(_cutThenMaintain, offer: true, hint: true),
      );
      await _pump(tester, h.build());
      expect(find.text('Move to Maintenance'), findsNothing);
      expect(find.text('Edit roadmap'), findsNothing);
      expect(find.text('Review nutrition targets'), findsNothing);
      expect(find.text('Log measurements to refine this.'), findsNothing);
      expect(find.text('Cut'), findsOneWidget);
    });

    testWidgets(
      'accepting advances persisted rows, writes no nutrition target and '
      'offers Set targets',
      (tester) async {
        final clock = FakeClock(DateTime(2026, 10, 1, 9));
        late AppDatabase db;
        late PhysiqueRoadmapRepository repo;
        late int goalId;
        late List<PhysiqueRoadmapPhaseData> rows;
        late int targetsBefore;
        await tester.runAsync(() async {
          db = await openTestDatabase();
          final goals = PhysiqueGoalRepository(db, clock);
          repo = PhysiqueRoadmapRepository(db, clock);
          goalId = await goals.startGoal(
            StartGoalInput(
              estimatedMonths: 6,
              targetBfPercent: 12,
              analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 30))],
              roadmap: [
                RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 12),
                RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 4),
              ],
            ),
          );
          await repo.replaceRoadmap(goalId, [
            const RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 12),
            const RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 4),
          ], accept: true);
          rows = await repo.watchPhases(goalId).first;
          targetsBefore = (await db.select(db.nutritionTargets).get()).length;
        });
        addTearDown(() => db.close());

        // Seed ids differ from the fixed _id used by the harness.
        final phases = [
          for (final r in rows)
            _row(
              r.id,
              DietPhase.values.firstWhere((p) => p.name == r.phaseType),
              r.plannedWeeks,
              status: r.status,
            ),
        ];
        final h = _Harness(
          phases: phases,
          status: _status(phases, offer: true, metWeight: true),
          repo: repo,
        );
        // advancePhase takes the real goal id; the harness goal id is _id.
        expect(goalId, _id);

        await _pump(tester, h.build());
        await tester.runAsync(() async {
          await tester.tap(find.text('Move to Maintenance'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        late List<PhysiqueRoadmapPhaseData> after;
        late int targetsAfter;
        await tester.runAsync(() async {
          after = await repo.watchPhases(goalId).first;
          targetsAfter = (await db.select(db.nutritionTargets).get()).length;
        });
        expect(after.map((p) => p.status), ['done', 'current']);
        expect(targetsAfter, targetsBefore);
        // Notices drop in as a pill; its text shows once the entrance settles.
        await tester.pump(const Duration(milliseconds: 1200));
        expect(
          find.text('Moved to Maintenance. Review your nutrition targets.'),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Set targets'));
        await tester.pumpAndSettle();
        expect(h.lastExtra, DietPhase.maintain);
      },
    );

    testWidgets('Not yet postpones one week and confirms', (tester) async {
      final clock = FakeClock(DateTime(2026, 10, 1, 9));
      late AppDatabase db;
      late PhysiqueRoadmapRepository repo;
      late PhysiqueGoalRepository goals;
      await tester.runAsync(() async {
        db = await openTestDatabase();
        goals = PhysiqueGoalRepository(db, clock);
        repo = PhysiqueRoadmapRepository(db, clock);
        await goals.startGoal(
          StartGoalInput(
            estimatedMonths: 6,
            targetBfPercent: 12,
            analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 30))],
            roadmap: [
              RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 12),
              RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 4),
            ],
          ),
        );
        await repo.replaceRoadmap(_id, [
          const RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 12),
          const RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 4),
        ], accept: true);
      });
      addTearDown(() => db.close());
      final h = _Harness(
        phases: _cutThenMaintain,
        status: _status(_cutThenMaintain, offer: true, metWeight: true),
        repo: repo,
      );
      await _pump(tester, h.build());
      await tester.runAsync(() async {
        await tester.tap(find.text('Not yet'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      late PhysiqueGoalData? goal;
      await tester.runAsync(() async => goal = await goals.getGoal(_id));
      expect(goal!.advanceSnoozedUntil, DateTime(2026, 10, 8));
      // Notices drop in as a pill; its text shows once the entrance settles.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text("We'll ask again in a week."), findsOneWidget);
    });
  });

  group('deep links', () {
    testWidgets('Review nutrition targets pushes a coerced DietPhase', (
      tester,
    ) async {
      final h = _Harness(
        phases: _cutThenMaintain,
        eligibility: const PhaseEligibility(
          reasons: {PhaseRestrictionReason.under18},
          allowedPhases: {
            DietPhase.maintain,
            DietPhase.recomp,
            DietPhase.maingain,
          },
        ),
      );
      await _pump(tester, h.build());
      await tester.tap(find.text('Review nutrition targets'));
      await tester.pumpAndSettle();
      expect(h.lastExtra, isA<DietPhase>());
      expect(h.lastExtra, DietPhase.recomp);
    });
  });

  group('proposal state (D-01)', () {
    final proposalPhases = [
      _row(1, DietPhase.cut, 12, rate: 0.5, targetWeight: 82),
      _row(2, DietPhase.maintain, 4),
    ];

    testWidgets('names the first proposed phase and offers Edit roadmap', (
      tester,
    ) async {
      final h = _Harness(
        phases: proposalPhases,
        goal: _goal(accepted: false),
        status: _status(proposalPhases, proposal: true),
      );
      await _pump(tester, h.build());
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Phase 1 of 2'), findsOneWidget);
      expect(
        find.text('This roadmap is a proposal until you accept it.'),
        findsOneWidget,
      );
      expect(find.text('Edit roadmap'), findsOneWidget);
      expect(find.text('Exit when'), findsNothing);
      expect(find.textContaining('Week '), findsNothing);
      expect(find.text('Move to Maintenance'), findsNothing);
    });

    testWidgets('photos-only legacy goal reads as an imported proposal', (
      tester,
    ) async {
      final legacyPhases = [_row(1, DietPhase.maintain, 8)];
      final h = _Harness(
        phases: legacyPhases,
        goal: _goal(accepted: false, style: '', targetBf: null),
        status: _status(legacyPhases, proposal: true),
      );
      await _pump(
        tester,
        h.build(
          cards: [
            GoalHeaderCard(goalId: _id),
            ActivePhaseCard(goalId: _id),
          ],
        ),
      );
      expect(find.text('Imported progress photos'), findsOneWidget);
      expect(find.text('Started Sep 1, 2026'), findsOneWidget);
      expect(find.textContaining('Target'), findsNothing);
      expect(
        find.text('This roadmap is a proposal until you accept it.'),
        findsOneWidget,
      );
      expect(find.text('Exit when'), findsNothing);
    });
  });

  group('measurement hint', () {
    testWidgets('shown when the hint is on and a body-fat row exists', (
      tester,
    ) async {
      final h = _Harness(
        phases: _cutThenMaintain,
        status: _status(_cutThenMaintain, hint: true),
      );
      await _pump(tester, h.build());
      await tester.tap(find.text('Log measurements to refine this.'));
      await tester.pumpAndSettle();
      expect(find.text('MEASUREMENTS'), findsOneWidget);
    });

    testWidgets('hidden when a measured reading exists', (tester) async {
      await _pump(tester, _Harness(phases: _cutThenMaintain).build());
      expect(find.text('Log measurements to refine this.'), findsNothing);
    });
  });

  group('GoalHeaderCard and RoadmapTimelineCard', () {
    testWidgets('header shows target, start date and Archived pill', (
      tester,
    ) async {
      final h = _Harness(
        phases: _cutThenMaintain,
        goal: _goal(status: 'archived'),
      );
      await _pump(tester, h.build(cards: [GoalHeaderCard(goalId: _id)]));
      expect(find.text('Lean athletic'), findsOneWidget);
      expect(
        find.text('Target 12% body fat · started Sep 1, 2026'),
        findsOneWidget,
      );
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('timeline renders done, current and upcoming nodes', (
      tester,
    ) async {
      final phases = [
        _row(1, DietPhase.cut, 12, status: 'done'),
        _row(2, DietPhase.maintain, 4, status: 'current'),
        _row(3, DietPhase.bulk, 16),
      ];
      final h = _Harness(phases: phases);
      await _pump(tester, h.build(cards: [RoadmapTimelineCard(goalId: _id)]));
      expect(find.byKey(const Key('timeline-node-done-0')), findsOneWidget);
      expect(find.byKey(const Key('timeline-node-current-1')), findsOneWidget);
      expect(find.byKey(const Key('timeline-node-upcoming-2')), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('16 weeks'), findsOneWidget);
    });

    testWidgets('timeline names the weight each phase ends at, with dates '
        'and pace', (tester) async {
      final phases = [
        _row(
          1,
          DietPhase.cut,
          12,
          status: 'current',
          rate: 0.5,
          targetWeight: 74,
          targetBf: 12,
        ),
        _row(2, DietPhase.maintain, 2, rate: 0, targetWeight: 74),
        _row(3, DietPhase.maingain, 38, rate: 0.11, targetWeight: 78.2),
      ];
      final h = _Harness(phases: phases, goal: _goal(startWeight: 80));
      await _pump(tester, h.build(cards: [RoadmapTimelineCard(goalId: _id)]));
      expect(find.text('80 → 74 kg'), findsOneWidget);
      expect(find.text('74 → 74 kg'), findsOneWidget);
      expect(find.text('74 → 78.2 kg'), findsOneWidget);
      expect(find.text('Dream weight 78.2 kg'), findsOneWidget);
      expect(find.text('52 weeks · about 12 months'), findsOneWidget);
      expect(find.text('−0.5 kg/wk'), findsOneWidget);
      expect(find.text('Sep 2 – Nov 24, 2026'), findsOneWidget);
      expect(find.text('Target 12% body fat'), findsOneWidget);
    });

    testWidgets('timeline says when the roadmap stops short of the goal', (
      tester,
    ) async {
      final short = [
        _row(1, DietPhase.cut, 5, status: 'current', targetWeight: 77.5),
      ];
      await _pump(
        tester,
        _Harness(
          phases: short,
          goal: _goal(startWeight: 80, estimatedMonths: 12),
        ).build(cards: [RoadmapTimelineCard(goalId: _id)]),
      );
      expect(
        find.text(
          'This roadmap covers 1 of 12 months. Use Update roadmap below to '
          'plan the rest.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no such note when the roadmap covers the goal', (
      tester,
    ) async {
      final full = [
        _row(1, DietPhase.cut, 12, status: 'current', targetWeight: 74),
        _row(2, DietPhase.maintain, 2, targetWeight: 74),
        _row(3, DietPhase.maingain, 38, targetWeight: 78.2),
      ];
      await _pump(
        tester,
        _Harness(
          phases: full,
          goal: _goal(startWeight: 80, estimatedMonths: 12),
        ).build(cards: [RoadmapTimelineCard(goalId: _id)]),
      );
      expect(find.byKey(const Key('timeline-covers-less')), findsNothing);
    });

    testWidgets('timeline shows only the end weight when the start is '
        'unknown', (tester) async {
      final phases = [
        _row(1, DietPhase.cut, 12, status: 'current', targetWeight: 74),
      ];
      final h = _Harness(phases: phases);
      await _pump(tester, h.build(cards: [RoadmapTimelineCard(goalId: _id)]));
      expect(find.text('74 kg'), findsOneWidget);
    });

    testWidgets('proposal phases all read Up next', (tester) async {
      final phases = [
        _row(1, DietPhase.cut, 12),
        _row(2, DietPhase.maintain, 4),
      ];
      final h = _Harness(phases: phases, goal: _goal(accepted: false));
      await _pump(tester, h.build(cards: [RoadmapTimelineCard(goalId: _id)]));
      expect(find.text('Up next'), findsNWidgets(2));
      expect(find.text('Current'), findsNothing);
    });
  });

  testWidgets('survives 320 dp at 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(
      phases: _cutThenMaintain,
      status: _status(_cutThenMaintain, offer: true, hint: true),
    );
    await _pump(
      tester,
      h.build(
        textScale: 2,
        cards: [
          GoalHeaderCard(goalId: _id),
          ActivePhaseCard(goalId: _id),
          RoadmapTimelineCard(goalId: _id),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('sources avoid nutrition writes, colour literals and heavy weights', () {
    final banned = RegExp(
      'nutrition_repository|NutritionTarget|AppColors|Color\\(0x|Colors\\.|'
      'boxShadow|FontWeight\\.w[5789]',
    );
    for (final f in [
      'goal_header_card',
      'active_phase_card',
      'roadmap_timeline_card',
    ]) {
      final src = File(
        'lib/features/physique/presentation/widgets/$f.dart',
      ).readAsStringSync();
      expect(banned.hasMatch(src), isFalse, reason: f);
    }
  });
}
