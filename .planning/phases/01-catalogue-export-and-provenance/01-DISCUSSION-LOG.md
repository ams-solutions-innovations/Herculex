# Phase 1: Catalogue export and provenance - Discussion Log

> **Audit trail only.** Decisions are captured in `01-CONTEXT.md`.

**Date:** 2026-07-30
**Phase:** 1-catalogue-export-and-provenance
**Areas discussed:** source semantics, local-first delivery, data integrity, future capture UX

## Source semantics

| Option | Description | Selected |
|---|---|---|
| Convert every row to 100 g | Would fabricate conversions for unweighted legacy servings. | |
| Preserve the supplied basis | Keeps numeric values trustworthy and lets later UI disclose basis. | ✓ |

**User's choice:** Own food database must become the source for the product.

## Delivery

| Option | Description | Selected |
|---|---|---|
| Runtime nutrition API | Existing Open Food Facts fallback. | |
| Local JSON catalogue | Immediate project asset; later transferred to a server. | ✓ |

**User's choice:** Do not rely on an API for the food database.
