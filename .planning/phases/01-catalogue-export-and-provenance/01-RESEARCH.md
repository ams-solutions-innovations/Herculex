# Phase 1 research — Food catalogue and MyFitnessPal parity

## Source workbook findings

- **44,913 products, 87 columns.** 39,427 foods and 5,486 drinks.
- **Barcode coverage:** 29,729 non-empty codes: 14,649 twelve-digit, 14,460 thirteen-digit, 613 eight-digit; a few other lengths need validation/normalisation rather than rejection.
- **Basis:** 43,996 values are `100 g`, 182 are `100 ml`, and 735 are `Legacy serving (unverified)`. It is unsafe to silently convert the latter to 100 g.
- **Completeness:** 272 rows lack calories, 19 protein, 56 carbohydrates and 36 fat. The UI must distinguish “unknown” from zero.
- **Provenance:** source distribution includes USDA Global Branded (15,000), Open Food Facts (14,717), USDA FoodData Central (13,588) and user-provided data (1,596). Public re-hosting needs a licence/provenance review first.

## Functional baseline to meet or exceed

MyFitnessPal currently provides manual search by food/brand, serving adjustment, meal/date selection, saved meals, recipes, recent/frequent lists, quick add, barcode scan, meal scan, voice logging, recipe imports, diary copy/edit/delete and nutrient progress. Its recent Today experience also groups food logging modes and supports copying a whole meal. Implement the reliable local diary foundation first; do not copy its premium restrictions or its limit of two additional meal names.

Required Herculex UX rules:

1. **Search:** exact barcode > exact name/brand > token name/brand; show brand, basis, key macros and quality/provenance indicators.
2. **Portion:** let users choose grams, ml or named serving only when its weight/unit supports honest calculation; instant nutrient preview before Log.
3. **Micros:** dropdown/custom picker controls visible nutrients. Totals show both amount and coverage, never a false `0` for absent source data.
4. **Meal slots:** persisted ordered records, seeded Breakfast/Lunch/Dinner/Snacks. Edit nutrients supports unlimited user-defined slots such as Breakfast 1/2, Pre-workout, Post-workout; older logs retain their original display names.
5. **Barcode miss:** scan → validate → exact local lookup → manual code/search → photograph label → create editable draft. A code prefix identifies a GS1 allocation, not a product's origin.
6. **Camera:** label OCR and meal photo detection produce only a reviewable draft with confidence/source; direct logging is prohibited. Internet/AI analysis is opt-in and must state that the image/text is sent externally.

## Barcode standard

Store canonical digits as text. Accept EAN-8, UPC-A, EAN-13 and GTIN-14 after stripping permitted presentation separators; use the GS1 Mod-10 check digit where the scanner supplies a complete GTIN. Do not add a leading zero to a code unless the lookup layer explicitly performs a documented UPC-A/EAN-13 equivalence candidate search. GS1 says prefix ranges identify the GS1 Member Organisation that allocated the company prefix, not the manufacturing country.

## Architecture recommendation

Do not parse a 45k × 90 field JSON file on every search. Phase 1 places a portable server-ready asset in the application. Phase 2 imports it once, in batches, into an indexed SQLite catalogue and builds a local FTS search index plus barcode index. Keep raw source fields/provenance separately available for detail/audit views.

## References

- [MyFitnessPal: add food, serving and meal/date choice](https://support.myfitnesspal.com/hc/en-us/articles/360032274592-How-do-I-add-a-food-to-my-food-diary)
- [MyFitnessPal: meal names and extra meals](https://support.myfitnesspal.com/hc/en-us/articles/360032622311-Can-I-change-my-meal-names-or-add-more-meals)
- [MyFitnessPal: barcode scan flow](https://support.myfitnesspal.com/hc/en-us/articles/360032624771-How-do-I-use-the-barcode-scanner-to-log-foods)
- [MyFitnessPal: saved meals](https://support.myfitnesspal.com/hc/en-us/articles/360032625331-Meal-Creation-FAQ)
- [MyFitnessPal: recipe importer and unit conversion](https://support.myfitnesspal.com/hc/en-us/articles/360032271592-How-does-the-Recipe-Importer-on-the-website-work)
- [MyFitnessPal: Meal Scan review workflow](https://support.myfitnesspal.com/hc/en-us/articles/360045761612-Meal-Scan-FAQ)
- [MyFitnessPal: Voice Log review/edit and online dependency](https://support.myfitnesspal.com/hc/en-us/articles/30332897072269-Voice-Logging)
- [MyFitnessPal: Today, copy meals and nutrient views](https://support.myfitnesspal.com/hc/en-us/articles/39985611667341-Introducing-the-brand-new-Today-tab)
- [GS1: barcode verification and GTIN check-digit guidance](https://www.gs1.org/services/check-digit-calculator)
- [GS1: prefix does not indicate product origin](https://support.gs1.org/support/solutions/articles/43000734356-can-a-barcode-tell-me-where-a-product-was-made-)
