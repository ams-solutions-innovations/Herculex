import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/error/app_error_view.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_controller.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_service.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_report_view.dart';
import 'package:herculex/features/weekly_report/presentation/views/weekly_reports_history_view.dart';

import '../../support/fake_clock.dart';

class _NoopController implements WeeklyReportController {
  @override
  Future<WeeklyReportOpenResult> open(IsoWeek week) async =>
      const WeeklyReportNoData();

  @override
  Future<NarrativeOutcome> retryNarrative(IsoWeek week) async =>
      NarrativeOutcome.alreadySaved;

  @override
  Future<NarrativeOutcome>? narrationInFlight(IsoWeek week) => null;
}

List<String> _flatten(List<RouteBase> routes) => [
  for (final r in routes)
    if (r is GoRoute) r.path,
];

/// Pumps a router whose weekly-report routes use the production builders,
/// parked at [location].
Future<void> _pumpAt(WidgetTester tester, String location) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.weeklyReports,
        builder: (_, _) => const WeeklyReportsHistoryView(),
      ),
      GoRoute(path: AppRoutes.weeklyReport, builder: buildWeeklyReportRoute),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weeklyReportControllerProvider.overrideWithValue(_NoopController()),
        weeklyReportProvider.overrideWith((ref, week) => Stream.value(null)),
        weeklyReportHistoryProvider.overrideWith((ref) => Stream.value([])),
        weeklyReportEnabledProvider.overrideWithValue(true),
        weeklyReportDueWeekProvider.overrideWithValue(null),
        clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 5, 9))),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('weekly report route constants', () {
    test('AppPaths.weeklyReport builds the concrete path', () {
      expect(AppPaths.weeklyReport(2026, 40), '/weekly-report/2026/40');
    });

    test('AppRoutes.weeklyReport carries both path parameters', () {
      expect(AppRoutes.weeklyReport, contains(':isoYear'));
      expect(AppRoutes.weeklyReport, contains(':isoWeek'));
    });

    test('AppRoutes.weeklyReports is the history list', () {
      expect(AppRoutes.weeklyReports, '/weekly-reports');
    });
  });

  group('weekly report route registration', () {
    test('routerProvider registers both weekly report paths', () {
      final container = ProviderContainer(
        overrides: [profileProvider.overrideWith((ref) => Stream.value(null))],
      );
      addTearDown(container.dispose);
      final paths = _flatten(
        container.read(routerProvider).configuration.routes,
      );
      expect(paths, contains(AppRoutes.weeklyReports));
      expect(paths, contains(AppRoutes.weeklyReport));
    });
  });

  group('weekly report route builders', () {
    testWidgets('/weekly-reports builds the history view', (tester) async {
      await _pumpAt(tester, AppRoutes.weeklyReports);
      expect(find.byType(WeeklyReportsHistoryView), findsOneWidget);
    });

    testWidgets('a valid path builds WeeklyReportView for that week', (
      tester,
    ) async {
      await _pumpAt(tester, AppPaths.weeklyReport(2026, 40));
      final view = tester.widget<WeeklyReportView>(
        find.byType(WeeklyReportView),
      );
      expect(view.week, IsoWeek(2026, 40));
    });

    for (final bad in const [
      '/weekly-report/2026/99',
      '/weekly-report/2026/0',
      '/weekly-report/abc/40',
      '/weekly-report/2026/xyz',
      '/weekly-report/2027/53',
    ]) {
      testWidgets('$bad shows the bad-parameter screen', (tester) async {
        await _pumpAt(tester, bad);
        expect(find.byType(WeeklyReportView), findsNothing);
        expect(find.byType(AppErrorScreen), findsOneWidget);
      });
    }
  });
}
