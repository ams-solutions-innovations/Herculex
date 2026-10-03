import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_reports_history_view.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/weekly_report_ready_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/weekly_reports_entry_card.dart';

import '../../support/fake_clock.dart';
import '../../support/go_router_test_harness.dart';

String _payload(IsoWeek week, {bool nutrition = true, bool physique = false}) {
  final payload = WeeklyReportPayload(
    isoYear: week.isoYear,
    isoWeek: week.isoWeek,
    weekStartIso: week.startIso,
    weekEndIso: week.endIso,
    windowEnd: week.endExclusive,
    nutrition: nutrition
        ? const NutritionSection(
            daysLogged: 4,
            avgKcal: 2000,
            avgProteinG: 120,
            topFoods: [],
          )
        : null,
    physique: physique
        ? const PhysiqueSection(bodyweightKg: 80, bodyweightDeltaKg: 0)
        : null,
  );
  return jsonEncode(payload.toJson());
}

WeeklyReportRecord _record(
  IsoWeek week, {
  String? payloadJson,
  String? narrativeJson,
  DateTime? viewedAt,
}) {
  return WeeklyReportRecord(
    id: week.isoYear * 100 + week.isoWeek,
    week: week,
    weekStartIso: week.startIso,
    generatedAt: DateTime(2026, 10, 4, 18),
    payloadVersion: 1,
    payloadJson: payloadJson ?? _payload(week),
    narrativeJson: narrativeJson,
    narrativeAttempts: 0,
    knowledgeVersion: null,
    modelVersion: null,
    tdeeDecision: null,
    tdeeDecisionKcal: null,
    viewedAt: viewedAt,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<WeeklyReportRecord> records,
  bool enabled = true,
  DateTime? now,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = GoRouterTestHarness(
    home: (_) => const WeeklyReportsHistoryView(),
    stubRoutes: {
      AppRoutes.notifications: (context, state) =>
          const StubRouteScreen(label: 'Notifications'),
      AppRoutes.weeklyReport: (context, state) => StubRouteScreen(
        label: 'Report',
        value:
            '${state.pathParameters['isoYear']}-${state.pathParameters['isoWeek']}',
      ),
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weeklyReportHistoryProvider.overrideWith(
          (ref) => Stream.value(records),
        ),
        weeklyReportEnabledProvider.overrideWithValue(enabled),
        clockProvider.overrideWithValue(
          FakeClock(now ?? DateTime(2026, 10, 3, 12)),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: harness.router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('WeeklyReportsHistoryView', () {
    testWidgets('lists reports newest first', (tester) async {
      await _pump(
        tester,
        records: [
          _record(IsoWeek(2026, 38)),
          _record(IsoWeek(2026, 40)),
          _record(IsoWeek(2026, 39)),
        ],
      );
      final y40 = tester.getTopLeft(find.text('Week 40')).dy;
      final y39 = tester.getTopLeft(find.text('Week 39')).dy;
      final y38 = tester.getTopLeft(find.text('Week 38')).dy;
      expect(y40, lessThan(y39));
      expect(y39, lessThan(y38));
    });

    testWidgets('shows the Monday to Sunday range', (tester) async {
      await _pump(tester, records: [_record(IsoWeek(2026, 40))]);
      expect(find.text('Mon 28 Sep – Sun 4 Oct'), findsOneWidget);
    });

    testWidgets('unread dot only when viewedAt is null', (tester) async {
      await _pump(
        tester,
        records: [
          _record(IsoWeek(2026, 40)),
          _record(IsoWeek(2026, 39), viewedAt: DateTime(2026, 10, 1)),
        ],
      );
      final unread = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Unread',
      );
      expect(unread, findsOneWidget);
    });

    testWidgets('pending pill needs an empty narrative and a signal', (
      tester,
    ) async {
      await _pump(
        tester,
        records: [
          // Narrative signal, no narrative -> pill.
          _record(IsoWeek(2026, 40)),
          // Narrative present -> no pill.
          _record(IsoWeek(2026, 39), narrativeJson: '{"summary":"x"}'),
          // Physique only -> no narrative signal -> no pill.
          _record(
            IsoWeek(2026, 38),
            payloadJson: _payload(
              IsoWeek(2026, 38),
              nutrition: false,
              physique: true,
            ),
          ),
          // Undecodable payload -> no pill, no crash.
          _record(IsoWeek(2026, 37), payloadJson: 'not json'),
        ],
      );
      expect(find.text('Narrative pending'), findsOneWidget);
      expect(find.text('Week 37'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every row is at least 48 high', (tester) async {
      await _pump(tester, records: [_record(IsoWeek(2026, 40))]);
      expect(
        tester.getSize(find.byType(HxCard).first).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('tapping a row opens that week', (tester) async {
      await _pump(tester, records: [_record(IsoWeek(2026, 40))]);
      await tester.tap(find.text('Week 40'));
      await tester.pumpAndSettle();
      expect(find.text('Report:2026-40'), findsOneWidget);
    });

    testWidgets('empty state with opt-in on offers this week', (tester) async {
      await _pump(tester, records: const []);
      expect(find.text('No weekly reports yet'), findsOneWidget);
      expect(
        find.text(
          "Turn on Weekly report in notification settings. Your first report appears on Sunday, or open this week's now.",
        ),
        findsOneWidget,
      );
      expect(find.text('Turn on weekly report'), findsNothing);
      await tester.tap(find.text("Open this week's report"));
      await tester.pumpAndSettle();
      // 2026-10-03 is a Saturday in ISO week 40.
      expect(find.text('Report:2026-40'), findsOneWidget);
    });

    testWidgets('empty state with opt-in off has no open button', (
      tester,
    ) async {
      await _pump(tester, records: const [], enabled: false);
      expect(find.text('No weekly reports yet'), findsOneWidget);
      expect(find.text("Open this week's report"), findsNothing);
      expect(find.text('Turn on weekly report'), findsOneWidget);
    });

    testWidgets('opt-in off keeps history and shows a banner to settings', (
      tester,
    ) async {
      await _pump(
        tester,
        records: [_record(IsoWeek(2026, 40))],
        enabled: false,
      );
      expect(find.text('Week 40'), findsOneWidget);
      expect(find.text('Turn on weekly report'), findsOneWidget);
      await tester.tap(find.text('Turn on weekly report'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('opt-in on shows no banner', (tester) async {
      await _pump(tester, records: [_record(IsoWeek(2026, 40))]);
      expect(find.text('Turn on weekly report'), findsNothing);
    });
  });

  group('WeeklyReportsEntryCard', () {
    testWidgets('is at least 48 high and opens the history', (tester) async {
      await _pumpCard(tester, const WeeklyReportsEntryCard());
      expect(find.text('Weekly reports'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(
        tester.getSize(find.byType(HxCard)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Weekly reports'));
      await tester.pumpAndSettle();
      expect(find.text('Weekly reports list'), findsOneWidget);
    });
  });

  group('WeeklyReportReadyCard', () {
    testWidgets('renders nothing when no report is ready', (tester) async {
      await _pumpCard(tester, const WeeklyReportReadyCard());
      expect(find.byType(HxCard), findsNothing);
      expect(find.textContaining('is ready'), findsNothing);
    });

    testWidgets('shows the ready week and opens it on tap', (tester) async {
      await _pumpCard(
        tester,
        const WeeklyReportReadyCard(),
        ready: IsoWeek(2026, 40),
      );
      expect(find.text('Your week 40 report is ready'), findsOneWidget);
      expect(find.text('Tap to open'), findsOneWidget);
      expect(find.byIcon(Icons.insights), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      expect(
        tester.getSize(find.byType(HxCard)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Your week 40 report is ready'));
      await tester.pumpAndSettle();
      expect(find.text('Report:2026-40'), findsOneWidget);
    });

    testWidgets('disappears when the ready provider turns null', (
      tester,
    ) async {
      final container = await _pumpCard(
        tester,
        const WeeklyReportReadyCard(),
        ready: IsoWeek(2026, 40),
      );
      expect(find.text('Tap to open'), findsOneWidget);
      container.read(_readyState.notifier).state = null;
      await tester.pumpAndSettle();
      expect(find.text('Tap to open'), findsNothing);
    });
  });
}

final _readyState = StateProvider<IsoWeek?>((ref) => null);

Future<ProviderContainer> _pumpCard(
  WidgetTester tester,
  Widget card, {
  IsoWeek? ready,
}) async {
  final harness = GoRouterTestHarness(
    home: (_) => Scaffold(body: card),
    stubRoutes: {
      AppRoutes.weeklyReports: (context, state) =>
          const StubRouteScreen(label: 'Weekly reports list'),
      AppRoutes.weeklyReport: (context, state) => StubRouteScreen(
        label: 'Report',
        value:
            '${state.pathParameters['isoYear']}-${state.pathParameters['isoWeek']}',
      ),
    },
  );
  final container = ProviderContainer(
    overrides: [
      weeklyReportReadyProvider.overrideWith((ref) => ref.watch(_readyState)),
    ],
  );
  addTearDown(container.dispose);
  container.read(_readyState.notifier).state = ready;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: harness.router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
