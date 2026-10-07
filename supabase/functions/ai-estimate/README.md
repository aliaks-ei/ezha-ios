# Meal detection v2

The model identifies foods, preparation and portions. Matched nutrition comes
from the user's saved foods or the bundled USDA catalog; unmatched foods use an
explicitly marked model estimate. Code scales nutrients and computes totals.

## Models

- `gpt-6-luna`: routine meals with low reasoning; label extraction with none.
- `gpt-6.1-sol`: one fallback for unclear image recognition or unreadable label
  extraction, with low reasoning.
- Missing portion scale alone never triggers fallback. Non-food input never
  triggers fallback.
- GPT-4.1 and other models are excluded. Model settings use an explicit
  allowlist, with no temperature parameter.

The existing hosted `OPENAI_API_KEY` is reused. Optional settings:

| Setting                          | Default                                         |
| -------------------------------- | ----------------------------------------------- |
| `OPENAI_ESTIMATE_MODEL`          | `gpt-6-luna`                                    |
| `OPENAI_ESTIMATE_FALLBACK_MODEL` | `gpt-6.1-sol`                                   |
| `ESTIMATE_TIMEOUT_MS`            | 35000 for the whole request, including fallback |
| `MAX_OUTPUT_TOKENS`              | 2400, including reasoning                       |

Legacy `OPENAI_MODEL` does not select the estimate model, so existing suggestion
configuration cannot accidentally keep meals on an older model. Existing
`OPENAI_BASE_URL`, `FOOD_IMAGES_BUCKET`, `VERIFY_JWT`, and `STREAM_TIMEOUT_MS`
remain supported. No hosted settings have been changed by this implementation.

## Labels and portions

Labels have their own strict schema. The model returns the printed nutrition
column and basis (`per_100g`, `per_100ml`, or `per_serving`), energy unit, and
any printed gram mass corresponding to that column. It never scales for the
amount eaten. Code converts kJ and known serving masses to per-100-g nutrition.
The normalized result explicitly declares `nutrition_basis: per_100g`; iOS
scales it once to grams eaten.

The original label reading remains in the `label` response field. Printed energy
is preserved even when fibre, polyols or rounding mean it differs from 4P+4C+9F.
Unreadable required fields are rejected rather than filled with zero.

EZHA's logging domain uses grams. A per-100-ml label without a printed mass
conversion, or a serving label without a readable gram mass, returns an
actionable manual-entry error. No water-density assumption or invented serving
weight is used.

Meals return itemized per-portion results with `nutrition_basis: per_portion`.
Each item has `nutrition_source`, `nutrition_source_id`, and
`portion_estimated`. User weights are distinguished from count conversions,
visual guesses and typical portions. At most one review question is returned.
Changing or confirming a portion recalculates locally; ingredient or identity
answers update the description and request a new estimate. Assumptions and
provenance remain in persisted item notes.

## Grounding

`food-catalog.json` contains 42 common food references from USDA FoodData
Central SR Legacy, April 2018 (the final release). Every row preserves its FDC
ID, exact source description and per-100-g energy/protein/carbohydrate/fat
values. `catalog-provenance.json` records the archive URL, hash, nutrient IDs
and CC0 attribution.

The catalog is intentionally limited. It does not cover all foods, brands or
recipes. The model must not match raw to cooked food or a mixed recipe to a
plain ingredient merely to find a reference. Unsupported matches fall back to an
estimate and disclose that fact. Even a sourced nutrient match does not verify
the actual portion or hidden ingredients.

User library lookup uses their bearer token and the existing RLS policies. Up to
60 non-meal foods, prioritized by favorites/recent use, are available as
candidates. A 1.5-second optional lookup deadline allows the USDA catalog to
work if personalization is unavailable. Known serving masses are converted
deterministically; `saved_foods.serving_size` is grams and `serving_unit` is a
display name such as cup.

To regenerate the catalog from the public archive:

```sh
python3 supabase/scripts/build-food-catalog.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
```

## Streaming and verification

Client events are `status`, `item` (a complete provisional item with its index),
`reset` (discard previews before fallback), `result` (fully validated), and
`error`. Provisional items never enter the draft or enable logging. A completed
OpenAI terminal event is required even if streamed text already parses as JSON.
Timeouts and client cancellation abort upstream fetches.

Structured logs include preparation time, first output/item time, model and
total time, grounded/estimated counts, and response IDs/token usage for each
model attempt. They omit meal text, photo paths and credentials. These
measurements support later p50/p95 latency and cost comparisons; this change
does not establish live model accuracy or latency.

```sh
deno check supabase/functions/ai-estimate/index.ts
deno test supabase/functions/ai-estimate/core.test.ts
xcodebuild -scheme EZHA -destination 'platform=iOS Simulator,name=EZHA iPhone 17 Pro' build test
```

The function entrypoint imports `service.ts`, `core.ts`, and
`food-catalog.json`; include these dependencies when deploying. Deploy the
updated backend before distributing the updated iOS client: the client rejects
legacy label responses without an explicit per-100-g basis. The existing
text/meal response shape remains compatible with older clients; additional
metadata can be ignored.

Official references:
[OpenAI vision](https://developers.openai.com/api/docs/guides/images-vision),
[Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna),
[GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol),
[USDA downloadable data](https://fdc.nal.usda.gov/download-datasets/).
