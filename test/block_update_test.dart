import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/application/block_update_controller.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/block_adjustment_advisor.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

import 'support/fake_clock.dart';
import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlockAdjustmentAdvisor', () {
    test('suggests fewer days when most recent weeks fall short', () {
      final rec = BlockAdjustmentAdvisor.evaluate(
        daysPerWeek: 5,
        recentWeeks: const [
          (planned: 5, done: 3),
          (planned: 5, done: 3),
          (planned: 5, done: 5),
        ],
        deloadRecommended: false,
        cnsDeloadSuggested: false,
      );
      expect(rec?.reason, BlockAdjustmentReason.lowAdherence);
      expect(rec?.suggestedDaysPerWeek, 4);
      expect(rec?.lighter, isFalse);
    });

    test('a single missed week is not a pattern', () {
      expect(
        BlockAdjustmentAdvisor.evaluate(
          daysPerWeek: 4,
          recentWeeks: const [
            (planned: 4, done: 4),
            (planned: 4, done: 1),
            (planned: 4, done: 4),
          ],
          deloadRecommended: false,
          cnsDeloadSuggested: false,
        ),
        isNull,
      );
    });

    test('poor recovery suggests a lighter block with a day less', () {
      final rec = BlockAdjustmentAdvisor.evaluate(
        daysPerWeek: 4,
        recentWeeks: const [(planned: 4, done: 4), (planned: 4, done: 4)],
        deloadRecommended: false,
        cnsDeloadSuggested: false,
        averageRecoveryScore: 30,
      );
      expect(rec?.reason, BlockAdjustmentReason.poorRecovery);
      expect(rec?.suggestedDaysPerWeek, 3);
      expect(rec?.lighter, isTrue);
    });

    test('never goes below two days', () {
      final rec = BlockAdjustmentAdvisor.evaluate(
        daysPerWeek: 2,
        recentWeeks: const [],
        deloadRecommended: true,
        cnsDeloadSuggested: false,
      );
      expect(rec?.suggestedDaysPerWeek, 2);
    });
  });

  group('BlockUpdateController', () {
    late AppDatabase db;
    late ProviderContainer container;
    late ProgramsRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 14, 9))),
        ],
      );
      repo = container.read(programsRepositoryProvider);
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<ProgramData> fourDayBlock() async {
      final id = await repo.createProgramFromSplit(
        name: 'Upper / Lower',
        weeks: 4,
        plan: SplitTemplates.generate(
          type: SplitType.upperLower,
          daysPerWeek: 4,
        ),
        startDate: DateTime(2026, 10, 5),
        buildMode: ProgramBuildMode.smart,
      );
      await repo.setActiveProgram(id);
      return (await repo.getProgram(id))!;
    }

    test('rebuilds the remaining weeks as an inactive draft', () async {
      final program = await fourDayBlock();
      final controller = container.read(blockUpdateControllerProvider);

      final draftId = await controller.buildDraft(
        program,
        const BlockUpdateRequest(
          daysPerWeek: 3,
          sessionMinutes: 45,
          lighter: true,
        ),
      );

      final draft = (await repo.getProgram(draftId))!;
      expect(draft.archived, isTrue);
      expect(draft.isActive, isFalse);
      expect(draft.daysPerWeek, 3);
      expect(draft.weeks, lessThan(program.weeks));
      final weeks = await repo.watchProgramWeeks(draftId).first;
      expect(weeks.every((w) => w.adjustmentFactor < 1), isTrue);
      // The old block is untouched until the user confirms.
      expect((await repo.getProgram(program.id))!.isActive, isTrue);
    });

    test(
      'retiring keeps trained sessions and drops untouched future ones',
      () async {
        final program = await fourDayBlock();
        await repo.rematerializeProgram(program.id, futureOnly: false);
        final rows = await (db.select(
          db.scheduledWorkouts,
        )..where((t) => t.programId.equals(program.id))).get();
        final past = rows.firstWhere(
          (r) => r.dateIso.compareTo('2026-10-14') < 0,
        );
        await (db.update(
          db.scheduledWorkouts,
        )..where((t) => t.id.equals(past.id))).write(
          const ScheduledWorkoutsCompanion(status: Value(ScheduleStatus.done)),
        );

        await container.read(blockUpdateControllerProvider).retire(program.id);

        final left = await (db.select(
          db.scheduledWorkouts,
        )..where((t) => t.programId.equals(program.id))).get();
        expect(left.any((r) => r.id == past.id), isTrue);
        expect(
          left.where(
            (r) =>
                r.status == ScheduleStatus.planned &&
                r.dateIso.compareTo('2026-10-15') >= 0,
          ),
          isEmpty,
        );
        expect((await repo.getProgram(program.id))!.archived, isTrue);
      },
    );

    test('recent adherence counts the full weeks before this one', () async {
      final program = await fourDayBlock();
      await repo.rematerializeProgram(program.id, futureOnly: false);
      final weeks = await repo.recentAdherence(
        program.id,
        now: DateTime(2026, 10, 14),
        weeks: 2,
      );
      // 28 Sep week predates the block; 5 Oct week has its 4 sessions.
      expect(weeks.first, (planned: 0, done: 0));
      expect(weeks.last.planned, 4);
    });
  });
}
