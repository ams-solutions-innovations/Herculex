# Phase 5 context: barcode capture hardening

## Locked decisions

- Barcode identifiers are opaque strings. Country prefixes are never used to
  infer product origin.
- Supported validated formats are EAN-8, UPC-A, EAN-13 and GTIN-14.
- Scanner output and manual input use the same normalizer and check-digit
  validator; separators are removed while leading zeroes are preserved.
- Lookup is local-only against the bundled catalogue and user-created foods.
  A miss opens an editable custom-food flow rather than making an internet
  request or silently logging an unverified product.
- UPC-A lookup may try its EAN-13 zero-padded representation as a storage
  compatibility candidate; this is symbology conversion, not geography.
- A custom food created after a scan stores the corrected canonical barcode.

## Scope fence

Label OCR and meal-photo analysis remain Phase 6. Server sync, public catalogue
hosting and remote Open Food Facts fallback are out of scope for this phase.
