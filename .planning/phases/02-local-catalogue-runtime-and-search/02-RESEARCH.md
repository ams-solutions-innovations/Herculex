# Phase 2 research

The source asset is 49.4 MB and contains 44,913 records. Parsing it on every search would be a poor mobile UX, so the app needs a one-time import and indexed local queries. Reusing `Foods` avoids a second food identity and preserves foreign keys from existing `FoodEntries` and `RecipeIngredients`.

The current repository already has the correct facade boundary. The safe migration is additive: new nullable metadata columns plus a marker table. The marker prevents a full import on every startup and allows a future `schemaVersion` refresh. Barcode identifiers must remain text; no origin inference is allowed from a GS1 prefix.
