---
phase: 5
plan: 1
type: execute
depends_on: [04-01]
autonomous: true
---

# Phase 5 plan: barcode capture hardening

1. Add a shared retail barcode normalizer with EAN-8, UPC-A, EAN-13 and
   GTIN-14 check-digit validation.
2. Make repository barcode lookup local-only, canonical and tolerant of the
   UPC-A/EAN-13 storage representation.
3. Add camera-screen manual entry and correction; route invalid scans through
   the same validator.
4. Persist the corrected barcode in custom-food create/edit flows and replace
   misleading remote-search UI with a local custom-food recovery action.
5. Add unit and database-backed tests, run analyzer and the full Flutter suite.

Acceptance: valid supported codes resolve offline, invalid check digits cannot
be logged as barcodes, manual correction is available from the camera screen,
and a no-match product can be edited and saved with its canonical code.
