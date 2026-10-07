import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/recovery/data/joint_pain_repository.dart';
import 'package:herculex/features/recovery/domain/joint_model.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JointPainRepository', () {
    late AppDatabase db;
    late JointPainRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = JointPainRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('unflagged joints report severity 0 and are not flagged', () async {
      final statuses = await repo.watchCurrentStatuses().first;
      expect(statuses, hasLength(JointModel.joints.length));
      for (final joint in JointModel.joints) {
        expect(statuses[joint]!.isFlagged, isFalse);
        expect(statuses[joint]!.severity, 0);
      }
    });

    test('setStatus flags a joint with the given severity and note', () async {
      await repo.setStatus(
        joint: 'Elbow',
        severity: 2,
        note: 'sharp on lockout',
        at: DateTime(2026, 6, 1, 9),
      );

      final statuses = await repo.watchCurrentStatuses().first;
      final elbow = statuses['Elbow']!;
      expect(elbow.isFlagged, isTrue);
      expect(elbow.severity, 2);
      expect(elbow.note, 'sharp on lockout');
      expect(elbow.flaggedSince, DateTime(2026, 6, 1, 9));
    });

    test(
      'flaggedSince reflects only the latest contiguous streak, not an earlier resolved one',
      () async {
        // First streak: flagged, then resolved.
        await repo.setStatus(
          joint: 'Knee',
          severity: 1,
          at: DateTime(2026, 5, 1, 9),
        );
        await repo.clear('Knee', at: DateTime(2026, 5, 10, 9));

        // Second streak, days later.
        await repo.setStatus(
          joint: 'Knee',
          severity: 2,
          at: DateTime(2026, 6, 1, 9),
        );

        final statuses = await repo.watchCurrentStatuses().first;
        final knee = statuses['Knee']!;
        expect(knee.isFlagged, isTrue);
        expect(knee.severity, 2);
        expect(knee.flaggedSince, DateTime(2026, 6, 1, 9));
      },
    );

    test(
      'a contiguous run of severity changes keeps flaggedSince at the streak start',
      () async {
        await repo.setStatus(
          joint: 'Wrist',
          severity: 1,
          at: DateTime(2026, 6, 1, 9),
        );
        await repo.setStatus(
          joint: 'Wrist',
          severity: 2,
          at: DateTime(2026, 6, 3, 9),
        );
        await repo.setStatus(
          joint: 'Wrist',
          severity: 3,
          at: DateTime(2026, 6, 5, 9),
        );

        final statuses = await repo.watchCurrentStatuses().first;
        final wrist = statuses['Wrist']!;
        expect(wrist.severity, 3);
        expect(wrist.flaggedSince, DateTime(2026, 6, 1, 9));
      },
    );

    test('clear marks the joint resolved', () async {
      await repo.setStatus(
        joint: 'Hip',
        severity: 1,
        at: DateTime(2026, 6, 1, 9),
      );
      await repo.clear('Hip', at: DateTime(2026, 6, 2, 9));

      final statuses = await repo.watchCurrentStatuses().first;
      expect(statuses['Hip']!.isFlagged, isFalse);
      expect(statuses['Hip']!.severity, 0);
    });

    test('flagging one joint does not affect another', () async {
      await repo.setStatus(
        joint: 'Shoulder',
        severity: 1,
        at: DateTime(2026, 6, 1, 9),
      );

      final statuses = await repo.watchCurrentStatuses().first;
      expect(statuses['Shoulder']!.isFlagged, isTrue);
      expect(statuses['Lower Back']!.isFlagged, isFalse);
    });
  });
}
