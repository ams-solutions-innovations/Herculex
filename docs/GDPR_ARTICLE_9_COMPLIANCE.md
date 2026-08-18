# GDPR Article 9 (Special Category Data) Compliance Memo

**Product:** Herculex  
**Entity:** AMS Solutions Studio  
**Date:** August 17, 2026  

---

## 1. Executive Summary & Direct Answer
**Is GDPR Article 9 Special Category Data processed in Herculex?**  
**YES.** Specifically, two features process data classified as "data concerning health":
1. **Menstrual Cycle Tracking (`cycle_logs`, `cycle_settings`)**: Period dates, cycle phase, flow intensity.
2. **Body Measurements (`body_measurements`, `daily_summaries`)**: Body weight, body fat %, physical circumferences.
3. **Biometric HealthKit / Health Connect Data (`health_samples`)**: Heart rate, HRV, sleep stages, SpO₂ (*Note: Kept local-only*).

---

## 2. What Does GDPR Article 9 Require?
Under **GDPR Article 9(1)**, processing of personal data concerning health or biometric data is prohibited unless an exception under **Article 9(2)** applies.

The applicable legal standard for consumer wellness/fitness mobile apps is:
> **Article 9(2)(a)**: *"The data subject has given explicit consent to the processing of those personal data for one or more specified purposes..."*

### The 4 Requirements for Valid Explicit Consent:
1. **Freely Given**: The core workout tracking app must remain functional even if the user chooses NOT to track menstrual cycles or connect HealthKit.
2. **Specific & Informed**: The user must be informed exactly what health metrics are logged and what they are used for (e.g. training readiness calculations).
3. **Unambiguous / Affirmative Action**: Consent cannot be buried in general Terms of Service; it must be an explicit toggle, button, or onboarding confirmation.
4. **Easily Withdrawn**: The user can toggle off HealthKit sync or delete their cycle data at any time inside the app settings.

---

## 3. Herculex Architectural Safeguards (Why You Are Protected)

Herculex is architected with several structural privacy safeguards:

### A. Pseudonymization by Design (GDPR Art. 32 / Art. 25)
* No real names, physical addresses, phone numbers, or national identification numbers exist anywhere in Herculex.
* All database records are linked exclusively to an opaque Supabase Auth `UUID` (e.g., `550e8400-e29b-41d4-a716-446655440000`).
* Even if an attacker looked directly at the database tables, they could not link a cycle log or weight measurement to an individual person without the separate auth credentials.

### B. Local-Only Boundaries for High-Risk Data
* **Progress Photos**: Stored strictly in local app documents storage. Never sent to Supabase.
* **Raw Motion Sensors**: Streamed in RAM only during active exercise sets and discarded immediately at set completion. Never written to disk or transmitted over the wire.
* **Raw HealthKit Samples (`health_samples`)**: Kept in the on-device SQLite database. Never synced to Supabase.

### C. Row Level Security (RLS)
* Supabase PostgreSQL enforces strict Row Level Security on every table. A user's JWT token can only read and write rows matching `auth.uid() = user_id`.

### D. Hardened Android Backup Rules
* In `AndroidManifest.xml`, `android:allowBackup="false"` and `android:fullBackupContent="false"` are declared with `tools:replace="android:allowBackup"`, preventing health data extraction through ADB or unencrypted device-to-device transfers.

---

## 4. Recommendations for Complete Peace of Mind

1. **Host the Privacy Policy**: Put `PRIVACY_POLICY.md` on the AMS Solutions Studio website (e.g. `https://ams-solutions.com/herculex/privacy`).
2. **App Store Connect URL**: Provide that exact URL in App Store Connect under the Privacy Policy URL field.
3. **App Privacy Details in App Store Connect**: Select "Health & Fitness", "User Content", "Identifiers" (User ID), and mark them as "Not used for tracking" and "Linked to User".
4. **Account Deletion Button**: Ensure the in-app Settings screen includes a one-tap "Delete Account & Data" action that invokes the Supabase user deletion endpoint (required by Apple Guideline 5.1.1(v) and GDPR Art. 17).
