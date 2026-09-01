import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_repository.dart';
import 'package:herculex/features/fasting/data/fasting_stage_importer.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_occurrence.dart';
import 'package:herculex/features/fasting/domain/fasting_stage.dart';
import 'package:herculex/features/fasting/domain/fasting_sync_snapshot.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fasting stages domain & resolver', () {
    final stages = [
      const FastingStage(
        hour: 6,
        stageName: 'Faza zgodnje presnove',
        stageCategory: 'Prebava & Stabilizacija',
        shortMessage:
            'Krvni sladkor se stabilizira, raven inzulina začne upadati.',
      ),
      const FastingStage(
        hour: 12,
        stageName: 'Začetek ketoze & kurjenje glikogena',
        stageCategory: 'Ketoza & Maščobe',
        shortMessage: 'Glikogenske rezerve v jetrih so skoraj izpraznjene.',
      ),
      const FastingStage(
        hour: 16,
        stageName: 'Optimalno kurjenje maščob (16:8)',
        stageCategory: 'Ketoza & Maščobe',
        shortMessage:
            'Raven inzulina je na dnu, raven rastnega hormona (HGH) raste.',
      ),
      const FastingStage(
        hour: 18,
        stageName: 'Začetek avtofagije',
        stageCategory: 'Avtofagija',
        shortMessage: 'Začne se proces celičnega čiščenja (avtofagija).',
      ),
      const FastingStage(
        hour: 24,
        stageName: 'Globoka avtofagija & regeneracija',
        stageCategory: 'Avtofagija',
        shortMessage: 'Celično recikliranje je v polnem teku.',
      ),
      const FastingStage(
        hour: 72,
        stageName: 'Popolna regeneracija imunskega sistema & matičnih celic',
        stageCategory: 'Matične celice & Imunost',
        shortMessage:
            'Matične celice se prebudijo in tvorijo popolnoma nove bele krvničke.',
      ),
    ];

    test(
      'resolveForElapsed returns stage for exact or nearest preceding hour',
      () {
        expect(
          FastingStage.resolveForElapsed(const Duration(hours: 3), stages).hour,
          6,
        );
        expect(
          FastingStage.resolveForElapsed(const Duration(hours: 6), stages).hour,
          6,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 11),
            stages,
          ).hour,
          6,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 12),
            stages,
          ).hour,
          12,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 15),
            stages,
          ).hour,
          12,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 16),
            stages,
          ).hour,
          16,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 17),
            stages,
          ).hour,
          16,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 18),
            stages,
          ).hour,
          18,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 25),
            stages,
          ).hour,
          24,
        );
        expect(
          FastingStage.resolveForElapsed(
            const Duration(hours: 80),
            stages,
          ).hour,
          72,
        );
      },
    );

    test('parseFromJson parses JSON string into FastingStage instances', () {
      const jsonStr = '''
      [
        {
          "hour": 6,
          "stageName": "Test stage",
          "stageCategory": "Test cat",
          "shortMessage": "Short text",
          "detail": "Detailed explanation",
          "icon": "spa"
        }
      ]
      ''';
      final parsed = FastingStageImporter.parseFromJson(jsonStr);
      expect(parsed.length, 1);
      expect(parsed.first.hour, 6);
      expect(parsed.first.stageName, "Test stage");
      expect(parsed.first.icon, "spa");
    });
  });

  group('Fasting stages DB storage and repository queries', () {
    late AppDatabase db;
    late _FixedClock clock;
    late FastingRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      clock = _FixedClock(DateTime(2026, 8, 14, 12, 0, 0));
      repo = FastingRepository(db, clock);
    });

    tearDown(() async {
      await db.close();
    });

    test('automatically seeds all 72 fasting stages into DB on open', () async {
      final allStages = await repo.fastingStages();
      expect(allStages.length, 72);
      expect(allStages.first.hour, 1);
      expect(allStages.last.hour, 72);

      final stage6 = await repo.fastingStage(6);
      expect(stage6, isNotNull);
      expect(stage6!.hour, 6);
      expect(stage6.stageCategory, isNotEmpty);
      expect(stage6.shortMessage, isNotEmpty);

      final stage16 = await repo.fastingStage(16);
      expect(stage16, isNotNull);
      expect(stage16!.stageName, contains('16:8'));
      expect(stage16.icon, isNotNull);

      final stage72 = await repo.fastingStage(72);
      expect(stage72, isNotNull);
      expect(stage72!.stageCategory, 'Regeneracija');
      expect(stage72.stageName, contains('72-urni'));
    });
  });

  group('Next scheduled fast occurrence calculation', () {
    test('calculates correct next occurrence today or next week', () {
      final monday10am = DateTime(2026, 8, 10, 10, 0); // Monday (weekday = 1)

      // Schedule for Monday 20:00 (startTimeMinutes = 20 * 60 = 1200)
      final nextToday = nextOccurrence(
        daysOfWeek: weekdayBit(DateTime.monday),
        startTimeMinutes: 20 * 60,
        from: monday10am,
      );
      expect(nextToday, isNotNull);
      expect(nextToday!.day, 10);
      expect(nextToday.hour, 20);

      // Schedule for Monday 08:00 (already passed today) -> next Monday 17th
      final nextMonday = nextOccurrence(
        daysOfWeek: weekdayBit(DateTime.monday),
        startTimeMinutes: 8 * 60,
        from: monday10am,
      );
      expect(nextMonday, isNotNull);
      expect(nextMonday!.day, 17);
      expect(nextMonday.hour, 8);
    });
  });

  group('Wear OS fasting sync payload', () {
    test('encodes next fast and stage message properly', () {
      final nextTime = DateTime(2026, 8, 10, 20, 0);
      final payload = fastingPayloadFromSession(
        null,
        nextFastStartTime: nextTime,
        nextFastPlanName: '16:8 Protocol',
        nextFastTargetSeconds: 16 * 3600,
        hasSchedule: true,
        currentStageMessage: '16h: Optimalno kurjenje maščob',
      );

      expect(payload['hasActiveFast'], isFalse);
      expect(payload['nextFastEpochMs'], nextTime.millisecondsSinceEpoch);
      expect(payload['nextFastPlanName'], '16:8 Protocol');
      expect(payload['nextFastTargetSeconds'], 16 * 3600);
      expect(payload['hasSchedule'], isTrue);
      expect(payload['currentStageMessage'], '16h: Optimalno kurjenje maščob');
    });
  });
}
