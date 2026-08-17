-- UI rework Phase 8: session start times. Plain nullable columns on two
-- already-synced tables — SyncService derives the push/pull payload
-- generically from whatever local columns exist beyond the registered
-- FK/localOnly/dateTime ones (see sync_service.dart's _buildRemotePayload
-- doc comment), so no sync_table_specs.dart change was needed app-side and
-- none is needed here either: adding the columns is the whole migration.

alter table program_days add column start_time_minutes integer;
alter table scheduled_workouts add column start_time_minutes integer;
