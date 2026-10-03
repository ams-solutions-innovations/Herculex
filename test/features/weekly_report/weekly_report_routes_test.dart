import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/router/routes.dart';

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
}
