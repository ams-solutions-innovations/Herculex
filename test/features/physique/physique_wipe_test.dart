import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/local_data_wipe.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory docs;

  setUp(() async {
    db = await openTestDatabase();
    docs = Directory.systemTemp.createTempSync('wipe_docs_');
  });
  tearDown(() async {
    await db.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<int> countOf(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  test('folder name constant equals PhysiquePhotoStore.rootFolderName', () {
    expect(physiquePhotoFolderName, PhysiquePhotoStore.rootFolderName);
  });

  test('wipe clears physique tables and deletes the photo folder', () async {
    final repo = PhysiqueGoalRepository(db, FakeClock(DateTime(2026, 10, 1)));
    await repo.startGoal(
      StartGoalInput(
        estimatedMonths: 6,
        targetBfPercent: 12,
        analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 1))],
        roadmap: const [],
        baselinePhotos: [
          NewPhotoRow(
            pose: 'front',
            relativePath: 'physique/g1/a.jpg',
            takenAt: DateTime(2026, 9, 1),
          ),
        ],
      ),
    );
    final file = File('${docs.path}/physique/g1/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    expect(countOf('physique_goals'), completion(1));

    await wipeAllLocalUserData(db, documentsDirectory: docs);

    for (final t in [
      'physique_goals',
      'physique_assessments',
      'physique_roadmap_phases',
      'physique_photos',
      'tdee_estimates',
      'herculex_ai_program_briefs',
    ]) {
      expect(await countOf(t), 0, reason: t);
    }
    expect(file.existsSync(), isFalse);
    expect(Directory('${docs.path}/physique').existsSync(), isFalse);
  });

  test('wipe without a documents directory does not throw', () async {
    await wipeAllLocalUserData(db);
  });
}
