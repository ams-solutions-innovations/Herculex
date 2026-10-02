---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 03
subsystem: physique
tags: [privacy, gdpr, exif, face-blur, mlkit, image, isolate]
requires: []
provides:
  - PhysiquePhotoStore (sandboxed relative-path store, traversal rejection)
  - PhysiquePhotoSanitizer (EXIF strip, orientation bake, optional face blur)
  - FaceDetectorPort / MlKitFaceDetector
  - PhysiquePrivacyPreferences (consent version, last blur choice)
affects: [23-09, 23-11, 23-17]
tech-stack:
  added: [google_mlkit_face_detection 0.14.0, image (moved to dependencies)]
  patterns: [port/adapter seam for ML Kit, Isolate.run for image work]
key-files:
  created:
    - lib/features/physique/data/physique_photo_store.dart
    - lib/features/physique/data/physique_privacy_preferences.dart
    - lib/features/physique/data/physique_photo_sanitizer.dart
    - lib/features/physique/data/ml_kit_face_detector.dart
    - test/support/exif_jpeg_fixture.dart
    - test/support/fake_face_detector.dart
    - test/features/physique/physique_photo_store_test.dart
    - test/features/physique/physique_photo_sanitizer_test.dart
  modified: [pubspec.yaml, pubspec.lock]
decisions:
  - "Face detector runs on the already-baked EXIF-free temp file so box coordinates match the pixels that get blurred"
  - "Zero faces with blur requested reports noFaceFound and never claims blurApplied"
metrics:
  tasks: 2
  tests: 23
completed: 2026-10-02
---

# Phase 23 Plan 03: Private photo pipeline Summary

Documents-dir sandbox store, EXIF-stripping orientation-baking sanitiser with optional on-device face blur behind a FaceDetectorPort, and consent/blur preferences.

## Commits

- 36fa6b0: dependencies, PhysiquePhotoStore, PhysiquePrivacyPreferences, store tests
- 7335b41: sanitiser, ML Kit adapter, fixtures, sanitiser tests

## Verification

- `flutter test test/features/physique/physique_photo_store_test.dart test/features/physique/physique_photo_sanitizer_test.dart`: 23/23 pass
- `flutter analyze lib/features/physique test/support test/features/physique`: no issues
- `dart format --set-exit-if-changed` clean; no `DateTime.now`/`print(` in `lib/features/physique/data`
- Lockfile: `google_mlkit_commons 0.12.0`, `google_mlkit_text_recognition 0.16.0` unchanged; `google_mlkit_face_detection 0.14.0`

## Deviations from Plan

None to the design. One test adjustment: the blur test uses a high-frequency checker image and a recompression tolerance outside the box, because a gradient fixture shifted by one level on JPEG re-encode and pixelating a smooth gradient is barely detectable.

## Known Stubs

None. `MlKitFaceDetector` cannot run under `flutter test`; real-device blur on a rotated sample is a manual check in Plan 17 (RESEARCH A4).

## Threat Flags

None beyond the plan's threat model.

## Self-Check: PASSED
