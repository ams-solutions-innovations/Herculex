// Phase 29 (RPT-04, GDPR Art. 9): a weekly report is aggregated health data,
// so the local wipe that account deletion runs must clear `weekly_reports`.
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/local_data_wipe.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wipe clears weekly_reports', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    await db
        .into(db.weeklyReports)
        .insert(
          WeeklyReportsCompanion.insert(
            isoYear: 2026,
            isoWeek: 40,
            weekStartIso: '2026-09-28',
            payloadJson: '{"sleep":7.5}',
          ),
        );
    expect(await db.select(db.weeklyReports).get(), hasLength(1));

    await wipeAllLocalUserData(db);

    expect(await db.select(db.weeklyReports).get(), isEmpty);
  });
}
