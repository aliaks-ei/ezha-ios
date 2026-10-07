"""Build the bundled catalog from the public USDA SR Legacy April 2018 CSV archive.
Usage: python3 supabase/scripts/build-food-catalog.py /path/to/archive.zip
The archive is downloaded separately from the URL in catalog-provenance.json.
"""
import csv
import hashlib
import io
import json
from pathlib import Path
import sys
import zipfile

FOODS = {
    171477: "Chicken breast, roasted, skinless",
    168878: "White rice, cooked",
    169704: "Brown rice, cooked",
    169737: "Pasta, cooked, without added salt",
    173424: "Egg, hard-boiled",
    173423: "Egg, fried",
    172187: "Egg, scrambled",
    173944: "Banana, raw",
    171688: "Apple with skin, raw",
    170440: "Potato, boiled, peeled",
    175168: "Atlantic farmed salmon, cooked",
    173904: "Oats, dry",
    172688: "Whole-wheat bread",
    174924: "White bread",
    170894: "Plain Greek yogurt, nonfat",
    170903: "Plain Greek yogurt, lowfat",
    171304: "Plain Greek yogurt, whole milk",
    171413: "Olive oil",
    173410: "Butter, salted",
    173414: "Cheddar cheese",
    169967: "Broccoli, boiled, drained",
    170457: "Tomato, raw",
    168409: "Cucumber with peel, raw",
    169249: "Green-leaf lettuce, raw",
    170393: "Carrot, raw",
    170567: "Almonds",
    170187: "Walnuts",
    172421: "Lentils, boiled",
    173757: "Chickpeas, boiled",
    173735: "Black beans, boiled",
    168917: "Quinoa, cooked",
    171705: "Avocado, raw",
    167762: "Strawberry, raw",
    171711: "Blueberry, raw",
    171265: "Whole milk, 3.25% fat",
    172470: "Peanut butter, smooth, unsalted",
    172475: "Firm tofu, calcium-set",
    171986: "Light tuna, canned in water, drained",
    174516: "Turkey breast, roasted, skinless",
    171794: "Ground beef, 90% lean, cooked crumbles",
    168483: "Sweet potato, baked flesh",
    168462: "Spinach, raw",
}
NUTRIENTS = {1008: "calories", 1003: "protein", 1005: "carbs", 1004: "fat"}
archive = Path(sys.argv[1])
with zipfile.ZipFile(archive) as z:
    prefix = "FoodData_Central_sr_legacy_food_csv_2018-04/"
    descriptions = {
        int(r["fdc_id"]): r["description"]
        for r in csv.DictReader(io.TextIOWrapper(z.open(prefix + "food.csv")))
        if int(r["fdc_id"]) in FOODS
    }
    values = {fdc_id: {} for fdc_id in FOODS}
    for r in csv.DictReader(io.TextIOWrapper(z.open(prefix + "food_nutrient.csv"))):
        fdc_id, nutrient = int(r["fdc_id"]), int(r["nutrient_id"])
        if fdc_id in FOODS and nutrient in NUTRIENTS:
            values[fdc_id][NUTRIENTS[nutrient]] = float(r["amount"])
for fdc_id, nutrients in values.items():
    assert nutrients.keys() == set(NUTRIENTS.values()), f"Missing nutrients: {fdc_id}"
rows = [
    {"id": f"usda:{fdc_id}", "name": name, "description": descriptions[fdc_id],
     "source": "usda", "source_id": str(fdc_id), "per100g": values[fdc_id]}
    for fdc_id, name in FOODS.items()
]
out = Path(__file__).resolve().parents[1] / "functions" / "ai-estimate"
(out / "food-catalog.json").write_text(json.dumps(rows, indent=2) + "\n")
(out / "catalog-provenance.json").write_text(json.dumps({
    "source": "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central.",
    "dataset": "SR Legacy, April 2018 (final release)",
    "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip",
    "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    "license": "CC0 1.0",
    "basis": "per 100 g edible portion; kcal and grams",
    "nutrient_ids": NUTRIENTS,
    "food_count": len(rows),
}, indent=2) + "\n")
print(f"Generated {len(rows)} sourced foods")
