import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_tdee_actions.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/tdee_target_proposal.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/tdee_shift_card.dart';

import '../../support/fake_clock.dart';

const _section = TdeeSection(
  oldKcal: 2500,
  newKcal: 2640,
  deltaKcal: 140,
  material: true,
  confidence: 'medium',
);

const _proposal = TdeeTargetProposal(
  kcal: 2540,
  proteinG: 180,
  carbsG: 298,
  fatG: 70,
  appliesTo: 'global',
);

const _rule = TargetRule(
  kcal: 2400,
  proteinG: 180,
  carbsG: 250,
  fatG: 70,
  appliesTo: 'global',
);

WeeklyReportRecord _record({
  IsoWeek? week,
  String? decision,
  int? decisionKcal,
}) => WeeklyReportRecord(
  id: 1,
  week: week ?? IsoWeek(2026, 40),
  weekStartIso: '2026-09-28',
  generatedAt: DateTime(2026, 10, 1),
  payloadVersion: 1,
  payloadJson: '{}',
  narrativeJson: null,
  narrativeAttempts: 0,
  knowledgeVersion: null,
  modelVersion: null,
  tdeeDecision: decision,
  tdeeDecisionKcal: decisionKcal,
  viewedAt: null,
);

class _FakeActions implements TdeeDecisionActions {
  final updates =
      <
        ({IsoWeek week, TdeeTargetProposal displayed, int oldKcal, int newKcal})
      >[];
  final keeps = <({IsoWeek week, int currentKcal})>[];
  Completer<TdeeActionResult>? gate;
  TdeeActionResult result = TdeeActionResult.applied;
  Object? error;

  Future<TdeeActionResult> _answer() async {
    if (error != null) throw error!;
    return gate?.future ?? result;
  }

  @override
  Future<TdeeActionResult> update({
    required IsoWeek week,
    required int oldEstimateKcal,
    required int newEstimateKcal,
    required TdeeTargetProposal displayed,
  }) {
    updates.add((
      week: week,
      displayed: displayed,
      oldKcal: oldEstimateKcal,
      newKcal: newEstimateKcal,
    ));
    return _answer();
  }

  @override
  Future<TdeeActionResult> keep({
    required IsoWeek week,
    required int currentKcal,
  }) {
    keeps.add((week: week, currentKcal: currentKcal));
    return _answer();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required WeeklyReportRecord record,
  required _FakeActions actions,
  TdeeTargetProposalResult? result,
  IsoWeek? dueWeek,
  TargetRule rule = _rule,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final proposalResult =
      result ??
      const TdeeTargetProposalResult(TdeeProposalStatus.proposed, _proposal);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 1, 9))),
        weeklyReportDueWeekProvider.overrideWithValue(dueWeek),
        tdeeDecisionActionsProvider.overrideWithValue(actions),
        tdeeTargetProposalProvider.overrideWith(
          (ref, shift) async => proposalResult,
        ),
        savedTargetForTodayProvider.overrideWith((ref) async => rule),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TdeeShiftCard(record: record, section: _section),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _updateButton => find.text('Update my target to 2540 kcal');
Finder get _keepButton => find.text('Keep current target');

void main() {
  group('TdeeShiftCard actionable', () {
    testWidgets('shows the shift, the delta and both actions', (tester) async {
      await _pump(tester, record: _record(), actions: _FakeActions());
      expect(find.text('Your energy estimate moved'), findsOneWidget);
      expect(find.text('2500 → 2640 kcal'), findsOneWidget);
      expect(find.textContaining('+140'), findsOneWidget);
      expect(_updateButton, findsOneWidget);
      expect(_keepButton, findsOneWidget);
      expect(
        tester.getSize(find.byType(PremiumButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(find.widgetWithText(TextButton, 'Keep current target'))
            .height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('the due week is actionable too', (tester) async {
      await _pump(
        tester,
        record: _record(week: IsoWeek(2026, 39)),
        actions: _FakeActions(),
        dueWeek: IsoWeek(2026, 39),
      );
      expect(_updateButton, findsOneWidget);
    });

    testWidgets('Update calls the action once and shows a snackbar', (
      tester,
    ) async {
      final actions = _FakeActions();
      await _pump(tester, record: _record(), actions: actions);
      await tester.tap(_updateButton);
      await tester.pump();
      await tester.pump();
      expect(actions.updates, hasLength(1));
      expect(actions.updates.single.displayed.kcal, 2540);
      expect(actions.updates.single.oldKcal, 2500);
      expect(actions.updates.single.newKcal, 2640);
      expect(actions.updates.single.week, IsoWeek(2026, 40));
      expect(actions.keeps, isEmpty);
      expect(find.text('Target updated to 2540 kcal'), findsOneWidget);
    });

    testWidgets('Keep calls keep once with the saved rule kcal', (
      tester,
    ) async {
      final actions = _FakeActions();
      await _pump(tester, record: _record(), actions: actions);
      await tester.tap(_keepButton);
      await tester.pump();
      expect(actions.keeps, hasLength(1));
      expect(actions.keeps.single.currentKcal, 2400);
      expect(actions.updates, isEmpty);
    });

    testWidgets('both buttons ignore taps while a call runs', (tester) async {
      final actions = _FakeActions()..gate = Completer<TdeeActionResult>();
      await _pump(tester, record: _record(), actions: actions);
      await tester.tap(_updateButton);
      await tester.pump();
      await tester.tap(_updateButton, warnIfMissed: false);
      await tester.tap(_keepButton, warnIfMissed: false);
      await tester.pump();
      expect(actions.updates, hasLength(1));
      expect(actions.keeps, isEmpty);
      actions.gate!.complete(TdeeActionResult.applied);
      await tester.pumpAndSettle();
    });
    group('results and failures', () {
      Future<void> tapUpdate(WidgetTester tester, _FakeActions actions) async {
        await _pump(tester, record: _record(), actions: actions);
        await tester.tap(_updateButton);
        await tester.pump();
        await tester.pump();
      }

      void expectEnabled(WidgetTester tester) {
        expect(
          tester
              .widget<IgnorePointer>(
                find
                    .ancestor(
                      of: find.byType(PremiumButton),
                      matching: find.byType(IgnorePointer),
                    )
                    .first,
              )
              .ignoring,
          isFalse,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Keep current target'),
              )
              .onPressed,
          isNotNull,
        );
      }

      final cases = <TdeeActionResult, String>{
        TdeeActionResult.alreadyDecided:
            'You already made this choice for this week.',
        TdeeActionResult.stale:
            'Your target changed since this suggestion. '
            'Review it in nutrition settings.',
        TdeeActionResult.notActionable: 'This report is read-only.',
        TdeeActionResult.invalidInput: "Couldn't save your choice. Try again.",
      };
      for (final entry in cases.entries) {
        testWidgets('update ${entry.key.name} shows a message and re-enables', (
          tester,
        ) async {
          final actions = _FakeActions()..result = entry.key;
          await tapUpdate(tester, actions);
          expect(find.text(entry.value), findsOneWidget);
          expectEnabled(tester);
        });
      }

      testWidgets('success clears busy even if the record has not updated', (
        tester,
      ) async {
        final actions = _FakeActions();
        await tapUpdate(tester, actions);
        expect(find.text('Target updated to 2540 kcal'), findsOneWidget);
        expectEnabled(tester);
      });

      testWidgets('an exception shows the failure message and re-enables', (
        tester,
      ) async {
        final actions = _FakeActions()..error = StateError('x');
        await tapUpdate(tester, actions);
        expect(
          find.text("Couldn't update your target. Try again."),
          findsOneWidget,
        );
        expectEnabled(tester);
      });

      testWidgets('keep exception shows a message and re-enables', (
        tester,
      ) async {
        final actions = _FakeActions()..error = StateError('x');
        await _pump(tester, record: _record(), actions: actions);
        await tester.tap(_keepButton);
        await tester.pump();
        await tester.pump();
        expect(
          find.text("Couldn't save your choice. Try again."),
          findsOneWidget,
        );
        expectEnabled(tester);
      });

      testWidgets('keep with a saved kcal below 800 does not call the action', (
        tester,
      ) async {
        final actions = _FakeActions();
        await _pump(
          tester,
          record: _record(),
          actions: actions,
          rule: const TargetRule(
            kcal: 799,
            proteinG: 100,
            carbsG: 100,
            fatG: 30,
            appliesTo: 'global',
          ),
        );
        await tester.tap(_keepButton);
        await tester.pump();
        expect(actions.keeps, isEmpty);
        expect(
          find.text("Couldn't save your choice. Try again."),
          findsOneWidget,
        );
      });
    });
  });

  group('TdeeShiftCard read-only states', () {
    testWidgets('an updated decision shows its label and no buttons', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(decision: 'updated', decisionKcal: 2540),
        actions: _FakeActions(),
      );
      expect(find.text('You updated your target to 2540 kcal'), findsOneWidget);
      expect(find.byType(PremiumButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(_keepButton, findsNothing);
    });

    testWidgets('a kept decision shows its label and no buttons', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(decision: 'kept', decisionKcal: 2400),
        actions: _FakeActions(),
      );
      expect(find.text('You kept your target at 2400 kcal'), findsOneWidget);
      expect(find.byType(PremiumButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a past undecided week is read-only', (tester) async {
      await _pump(
        tester,
        record: _record(week: IsoWeek(2026, 36)),
        actions: _FakeActions(),
        dueWeek: IsoWeek(2026, 39),
      );
      expect(
        find.text('Your energy estimate moved from 2500 to 2640 kcal.'),
        findsOneWidget,
      );
      expect(find.byType(PremiumButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('no saved rule explains that the target follows the estimate', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(),
        actions: _FakeActions(),
        result: const TdeeTargetProposalResult(TdeeProposalStatus.noSavedRule),
      );
      expect(
        find.text('Your target already follows your energy estimate.'),
        findsOneWidget,
      );
      expect(find.byType(PremiumButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    for (final status in [
      TdeeProposalStatus.noChange,
      TdeeProposalStatus.belowMacroFloor,
    ]) {
      testWidgets('$status offers nothing', (tester) async {
        await _pump(
          tester,
          record: _record(),
          actions: _FakeActions(),
          result: TdeeTargetProposalResult(status),
        );
        expect(
          find.text('No target change is suggested for this shift.'),
          findsOneWidget,
        );
        expect(find.byType(PremiumButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
      });
    }
  });
}
