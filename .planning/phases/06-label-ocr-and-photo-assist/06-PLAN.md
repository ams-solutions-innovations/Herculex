---
phase: 6
plan: 1
type: execute
depends_on: [05-01]
autonomous: true
---

# Phase 6 plan: label OCR and Gemini fallback

1. Add an on-device nutrition-label OCR parser with English/Slovenian field
   aliases, serving-to-100 g conversion and confidence scoring.
2. Extend the Gemini nutrition service with a strict JSON label-extraction
   fallback that receives OCR evidence and returns confidence/source metadata.
3. Add an editable review dialog with source badges, warnings and explicit
   save-and-log confirmation.
4. Persist label evidence in custom food metadata and expose the capture mode
   alongside meal-photo analysis.
5. Add parser tests, analyzer coverage and run the full Flutter test suite.

Acceptance: a clear label is parsed locally; an incomplete/low-confidence label
uses Gemini; failed Gemini leaves an editable warning draft; no result logs
without review; all saved label evidence remains inspectable locally.
