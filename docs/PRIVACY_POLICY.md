# Privacy Policy for Herculex

**Last Updated:** August 17, 2026  
**Publisher:** AMS Solutions Studio  
**Application:** Herculex (iOS & Android)

AMS Solutions Studio ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how Herculex collects, uses, stores, and protects your data in accordance with the **General Data Protection Regulation (GDPR)** and Apple & Google platform standards.

---

## 1. Zero Direct Personal Identifiers (Data Minimization)
Herculex is built around **privacy by design**:
* We do **not** collect your legal name, physical address, telephone number, contacts list, or government ID.
* Your account is tied to an anonymous unique identifier (UUID) generated upon login via Supabase Auth (Sign in with Apple, Sign in with Google, or Email).

---

## 2. What Data We Collect and Where It Lives

### A. Workout & Fitness Data (Synced to Encrypted Cloud)
* **What we store:** Workout names, start/end timestamps, logged exercises, set logs (weight, reps, RPE), workout templates, routine splits, and custom gym profiles.
* **Storage location:** Stored locally in an on-device database and synchronized with your private account in our secure Supabase backend.
* **Purpose:** To provide training logging, calculate volume, track progressive overload, and sync your workout history across devices.

### B. Nutrition & Diet Data (Synced to Encrypted Cloud)
* **What we store:** Meal logs, calories, macronutrients (protein, carbs, fat), micronutrients, custom food items, recipes, target nutrition goals, and fasting intervals.
* **Storage location:** Stored locally on device and synchronized with your private account.
* **Purpose:** To provide calorie/macro tracking, adherence stats, and nutrition insights.

### C. Sensitive Health & Biometric Data (GDPR Article 9 Special Category)
Under GDPR Article 9, data concerning health requires explicit consent and heightened protection:
* **Body Measurements:** Body weight (kg) and body circumferences (waist, arms, chest, etc.) are synced to your private account to graph physical progress.
* **Menstrual Cycle Tracking:** Period dates, cycle phase, and flow intensity are synced to your private account strictly to provide training readiness and fatigue predictions.
* **HealthKit / Health Connect Biometrics:** Daily steps, sleep duration/stages, heart rate, resting heart rate, and HRV read from Apple Health or Google Health Connect are **stored locally on your device only and are NEVER transmitted to our remote cloud servers**.
* **Legal Basis:** We process special category health data strictly based on your **explicit consent** (GDPR Art. 9(2)(a)). You can enable or disable health integrations or cycle tracking at any time in the app settings.

### D. Progress Photos (Strictly Local on Device)
* Progress photos captured in the app remain strictly in your device's local sandboxed storage.
* **Progress photos are NEVER uploaded to our cloud servers or shared with any third party.**

### E. Camera Access & Barcode Scanning
* **Camera stream:** Used in real time exclusively to decode food packaging barcodes (EAN/UPC).
* The video stream is processed in-memory locally on your device and is discarded instantly. No photos or video recordings are taken or saved.

### F. Motion Sensors & Assisted Rep Tracking
* Accelerometer and gyroscope data used for rep tracking is processed in real time in device memory and immediately discarded.
* Only anonymous, mathematically derived feature values (e.g. repetition frequency) are stored locally on the device for algorithm calibration.

---

## 3. Third-Party Integrations & Processing

1. **Supabase (Backend & Database)**:
   * Provides authentication and encrypted PostgreSQL database hosting.
   * All database tables enforce strict **Row Level Security (RLS)**, ensuring that only you (via your authenticated token) can access or edit your data.
2. **Apple HealthKit & Google Health Connect**:
   * Herculex reads and writes health samples solely in accordance with Apple and Google developer policies.
   * **We never sell, rent, or disclose HealthKit/Health Connect data to advertising platforms, data brokers, or information resellers.**
3. **AI Meal Recognition (Google Gemini via Supabase Edge Functions)**:
   * If you choose to analyze a meal via the AI scanner, the image/query is transmitted ephemerally to the API for nutrient analysis and is not stored or used to train public AI models.

---

## 4. Your Rights Under GDPR
As an EU/EEA user, you have full rights under the GDPR:
* **Right of Access (Art. 15)**: You can view all your stored workouts, diet logs, and measurements inside the app.
* **Right to Erasure / Account Deletion (Art. 17)**: You can request complete deletion of your account and all associated cloud data directly inside the app or by contacting support.
* **Right to Data Portability (Art. 20)**: You can export your data in standard format upon request.
* **Right to Withdraw Consent (Art. 7(3))**: You can withdraw consent for camera access, health synchronization, or cycle tracking at any time by toggling them off in device settings or app preferences.

---

## 5. Data Security
* All network communications use TLS 1.3 / HTTPS encryption.
* Cloud database storage is secured with PostgreSQL Row Level Security (RLS) policies.
* Local device storage utilizes system-level sandbox protection with backup disabled (`allowBackup=false`) on Android to prevent unintended extraction.

---

## 6. Contact & Data Controller
If you have any questions regarding this Privacy Policy or your data:
* **Data Controller:** AMS Solutions Studio
* **Email:** support@ams-solutions.com
