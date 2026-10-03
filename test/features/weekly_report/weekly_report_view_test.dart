import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_controller.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_narrative_service.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_service.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_report_view.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/ai_narrative_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/nutrition_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/physique_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/recovery_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/tdee_shift_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/training_section_card.dart';

import '../../support/fake_clock.dart';
import '../../support/go_router_test_harness.dart';

final _week = IsoWeek(2026, 40);

const _tdeeMaterial = TdeeSection(
  oldKcal: 2500,
  newKcal: 2640,
  deltaKcal: 140,
  material: true,
  confidence: 'medium',
);

const _tdeeSmall = TdeeSection(
  oldKcal: 2500,
  newKcal: 2520,
  deltaKcal: 20,
  material: false,
  confidence: 'medium',
);

const _narrativeJson =
    '{"summary":"You ate steadily and trained three times.",'
    '"suggestions":["Keep protein steady.","Add one easy walk."]}';

String _payload(
  IsoWeek week, {
  bool nutrition = true,
  bool training = true,
  bool recovery = true,
  bool physique = true,
  TdeeSection? tdee,
}) {
  final payload = WeeklyReportPayload(
    isoYear: week.isoYear,
    isoWeek: week.isoWeek,
    weekStartIso: week.startIso,
    weekEndIso: week.endIso,
    windowEnd: week.endExclusive,
    nutrition: nutrition
        ? const NutritionSection(
            daysLogged: 6,
            avgKcal: 2314,
            avgProteinG: 151,
            topFoods: [],
          )
        : null,
    training: training
        ? const TrainingSection(sessions: 3, tonnageKg: 12345, e1rmMovers: [])
        : null,
    recovery: recovery
        ? const RecoverySection(
            cnsDeloadSuggested: false,
            recoveryWarnings: [],
            correlations: [],
            avgSleepHours: 7.5,
          )
        : null,
    physique: physique
        ? const PhysiqueSection(bodyweightKg: 80, bodyweightDeltaKg: -0.5)
        : null,
    tdee: tdee,
  );
  return jsonEncode(payload.toJson());
}

WeeklyReportRecord _record({
  IsoWeek? week,
  String? payloadJson,
  String? narrativeJson,
  DateTime? generatedAt,
}) {
  final w = week ?? _week;
  return WeeklyReportRecord(
    id: 1,
    week: w,
    weekStartIso: w.startIso,
    generatedAt: generatedAt ?? DateTime(2026, 10, 4, 18),
    payloadVersion: 1,
    payloadJson: payloadJson ?? _payload(w),
    narrativeJson: narrativeJson,
    narrativeAttempts: 0,
    knowledgeVersion: null,
    modelVersion: null,
    tdeeDecision: null,
    tdeeDecisionKcal: null,
    viewedAt: null,
  );
}

class _FakeController implements WeeklyReportController {
  _FakeController({this.openResult = const WeeklyReportNoData()});

  final WeeklyReportOpenResult openResult;
  final opened = <IsoWeek>[];
  final retried = <IsoWeek>[];

  @override
  Future<WeeklyReportOpenResult> open(IsoWeek week) async {
    opened.add(week);
    return openResult;
  }

  @override
  Future<NarrativeOutcome> retryNarrative(IsoWeek week) async {
    retried.add(week);
    return NarrativeOutcome.alreadySaved;
  }

  @override
  Future<NarrativeOutcome>? narrationInFlight(IsoWeek week) => null;
}

class _Harness {
  _Harness({
    this.record,
    this.enabled = true,
    this.ui = const NarrativeUiState(),
    DateTime? now,
    WeeklyReportOpenResult openResult = const WeeklyReportNoData(),
  }) : controller = _FakeController(openResult: openResult),
       clock = FakeClock(now ?? DateTime(2026, 10, 5, 9));

  final WeeklyReportRecord? record;
  final bool enabled;
  final NarrativeUiState ui;
  final _FakeController controller;
  final FakeClock clock;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  WeeklyReportRecord? record,
  bool enabled = true,
  NarrativeUiState ui = const NarrativeUiState(),
  DateTime? now,
  WeeklyReportOpenResult openResult = const WeeklyReportNoData(),
}) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness(
    record: record,
    enabled: enabled,
    ui: ui,
    now: now,
    openResult: openResult,
  );
  final router = GoRouterTestHarness(
    home: (_) => WeeklyReportView(week: _week),
    stubRoutes: {
      AppRoutes.notifications: (context, state) =>
          const StubRouteScreen(label: 'Notifications'),
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weeklyReportControllerProvider.overrideWithValue(h.controller),
        weeklyReportProvider.overrideWith((ref, week) {
          return Stream.value(h.record);
        }),
        weeklyReportEnabledProvider.overrideWithValue(enabled),
        weeklyReportDueWeekProvider.overrideWithValue(null),
        clockProvider.overrideWithValue(h.clock),
        narrativeUiStateProvider.overrideWith((ref, week) => ui),
        // A live target that differs from anything in the payload: the report
        // must never read it.
        savedTargetForTodayProvider.overrideWith(
          (ref) async => const TargetRule(
            kcal: 9999,
            proteinG: 999,
            carbsG: 999,
            fatG: 99,
            appliesTo: 'global',
          ),
        ),
      ],
      child: MaterialApp.router(
        // Pinky: its primary differs from every domain colour, unlike classicBlue
        // where primary == domainTraining, so a primary-tint check is meaningful.
        theme: AppTheme.darkThemeWith(AppColorTheme.pinky),
        routerConfig: router.router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Finder get _retry => find.text('Retry narrative');

void main() {
  group('WeeklyReportView generation', () {
    testWidgets('calls open(week) exactly once, even across rebuilds', (
      tester,
    ) async {
      final h = await _pump(tester, record: _record());
      expect(h.controller.opened, [_week]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.controller.opened, [_week]);
    });
  });

  group('WeeklyReportView layout', () {
    testWidgets('cards render in order with a 32 gap before the AI card', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(payloadJson: _payload(_week, tdee: _tdeeMaterial)),
      );
      double top(Type t) => tester.getTopLeft(find.byType(t)).dy;
      expect(top(NutritionSectionCard), lessThan(top(TrainingSectionCard)));
      expect(top(TrainingSectionCard), lessThan(top(RecoverySectionCard)));
      expect(top(RecoverySectionCard), lessThan(top(PhysiqueSectionCard)));
      expect(top(PhysiqueSectionCard), lessThan(top(TdeeShiftCard)));
      expect(top(TdeeShiftCard), lessThan(top(AiNarrativeCard)));
      final gap =
          tester.getTopLeft(find.byType(AiNarrativeCard)).dy -
          tester.getBottomLeft(find.byType(TdeeShiftCard)).dy;
      expect(gap, HxSpace.x8);
    });

    testWidgets('a non-material TDEE section mounts no TdeeShiftCard', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(payloadJson: _payload(_week, tdee: _tdeeSmall)),
      );
      expect(find.byType(TdeeShiftCard), findsNothing);
      expect(find.byType(NutritionSectionCard), findsOneWidget);
    });

    testWidgets('a null section renders No data this week', (tester) async {
      await _pump(
        tester,
        record: _record(payloadJson: _payload(_week, physique: false)),
      );
      expect(find.byType(PhysiqueSectionCard), findsOneWidget);
      expect(find.text('No data this week'), findsOneWidget);
    });

    testWidgets('shows the title and Monday to Sunday range', (tester) async {
      await _pump(tester, record: _record());
      expect(find.text('Week 40'), findsOneWidget);
      expect(find.text('Mon 28 Sep – Sun 4 Oct'), findsOneWidget);
    });

    testWidgets('a past week shows the snapshot caption', (tester) async {
      await _pump(
        tester,
        record: _record(generatedAt: DateTime(2026, 10, 4, 18)),
        now: DateTime(2026, 10, 12, 9),
      );
      expect(find.text('Snapshot from 4 Oct 2026'), findsOneWidget);
    });

    testWidgets('the current week shows no snapshot caption', (tester) async {
      await _pump(tester, record: _record(), now: DateTime(2026, 10, 1, 9));
      expect(find.textContaining('Snapshot from'), findsNothing);
    });

    testWidgets('only the AI card carries the brand tint', (tester) async {
      await _pump(
        tester,
        record: _record(payloadJson: _payload(_week, tdee: _tdeeMaterial)),
      );
      final hx = tester.element(find.byType(AiNarrativeCard)).hx;
      Finder primaryCardsIn(Type t) => find.descendant(
        of: find.byType(t),
        matching: find.byWidgetPredicate(
          (w) => w is HxCard && w.accent == hx.primary,
        ),
      );
      expect(primaryCardsIn(AiNarrativeCard), findsOneWidget);
      // Nutrition, recovery and the TDEE card use domain colours that differ
      // from the brand colour in every palette. (The training domain colour is
      // by design the same value as the brand colour, so it is not asserted
      // here; the AI card is told apart by its pill, glyph and position.)
      expect(primaryCardsIn(NutritionSectionCard), findsNothing);
      expect(primaryCardsIn(RecoverySectionCard), findsNothing);
      expect(primaryCardsIn(TdeeShiftCard), findsNothing);
      expect(find.byType(AiNarrativeCard), findsOneWidget);
    });

    testWidgets('values come from the stored payload, not live providers', (
      tester,
    ) async {
      await _pump(tester, record: _record());
      expect(find.text('2314'), findsOneWidget);
      expect(find.textContaining('9999'), findsNothing);
      expect(find.textContaining('999'), findsNothing);
    });
  });

  group('WeeklyReportView narrative states', () {
    testWidgets('saved narrative shows ready with the stored summary', (
      tester,
    ) async {
      await _pump(tester, record: _record(narrativeJson: _narrativeJson));
      expect(
        find.text('You ate steadily and trained three times.'),
        findsOneWidget,
      );
      expect(_retry, findsNothing);
    });

    testWidgets('in flight shows the loading state', (tester) async {
      await _pump(
        tester,
        record: _record(),
        ui: const NarrativeUiState(inFlight: true),
      );
      expect(find.text('Herculex AI is reading your week…'), findsOneWidget);
    });

    testWidgets('offline failure shows offline copy with Retry', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(),
        ui: const NarrativeUiState(failure: NarrativeFailureKind.offline),
      );
      expect(
        find.text("You're offline. Reconnect and tap Retry narrative."),
        findsOneWidget,
      );
      expect(_retry, findsOneWidget);
    });

    testWidgets('quota failure the same day disables Retry', (tester) async {
      final h = await _pump(
        tester,
        record: _record(),
        now: DateTime(2026, 10, 5, 9),
        ui: const NarrativeUiState(
          failure: NarrativeFailureKind.quotaExhausted,
          quotaDayIso: '2026-10-05',
        ),
      );
      expect(
        find.textContaining("You've used today's Herculex AI summaries"),
        findsOneWidget,
      );
      await tester.tap(_retry, warnIfMissed: false);
      await tester.pump();
      expect(h.controller.retried, isEmpty);
    });

    testWidgets('quota failure from an earlier day allows Retry', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        record: _record(),
        now: DateTime(2026, 10, 6, 9),
        ui: const NarrativeUiState(
          failure: NarrativeFailureKind.quotaExhausted,
          quotaDayIso: '2026-10-05',
        ),
      );
      await tester.tap(_retry);
      await tester.pump();
      expect(h.controller.retried, [_week]);
    });

    testWidgets('no narrative signal renders no AI card', (tester) async {
      await _pump(
        tester,
        record: _record(
          payloadJson: _payload(
            _week,
            nutrition: false,
            training: false,
            recovery: false,
          ),
        ),
      );
      expect(find.byType(AiNarrativeCard), findsNothing);
      expect(find.byType(PhysiqueSectionCard), findsOneWidget);
    });

    testWidgets('tapping Retry calls retryNarrative exactly once', (
      tester,
    ) async {
      final h = await _pump(tester, record: _record());
      await tester.tap(_retry);
      await tester.pump();
      expect(h.controller.retried, [_week]);
    });
  });

  group('WeeklyReportView error and empty states', () {
    testWidgets('a corrupt payload shows the error copy and no cards', (
      tester,
    ) async {
      await _pump(
        tester,
        record: _record(payloadJson: '{"payloadVersion": 99}'),
      );
      expect(
        find.text("Couldn't load this report. Go back and open it again."),
        findsOneWidget,
      );
      expect(find.byType(NutritionSectionCard), findsNothing);
      expect(find.byType(AiNarrativeCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opt-in off and no row shows the turn-on state', (
      tester,
    ) async {
      await _pump(tester, enabled: false);
      expect(find.text('Turn on weekly report'), findsOneWidget);
      expect(find.byType(NutritionSectionCard), findsNothing);
      await tester.tap(find.text('Turn on weekly report'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('opt-in off with a stored row still renders the report', (
      tester,
    ) async {
      await _pump(tester, record: _record(), enabled: false);
      expect(find.byType(NutritionSectionCard), findsOneWidget);
      expect(find.text('Turn on weekly report'), findsNothing);
    });

    testWidgets('a NoData open result shows No data this week only', (
      tester,
    ) async {
      await _pump(tester, openResult: const WeeklyReportNoData());
      expect(find.text('No data this week'), findsOneWidget);
      expect(find.byType(AiNarrativeCard), findsNothing);
      expect(find.byType(NutritionSectionCard), findsNothing);
    });

    testWidgets('a Failed open result shows the error copy', (tester) async {
      await _pump(tester, openResult: const WeeklyReportFailed());
      expect(
        find.text("Couldn't load this report. Go back and open it again."),
        findsOneWidget,
      );
    });
  });
}
