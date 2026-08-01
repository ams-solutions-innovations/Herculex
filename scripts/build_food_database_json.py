#!/usr/bin/env python3
"""Export the Herculex EU food workbook to the portable v1 JSON schema.

This script is deliberately read-only with respect to the workbook.  It keeps
source numeric values under their declared reference basis instead of inventing
per-100 g conversions for unweighted serving-based records.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import openpyxl


NUTRIENTS: dict[str, tuple[str, str]] = {
    "Calories": ("energy_kcal", "kcal"),
    "Protein": ("protein", "g"),
    "Carbohydrates": ("carbohydrates", "g"),
    "Sugars": ("sugars", "g"),
    "Added Sugars": ("added_sugars", "g"),
    "Fiber": ("fiber", "g"),
    "Fat": ("fat", "g"),
    "Saturated Fat": ("saturated_fat", "g"),
    "Monounsaturated Fat": ("monounsaturated_fat", "g"),
    "Polyunsaturated Fat": ("polyunsaturated_fat", "g"),
    "Trans Fat": ("trans_fat", "g"),
    "Cholesterol": ("cholesterol", "mg"),
    "Sodium": ("sodium", "mg"),
    "Salt": ("salt", "g"),
    "Potassium": ("potassium", "mg"),
    "Calcium": ("calcium", "mg"),
    "Iron": ("iron", "mg"),
    "Magnesium": ("magnesium", "mg"),
    "Zinc": ("zinc", "mg"),
    "Copper": ("copper", "mg"),
    "Phosphorus": ("phosphorus", "mg"),
    "Selenium": ("selenium", "µg"),
    "Manganese": ("manganese", "mg"),
    "Iodine": ("iodine", "µg"),
    "Vitamin A": ("vitamin_a", "µg"),
    "Vitamin B1": ("vitamin_b1", "mg"),
    "Vitamin B2": ("vitamin_b2", "mg"),
    "Vitamin B3": ("vitamin_b3", "mg"),
    "Vitamin B5": ("vitamin_b5", "mg"),
    "Vitamin B6": ("vitamin_b6", "mg"),
    "Vitamin B12": ("vitamin_b12", "µg"),
    "Vitamin C": ("vitamin_c", "mg"),
    "Vitamin D": ("vitamin_d", "µg"),
    "Vitamin E": ("vitamin_e", "mg"),
    "Vitamin K": ("vitamin_k", "µg"),
    "Folate": ("folate", "µg"),
    "Biotin": ("biotin", "µg"),
    "Omega 3": ("omega_3", "g"),
    "Omega 6": ("omega_6", "g"),
    "Caffeine": ("caffeine", "mg"),
    "Alcohol": ("alcohol", "g"),
    "Water": ("water", "g"),
}

ALLERGENS = {
    "Gluten": "gluten", "Milk": "milk", "Egg": "egg", "Soy": "soy",
    "Peanuts": "peanuts", "Tree Nuts": "tree_nuts", "Fish": "fish",
    "Shellfish": "shellfish", "Sesame": "sesame", "Mustard": "mustard",
    "Celery": "celery", "Lupin": "lupin", "Sulphites": "sulphites",
    "Molluscs": "molluscs",
}

NON_NUTRIENT_SOURCE_COLUMNS = {
    "ID", "Barcode (EAN)", "Brand", "Product Name", "Category", "Subcategory",
    "Country", "Manufacturer", "Serving Size", "Serving Unit", "Serving Weight (g/ml)",
    "Calories per Serving", "Vegan", "Vegetarian", "Gluten Free", "Lactose Free",
    "Halal", "Kosher", "Nutri-Score", "NOVA Classification", "Reference Basis",
    "Food Group", "Product Type", "Original Product Name", "Source", "Source ID",
    "Source URL", "Source Data Type", "Source Release", "Data Notes", "Duplicate Status",
}


def defined(value: Any) -> bool:
    return value is not None and value != ""


def clean(value: Any) -> Any:
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def barcode(value: Any) -> str | None:
    """Keep identifiers as strings; do not coerce/complete a GTIN."""
    if not defined(value):
        return None
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value).strip() or None


def put(target: dict[str, Any], key: str, value: Any) -> None:
    if defined(value):
        target[key] = clean(value)


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def food_from_row(row: tuple[Any, ...], index: dict[str, int]) -> dict[str, Any]:
    def get(header: str) -> Any:
        return row[index[header]] if index[header] < len(row) else None

    result: dict[str, Any] = {
        "id": str(get("ID")),
        "name": str(get("Product Name")),
        "referenceBasis": get("Reference Basis"),
    }
    code = barcode(get("Barcode (EAN)"))
    if code:
        result["barcode"] = code

    catalogue: dict[str, Any] = {}
    for header, key in {
        "Brand": "brand", "Category": "category", "Subcategory": "subcategory",
        "Country": "country", "Manufacturer": "manufacturer", "Food Group": "foodGroup",
        "Product Type": "productType", "Original Product Name": "originalName",
    }.items():
        put(catalogue, key, get(header))
    if catalogue:
        result["catalogue"] = catalogue

    serving: dict[str, Any] = {}
    for header, key in {
        "Serving Size": "amount", "Serving Unit": "unit",
        "Serving Weight (g/ml)": "weightGramsOrMl", "Calories per Serving": "caloriesKcal",
    }.items():
        put(serving, key, get(header))
    if serving:
        result["serving"] = serving

    nutrients: dict[str, Any] = {}
    for header, (key, _) in NUTRIENTS.items():
        put(nutrients, key, get(header))
    if nutrients:
        result["nutrients"] = nutrients

    claims: dict[str, Any] = {}
    for header, key in {
        "Vegan": "vegan", "Vegetarian": "vegetarian", "Gluten Free": "glutenFree",
        "Lactose Free": "lactoseFree", "Halal": "halal", "Kosher": "kosher",
        "Nutri-Score": "nutriScore", "NOVA Classification": "novaClassification",
    }.items():
        put(claims, key, get(header))
    if claims:
        result["dietaryClaims"] = claims

    allergens: dict[str, Any] = {}
    for header, key in ALLERGENS.items():
        put(allergens, key, get(header))
    if allergens:
        result["allergens"] = allergens

    provenance: dict[str, Any] = {}
    for header, key in {
        "Source": "source", "Source ID": "sourceId", "Source URL": "sourceUrl",
        "Source Data Type": "dataType", "Source Release": "release",
    }.items():
        put(provenance, key, get(header))
    if provenance:
        result["provenance"] = provenance

    quality: dict[str, Any] = {}
    for header, key in {"Data Notes": "notes", "Duplicate Status": "duplicateStatus"}.items():
        put(quality, key, get(header))
    if quality:
        result["quality"] = quality
    return result


def export(input_path: Path, output_path: Path) -> dict[str, Any]:
    workbook = openpyxl.load_workbook(input_path, read_only=True, data_only=True)
    sheet = workbook["Food Database"]
    iterator = sheet.iter_rows(values_only=True)
    headers = tuple(next(iterator))
    index = {str(header): position for position, header in enumerate(headers)}
    required = {"ID", "Product Name", "Reference Basis", *NUTRIENTS, *ALLERGENS}
    missing = required.difference(index)
    if missing:
        raise ValueError(f"Workbook headers missing: {sorted(missing)}")
    unmapped = set(headers).difference(NUTRIENTS).difference(ALLERGENS).difference(
        NON_NUTRIENT_SOURCE_COLUMNS
    )
    if unmapped:
        raise ValueError(f"Workbook headers without an export mapping: {sorted(unmapped)}")

    foods: list[dict[str, Any]] = []
    bases: Counter[str] = Counter()
    barcode_count = 0
    for row in iterator:
        item = food_from_row(row, index)
        if not item["id"] or item["id"] == "None" or not item["name"] or item["name"] == "None":
            raise ValueError("Food Database contains an item without ID or Product Name")
        foods.append(item)
        bases[str(item["referenceBasis"])] += 1
        barcode_count += int("barcode" in item)

    ids = [item["id"] for item in foods]
    if len(ids) != len(set(ids)):
        raise ValueError("Food Database IDs are not unique")

    document = {
        "schemaVersion": "herculex-food-catalogue/v1",
        "sourceWorkbook": {
            "filename": input_path.name,
            "sha256": file_hash(input_path),
            "exportedAtUtc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "sheet": "Food Database",
            "columns": list(headers),
        },
        "nutrientDefinitions": {
            key: {"sourceColumn": source, "unit": unit}
            for source, (key, unit) in NUTRIENTS.items()
        },
        "statistics": {
            "foodCount": len(foods),
            "barcodeCount": barcode_count,
            "sourceColumnCount": len(headers),
            "referenceBasisCounts": dict(sorted(bases.items())),
        },
        "foods": foods,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return document


def validate(document: dict[str, Any]) -> None:
    foods = document["foods"]
    assert document["schemaVersion"] == "herculex-food-catalogue/v1"
    assert len(document["sourceWorkbook"]["columns"]) == document["statistics"]["sourceColumnCount"]
    assert document["statistics"]["sourceColumnCount"] == 87
    assert len(foods) == document["statistics"]["foodCount"]
    assert len({food["id"] for food in foods}) == len(foods)
    sample = next(food for food in foods if food["id"] == "LEGACY-000001")
    assert sample["referenceBasis"] == "Legacy serving (unverified)"
    assert sample["nutrients"]["energy_kcal"] == 508
    assert isinstance(next(food["barcode"] for food in foods if "barcode" in food), str)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Path to the source .xlsx workbook")
    parser.add_argument("--output", required=True, type=Path, help="Path for the generated .json catalogue")
    args = parser.parse_args()
    document = export(args.input, args.output)
    validate(json.loads(args.output.read_text(encoding="utf-8")))
    print(json.dumps(document["statistics"], ensure_ascii=False))


if __name__ == "__main__":
    main()
