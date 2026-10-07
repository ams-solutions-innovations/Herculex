import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_legacy_migrator.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/exif_jpeg_fixture.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_face_detector.dart';
import '../../support/test_database.dart';

const _historyKey = 'herculex.dream_physique_summary_history.v1';
const _reportedKey =
    'herculex.physique_legacy_migration.v2_reported_unrecoverable';

class _ThrowingStart extends PhysiqueGoalRepository {
  _ThrowingStart(super.db, super.clock);
  @override
  Future<int> startGoal(StartGoalInput input) async =>
      throw StateError('start boom');
}

class _ThrowingAppend extends PhysiqueGoalRepository {
  _ThrowingAppend(super.db, super.clock);
  @override
  Future<int> appendLegacyPhotos(int goalId, List<NewPhotoRow> photos) async =>
      throw StateError('append boom');
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late Directory docs;
  late Directory staging;
  late Directory cache;
  late PhysiqueGoalRepository goals;
  late PhysiquePhotoStore store;
  late PhysiquePhotoSanitizer sanitizer;
  late SharedPreferences prefs;
  Profile? profile;

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 2, 9));
    docs = Directory.systemTemp.createTempSync('mig_docs_');
    staging = Directory.systemTemp.createTempSync('mig_stg_');
    cache = Directory.systemTemp.createTempSync('mig_cache_');
    goals = PhysiqueGoalRepository(db, clock);
    store = PhysiquePhotoStore(documentsDirectory: () async => docs);
    sanitizer = PhysiquePhotoSanitizer(
      faceDetector: FakeFaceDetector(),
      stagingDirectory: () async => staging,
    );
    profile = null;
  });

  tearDown(() async {
    await db.close();
    for (final d in [docs, staging, cache]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<void> seedHistory(List<DreamPhysiqueAnalysisSummary> entries) async {
    SharedPreferences.setMockInitialValues({
      _historyKey: [for (final e in entries) jsonEncode(e.toJson())],
    });
    prefs = await SharedPreferences.getInstance();
  }

  Future<void> noHistory() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }

  PhysiqueLegacyMigrator migrator({PhysiqueGoalRepository? repo}) =>
      PhysiqueLegacyMigrator(
        db: db,
        goals: repo ?? goals,
        sanitizer: sanitizer,
        store: store,
        summaries: DreamPhysiqueSummaryRepository(prefs),
        prefs: prefs,
        readProfile: () => profile,
        clock: clock,
      );

  DreamPhysiqueAnalysisSummary entry(
    DateTime at, {
    String style = 'lean',
    int months = 8,
    double target = 12,
    double bf = 20,
  }) => DreamPhysiqueAnalysisSummary(
    schemaVersion: 1,
    analyzedAt: at.toUtc(),
    targetAestheticStyle: style,
    timeframeRange: '$months months',
    estimatedMonths: months,
    targetBfPercent: target,
    currentEstimatedBf: bf,
    weightChangeKg: -4,
    currentPhotoCount: 1,
    targetPhotoCount: 1,
  );

  Future<int> legacyRow(
    String name, {
    String dateIso = '2026-09-01',
    bool createFile = true,
    List<int>? bytes,
  }) async {
    final path = '${cache.path}/$name';
    if (createFile) File(path).writeAsBytesSync(bytes ?? buildJpegWithExif());
    return db
        .into(db.progressPhotos)
        .insert(
          ProgressPhotosCompanion.insert(
            dateIso: dateIso,
            pose: 'front',
            filePath: path,
          ),
        );
  }

  Future<List<PhysiqueGoalData>> allGoals() =>
      db.select(db.physiqueGoals).get();
  Future<List<PhysiquePhotoData>> allPhotos() =>
      db.select(db.physiquePhotos).get();
  Future<List<ProgressPhotoData>> legacyRows() =>
      db.select(db.progressPhotos).get();

  Future<void> expectExifFree(PhysiquePhotoData p) async {
    final file = await store.resolve(p.relativePath);
    expect(file.existsSync(), isTrue);
    final out = img.decodeJpg(file.readAsBytesSync())!;
    expect(out.exif.imageIfd.make, isNull);
    expect(out.exif.gpsIfd.gpsLatitude, isNull);
  }

  Future<int> startLive({DateTime? at}) => goals.startGoal(
    StartGoalInput(
      estimatedMonths: 6,
      targetBfPercent: 12,
      startedAt: at ?? DateTime(2026, 10, 1),
      analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 30))],
    ),
  );

  group('with history', () {
    test('creates one legacy goal from history and photos', () async {
      final d1 = DateTime.utc(2026, 7, 1);
      final d2 = DateTime.utc(2026, 8, 1);
      final d3 = DateTime.utc(2026, 9, 1);
      await seedHistory([
        entry(d3, style: 'newest', months: 9, target: 11, bf: 18),
        entry(d2),
        entry(d1, bf: 24),
      ]);
      profile = const Profile(
        goal: FitnessGoal.weightLoss,
        activityLevel: ActivityLevel.active,
        weightKg: 85,
        ageYears: 30,
      );
      final r1 = await legacyRow('a.jpg');
      final r2 = await legacyRow('b.jpg');

      final result = await migrator().run();

      expect(result.ran, isTrue);
      expect(result.analyses, 3);
      expect(result.photosMigrated, 2);
      expect(result.photosUnrecoverable, 0);

      final gs = await allGoals();
      expect(gs, hasLength(1));
      final g = gs.single;
      expect(g.source, 'legacy_import');
      expect(g.status, 'active');
      expect(g.targetAestheticStyle, 'newest');
      expect(g.estimatedMonths, 9);
      expect(g.targetBfPercent, 11);
      expect(
        g.startedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        d1.millisecondsSinceEpoch ~/ 1000,
      );

      final assessments = await (db.select(
        db.physiqueAssessments,
      )..orderBy([(a) => OrderingTerm.asc(a.id)])).get();
      expect(assessments, hasLength(3));
      expect(assessments.every((a) => a.kind == 'analysis'), isTrue);
      expect(
        assessments.first.summaryJson,
        jsonEncode(entry(d1, bf: 24).toJson()),
      );

      final phases = await db.select(db.physiqueRoadmapPhases).get();
      expect(phases, isNotEmpty);
      expect(
        phases.first.phaseType,
        PhysiqueRoadmapGenerator.propose(
          const PhysiqueRoadmapInput(
            weightKg: 85,
            currentBfPercent: 18,
            targetBfPercent: 11,
            plannedWeightChangeKg: -4,
            estimatedMonths: 9,
            ageYears: 30,
            prefersWeightLoss: true,
          ),
        ).phases.first.phase.name,
      );

      final photos = await allPhotos();
      expect(photos, hasLength(2));
      expect(photos.map((p) => p.legacyRef).toSet(), {
        'progress_photo:$r1',
        'progress_photo:$r2',
      });
      for (final p in photos) {
        expect(p.role, 'baseline');
        expect(p.source, 'legacy_import');
        expect(p.assessmentId, isNull);
        expect(p.relativePath, startsWith('physique/${g.syncUuid}/'));
        await expectExifFree(p);
      }
      expect(await legacyRows(), isEmpty);
      expect(cache.listSync(), isEmpty);
    });

    test('no profile weight falls back to a single maintain phase', () async {
      await seedHistory([entry(DateTime.utc(2026, 9, 1))]);
      await migrator().run();
      final phases = await db.select(db.physiqueRoadmapPhases).get();
      expect(phases, hasLength(1));
      expect(phases.single.phaseType, DietPhase.maintain.name);
    });

    test(
      'history entry older than live goal still leaves live active',
      () async {
        await seedHistory([entry(DateTime.utc(2026, 5, 1))]);
        final liveId = await startLive();

        await migrator().run();

        final gs = await allGoals();
        final live = gs.firstWhere((g) => g.id == liveId);
        final legacy = gs.firstWhere((g) => g.source == 'legacy_import');
        expect(live.status, 'active');
        expect(legacy.status, 'archived');
        expect(legacy.archivedAt, isNotNull);
      },
    );
  });

  group('photos only (D-08)', () {
    test('synthesizes a neutral legacy goal', () async {
      await noHistory();
      await legacyRow('a.jpg', dateIso: '2026-09-10');
      await legacyRow('b.jpg', dateIso: '2026-08-15');

      final result = await migrator().run();

      expect(result.analyses, 0);
      expect(result.photosMigrated, 2);
      final g = (await allGoals()).single;
      expect(g.source, 'legacy_import');
      expect(g.targetBfPercent, isNull);
      expect(g.estimatedMonths, isNull);
      expect(g.targetAestheticStyle, '');
      expect(g.timeframeRange, '');
      expect(g.roadmapAcceptedAt, isNull);
      expect(g.startedAt, DateTime(2026, 8, 15));
      expect(await db.select(db.physiqueAssessments).get(), isEmpty);
      final phases = await db.select(db.physiqueRoadmapPhases).get();
      expect(phases, hasLength(1));
      expect(phases.single.phaseType, 'maintain');
      final photos = await allPhotos();
      expect(photos, hasLength(2));
      for (final p in photos) {
        expect(p.assessmentId, isNull);
        expect(p.legacyRef, isNotNull);
        expect(p.relativePath, startsWith('physique/${g.syncUuid}/'));
        await expectExifFree(p);
      }
      expect(await legacyRows(), isEmpty);
    });

    test('unparsable dates fall back to the clock', () async {
      await noHistory();
      await legacyRow('a.jpg', dateIso: 'garbage');
      await migrator().run();
      expect((await allGoals()).single.startedAt, clock.now());
    });

    test('live goal started 2026-10-01 is never displaced', () async {
      await noHistory();
      final liveId = await startLive();
      await legacyRow('a.jpg', dateIso: '2026-10-05');

      final m = migrator();
      await m.run();

      Future<void> expectState() async {
        final gs = await allGoals();
        expect(gs.firstWhere((g) => g.id == liveId).status, 'active');
        final legacy = gs.firstWhere((g) => g.source == 'legacy_import');
        expect(legacy.status, 'archived');
        expect(
          (await allPhotos()).where((p) => p.goalId == legacy.id),
          hasLength(1),
        );
      }

      await expectState();
      await m.run();
      await goals.reconcileSingleActive();
      await expectState();
    });

    test('active when no live goal exists', () async {
      await noHistory();
      await legacyRow('a.jpg');
      await migrator().run();
      expect((await allGoals()).single.status, 'active');
    });
  });

  group('tolerance', () {
    test('missing and corrupt files are unrecoverable and kept', () async {
      await noHistory();
      await legacyRow('ok.jpg');
      final missing = await legacyRow('gone.jpg', createFile: false);
      final corrupt = await legacyRow('bad.jpg', bytes: [1, 2, 3, 4]);

      final result = await migrator().run();

      expect(result.photosMigrated, 1);
      expect(result.photosUnrecoverable, 2);
      expect(result.hasNotice, isTrue);
      final left = (await legacyRows()).map((r) => r.id).toSet();
      expect(left, {missing, corrupt});
      expect(File('${cache.path}/bad.jpg').existsSync(), isTrue);
    });

    test(
      'empty history and only unrecoverable photos creates no goal',
      () async {
        await noHistory();
        await legacyRow('gone.jpg', createFile: false);
        final result = await migrator().run();
        expect(result.ran, isFalse);
        expect(result.photosUnrecoverable, 1);
        expect(await allGoals(), isEmpty);
        expect(await legacyRows(), hasLength(1));
      },
    );

    test('unrecoverable rows are reported once', () async {
      await noHistory();
      await legacyRow('ok.jpg');
      await legacyRow('gone.jpg', createFile: false);
      final m = migrator();
      await m.run();
      expect(prefs.getStringList(_reportedKey), hasLength(1));

      final second = await m.run();
      expect(second.photosUnrecoverable, 0);
      expect(second.hasNotice, isFalse);
      expect(await legacyRows(), hasLength(1));
    });
  });

  group('rollback', () {
    test('startGoal failure keeps originals and removes the folder', () async {
      await seedHistory([entry(DateTime.utc(2026, 9, 1))]);
      await legacyRow('a.jpg');

      await expectLater(
        migrator(repo: _ThrowingStart(db, clock)).run(),
        throwsA(isA<StateError>()),
      );

      expect(await legacyRows(), hasLength(1));
      expect(File('${cache.path}/a.jpg').existsSync(), isTrue);
      expect(await allGoals(), isEmpty);
      final root = Directory('${docs.path}/physique');
      expect(!root.existsSync() || root.listSync().isEmpty, isTrue);
    });

    test('appendLegacyPhotos failure removes only this run files', () async {
      await noHistory();
      await legacyRow('first.jpg');
      await migrator().run();
      final goal = (await allGoals()).single;
      final before = (await allPhotos()).single;

      await legacyRow('second.jpg');
      await expectLater(
        migrator(repo: _ThrowingAppend(db, clock)).run(),
        throwsA(isA<StateError>()),
      );

      expect(await legacyRows(), hasLength(1));
      expect(File('${cache.path}/second.jpg').existsSync(), isTrue);
      final dir = Directory('${docs.path}/physique/${goal.syncUuid}');
      expect(dir.listSync(), hasLength(1));
      expect(await store.resolve(before.relativePath), isA<File>());
      expect((await store.resolve(before.relativePath)).existsSync(), isTrue);
    });
  });

  group('idempotence', () {
    test('second run creates nothing', () async {
      await seedHistory([entry(DateTime.utc(2026, 9, 1))]);
      await legacyRow('a.jpg');
      final m = migrator();
      await m.run();
      final second = await m.run();
      expect(second.ran, isFalse);
      expect(await allGoals(), hasLength(1));
      expect(await allPhotos(), hasLength(1));
    });

    test('existing legacy goal and no rows creates nothing', () async {
      await seedHistory([entry(DateTime.utc(2026, 9, 1))]);
      final m = migrator();
      await m.run();
      final again = await m.run();
      expect(again.ran, isFalse);
      expect(await allGoals(), hasLength(1));
    });

    test('empty history and no rows creates nothing', () async {
      await noHistory();
      final result = await migrator().run();
      expect(result.ran, isFalse);
      expect(await allGoals(), isEmpty);
    });

    test('later legacy rows are appended once, even after archive', () async {
      await noHistory();
      await legacyRow('a.jpg');
      final m = migrator();
      await m.run();
      final goal = (await allGoals()).single;
      await goals.archiveGoal(goal.id);

      await legacyRow('later.jpg');
      final second = await m.run();

      expect(second.photosMigrated, 1);
      expect(second.analyses, 0);
      expect(await allGoals(), hasLength(1));
      final photos = await allPhotos();
      expect(photos, hasLength(2));
      for (final p in photos) {
        expect(p.goalId, goal.id);
        expect(p.source, 'legacy_import');
        expect(p.relativePath, startsWith('physique/${goal.syncUuid}/'));
        await expectExifFree(p);
      }
      expect(await legacyRows(), isEmpty);

      final third = await m.run();
      expect(third.ran, isFalse);
      expect(await allPhotos(), hasLength(2));
    });

    test('crash recovery: already-copied ref is not copied again', () async {
      await noHistory();
      await legacyRow('a.jpg');
      await migrator().run();
      final goal = (await allGoals()).single;
      final photo = (await allPhotos()).single;

      // Simulate a crash before cleanup: the row and file reappear.
      final id = await legacyRow('a2.jpg');
      await (db.update(
        db.physiquePhotos,
      )..where((p) => p.id.equals(photo.id))).write(
        PhysiquePhotosCompanion(legacyRef: Value('progress_photo:$id')),
      );

      final result = await migrator().run();

      expect(result.photosMigrated, 0);
      expect(await allPhotos(), hasLength(1));
      expect(await legacyRows(), isEmpty);
      expect(File('${cache.path}/a2.jpg').existsSync(), isFalse);
      expect(
        Directory('${docs.path}/physique/${goal.syncUuid}').listSync(),
        hasLength(1),
      );
    });
  });
}
