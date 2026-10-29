import 'package:drift/drift.dart';
import 'package:herculex/data/local/tables.dart';

/// Portable prescription and edit facts. Sensor data and health explanations
/// stay in the local report tables.
@DataClassName('WorkoutBehaviorSnapshotData')
class WorkoutBehaviorSnapshots extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get snapshotJson => text()();
  DateTimeColumn get capturedAt => dateTime()();
  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId},
  ];
}

@DataClassName('TrainingCoachingProposalData')
class TrainingCoachingProposals extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get programId => integer().nullable().references(
    Programs,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get sourceSessionId => integer().nullable().references(
    WorkoutSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get kind => text()();
  TextColumn get proposalKey => text()();
  TextColumn get status => text().withDefault(const Constant('proposed'))();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  @override
  List<Set<Column>> get uniqueKeys => [
    {proposalKey},
  ];
}

@DataClassName('TrainingCoachingOverrideData')
class TrainingCoachingOverrides extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get proposalId => integer().references(
    TrainingCoachingProposals,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get scheduleId => integer().references(
    ScheduledWorkouts,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get planJson => text()();
  TextColumn get originalPlanJson => text()();
  @override
  List<Set<Column>> get uniqueKeys => [
    {proposalId, scheduleId},
  ];
}

@DataClassName('ExerciseHistoryTransferData')
class ExerciseHistoryTransfers extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get undoneAt => dateTime().nullable()();
}
