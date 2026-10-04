import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/application/physique_check_in_flow.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';
import 'package:herculex/features/physique/presentation/views/physique_progress_view.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_block.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/exif_jpeg_fixture.dart';
import '../../../support/fake_clock.dart';

const _id = 1;

class _FakeFlow implements PhysiqueCheckInFlow {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PhysiqueGoalData _goal({
  int id = _id,
  String status = 'active',
  bool accepted = true,
  String style = 'Lean athletic',
  DateTime? startedAt,
}) => PhysiqueGoalData(
  id: id,
  status: status,
  source: 'ai_analysis',
  targetAestheticStyle: style,
  timeframeRange: '6 months',
  targetBfPercent: 12,
  startedAt: startedAt ?? DateTime(2026, 9, 1),
  roadmapAcceptedAt: accepted ? DateTime(2026, 9, 2) : null,
);

PhysiqueRoadmapPhaseData _row(
  int id,
  DietPhase phase,
  int weeks, {
  String status = 'upcoming',
  int goalId = _id,
}) => PhysiqueRoadmapPhaseData(
  id: id,
  goalId: goalId,
  orderIndex: id - 1,
  phaseType: phase.name,
  plannedWeeks: weeks,
  targetWeightKg: phase == DietPhase.cut ? 82 : null,
  weeklyRateKg: 0.5,
  tempoCapped: false,
  status: status,
  startedAt: status == 'upcoming' ? null : DateTime(2026, 9, 2),
);

PhysiqueAssessmentData _checkIn(
  int id, {
  String verdict = 'on_track',
  String reason = 'Shoulders look fuller, about 70% of the way.',
  DateTime? at,
}) => PhysiqueAssessmentData(
  id: id,
  goalId: _id,
  kind: 'checkin',
  assessedAt: at ?? DateTime(2026, 9, 20),
  dateIso: '2026-09-20',
  confidence: 'medium',
  verdict: verdict,
  directionBandLow: 0.3,
  directionBandHigh: 0.6,
  reason: reason,
  source: 'ai',
);

PhysiquePhotoData _photo(int id, String role, {int? assessmentId}) =>
    PhysiquePhotoData(
      id: id,
      goalId: _id,
      assessmentId: assessmentId,
      role: role,
      pose: 'front',
      dateIso: '2026-09-02',
      takenAt: DateTime(2026, 9, 2),
      relativePath: 'missing/$id.jpg',
      blurred: false,
      source: 'camera',
    );

PhysiquePhaseStatus _status(
  List<PhysiqueRoadmapPhaseData> phases, {
  bool offer = false,
  bool proposal = false,
}) {
  final idx = phases.indexWhere((p) => p.status == 'current');
  final current = idx < 0 ? null : phases[idx];
  return PhysiquePhaseStatus(
    current: current,
    next: phases
        .skip(idx < 0 ? 0 : idx + 1)
        .where((p) => p.status == 'upcoming')
        .firstOrNull,
    position: idx + 1,
    total: phases.length,
    evaluation: current == null
        ? null
        : ExitEvaluation(
            criteria: [
              ExitCriterionStatus(
                kind: ExitCriterionKind.duration,
                met: false,
                target: current.plannedWeeks.toDouble(),
              ),
            ],
            weekInPhase: 3,
            plannedWeeks: current.plannedWeeks,
            targetReached: false,
            durationElapsed: false,
          ),
    offerAdvance: offer,
    proposalPending: proposal,
    bfReading: PhysiqueBfReading.none,
    logMeasurementsHint: false,
  );
}

final _phases = [
  _row(1, DietPhase.cut, 12, status: 'current'),
  _row(2, DietPhase.maintain, 4),
];

class _Data {
  _Data({
    PhysiqueGoalData? goal,
    List<PhysiqueRoadmapPhaseData>? phases,
    this.checkIns = const [],
    List<PhysiquePhotoData>? photos,
    this.last,
    this.offer = false,
    this.proposal = false,
    this.archived = const [],
    this.eligibility = const PhaseEligibility.unrestricted(),
    this.now,
    this.hasActiveGoal = true,
    this.resumed,
  }) : goal = goal ?? _goal(accepted: !proposal),
       phases = phases ?? _phases,
       photos = photos ?? [_photo(1, 'baseline')];

  final PhysiqueGoalData goal;
  final List<PhysiqueRoadmapPhaseData> phases;
  final List<PhysiqueAssessmentData> checkIns;
  final List<PhysiquePhotoData> photos;
  final DateTime? last;
  final bool offer;
  final bool proposal;
  final List<PhysiqueGoalData> archived;
  final PhaseEligibility eligibility;
  final DateTime? now;
  final bool hasActiveGoal;
  final ResumedCapture? resumed;
  Object? lastExtra;

  List<Override> overrides({SharedPreferences? prefs}) {
    final g = goal;
    return [
      clockProvider.overrideWithValue(FakeClock(now ?? DateTime(2026, 10, 1))),
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      physiqueCheckInFlowProvider.overrideWithValue(_FakeFlow()),
      activePhysiqueGoalProvider.overrideWith(
        (ref) => Stream.value(hasActiveGoal && g.status == 'active' ? g : null),
      ),
      archivedPhysiqueGoalsProvider.overrideWith(
        (ref) => Stream.value(archived),
      ),
      physiqueGoalProvider(g.id).overrideWith((ref) => Stream.value(g)),
      physiqueRoadmapPhasesProvider(
        g.id,
      ).overrideWith((ref) => Stream.value(phases)),
      physiquePhaseStatusProvider(g.id).overrideWith(
        (ref) => _status(phases, offer: offer, proposal: proposal),
      ),
      physiqueBodyFatReadingProvider(
        g.id,
      ).overrideWith((ref) => PhysiqueBfReading.none),
      physiqueDreamPhotoProvider(
        g.syncUuid ?? '',
      ).overrideWith((ref) async => null),
      physiqueRoadmapEligibilityProvider(
        g.id,
      ).overrideWith((ref) => eligibility),
      physiqueCheckInsProvider(
        g.id,
      ).overrideWith((ref) => Stream.value(checkIns)),
      physiquePhotosProvider(g.id).overrideWith((ref) => Stream.value(photos)),
      physiqueLastCheckInAtProvider(
        g.id,
      ).overrideWith((ref) => Stream.value(last)),
      physiqueWeightChartProvider(
        g.id,
      ).overrideWith((ref) => WeightChartData.empty),
      physiqueStrengthChartProvider(
        g.id,
      ).overrideWith((ref) => StrengthChartData.empty),
      physiqueTrainingLevelChartProvider(g.id).overrideWith((ref) => const []),
      if (resumed != null)
        physiqueResumedCaptureProvider.overrideWith((ref) => resumed),
    ];
  }
}

Widget _host(
  _Data d, {
  ThemeData? theme,
  double textScale = 1,
  int? goalId,
  SharedPreferences? prefs,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => PhysiqueProgressView(goalId: goalId),
      ),
      GoRoute(
        path: AppRoutes.nutritionTargets,
        builder: (_, s) {
          d.lastExtra = s.extra;
          return Scaffold(body: Text('NT ${s.extra}'));
        },
      ),
      GoRoute(
        path: AppRoutes.dreamPhysique,
        builder: (_, _) => const Scaffold(body: Text('DREAM PHYSIQUE')),
      ),
      GoRoute(
        path: AppRoutes.measurements,
        builder: (_, _) => const Scaffold(body: Text('MEASUREMENTS')),
      ),
    ],
  );
  return ProviderScope(
    overrides: d.overrides(prefs: prefs),
    child: MaterialApp.router(
      theme: theme ?? AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget w, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(420, 7000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _y(WidgetTester tester, Finder f) => tester.getTopLeft(f.first).dy;

void main() {
  for (final entry in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets('lays out the S1 sections in order (${entry.key})', (
      tester,
    ) async {
      final d = _Data(
        checkIns: [_checkIn(1)],
        archived: [_goal(id: 9, status: 'archived')],
      );
      await _pump(tester, _host(d, theme: entry.value));
      final order = [
        find.text('Lean athletic'),
        find.text('Phase 1 of 2'),
        find.text('Roadmap'),
        find.text('Herculex AI'),
        find.text('1M'),
        find.text('Bodyweight'),
        find.text('Strength'),
        find.text('Training level'),
        find.text('Past goals · 1'),
      ];
      for (final f in order) {
        expect(f, findsWidgets);
      }
      final ys = [for (final f in order) _y(tester, f)];
      expect([...ys]..sort(), ys, reason: 'sections out of order: $ys');
      expect(find.text('Physique progress'), findsWidgets);
    });
  }

  group('goal selection', () {
    testWidgets('empty state offers Create my goal', (tester) async {
      final d = _Data(hasActiveGoal: false);
      await _pump(
        tester,
        ProviderScope(
          overrides: [
            ...d.overrides(),
            activePhysiqueGoalProvider.overrideWith(
              (ref) => Stream.value(null),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PhysiqueProgressView(),
          ),
        ),
      );
      expect(find.text('No Dream Physique goal yet'), findsOneWidget);
      expect(
        find.text(
          'Pick a target physique and Herculex AI will build a phased plan '
          'you can edit.',
        ),
        findsOneWidget,
      );
      expect(find.text('Create my goal'), findsOneWidget);
    });

    testWidgets('Create my goal pushes the Dream Physique route', (
      tester,
    ) async {
      final d = _Data(hasActiveGoal: false);
      await _pump(tester, _host(d));
      await tester.tap(find.text('Create my goal'));
      await tester.pumpAndSettle();
      expect(find.text('DREAM PHYSIQUE'), findsOneWidget);
    });
  });

  group('archived goal (D-03)', () {
    testWidgets('is read-only with an Archived pill', (tester) async {
      final d = _Data(
        goal: _goal(status: 'archived'),
        checkIns: [_checkIn(1, verdict: 'off_track')],
        offer: true,
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain},
          reasons: {PhaseRestrictionReason.under18},
        ),
        archived: [_goal(id: 9, status: 'archived')],
      );
      await _pump(tester, _host(d, goalId: _id));
      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('Add check-in'), findsNothing);
      expect(find.text('Add baseline photo'), findsNothing);
      expect(find.text('Edit roadmap'), findsNothing);
      expect(find.text('Move to Vzdrževanje'), findsNothing);
      expect(find.text('Review nutrition targets'), findsNothing);
      expect(find.textContaining('nista na voljo pod 18 let'), findsNothing);
      expect(find.textContaining('Past goals'), findsNothing);
      // The history stays.
      expect(find.text('See all check-ins'), findsOneWidget);
      expect(find.text('Off track'), findsOneWidget);
    });
  });

  group('proposal (D-01)', () {
    testWidgets('says so, offers review and never an advance', (tester) async {
      final d = _Data(
        proposal: true,
        phases: [_row(1, DietPhase.cut, 12), _row(2, DietPhase.maintain, 4)],
        offer: true,
      );
      await _pump(tester, _host(d));
      expect(
        find.text('This roadmap is a proposal until you accept it.'),
        findsOneWidget,
      );
      expect(find.text('Edit roadmap'), findsOneWidget);
      expect(find.text('Move to Vzdrževanje'), findsNothing);
    });
  });

  group('check-in button', () {
    testWidgets('eligible: a filled Add check-in', (tester) async {
      await _pump(tester, _host(_Data(last: DateTime(2026, 9, 20))));
      final b = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(b.onPressed, isNotNull);
      expect(find.text('Add check-in'), findsWidgets);
    });

    testWidgets('advance prompt visible: Add check-in is outlined', (
      tester,
    ) async {
      await _pump(tester, _host(_Data(offer: true)));
      expect(
        find.widgetWithText(OutlinedButton, 'Add check-in'),
        findsOneWidget,
      );
      // Move to {Phase} is the single filled primary action.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Move to Vzdrževanje'),
        findsOneWidget,
      );
    });

    testWidgets('capped: disabled, dated label and a lock semantics label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final d = _Data(last: DateTime(2026, 10, 5), now: DateTime(2026, 10, 8));
      await _pump(tester, _host(d));
      final b = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(b.onPressed, isNull);
      expect(find.text('Next check-in available Mon, Oct 12'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.text('Add check-in'), findsNothing);
      expect(
        find.bySemanticsLabel('Check-in locked until Monday, October 12'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('cap lifts on the unlock day', (tester) async {
      final d = _Data(last: DateTime(2026, 10, 5), now: DateTime(2026, 10, 12));
      await _pump(tester, _host(d));
      expect(find.text('Add check-in'), findsOneWidget);
    });

    testWidgets('baseline-less goal says so and is never capped', (
      tester,
    ) async {
      final d = _Data(
        photos: const [],
        last: DateTime(2026, 10, 5),
        now: DateTime(2026, 10, 6),
      );
      await _pump(tester, _host(d));
      expect(find.text('Add baseline photo'), findsOneWidget);
      expect(
        find.text(
          'Add a baseline photo so Herculex AI has something to compare '
          'with.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('no check-ins yet shows the empty state', (tester) async {
      await _pump(tester, _host(_Data()));
      expect(find.text('No check-ins yet'), findsOneWidget);
      expect(
        find.text(
          'Take your first photo to set a baseline. You can check in once a '
          'week.',
        ),
        findsOneWidget,
      );
    });
  });

  group('verdict', () {
    for (final (wire, label) in [
      ('on_track', 'On track'),
      ('off_track', 'Off track'),
      ('inconclusive', 'Inconclusive'),
    ]) {
      testWidgets('$label renders chip, reason and footnote, no percent', (
        tester,
      ) async {
        await _pump(
          tester,
          _host(_Data(checkIns: [_checkIn(1, verdict: wire)])),
        );
        expect(find.text(label), findsOneWidget);
        expect(
          find.text('An estimate from your photos, not a measurement.'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(VerdictBlock),
            matching: find.textContaining('%'),
          ),
          findsNothing,
        );
        // Off track and inconclusive offer a review; on track does not.
        expect(
          find.text('Review nutrition targets'),
          findsNWidgets(wire == 'on_track' ? 1 : 2),
        );
      });
    }

    testWidgets('a verdict without a reason falls back to the AI line', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(
          _Data(
            checkIns: [_checkIn(1, verdict: 'inconclusive', reason: '')],
          ),
        ),
      );
      expect(
        find.text(
          "Herculex AI couldn't review this photo, so this check-in is "
          'inconclusive.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Review nutrition targets pushes a DietPhase', (tester) async {
      final d = _Data(checkIns: [_checkIn(1, verdict: 'off_track')]);
      await _pump(tester, _host(d));
      await tester.tap(find.text('Review nutrition targets').last);
      await tester.pumpAndSettle();
      expect(d.lastExtra, DietPhase.cut);
    });
  });

  testWidgets('range tabs drive physiqueChartRangeProvider', (tester) async {
    await _pump(tester, _host(_Data(), theme: AppTheme.lightTheme));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhysiqueProgressView)),
    );
    expect(container.read(physiqueChartRangeProvider), isNull);
    // Goal started Sep 1, now Oct 1: 30 days old, so the default is 3M.
    await tester.tap(find.text('1M'));
    await tester.pump();
    expect(container.read(physiqueChartRangeProvider), ChartRange.month);
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(container.read(physiqueChartRangeProvider), ChartRange.all);
  });

  testWidgets('a goal under 30 days old defaults the range to All', (
    tester,
  ) async {
    final d = _Data(goal: _goal(startedAt: DateTime(2026, 9, 25)));
    await _pump(tester, _host(d));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhysiqueProgressView)),
    );
    expect(container.read(physiqueEffectiveRangeProvider(_id)), ChartRange.all);
  });

  group('resumed capture', () {
    testWidgets('opens the check-in sheet once and clears the hand-off', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('pv_resume_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows keeps the decoded fixture open until the image is GC'd.
        }
      });
      final file = File('${dir.path}/c.jpg')
        ..writeAsBytesSync(buildJpegWithExif());
      SharedPreferences.setMockInitialValues({});
      late SharedPreferences prefs;
      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
      });
      final d = _Data(
        resumed: ResumedCapture(goalId: _id, pose: 'side', path: file.path),
      );
      await _pump(tester, _host(d, prefs: prefs));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Step 2 of'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PhysiqueProgressView)),
      );
      expect(container.read(physiqueResumedCaptureProvider), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Step 2 of'), findsOneWidget);
    });

    testWidgets('ignores a capture for another goal', (tester) async {
      final d = _Data(
        resumed: const ResumedCapture(goalId: 99, pose: 'front', path: '/x'),
      );
      await _pump(tester, _host(d));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Step 2 of'), findsNothing);
    });
  });

  group('loading and errors', () {
    testWidgets('provider loading shows an adaptive indicator in the card', (
      tester,
    ) async {
      final d = _Data();
      await _pump(
        tester,
        ProviderScope(
          overrides: [
            ...d.overrides(),
            physiqueCheckInsProvider(_id).overrideWith(
              (ref) => StreamController<List<PhysiqueAssessmentData>>().stream,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PhysiqueProgressView(goalId: _id),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('an error shows the line and Try again invalidates', (
      tester,
    ) async {
      final d = _Data();
      var builds = 0;
      await _pump(
        tester,
        ProviderScope(
          overrides: [
            ...d.overrides(),
            physiqueCheckInsProvider(_id).overrideWith((ref) {
              builds++;
              return Stream<List<PhysiqueAssessmentData>>.error('boom');
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PhysiqueProgressView(goalId: _id),
          ),
        ),
      );
      expect(find.text("Couldn't load this right now."), findsOneWidget);
      final before = builds;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(builds, greaterThan(before));
      expect(find.text("Couldn't load this right now."), findsOneWidget);
    });
  });

  testWidgets('survives 320 dp at 2.0 text scale', (tester) async {
    final d = _Data(
      checkIns: [_checkIn(1, verdict: 'off_track')],
      offer: true,
      archived: [_goal(id: 9, status: 'archived')],
      eligibility: const PhaseEligibility(
        allowedPhases: {DietPhase.maintain},
        reasons: {PhaseRestrictionReason.under18},
      ),
    );
    await _pump(tester, _host(d, textScale: 2), size: const Size(320, 14000));
    expect(tester.takeException(), isNull);
  });

  group('route registration (D-10)', () {
    Future<void> openAt(WidgetTester tester, String path, _Data d) async {
      tester.view.physicalSize = const Size(420, 7000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          ...d.overrides(),
          physiqueGoalProvider(
            7,
          ).overrideWith((ref) => Stream.value(_goal(id: 7, style: 'Seven'))),
          physiqueRoadmapPhasesProvider(7).overrideWith(
            (ref) => Stream.value([_row(10, DietPhase.cut, 12, goalId: 7)]),
          ),
          physiquePhaseStatusProvider(7).overrideWith((ref) => null),
          physiqueBodyFatReadingProvider(
            7,
          ).overrideWith((ref) => PhysiqueBfReading.none),
          physiqueRoadmapEligibilityProvider(
            7,
          ).overrideWith((ref) => const PhaseEligibility.unrestricted()),
          physiqueCheckInsProvider(
            7,
          ).overrideWith((ref) => Stream.value(const [])),
          physiquePhotosProvider(
            7,
          ).overrideWith((ref) => Stream.value(const [])),
          physiqueLastCheckInAtProvider(
            7,
          ).overrideWith((ref) => Stream.value(null)),
          physiqueWeightChartProvider(
            7,
          ).overrideWith((ref) => WeightChartData.empty),
          physiqueStrengthChartProvider(
            7,
          ).overrideWith((ref) => StrengthChartData.empty),
          physiqueTrainingLevelChartProvider(7).overrideWith((ref) => const []),
          profileProvider.overrideWith(
            (ref) => Stream.value(
              const Profile(
                goal: FitnessGoal.maintenance,
                activityLevel: ActivityLevel.active,
                ageYears: 30,
                weightKg: 80,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(profileProvider.future));
      final router = container.read(routerProvider);
      router.go(path);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('?goalId=7 opens that goal', (tester) async {
      await openAt(tester, AppPaths.dreamPhysiqueProgress(goalId: 7), _Data());
      expect(find.text('Seven'), findsOneWidget);
    });

    testWidgets('an absent goalId means the active goal', (tester) async {
      await openAt(tester, AppRoutes.dreamPhysiqueProgress, _Data());
      expect(find.text('Lean athletic'), findsOneWidget);
    });

    testWidgets('a non-integer goalId falls back to the active goal', (
      tester,
    ) async {
      await openAt(
        tester,
        '${AppRoutes.dreamPhysiqueProgress}?goalId=abc',
        _Data(),
      );
      expect(find.text('Lean athletic'), findsOneWidget);
      expect(find.text('Seven'), findsNothing);
    });
  });

  test('sources avoid forbidden literals and the real clock', () {
    final banned = RegExp(
      'AppColors|Color\\(0x|Colors\\.|boxShadow|FontWeight\\.w[5789]|'
      'DateTime\\.now|nutrition_repository|NutritionTarget',
    );
    for (final f in [
      'widgets/check_in_card.dart',
      'views/physique_progress_view.dart',
    ]) {
      final src = File(
        'lib/features/physique/presentation/$f',
      ).readAsStringSync();
      expect(banned.hasMatch(src), isFalse, reason: f);
    }
    final view = File(
      'lib/features/physique/presentation/views/physique_progress_view.dart',
    ).readAsLinesSync();
    expect(view.length, lessThanOrEqualTo(300));
    final router = File('lib/app/router/router.dart').readAsStringSync();
    expect(router, contains('AppRoutes.dreamPhysiqueProgress'));
    expect(router, contains("queryParameters['goalId']"));
  });
}
