-- Phase 10 sync — tombstone retention, plus the grant hardening that
-- `0005_sync_tombstones.sql` was amended with after the fact (idempotent, so
-- projects that already applied 0005 in its first form are brought in line).

revoke execute on function public.record_sync_tombstone() from public, anon, authenticated;

-- 90 days. MUST stay in sync with `kTombstoneRetention` in
-- `lib/data/sync/sync_service.dart`: a client whose tombstone cursor is older
-- than this can no longer trust delta pull and falls back to a full existence
-- reconcile.
--
-- The window is chosen against the observable failure mode — a device offline
-- longer than it reconnects still holding rows that were deleted elsewhere,
-- and re-uploads each one on its next local edit (mass resurrection: the exact
-- bug tombstones exist to fix, just rarer). 90 days covers a phone left in a
-- drawer for a season, at a cost of one four-column row per deleted entity.
create extension if not exists pg_cron;

select cron.schedule(
  'sync_tombstones_gc',
  '17 3 * * *',
  $$delete from public.sync_tombstones where deleted_at < now() - interval '90 days'$$
);
