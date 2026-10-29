# Web — manual setup

Steps outside the code that the web launch needs. Tick them off as they are done.

## Cloudflare Pages (account that owns `herculex.app`)

- [ ] Project **`herculex-site`** from the `Herculex Web` repo — build `npm run build`, output `dist`.
      Custom domain `herculex.app`.
- [ ] Redirect Rule: `www.herculex.app/*` → `https://herculex.app/$1` (301).
- [ ] Project **`herculex-app`** for the Flutter build — direct upload with
      `tool/web/deploy_web.ps1` (wrangler). Custom domain `app.herculex.app`.

## Supabase Auth (project `ldzgyzigvbwofbswitrv`)

- [ ] **Site URL**: `https://app.herculex.app`
- [ ] **Redirect URLs** (keep the existing deep link):
  - `https://app.herculex.app/**`
  - `https://*.herculex-app.pages.dev/**` (preview deploys)
  - `http://localhost:5555/**` (`flutter run -d chrome --web-port 5555`)
  - `io.supabase.herculex://login-callback/`
- [ ] **Custom SMTP** — the built-in sender is rate-limited and meant for testing.
- [ ] **Email templates** (Confirm signup, Reset password, Magic link) link to
      `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=<type>` so links work in any browser,
      not only the one that started the flow. Lands with W2.

## Google OAuth (GCP project `herculex-8bf9f`)

- [ ] Check the project is still active (the Gemini billing account was closed).
- [ ] Web OAuth client: authorised JavaScript origin `https://app.herculex.app`; authorised redirect URI
      `https://ldzgyzigvbwofbswitrv.supabase.co/auth/v1/callback`.
- [ ] Supabase → Auth → Providers → Google: the same web client ID and secret.

## Database (Supabase)

- [ ] `supabase db push` — applies `20261027120000_food_catalogue.sql` (W4) and
      `20261027130000_user_preferences.sql` (W3). Check `supabase migration list` first.
- [ ] Upload the food catalogue (≈45k rows, run once; re-run after a catalogue update):
      ```powershell
      $env:SUPABASE_URL = 'https://ldzgyzigvbwofbswitrv.supabase.co'
      $env:SUPABASE_SERVICE_ROLE_KEY = '<service role key>'   # never commit
      dart run tool/web/upload_food_catalogue.dart            # --dry-run to check first
      ```
- [ ] Redeploy the Edge Functions (`supabase functions deploy gemini-analyze delete-account`):
      they now only accept browser requests from `ALLOWED_ORIGINS` (default
      `https://app.herculex.app,https://herculex.app`), `*.herculex-app.pages.dev` previews
      and localhost. Set the `ALLOWED_ORIGINS` secret if the domains change.

## Gemini

- [ ] Restore billing so `gemini-analyze` stops returning 429. AI features on the web (W6) depend on it.

## Before launch

- [ ] Phone release containing W3 (synced preferences + natural keys) is out.
- [ ] `supabase db push` for the W3/W4 migrations; food catalogue uploaded (`tool/web/upload_food_catalogue.dart`).
- [ ] Edge Functions redeployed with the CORS allowlist (W7).
- [ ] Privacy policy updated for the web (browser storage, Cloudflare) and re-synced to the site.
