import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_roadmap_suggestion_provider.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/presentation/sheets/roadmap_editor_sheet.dart';
import 'package:herculex/features/profile/domain/profile.dart';

const _goalId = 1;

class _FakeRoadmapRepository implements PhysiqueRoadmapRepository {
  List<RoadmapPhaseDraft>? saved;
  bool? accepted;
  int calls = 0;

  @override
  Future<void> replaceRoadmap(
    int goalId,
    List<RoadmapPhaseDraft> drafts, {
    bool accept = false,
  }) async {
    calls++;
    saved = drafts;
    accepted = accept;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PhysiqueGoalData _goal({
  bool accepted = false,
  double? startWeightKg = 90,
  double? targetBf = 12,
}) => PhysiqueGoalData(
  id: _goalId,
  status: 'active',
  source: 'ai_analysis',
  targetAestheticStyle: 'Lean athletic',
  timeframeRange: '6 months',
  estimatedMonths: 6,
  targetBfPercent: targetBf,
  startWeightKg: startWeightKg,
  startedAt: DateTime(2026, 9, 1),
  roadmapAcceptedAt: accepted ? DateTime(2026, 9, 2) : null,
);

PhysiqueRoadmapPhaseData _row(
  int id,
  DietPhase phase,
  int weeks, {
  String status = 'upcoming',
  double? rate,
  bool capped = false,
}) => PhysiqueRoadmapPhaseData(
  id: id,
  goalId: _goalId,
  orderIndex: id,
  phaseType: phase.name,
  plannedWeeks: weeks,
  targetWeightKg: 80.0 + id,
  targetBfPercent: null,
  weeklyRateKg: rate,
  tempoCapped: capped,
  status: status,
);

final _threePhases = [
  _row(1, DietPhase.cut, 12, rate: 0.5, capped: true),
  _row(2, DietPhase.maintain, 4, rate: 0),
  _row(3, DietPhase.recomp, 8, rate: 0),
];

PhysiqueRoadmapProposal _suggestion() => const PhysiqueRoadmapProposal(
  phases: [
    RoadmapPhaseDraft(
      phase: DietPhase.bulk,
      plannedWeeks: 20,
      weeklyRateKg: 0.3,
    ),
  ],
  eligibility: PhaseEligibility.unrestricted(),
  requestedDirection: DietPhase.bulk,
  wasCoerced: false,
);

Widget _host({
  required ThemeData theme,
  required _FakeRoadmapRepository repo,
  List<PhysiqueRoadmapPhaseData>? phases,
  PhysiqueGoalData? goal,
  PhaseEligibility eligibility = const PhaseEligibility.unrestricted(),
  PhysiqueRoadmapProposal? suggestion,
  Profile? profile,
}) {
  return ProviderScope(
    overrides: [
      physiqueRoadmapRepositoryProvider.overrideWithValue(repo),
      physiqueGoalProvider(
        _goalId,
      ).overrideWith((ref) => Stream.value(goal ?? _goal())),
      physiqueRoadmapPhasesProvider(
        _goalId,
      ).overrideWith((ref) => Stream.value(phases ?? _threePhases)),
      physiqueRoadmapEligibilityProvider(
        _goalId,
      ).overrideWith((ref) => eligibility),
      physiqueRoadmapSuggestionProvider(
        _goalId,
      ).overrideWith((ref) => suggestion),
      profileProvider.overrideWith((ref) => Stream.value(profile)),
      maintenanceKcalProvider.overrideWith((ref) => 2500),
    ],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  RoadmapEditorSheet.show(context, goalId: _goalId),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Profile _profile(double? kg) => Profile(
  goal: FitnessGoal.weightLoss,
  activityLevel: ActivityLevel.active,
  ageYears: 30,
  weightKg: kg,
);

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void _performCustom(WidgetTester tester, String label, int nth) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  final id = CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
  final nodes = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    if (n.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false) {
      nodes.add(n);
    }
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  owner.performAction(
    (nth < 0 ? nodes.last : nodes[nth]).id,
    SemanticsAction.customAction,
    id,
  );
}

bool _hasCustom(WidgetTester tester, String label) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  final id = CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
  var found = false;
  void walk(SemanticsNode n) {
    if (n.getSemanticsData().customSemanticsActionIds?.contains(id) ?? false) {
      found = true;
    }
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return found;
}

void main() {
  for (final t in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final theme = t.$2;
    final name = t.$1;

    group('RoadmapEditorSheet ($name)', () {
      testWidgets('shows persisted non-done phases with tempo labels', (
        tester,
      ) async {
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            phases: [
              _row(0, DietPhase.bulk, 6, status: 'done'),
              ..._threePhases,
            ],
          ),
        );
        expect(find.text('Your roadmap'), findsOneWidget);
        expect(
          find.text(
            'Reorder, resize or remove phases. Nothing changes your calories '
            'until you set targets.',
          ),
          findsOneWidget,
        );
        expect(find.text('Accept roadmap'), findsOneWidget);
        expect(find.text('Masa'), findsNothing);
        expect(find.text('Redukcija'), findsOneWidget);
        expect(find.text('12 weeks'), findsOneWidget);
        expect(find.text('About 0.5 kg per week'), findsOneWidget);
        expect(find.text('Paced to a safe weekly rate'), findsOneWidget);
        expect(find.text('Hold your weight steady'), findsOneWidget);
        expect(
          find.text('Weight stays flat while body composition shifts'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(3));
        expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(3));
      });

      testWidgets('accepted goal reads Save roadmap', (tester) async {
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            goal: _goal(accepted: true),
          ),
        );
        expect(find.text('Save roadmap'), findsOneWidget);
        expect(find.text('Accept roadmap'), findsNothing);
      });

      testWidgets('stepper changes weeks and clamps at 2 and 52', (
        tester,
      ) async {
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            phases: [
              _row(1, DietPhase.cut, 3),
              _row(2, DietPhase.maintain, 52),
            ],
          ),
        );
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.remove_rounded).first,
        );
        await tester.pump();
        expect(find.text('2 weeks'), findsOneWidget);
        final fewer = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.remove_rounded).first,
        );
        expect(fewer.onPressed, isNull);
        final more = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add_rounded).last,
        );
        expect(more.onPressed, isNull);
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.add_rounded).first,
        );
        await tester.pump();
        expect(find.text('3 weeks'), findsOneWidget);
      });

      testWidgets('delete shows Undo that restores the row at its index', (
        tester,
      ) async {
        await _open(
          tester,
          _host(theme: theme, repo: _FakeRoadmapRepository()),
        );
        await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(1));
        await tester.pump();
        expect(find.text('Vzdrževanje'), findsNothing);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Phase removed'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        expect(find.text('Vzdrževanje'), findsOneWidget);
        expect(_y(tester, 'Redukcija') < _y(tester, 'Vzdrževanje'), isTrue);
        expect(_y(tester, 'Vzdrževanje') < _y(tester, 'Rekompozicija'), isTrue);
      });

      testWidgets('the last remaining phase cannot be deleted', (tester) async {
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            phases: [_row(1, DietPhase.maintain, 4)],
          ),
        );
        final del = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
        );
        expect(del.onPressed, isNull);
      });

      testWidgets('Move up / Move down semantics reorder without dragging', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _open(
          tester,
          _host(theme: theme, repo: _FakeRoadmapRepository()),
        );
        expect(_hasCustom(tester, 'Move up'), isTrue);
        expect(_hasCustom(tester, 'Move down'), isTrue);
        // First row (Cut) moves down: Maintain now precedes Cut.
        _performCustom(tester, 'Move down', 0);
        await tester.pumpAndSettle();
        expect(_y(tester, 'Vzdrževanje') < _y(tester, 'Redukcija'), isTrue);
        expect(_y(tester, 'Redukcija') < _y(tester, 'Rekompozicija'), isTrue);
        // Move the last row up.
        _performCustom(tester, 'Move up', -1);
        await tester.pumpAndSettle();
        expect(_y(tester, 'Rekompozicija') < _y(tester, 'Redukcija'), isTrue);
        handle.dispose();
      });

      testWidgets('single row exposes no move actions', (tester) async {
        final handle = tester.ensureSemantics();
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            phases: [_row(1, DietPhase.maintain, 4)],
          ),
        );
        expect(_hasCustom(tester, 'Move up'), isFalse);
        expect(_hasCustom(tester, 'Move down'), isFalse);
        handle.dispose();
      });

      testWidgets('drag handle reorder smoke test', (tester) async {
        await _open(
          tester,
          _host(theme: theme, repo: _FakeRoadmapRepository()),
        );
        final handle = find.byIcon(Icons.drag_indicator_rounded).first;
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await tester.pump(const Duration(milliseconds: 100));
        for (var i = 0; i < 5; i++) {
          await gesture.moveBy(const Offset(0, 60));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(_y(tester, 'Redukcija') > _y(tester, 'Vzdrževanje'), isTrue);
      });

      testWidgets('restricted phases are disabled with the reason shown', (
        tester,
      ) async {
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            eligibility: PhysiqueGuardrails.ageEligibility(16),
          ),
        );
        expect(
          find.textContaining('Redukcija in Masa nista na voljo pod 18 let'),
          findsOneWidget,
        );
        await tester.tap(find.text('Add phase'));
        await tester.pump();
        // The row list still shows Cut; the picker adds a second "Cut" pill.
        expect(find.text('Redukcija'), findsNWidgets(2));
        final rows = find.text('Masa');
        expect(rows, findsOneWidget);
        await tester.tap(rows);
        await tester.pump();
        // Bulk was ignored: still three rows.
        expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(3));
        // Allowed phase appends with 8 weeks.
        await tester.tap(find.text('Čista rast'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(4));
        expect(find.text('8 weeks'), findsNWidgets(2));
      });

      testWidgets('reset to suggestion confirms, then replaces drafts', (
        tester,
      ) async {
        await _open(
          tester,
          _host(
            theme: theme,
            repo: _FakeRoadmapRepository(),
            suggestion: _suggestion(),
          ),
        );
        await tester.tap(find.text('Reset to suggestion'));
        await tester.pumpAndSettle();
        expect(find.text('Reset your roadmap?'), findsOneWidget);
        await tester.tap(find.text('Keep my edits'));
        await tester.pumpAndSettle();
        expect(find.text('Redukcija'), findsOneWidget);
        await tester.tap(find.text('Reset to suggestion'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset roadmap'));
        await tester.pumpAndSettle();
        expect(find.text('Redukcija'), findsNothing);
        expect(find.text('Masa'), findsOneWidget);
        expect(find.text('20 weeks'), findsOneWidget);
      });

      testWidgets('reset is hidden without a suggestion', (tester) async {
        await _open(
          tester,
          _host(theme: theme, repo: _FakeRoadmapRepository()),
        );
        expect(find.text('Reset to suggestion'), findsNothing);
      });

      testWidgets('accept retargets with a weight and passes accept: true', (
        tester,
      ) async {
        final repo = _FakeRoadmapRepository();
        await _open(
          tester,
          _host(theme: theme, repo: repo, profile: _profile(90)),
        );
        await tester.tap(find.text('Accept roadmap'));
        await tester.pumpAndSettle();
        expect(repo.calls, 1);
        expect(repo.accepted, isTrue);
        // retarget recomputes targets; the fixtures' 81.0 is replaced.
        expect(repo.saved!.length, 3);
        expect(repo.saved!.first.targetWeightKg, isNot(81.0));
        expect(find.text('Your roadmap'), findsNothing);
      });

      testWidgets('saving an accepted roadmap passes accept: false', (
        tester,
      ) async {
        final repo = _FakeRoadmapRepository();
        await _open(
          tester,
          _host(theme: theme, repo: repo, goal: _goal(accepted: true)),
        );
        await tester.tap(find.text('Save roadmap'));
        await tester.pumpAndSettle();
        expect(repo.accepted, isFalse);
      });

      testWidgets(
        'no start weight: drafts saved as-is and Add phase is disabled',
        (tester) async {
          final repo = _FakeRoadmapRepository();
          await _open(
            tester,
            _host(
              theme: theme,
              repo: repo,
              goal: _goal(startWeightKg: null, targetBf: null),
            ),
          );
          expect(
            find.text('Add your weight in Profile to add phases.'),
            findsOneWidget,
          );
          final add = tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Add phase'),
          );
          expect(add.onPressed, isNull);
          // Reorder, resize and remove still work.
          await tester.tap(
            find.widgetWithIcon(IconButton, Icons.add_rounded).first,
          );
          await tester.pump();
          await tester.tap(find.text('Accept roadmap'));
          await tester.pumpAndSettle();
          final saved = repo.saved!;
          expect(saved.first.plannedWeeks, 13);
          expect(saved.first.targetWeightKg, 81.0);
          expect(saved.first.weeklyRateKg, 0.5);
          expect(saved.first.tempoCapped, isTrue);
          expect(saved[1].targetWeightKg, 82.0);
        },
      );

      testWidgets('dismissing with unsaved edits asks to discard', (
        tester,
      ) async {
        await _open(
          tester,
          _host(theme: theme, repo: _FakeRoadmapRepository()),
        );
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.add_rounded).first,
        );
        await tester.pump();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.text('Your roadmap'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard changes'));
        await tester.pumpAndSettle();
        expect(find.text('Your roadmap'), findsNothing);
      });

      testWidgets('dismissing without edits closes immediately', (
        tester,
      ) async {
        await _open(
          tester,
          _host(theme: theme, repo: _FakeRoadmapRepository()),
        );
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.text('Your roadmap'), findsNothing);
      });
    });
  }
}
