# Herculex Context

Last updated: 2026-08-17

## What Herculex is

A local-first Flutter workout + nutrition tracker (MyFitnessPal + Hevy +
cycle/recovery intelligence), with an optional Supabase cloud sync layer.
Phone (Flutter/Dart) + a native Wear OS companion app.

## Current State: App Store Compliance & Anti-Spam Hardening

All original release blockers (RB-01 through RB-05) are closed and verified. Current engineering focus is App Store submission readiness, GDPR compliance, and abuse prevention:

1. **Authentication Security & Character Minimization**:
   - `lib/core/auth_validator.dart`: `AuthValidator` enforces strict input whitelisting (RFC 5322 regex for email, 2–30 chars for usernames with alphanumeric regex, 8–72 chars for passwords to prevent hashing CPU DoS).
   - `AuthRateLimiter`: Sliding-window client lockout (30s+ cooldown after 5 consecutive failures) and `_authBusy` in-flight debounce to prevent brute-forcing, spamming, and double-tap race conditions.
   - Cloud defense: Supabase rate limits + Cloudflare DDoS/bot shield + Turnstile support + Postgres Row Level Security (RLS).
   - Email verification is deferred to v2 per product roadmap.

2. **Legal, Privacy & GDPR Article 9 Architecture**:
   - `docs/DATA_TRUTH_TABLE.md`: Exhaustive audit of all 36+ SQLite/Drift tables, local-only vs. remote sync boundaries, retention windows, and GDPR classification.
   - `docs/PRIVACY_POLICY.md`: Full GDPR/App Store Guideline 5.1.1 compliant privacy policy.
   - `docs/TERMS_OF_SERVICE.md`: Terms of Service including health, fitness, and medical liability disclaimers.
   - `docs/GDPR_ARTICLE_9_COMPLIANCE.md`: Compliance memo detailing why Herculex is protected under GDPR Article 9 (pseudonymization by design, local-only boundaries for raw motion traces and media, strict RLS).
   - **Strict Project Separation**: Herculex privacy and legal documentation is standalone; Tremble is completely untouched. Privacy policy will be hosted under `amssolutions.studio/herculex/privacy`.

3. **Cloud Sync (RB-02) & Gemini Edge Function (RB-01)**:
   - `SyncService` (`lib/data/sync/sync_service.dart`) handles push/pull/tombstones/quarantine/retry across all tables.
   - Gemini food analysis runs securely via Supabase Edge Function `supabase/functions/gemini-analyze` (no client-side API keys).

## Working agreement for this project

- **"Now" bar vs. backlog**: The app is submission-ready. Treat something as a blocker only if it stops current functionality or violates App Store guidelines. Longer-term/deferred items belong in `TASKS.md`'s Later section or `DEBT.md`.
- **Transparency**: Every privacy and data governance explanation must be completely clear, explicit, and accurate.
- **Headless Testing Limits**: Physical device testing is required for background push notifications, platform health permissions (HealthKit / Health Connect), and live watch sync.

## Where things are tracked

| File | Purpose |
| --- | --- |
| `CONTEXT.md` (this file) | Current project state, updated per session |
| `BLOCKERS.md` | What's actually stopping current functionality, right now |
| `TASKS.md` | Backlog, split Now / Later |
| `DEBT.md` | Known shortcuts, stale docs, cleanup owed |
| `LESSONS.md` | Durable lessons — testing gotchas, architecture traps |
| `HANDOFF.md` | Long-range feature roadmap (Phases 4–11) |
| `RELEASE.md` | Store-submission checklist and environment setup |
| `docs/DATA_TRUTH_TABLE.md` | Definitive database sync and retention catalog |
| `docs/PRIVACY_POLICY.md` | In-app and web-hosted Privacy Policy |
| `docs/TERMS_OF_SERVICE.md` | In-app and web-hosted Terms of Service |
| `docs/GDPR_ARTICLE_9_COMPLIANCE.md` | GDPR Article 9 legal/technical compliance memo |
| `docs/rb02-sync-verification.md` | Full RB-02 verification record |

