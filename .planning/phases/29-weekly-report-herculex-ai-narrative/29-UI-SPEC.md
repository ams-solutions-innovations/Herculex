---
phase: 29
slug: weekly-report-herculex-ai-narrative
status: approved
reviewed_at: 2026-10-03
shadcn_initialized: false
preset: none
created: 2026-10-03
---

# Phase 29 — UI Design Contract

> Visual and interaction contract. Flutter app (not web): shadcn gate not applicable. All values resolve through `lib/design_system/` tokens. Never use `AppColors.*` or literal `Color(0x...)` (the shim is being deleted by docs/ui-rework Phase 9); use `context.hx.*`.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (Flutter; in-house design system `lib/design_system/`) |
| Preset | not applicable (5 palettes via `HxColors.of(brightness, AppColorTheme)`, read with `context.hx`) |
| Component library | `HxCard`, `HxTextPill`/`HxPill`, `HxStatTile`, `HxScreenShell`, `HxBackButton`, `HxTopTabs`, `HxSheet`/`AppBottomSheet`, `PremiumButton` (from `design_system/components/components.dart`) |
| Icon library | Material `Icons.*` (project standard; `Icons.auto_awesome` is the existing AI glyph) |
| Font | Manrope (body, `AppTheme.fontBody`), SpaceGrotesk (display and headings, `AppTheme.fontDisplay`) |

New files import via `package:herculex/design_system/...`. Presentation files must stay under 600 lines; the report view splits per section into `widgets/` (one file per section card).

---

## Spacing Scale

Use `HxSpace` tokens (all multiples of 4).

| Token | Value | Usage |
|-------|-------|-------|
| xs (`x1`) | 4 | Icon gaps, pill-to-title gap |
| sm (`x2`) | 8 | Row gaps inside a section, list item gap |
| md (`x4`) | 16 | Gap between a card heading and its body, between stat tiles |
| lg (`x6`) | 24 | Gap between section cards |
| xl (`x8`) | 32 | Gap above the AI narrative card (separates measured from interpreted) |
| 2xl | 48 | Not used this phase |
| 3xl | 64 | Not used this phase |

Also permitted from `HxSpace`: `x3` = 12 (suggestion row internals), `x5` = 20 (the `HxCard` default padding; keep it). Card radius: `HxRadius.xl` via `HxCard` default.

Exceptions: touch targets (retry button, "Update my target", "Keep current target", history rows, dashboard card) minimum 48 high.

---

## Typography

Four sizes, two weights (400 and 600). Headings use SpaceGrotesk; everything else Manrope.

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body (narrative text, suggestion text, notes, row labels) | 16 | 400 | 1.5 |
| Label (pills, captions, "No data this week", week date range, units) | 14 | 400 | 1.5 |
| Heading (section card titles, "Herculex AI" card title, TDEE card title) | 20 | 600 | 1.2 |
| Display (headline stat values, e.g. kcal avg, total tonnage, week title) | 28 | 600 | 1.2 |

Button labels use 16 at weight 600 (within the 2-weight limit). Use the existing text-style helpers/theme text styles at these sizes; do not introduce 11/15/18/19 sizes from `app_theme.dart`.

---

## Color

Source: `context.hx` (HxColors). Per-theme values come from the active palette.

| Role | Token | Usage |
|------|-------|-------|
| Dominant (60%) | `hx.background` / `hx.backgroundGradient` | Screen background |
| Secondary (30%) | `hx.surfaceContainerLowest` (via `HxCard` default), `hx.outlineVariant` borders, `hx.surfaceVariant` for tracks | All measured section cards, history rows |
| Accent (10%) | `hx.primary` / `hx.primaryText` | See reserved list |
| Destructive | `hx.danger` | Not used for actions this phase (no destructive actions); only for the error-state icon |

Accent reserved for:
1. The "Herculex AI" narrative card tint (`HxCard(accent: hx.primary)`) and its `HxTextPill(label: 'Herculex AI')`.
2. Primary CTAs: "Retry narrative" and "Update my target to X".
3. The unread indicator dot and the "Weekly report ready" dashboard card border/icon.
4. Selected state of the opt-in toggle and active/current-week marker in the history list.

Domain colors (not accent): measured section cards tint with their domain via `HxCard(accent: ...)`: Nutrition `hx.domainNutrition`, Training `hx.domainTraining`, Recovery `hx.domainRecovery`, Physique and TDEE cards use no accent in the primary role (Physique neutral `HxCard`; TDEE `hx.domainNutrition`). Text on tints uses `hx.onSurface` / `hx.onSurfaceVariant`; small accent text uses `hx.primaryText`, never `hx.primary`, to hold 4.5:1 contrast.

Distinction rule (RPT-02): measured cards use domain tint only; the AI card is the only card tinted with `hx.primary` and the only one carrying the AI pill and the `Icons.auto_awesome` glyph.

---

## Screens and Components

### 1. Report view (route constant in `AppRoutes`; parameterised path via `AppPaths.weeklyReport(isoYear, isoWeek)`)
Scaffold: `HxScreenShell` + `HxBackButton`. Title: "Week {n}" (Display 28/600) with date range label (14/400, `hx.onSurfaceVariant`), e.g. "Mon 29 Sep – Sun 5 Oct". Past weeks show a small "Final" pill-less caption: "Snapshot from {date}" (label) to signal freeze (RPT-04).

Order (top to bottom), all `HxCard`, 24 gap:
1. Nutrition adherence and frequent foods (kcal avg vs target, protein avg vs target, days logged, top 3 foods).
2. Training volume and strength (tonnage, sessions, top estimated 1RM movers).
3. Recovery, sleep and activity (avg sleep, avg steps/activity, recovery warnings). Correlation sentence uses fixed template "On days with more sleep, your RPE tended to be lower" style; never causal. Do not reuse `BiometricCorrelationResult.interpretation`.
4. Physique progress (latest check-in verdict, measurement delta).
5. TDEE shift card, only when shift exceeds max(100 kcal, 5%) (D-11). See states below.
6. 32 gap, then the Herculex AI narrative card.

Each measured card: heading row (20/600) with domain icon, then `HxStatTile` pairs (Display value 28/600 + label 14/400). Sections with no data collapse to the heading plus one label line "No data this week".

### 2. Herculex AI narrative card
`HxCard(accent: hx.primary)`, heading row: `Icons.auto_awesome` (20, `hx.primaryText`) + "Herculex AI" (20/600) + `HxTextPill(label: 'Herculex AI')` is NOT repeated (use the heading text OR the pill; use the pill, matching `check_in_card.dart`, with heading "This week's read"). Content: summary paragraph (16/400), then 2–3 suggestion rows (12 gap): leading `Icons.arrow_right_alt`-style bullet in `hx.primaryText`, text 16/400. Footer note (14/400, `hx.onSurfaceVariant`): "Herculex AI interprets the numbers above. It does not change them." Suggestions are text only, no buttons.

States:
| State | Presentation |
|-------|--------------|
| Loading (first open, call in flight) | Card shown with heading, 3 skeleton lines (`hx.surfaceVariant`), label "Herculex AI is reading your week…". Measured cards already rendered above (D-02). |
| Ready | Summary + suggestions + footer note |
| Pending (failed or rejected, empty narrative) | Heading, body text, `PremiumButton` "Retry narrative" (48 high) |
| Pending, quota exhausted | Same, kind-specific message, button disabled |
| Skipped (no measurable data, D-06) | Card not rendered |
| Past week, no narrative | Pending state with Retry still available (user-initiated; D-02) |

Narrative is never regenerated once saved: no refresh affordance in Ready state.

### 3. TDEE shift card (measured part, D-11)
`HxCard`, heading "Your energy estimate moved" (20/600), Display value "{old} → {new} kcal", label with the delta. Two actions stacked at 8 gap: primary `PremiumButton` "Update my target to {X} kcal" and a text button "Keep current target". Tapping Update shows no extra dialog (it is the confirmation); success shows a snackbar "Target updated to {X} kcal". After a decision, and always on past weeks, the card is read-only: one label line "You updated your target to {X} kcal" or "You kept your target at {Y} kcal", no buttons.

### 4. History list (Analytics area, D-09)
Entry row in Analytics: "Weekly reports" (`HxCard` with onTap, chevron). Screen: `HxScreenShell`, list of `HxCard` rows (8 gap, 48+ high): "Week {n}" (16/600), date range (14/400), unread dot (`hx.primary`, 8), a pill "Narrative pending" when the narrative is empty. Newest first. Empty: see copy. If the opt-in is off, history stays visible and a banner row offers "Turn on weekly report".

### 5. Dashboard card (D-09)
`HxCard(accent: hx.primary, onTap: ...)` shown only when a report is ready and unread: icon `Icons.insights` (not the AI glyph, since the card promotes the measured report); title "Your week {n} report is ready" (16/600), label "Tap to open" (14). Disappears once opened.

### 6. Notification settings (D-07/D-08)
In `notification_settings_view.dart`, beside daily-log reminder: a toggle row "Weekly report" with sub-label "Sundays at 18:00" (14/400); when on, a time row opens the platform time picker. Notification: title "Your weekly report is ready", body "See how your week went." Callback only deep-links.

### Interaction and accessibility
- First open of a week: measured payload persists immediately; narrative fires automatically; screen never blocks on the AI call.
- `Haptics.selection()` on card taps (already inside `HxCard.onTap`).
- Every tappable target at least 48x48; pills/dots are not interactive.
- All colour pairs resolve via `hx` tokens in all five palettes, light and dark; verify AI card text at 4.5:1 using `hx.onSurface` / `hx.primaryText`.
- Semantics: AI card labelled "Herculex AI interpretation"; unread dot has semantic label "Unread".
- Motion: use `HxMotion` tokens for the skeleton-to-content fade; no looping animations.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | "Retry narrative" (AI card); "Update my target to {X} kcal" (TDEE card) |
| Secondary CTA | "Keep current target" |
| Empty state heading (no reports yet) | "No weekly reports yet" |
| Empty state body | "Turn on Weekly report in notification settings. Your first report appears on Sunday, or open this week's now." |
| Empty section | "No data this week" |
| Narrative pending (generic failure) | "Narrative pending. Herculex AI couldn't write this week's summary. Your numbers above are saved. Try again." |
| Narrative pending (offline) | "You're offline. Reconnect and tap Retry narrative." |
| Narrative pending (quota) | "You've used today's Herculex AI summaries. Your numbers above are saved. Try again tomorrow." |
| Narrative note | "Herculex AI interprets the numbers above. It does not change them." |
| Correlation phrasing | "tended to go with" (never "because", "caused", "led to") |
| Error state (report load) | "Couldn't load this report. Go back and open it again." |
| Destructive confirmation | none: no destructive actions in this phase. The target update is user-confirmed by tapping "Update my target to {X} kcal" and is reversible in nutrition settings. |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (Flutter) | not applicable |
| third-party | none | not applicable |

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
