# Herculex Data Truth Table (Comprehensive Architecture & GDPR Audit)

| Data Category | Specific Fields / Columns | Local Storage (Device) | Remote Sync (Supabase Postgres) | Cloud Sync Status | GDPR Classification | Purpose / Justification |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Authentication & Identity** | User UUID, Email, OAuth Provider (Google / Apple Subject ID) | Secure Keychain / Keystore | `auth.users` | **Synced** | Personal Data (Standard) | User account management, authentication, cross-device sync |
| **Workout Sessions** | Session name, start/end timestamps, session notes, overall RPE (1–10), gym ID, micro-workout link, session UUID | SQLite (`workout_sessions`) | Postgres (`workout_sessions`) | **Synced** | Personal Activity Data | Tracking workout duration, volume, and training history |
| **Workout Exercises & Sets** | Exercise ID, order, superset group, rest seconds, equipment variant, weight (kg), reps, RPE, warmup flag, set type (drop, rest-pause, myo-reps, partials), machine seat/angle settings, and — where the movement is measured that way — duration (s), distance (m) or calories | SQLite (`workout_exercises`, `set_entries`, `machine_settings`) | Postgres (`workout_exercises`, `set_entries`, `machine_settings`) | **Synced** | Personal Activity Data | Exercise load tracking, progressive overload calculations, volume analytics |
| **Templates & Programs** | Template names, target sets/reps, exercise folders, program weeks, splits (PPL, Upper/Lower, etc.), scheduled workout calendar | SQLite (`programs`, `program_weeks`, `program_days`, `workout_templates`, `scheduled_workouts`) | Postgres (`programs`, `program_weeks`, `program_days`, `workout_templates`, `scheduled_workouts`) | **Synced** | Personal Activity Data | Workout planning, schedule materialization, and routine organization |
| **Gym Profiles & Accessories** | Gym name, default gym flag, custom accessories (belts, knee sleeves, wraps, straps), resistance band tension (kg) | SQLite (`gyms`, `accessories`, `bands`, `set_accessories`, `set_bands`) | Postgres (`gyms`, `accessories`, `bands`, `set_accessories`, `set_bands`) | **Synced** *(Custom rows only)* | Non-personal / Config Data | Custom gym equipment configurations and effective load tracking |
| **Food & Meal Logs** | Date, meal type (breakfast, lunch, dinner, snack), grams/amount, portion unit, timestamp, nutritional snapshot (kcal, protein, carbs, fat, fiber, sodium, potassium, cholesterol, micros) | SQLite (`food_entries`) | Postgres (`food_entries`) | **Synced** | Personal Dietary Data | Macro and calorie tracking, diet history |
| **Custom Foods & Recipes** | Custom food names, brand, barcode, macro values per 100g, recipe ingredient combinations, servings | SQLite (`foods`, `recipes`, `recipe_ingredients`) | Postgres (`foods`, `recipes`, `recipe_ingredients`) | **Synced** *(Custom rows only)* | Personal Dietary Data | Custom meal and recipe logging |
| **Nutrition & Diet Targets** | Target calories, target protein/carbs/fat/fiber, training vs rest day targets, diet reduction schedules, weekly carb-cycling plans | SQLite (`nutrition_targets`, `diet_schedules`, `carb_cycle_plans`) | Postgres (`nutrition_targets`, `diet_schedules`, `carb_cycle_plans`) | **Synced** | Personal Dietary Data | Goal setting and automated nutrition adjustments |
| **Fasting Records** | Fast start/end timestamps, target duration (e.g. 16:8), completion flag, weekly recurring schedules | SQLite (`fasting_sessions`, `fasting_schedules`) | Postgres (`fasting_sessions`, `fasting_schedules`) | **Synced** | Personal Health / Lifestyle | Intermittent fasting tracking and scheduled start reminders |
| **Hydration & Daily Notes** | Daily water intake (ml), daily weigh-in (kg), daily summary notes | SQLite (`daily_summaries`) | Postgres (`daily_summaries`) | **Synced** | Personal Health / Lifestyle | Hydration tracking and daily reflection |
| **Body Weight & Circumferences** | Body weight (kg), body fat %, body circumferences (waist, arms, chest, neck, hips, etc.) | SQLite (`body_measurements`) | Postgres (`body_measurements`) | **Synced** | **GDPR Article 9 (Special Category - Health Data)** | Tracking body composition progress over time |
| **Menstrual Cycle Logs & Settings** | Period start/end dates, cycle length, cycle phase (menstrual, follicular, ovulatory, luteal), flow intensity (1–5), manual overrides | SQLite (`cycle_logs`, `cycle_settings`) | Postgres (`cycle_logs`, `cycle_settings`) | **Synced** | **GDPR Article 9 (Special Category - Health Data)** | Period cycle prediction, symptom correlation, workout readiness adjustments |
| **HealthKit / Health Connect Synced Data** | Daily steps, active calories burned, resting heart rate, HRV, sleep duration & sleep stages, SpO₂ | SQLite (`health_samples`) | None | **Local Only (Never Synced)** | **GDPR Article 9 (Special Category - Health Data)** | Biometric recovery scoring, CNS fatigue calculation, daily activity summaries |
| **Progress Photos** | Photo timestamps, pose (front, side, back), local file path on filesystem | SQLite (`progress_photos`) + Local Documents Directory | None | **Local Only (Never Synced)** | Biometric / Personal Imagery | Visual physique progress comparison |
| **Assisted Rep Tracking Calibration** | Motion feature vectors (frequency, peak acceleration, confidence), confirmed rep counts, confirmed RPE | SQLite (`rep_set_observations`, `rep_tracking_settings`, `rep_tracking_exercise_prefs`) | None | **Local Only (Never Synced)** | Local Telemetry / Calibration | Accelerometer-based rep detection calibration for the specific device |
| **Live Sensor Stream (Accelerometer / Gyroscope)** | Raw XYZ sensor acceleration arrays during active set | In-Memory (RAM) | None | **Ephemeral (Wiped immediately at set completion)** | Real-time Sensor Data | Real-time rep counting during exercise |
| **Camera Video Stream (Barcode Scanner)** | Live camera preview feed | In-Memory (RAM) | None | **Ephemeral (Wiped immediately, zero recording)** | Real-time Camera Feed | Scanning barcode numbers on food packaging |
| **AI Food Analysis (Gemini Scanner)** | Image snapshot of meal / nutritional label | In-Memory (RAM) | Supabase Edge Function `gemini-analyze` -> Gemini API | **Ephemeral (Processed in transit, not persisted in DB)** | Personal Imagery / Query | Automated estimation of meal calories and macros |
| **Supplements Checklist** | Supplement name, daily intake checkbox | `SharedPreferences` | None | **Local Only (Never Synced)** | Personal Dietary Data | Daily supplement adherence |
| **User Profile** | Display name, date of birth, sex, height, activity level, training goal, avatar | `SharedPreferences` | None | **Local Only (Never Synced)** | Personal Data (Standard) | Target calculation (BMR/TDEE), unit defaults, greeting |
| **User Settings & Unit Preferences** | Metric vs Imperial, rest timer duration, screen keep-awake toggle, notification preferences | `SharedPreferences` | None | **Local Only (Never Synced)** | Preference Data | App behavior customization |

---

## Storage & Privacy Summary
1. **Zero PII Collection**: No real names, physical addresses, telephone numbers, contacts, or GPS location data are collected.
2. **Encrypted Cloud Sync via Supabase**: All synced tables enforce Postgres Row Level Security (RLS), restricting access strictly to the authenticated user's `auth.uid()`.
3. **Strict Local-Only Boundaries**:
   - **Progress photos never touch the internet**.
   - **Raw motion sensor data is never saved to disk or transmitted**.
   - **HealthKit / Health Connect raw samples are kept locally on device**.

---

## Deletion (GDPR Article 17 / App Store Guideline 5.1.1(v))

**Profile → Account → Delete Account** deletes everything, in one action:

| Store | What is removed | How |
| :--- | :--- | :--- |
| Supabase `auth.users` | The account row | `delete-account` Edge Function, service-role `DELETE /auth/v1/admin/users/{id}` |
| Supabase Postgres | Every row in all 36 synced tables | `on delete cascade` on each table's `user_id` FK — no table list to keep in step |
| Supabase `sync_tombstones` | The user's tombstones, including the ones the cascade just wrote | Explicit delete, after the auth delete (see `0005_sync_tombstones.sql` for why this table has no FK) |
| Supabase Storage | Everything under `<user_id>/` in `user-photos` | Best-effort list + remove; currently a no-op because no client writes to that bucket yet |
| Device — SQLite | All user rows; custom catalogue rows; local-only rep-tracking, buddy, health and photo tables | `wipeAllLocalUserData` (`lib/data/local/local_data_wipe.dart`) |
| Device — filesystem | The progress-photo JPEGs the rows point at | Same function, before the rows go |
| Device — `SharedPreferences` | Profile, units, dashboard layout, meal slots, supplements, onboarding flags | `SharedPreferences.clear()` |

The bundled food and exercise catalogue is deliberately **kept**: it is shipped
asset data, identical on every install, and contains nothing about the user.

`product_catalogue` contributions are also kept, anonymized rather than removed
— `contributed_by` is `on delete set null`, and the rows are shared community
nutrition facts, not personal data.

The remote deletion runs **first**. If it fails, nothing local is touched and
the user can retry; the device is only wiped once the backend has confirmed the
account is gone.
