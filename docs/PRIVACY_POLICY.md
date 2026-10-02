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
* **Physique Goals & Check-ins:** Your physique goal, roadmap phases, photo metadata and the AI body-fat estimate from each check-in are synced to your private account. See section D for how photos are handled.
* **Menstrual Cycle Tracking:** Period dates, cycle phase, and flow intensity are synced to your private account strictly to provide training readiness and fatigue predictions.
* **HealthKit / Health Connect Biometrics:** Daily steps, sleep duration/stages, heart rate, resting heart rate, and HRV read from Apple Health or Google Health Connect are **stored locally on your device only and are NEVER transmitted to our remote cloud servers**.
* **Legal Basis:** We process special category health data strictly based on your **explicit consent** (GDPR Art. 9(2)(a)). You can enable or disable health integrations or cycle tracking at any time in the app settings.

### D. Progress & Physique Photos (Kept on Your Device)
* Progress and physique photo files remain in your device's local sandboxed storage and are never uploaded to our servers.
* Location and camera metadata (EXIF) is removed from the copies we store on your device. This does not apply to the image sent for a Dream Physique analysis, which is transmitted as you picked it; only weekly check-in photos are cleaned before they are sent.
* Face blur is optional and happens on your device.
* Only photo metadata (relative file name, pose, date) syncs to your private account, protected by Row Level Security.
* When you choose to analyze a Dream Physique goal or a weekly check-in, the photos are sent once, after your explicit consent, to Google Gemini through our Supabase edge function. They are transmitted ephemerally and not stored by Herculex (same terms as section 3 item 4).
* Deleting your account removes the photo files and all physique records.

### E. Camera Access & Barcode Scanning
* **Camera stream:** Used in real time exclusively to decode food packaging barcodes (EAN/UPC).
* The video stream is processed in-memory locally on your device and is discarded instantly. No photos or video recordings are taken or saved.

### F. Workout Bubble & "Display Over Other Apps" (Android only)
* The **Workout Bubble** is an optional, off-by-default floating shortcut you can enable under Settings → App Settings. It requires Android's "Display over other apps" permission, which you grant yourself in system settings and can revoke at any time.
* The bubble is shown **only** while a workout session is active and Herculex is in the background. It disappears when you return to the app or finish the workout.
* Tapping it expands a small card showing your **current workout only** — exercise name, set number, weight and reps, and elapsed time — with controls to adjust reps/weight and complete the set. That is the same information as the ongoing workout notification, and it is read from your device's local database. **Be aware this means workout details are briefly visible on top of whatever app you are using**, so leave the feature off if you would rather they were not.
* **Nothing flows the other way.** Herculex does **not** read, record, capture, or transmit anything about the apps underneath the bubble — not their content, not their identity, and not your interactions with them. The permission is used only to draw our own window.

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
4. **AI Physique Analysis (Google Gemini via Supabase Edge Functions)**:
   * If you choose to analyze a Dream Physique goal or a weekly check-in, the photos are transmitted ephemerally, only after your explicit consent, to the API for physique assessment and are not stored by Herculex or used to train public AI models. Only photo metadata syncs to your account; the image files stay on your device.

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
