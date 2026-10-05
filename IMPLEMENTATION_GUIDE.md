# EZHA iOS — Implementation Guide

This is the spec for the native iOS version of EZHA. Read it fully before you write code.

- Behavior reference: the `ezha-pwa` repo (Vue 3 + Supabase). File paths below like `src/...` are in that repo.
- If this guide and the PWA disagree, this guide wins. Section 12 lists the intentional changes.
- API names for iOS 26 and `supabase-swift` are written from memory. Check each one against current docs before you use it.

---

## 1. Product summary

EZHA is a daily calorie and macro tracker.

1. The user sets one or more named daily targets (calories, protein, carbs, fat).
2. The user logs meals from a photo, a nutrition-label photo, a text description, saved library items, or a combination. AI (edge function `ai-estimate`) estimates the items and macros. The user reviews and adjusts grams, then logs.
3. Today shows calories left (ring), macros left or over (bars), the day's target, and the logged meals.
4. The user can move to past days (never future days), change the target for a day, and delete entries.
5. Library holds saved foods (per 100 g or per serving) and saved meals (ingredient lists). Any item can be quick-logged.
6. Suggestions asks AI (edge function `ai-suggestions`) for 3 meal ideas that fit the remaining macros.
7. Logging works offline for library-only meals. Writes queue and retry. Logger drafts survive closing the app.

---

## 2. Tech stack

| Concern     | Choice                                                                                                                 |
| ----------- | ---------------------------------------------------------------------------------------------------------------------- |
| Min OS      | iOS 26.0, iPhone first. iPad runs the same layout with readable width.                                                 |
| Language    | Swift 6, strict concurrency                                                                                            |
| UI          | SwiftUI. UIKit only for `VNDocumentCameraViewController` and the camera picker.                                        |
| State       | Observation (`@Observable`), injected with `.environment(...)`                                                         |
| Backend     | Supabase (`supabase-swift` v2.x, SPM). The only third-party dependency.                                                |
| Local data  | SwiftData for the outbox and logger drafts. A JSON file cache in `Caches/` for last-seen server data.                  |
| Auth        | Supabase Auth: Sign in with Apple (native), Google (`ASWebAuthenticationSession` via supabase-swift), email + password |
| Images      | `PhotosPicker`, camera picker, VisionKit document camera. Resize and JPEG-encode with ImageIO.                         |
| Widgets     | WidgetKit + App Intents, in an App Group with the app                                                                  |
| Tests       | Swift Testing for `EZHAKit`. Xcode Previews for every screen.                                                          |
| Format/lint | `swift format` (ships with the Xcode toolchain). No SwiftLint.                                                         |

Animation uses SwiftUI only: springs, `PhaseAnimator`, `KeyframeAnimator`, `contentTransition(.numericText())`, `symbolEffect`, `matchedGeometryEffect`, zoom navigation transitions, `scrollTransition`, `MeshGradient`, `sensoryFeedback`. Do not add Lottie or similar.

---

## 3. Repository layout

Repo `~/Personal/ezha-ios` (remote `git@github-personal:aliaks-ei/ezha-ios.git`, branch `main`, already has an initial commit). Keep the `origin` URL as is: the `github-personal` SSH host is required for push. Move the backend into this repo, so app and backend change together.

```
ezha-ios/
  IMPLEMENTATION_GUIDE.md
  EZHA.xcodeproj
  Config/
    Shared.xcconfig            # committed; includes Secrets.xcconfig
    Secrets.xcconfig           # git-ignored: SUPABASE_URL, SUPABASE_ANON_KEY
    Secrets.example.xcconfig   # committed template
  EZHA/                        # app target
    App/                       # EZHAApp, RootView, AppModel, DeepLink
    Features/
      Auth/  Onboarding/  Today/  Logger/  Library/  Suggestions/  Settings/
    DesignSystem/              # Theme, MacroRing, MacroBar, Toast, Haptics, components
    Intents/                   # App Intents + AppShortcutsProvider
    Resources/                 # Assets.xcassets, Localizable.xcstrings, PrivacyInfo.xcprivacy
  EZHAWidgets/                 # widget extension: widgets + control
  Packages/EZHAKit/
    Sources/EZHAKit/
      Domain/                  # models + pure business rules
      Data/                    # Supabase clients
      Sync/                    # outbox, drafts, file cache, network monitor
      Shared/                  # WidgetSnapshot + App Group store (used by widget too)
    Tests/EZHAKitTests/
  supabase/                    # copied from ezha-pwa, then extended
    functions/ai-estimate/  functions/ai-suggestions/  functions/delete-account/
    migrations/
```

- One App Group: `group.<bundle-id>`. The app and widget share `WidgetSnapshot` through it.
- Keychain access group shared by app and widget is not needed. The widget reads only the snapshot.
- URL scheme: `ezha://`. Used for the OAuth callback, password reset, and widget/intent deep links.

---

## 4. Backend

The PWA will be retired after the iOS app ships. Backend changes are allowed. Keep them additive, so the PWA keeps working until then.

### 4.1 Current schema (from the PWA code)

There are no migrations in the PWA repo. Phase 0 captures the real schema. Until then, this is what the code uses:

| Table                    | Columns used                                                                                                                                                                                                                                           | Notes                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| `profiles`               | `user_id` PK, `calories_target`, `protein_target`, `carbs_target`, `fat_target`, `active_date` (yyyy-MM-dd), `active_target_id`, `created_at`, `updated_at`                                                                                            | One per user. Macro columns are legacy. `daily_targets` replaces them.                         |
| `daily_targets`          | `id`, `user_id`, `name`, `calories_target`, `protein_target`, `carbs_target`, `fat_target`, `created_at`, `updated_at`                                                                                                                                 | Named targets. A user always has at least one.                                                 |
| `daily_summaries`        | `user_id`, `date`, `calories`, `protein`, `carbs`, `fat`, `*_target` ×4, `has_data`, `daily_target_id`, `daily_target_name`, `created_at`                                                                                                              | Unique `(user_id, date)`. Stores totals and a **snapshot** of the target numbers for that day. |
| `food_entries`           | `id`, `user_id`, `date`, `input_type` (`photo`/`text`/`photo+text`), `input_text`, `image_path`, `calories`, `protein`, `carbs`, `fat`, `ai_confidence`, `ai_source` (`food_photo`/`label_photo`/`text`/`unknown`/`library`), `ai_notes`, `created_at` | One logged meal. Client generates `id`.                                                        |
| `food_entry_items`       | `id`, `entry_id`, `user_id`, `name`, `grams`, `calories`, `protein`, `carbs`, `fat`, `ai_confidence`, `ai_notes`, `created_at`                                                                                                                         | Items of an entry. Macros are absolute for the logged grams.                                   |
| `saved_foods`            | `id`, `user_id`, `name`, `unit_type` (`per_100g`/`per_serving`), `serving_size`, `serving_unit`, `*_per_100g` ×4, `*_per_serving` ×4, `is_meal`, `created_at`, `updated_at`                                                                            | Foods and meals in one table. Meals have all macro columns = 0.                                |
| `saved_meal_ingredients` | `id`, `meal_id`, `user_id`, `name`, `grams`, `calories`, `protein`, `carbs`, `fat`, `linked_food_id`, `created_at`                                                                                                                                     | Ingredient macros are absolute for its grams.                                                  |

- Storage bucket `food-images`. Object path `<user_id>/<entry_id>.jpg`.
- Edge function `ai-estimate`: source is in `supabase/functions/ai-estimate/index.ts`.
- Edge function `ai-suggestions`: source is **not** in the PWA repo. Phase 0 downloads it.

### 4.2 Edge function contracts

Both functions take `Authorization: Bearer <access_token>` and `apikey: <anon key>`.

**`ai-estimate`** — `POST /functions/v1/ai-estimate`

Request:

```json
{
  "text": "150g chicken, rice",
  "items": [{ "name": "rice", "grams": 200 }],
  "imagePath": "<uid>/<entryId>.jpg",
  "inputType": "food_photo",
  "stream": true
}
```

- `inputType`: `text`, `food_photo`, or `label_photo`. The PWA library-photo flow sends `photo`. Send `food_photo` instead.
- At least one of `text`, `items`, `imagePath` is required.

Non-stream response (JSON):

```json
{
  "totals": { "calories": 0, "protein": 0, "carbs": 0, "fat": 0 },
  "confidence": 0.8,
  "source": "food_photo",
  "food_name": "Chicken bowl",
  "notes": "...",
  "items": [
    {
      "name": "",
      "grams": 0,
      "calories": 0,
      "protein": 0,
      "carbs": 0,
      "fat": 0,
      "confidence": 0.8,
      "notes": ""
    }
  ],
  "error": "only on failure"
}
```

- Accept top-level `calories/protein/carbs/fat` when `totals` is missing. `source` and `notes` are required. Port `toEstimate` from `src/services/ai-analysis-service.ts`.
- **Today the function returns errors with HTTP 200 and `{ "error": "..." }`.** Always check the `error` field. Phase 0 fixes the status codes. Keep the body check anyway.
- For label photos, the result macros are **per 100 g**.

Stream response (`Accept: text/event-stream`, `"stream": true`). Server-sent events, blocks split by a blank line:

- `event: status` → `{"stage": "requesting_model" | "finalizing"}`
- `event: delta` → `{"delta": "<partial model text>"}`. Ignore the content. Use it only as a "still working" signal.
- `event: result` → same JSON as the non-stream response
- `event: error` → `{"error": "..."}`
- Server timeout is 20 s (`STREAM_TIMEOUT_MS`).

Use `URLSession.bytes(for:)` and read `.lines`. The PWA has a parser in `analyzeStream`, but nothing calls it. iOS uses streaming for the progress UI.

**`ai-suggestions`** — `POST /functions/v1/ai-suggestions`

Request (snake_case):

```json
{
  "remaining": { "calories": 900, "protein": 60, "carbs": 80, "fat": 25 },
  "meal_type": "Meal",
  "max_prep_minutes": 20,
  "count": 3,
  "ingredient_notes": "no peanuts",
  "variation_note": "Different options",
  "units": "grams"
}
```

Response: `{ "suggestions": [{ "title", "description", "calories", "protein", "carbs", "fat", "notes"? }], "error"? }`.
An empty or missing list is an error ("Suggestions returned an invalid response.").

**Auth retry rule (both functions):** on HTTP 401, refresh the session once and retry once. If the refresh fails, sign out and show "Your session expired. Please log in again."

### 4.3 Backend changes

Do these in Phase 0 and Phase 1. "Required" items are needed for correct iOS behavior.

1. **Required — capture the current state.**
   - `supabase link --project-ref eixwgqtyeaehczasvjup` (org "Pets"; the DB password is in `SUPABASE_DB_PASSWORD`), then `supabase db pull`. This writes the current schema, RLS policies, and indexes to `supabase/migrations/`.
   - `supabase functions download ai-suggestions`. Commit it.
   - Check: RLS is on for every table, with `user_id = auth.uid()`. The storage bucket is private, with policies limited to the `<auth.uid()>/` prefix. FKs from `food_entry_items.entry_id` and `saved_meal_ingredients.meal_id` use `on delete cascade`. If not, add them in a new migration. Record what you found in `PROGRESS.md` and continue.
   - Note the type of `date` columns (`date` or `text`). Adapt the SQL below to it.
2. **Required — fix edge function status codes.** `jsonError(message, status)`: 400 for bad input, 401 for auth, 502 for upstream model errors. Do the same in `ai-suggestions`. The PWA already reads `json.error` on non-2xx, so this is safe.
3. **Required — atomic, idempotent logging.** RPC `log_food_entry(p_entry jsonb, p_items jsonb, p_used_food_ids uuid[] default '{}') returns void`.
   - `security invoker`, so RLS applies. Force `user_id = auth.uid()` on every row.
   - Insert the entry with `on conflict (id) do nothing`. If nothing was inserted, return (the retry already succeeded). Then insert the items.
   - Set `saved_foods.last_used_at = now()` for `p_used_food_ids`.
   - One transaction. This replaces the PWA's two inserts plus manual rollback. It also makes outbox retries safe: today a retry after a lost response fails forever on the duplicate primary key.
4. **Required — server-side daily summary.**
   - `resolve_day_target(p_user uuid, p_date date) returns uuid`: the first non-null of
     1. this day's summary `daily_target_id`,
     2. the latest earlier day's summary with a `daily_target_id`,
     3. `profiles.active_target_id`,
     4. the user's oldest target.
   - `recompute_daily_summary(p_user uuid, p_date date)`: totals = sum of that day's `food_entries` macros, each rounded to an integer. `has_data = count > 0`. On insert, write the target snapshot from the resolved target. On conflict, update only the totals and `has_data`. Keep the existing target snapshot.
   - Trigger `after insert or update or delete on food_entries for each row` → recompute for the old and new `(user_id, date)`.
   - The iOS app never calls a summary sync. The PWA's own sync still works with this in place.
5. **Required — one call per day screen.** RPC `get_day(p_date date) returns jsonb`, read-only:

   ```json
   { "date": "2026-10-05",
     "target": { "id": "...", "name": "Basic", "calories_target": 2100, "protein_target": 140, "carbs_target": 220, "fat_target": 70 } ,
     "goals": { "calories": 2100, "protein": 140, "carbs": 220, "fat": 70 },
     "totals": { "calories": 640, "protein": 40, "carbs": 70, "fat": 20 },
     "targets": [ /* all daily_targets, oldest first */ ],
     "entries": [ { /* food_entries row */, "items": [ /* food_entry_items rows, oldest first */ ] } ] }
   ```

   - `goals`: the summary snapshot if a summary exists. Otherwise the resolved target, rounded. Otherwise `2100/140/220/70`.
   - `entries`: newest first.
   - This replaces `fetchDayBootstrap` (about 7 round-trips plus writes) with one read. Port its logic from `src/services/profile-bootstrap.ts`.

6. **Required — new-user bootstrap.** Trigger on `auth.users` insert: create the `profiles` row and one target named "Basic" with all zeros. Backfill the same for existing users without them. The client no longer runs `ensureProfileRowExists` / `ensureTargets`.
7. **Required — target RPCs.** Client dates are local. The server never computes "today".
   - `set_day_target(p_date date, p_target_id uuid, p_today date)`: upsert the day's summary with the target snapshot and recomputed totals. If `p_date = p_today`, also set `profiles.active_target_id`. Port `applyDailyTargetForDate` from `src/services/day-summary-service.ts`.
   - `save_daily_target(p_id uuid null, p_name text, p_calories, p_protein, p_carbs, p_fat, p_today date) returns uuid`: insert or update. On update, refresh the snapshot in `daily_summaries` where `daily_target_id = p_id and date >= p_today`. Past days keep their numbers. If the profile has no active target, set it.
   - `delete_daily_target(p_id uuid, p_today date)`: raise an error if it is the user's last target. If it was the active target, set active to the oldest remaining target.
8. **Required — atomic meals.** `save_meal(p_id uuid null, p_name text, p_ingredients jsonb) returns uuid`: create or rename the meal and replace all its ingredients in one transaction. This also enables meal editing (new in iOS).
9. **Required — account deletion** (App Store guideline 5.1.1(v)). Edge function `delete-account`: verify the JWT, delete storage objects under `<uid>/`, then `auth.admin.deleteUser(uid)`. Rows cascade. If any table does not cascade from `auth.users`, delete those rows explicitly first. The function uses the service-role key from function secrets only.
10. **Optional — synced favorites/recents.** Add `saved_foods.is_favorite boolean not null default false` and `saved_foods.last_used_at timestamptz`. The PWA keeps favorites in `localStorage`. Do not migrate them.

SQL checks for backend phases (run after `supabase db reset`):

- Insert an entry with `log_food_entry` twice with the same id → one entry, correct item count.
- Log, delete, and log on two dates → `daily_summaries` totals match the sum of entries.
- `get_day` for a date with no data → `goals` comes from the latest earlier target, `entries` is empty.
- Call `delete_daily_target` on the last target → error.
- As user B, read user A's rows → zero rows.

---

## 5. Business rules to port

Put all of these in `EZHAKit/Domain` as pure functions or value types. Port the matching Vitest cases to Swift Testing (section 10).

### 5.1 Dates — port from `src/lib/date.ts`, `src/lib/day-navigation.ts`

- A day is a `DateKey` (`yyyy-MM-dd`) in the device's current calendar and time zone. Use `en_US_POSIX` formatting. Never use UTC for date keys.
- `clamp(date, today)`: an invalid date or a future date becomes today.
- Previous day: −1 day. Next day: +1 day, clamped to today.
- Label: "Today" for today. Otherwise a short localized date ("Oct 4").
- Day boundary: if the user is on today and midnight passes, move to the new today. iOS: listen to `.NSCalendarDayChanged` and `scenePhase == .active`. Do not poll every minute.

### 5.2 Macros — port from `src/lib/macros.ts`

- `progressPercent(eaten, target)` = `round(eaten / target × 100)`, minimum 0. Returns 0 if target ≤ 0.
- Bar width = min(progressPercent, 100).
- Day totals = sum per macro, each rounded to an integer.
- Remaining = target − totals, per macro, unclamped.
- Calories in the ring: "kcal left" = max(0, target − eaten). When over, show "X kcal over" (new, section 12).
- Macro rows: show `abs(remaining)` and "left" or "over".
- `resolvedPer100g(food)` and per-serving fallbacks: port exactly. A food with only per-serving values derives per-100 g from `serving_size`.
- `formatMacro(value, maxFractionDigits)`: no grouping, max N fraction digits. In UI use `.formatted(.number.precision(.fractionLength(0...N)))`.

### 5.3 Number input — port from `src/lib/number.ts`

- Trim. Empty → nil. Remove spaces. If there is a comma and no dot, the comma is the decimal separator. Non-finite → nil.
- Use `.keyboardType(.decimalPad)`. It shows the locale's separator, which is why comma handling matters.

### 5.4 Logger item math — port from `src/features/add-log/log-meal-service.ts`

A `LogItem` has `id`, `name`, `gramsText`, `macroBasis` (`per100g` | `perOriginal`), `baseGrams`, base macros ×4, `origin` (`ai` | `libraryFood` | `libraryMeal`), `linkedFoodId`, `aiConfidence`, `aiNotes`, `isNutritionMissing`.

- Grams: parse, then clamp to `0...5000` (`MAX_LOG_ITEM_GRAMS`). Valid for logging only if > 0.
- Item macros: `per100g` → base × grams/100. `perOriginal` → base × grams/baseGrams. Missing nutrition → 0.
- Stepper: ±5 g, clamped. At 5000, show "Max grams per item is 5000g."
- When a grams field loses focus with invalid text, restore the last valid value for that item. For library foods, fall back to the last valid value for that food id, then to `baseGrams`. Keep this.
- From AI estimate: one item per estimate item (`perOriginal`, `baseGrams` = item grams). With no items, one item named by the suggested name with grams 100.
- From label estimate: items are `per100g`. Grams = "grams eaten" or 100.
- From saved food: `per100g` from `resolvedPer100g`. Default grams = serving size for per-serving foods, else 100.
- From saved meal: convert each ingredient to per-100 g. An ingredient with grams ≤ 0 or non-finite macros is `isNutritionMissing`.
- A new AI estimate replaces only the `ai` items. Library items stay.
- Label overrides: edited display macros at the current grams are converted back to per-100 g (`applyEditedLabelMacrosToItem`).

### 5.5 Entry payload — port `buildFoodEntryPayload`, `resolveFoodEntryInput`

- Rows skip items with no name, grams ≤ 0, or missing nutrition.
- `input_type` / `ai_source`:

| Sources used                     | input_type   | ai_source                                 |
| -------------------------------- | ------------ | ----------------------------------------- |
| photo + text                     | `photo+text` | `label_photo` if label, else `food_photo` |
| photo only                       | `photo`      | same rule                                 |
| text (or AI items without photo) | `text`       | `text`                                    |
| library only                     | `text`       | `library`                                 |
| none                             | `text`       | `unknown`                                 |

- `input_text` = item names joined with ", ", or "Meal". Quick log from Library uses the food or meal name.
- `ai_confidence` = average of non-null item confidences, else null.
- `ai_notes` = "Logged from combined meal sources".

### 5.6 Analyze gating

- Input fingerprint = trimmed text + photo identity + label flag.
- If text or a photo exists and the fingerprint differs from the last analyzed one, the primary button is **Estimate nutrition**. When they match, it is **Log meal · N kcal**.
- When the input changed after an estimate, show "Your photo or description changed. Update the estimate before logging."
- Library-only meals log without AI.
- Before logging: block if an item with grams > 0 has missing nutrition ("Remove items with missing nutrition before logging."). Require at least one valid item.

### 5.7 Library save — port from `src/features/add-log/library-save-service.ts`

- Manual food: name required. Macros are entered per 100 g. Per-serving requires serving grams > 0. Per-serving values = per-100 g × serving/100. Serving unit defaults to "serving".
- Photo food: display macros. For a label with grams eaten, convert back to per-100 g.
- Duplicate check: exact case-insensitive name match among non-meal foods → ask **Update existing** / **Create new** / **Cancel**.
- Suggested library name: first non-empty of: selected library food name, item names joined with " + ", description text, AI `food_name`. The suggested name fills the field until the user edits it.
- "Save this meal to Library" in the logger saves ingredients from the valid log items (`save_meal`). If it fails after the entry was saved, keep the entry and show "The library copy could not be saved. Your meal log is kept."

### 5.8 Library list — port from `src/features/library/library-helpers.ts`

- Filters: All, Foods, Meals, Favorites.
- Search: split on whitespace, case-insensitive, every term must be in the name, any order.
- Sort: recently used first (`last_used_at` desc, up to 16 recent), then by name.
- Row subtitle: meals → "Saved meal". Per 100 g → "Per 100g · N kcal". Per serving → "<size> <unit> · N kcal".

### 5.9 Quick log — port from `src/features/meal/MealQuickLogDialog.vue`

- Food: quantity in grams, default serving size or 100.
- Meal: quantity in portions, default 1. Each ingredient's grams × portions.
- Valid when quantity > 0, every item has grams in `(0, 5000]`, and no item has missing nutrition.
- Logs to the selected day with `ai_source = library`.

### 5.10 Targets

- Changing a day's target when the day has entries needs confirmation: "Change to <name>? Your logged meals stay the same. Only this day's goals and remaining macros update."
- The last target cannot be deleted ("At least one target is required.").
- Target editor: name required, 4 numeric fields.

### 5.11 Suggestions — port from `src/features/suggestions/SuggestionsPage.vue`

- Meal type: Meal | Snack. Max prep: 1–240 min (default 20). Notes optional. Count 3. Units "grams".
- Variation notes, exact strings: "Different options", "Adjust ingredients: <notes>", "Adjust prep time to <n> minutes".
- Warning per suggestion: "Exceeds calories by X kcal, protein by Y g, …" for each macro above remaining. Then the hint "Consider halving the portion or choosing a lighter option."
- If all goals are 0: "Set your daily targets in Settings for better suggestions."
- Changing the day clears the suggestions.

### 5.12 Images — port from `src/services/storage-service.ts`

- Longest side ≤ 1400 px, JPEG quality 0.75. Do it off the main actor with ImageIO (`CGImageSourceCreateThumbnailAtIndex`).
- Path `<user_id>/<entry_id>.jpg`, `upsert: false`. Upload once per logger session. Reuse `pendingImagePath` for re-estimates and for the final log.
- Strip location metadata before upload.

---

## 6. Client architecture

### 6.1 EZHAKit

**Domain/**: `Codable`, `Sendable` structs for every table row and RPC payload, with explicit `CodingKeys` for snake_case. Pure rule files: `DateKey`, `Macros`, `NumberInput`, `LogItemMath`, `EntryPayload`, `LibraryDrafts`, `LibraryFilter`, `SuggestionRules`.

**Data/**: one `SupabaseClient` instance (`SupabaseProvider`). Feature clients are structs of async closures, with a `.live` value and a `.preview` value. Do not use protocols.

```swift
public struct DayClient: Sendable {
  public var fetchDay: @Sendable (DateKey) async throws -> DayBundle            // rpc get_day
  public var setTarget: @Sendable (DateKey, UUID, DateKey) async throws -> Void // rpc set_day_target
  public var deleteEntry: @Sendable (UUID) async throws -> Void
}
```

Also: `LoggingClient` (`log_food_entry`, `save_meal`, image upload), `LibraryClient` (list, ingredients, insert/update/delete food, favorite, duplicate lookup), `TargetsClient`, `AIClient` (`estimateStream` → `AsyncThrowingStream<EstimateEvent, Error>`, `suggestions`), `AccountClient` (sign-in methods, sign out, reset password, delete account).

**Sync/**:

- `NetworkMonitor`: `NWPathMonitor` wrapped as `@Observable` (`isOnline`).
- `FileCache` (actor): `read<T: Decodable>(_ key: String)` / `write`. JSON files in `Caches/`. Keys: `day-<date>`, `library`, `targets`.
- `Outbox`: SwiftData `@Model PendingMutation { id, kind, payload: Data, attempts, nextAttemptAt, lastError, createdAt }`. Kinds: `logEntry` (payload = entry + items + used food ids), `deleteEntry`.
  - The processor is a `@ModelActor`. It runs one item at a time, in `createdAt` order.
  - Triggers: app launch, `scenePhase` active, network becomes reachable, a new enqueue.
  - Backoff: `min(2^attempts s, 300 s)`, the same as `retry-queue-service.ts`.
  - Network errors (`URLError` `.notConnectedToInternet`, `.networkConnectionLost`, `.timedOut`, `.cannotFindHost`, `.cannotConnectToHost`) → keep and back off. Any other error → keep it with `lastError` and show it in Settings › Sync. Never drop data silently.
- `DraftStore`: SwiftData `@Model LoggerDraft { dateKey (unique), state: Data, imageData: Data? (.externalStorage), updatedAt }`.

**Shared/**: `WidgetSnapshot { date, targetName, goals, totals, updatedAt }`. `SnapshotStore` reads and writes it as JSON in the App Group container.

### 6.2 App

- `AppModel` (`@Observable`, `@MainActor`): session state (`signedOut` / `onboarding` / `signedIn`), `selectedDate`, `isAIConsentGiven`, deep link routing.
- `DayStore` (`@Observable`): `bundles: [DateKey: DayBundle]`, load state per date, plus pending outbox entries merged in. Load order: show the cached bundle at once, then fetch, then write the cache. After each load of today, write `WidgetSnapshot` and call `WidgetCenter.shared.reloadAllTimelines()`.
- `LibraryStore`, `TargetsStore`: the same stale-while-revalidate pattern.
- `LoggerModel`: one per logger sheet, bound to a date. It owns the composer state, items, AI stream state, and debounced draft saving.
- Inject stores at the root with `.environment(store)`. Feature views read them with `@Environment(DayStore.self)`.

### 6.3 Data flow after writes

Logging does this:

1. Build the payload.
2. Optimistically insert the entry into `DayStore` for that date, marked `pending`.
3. Call the RPC. On success, refetch the day. On a network error, enqueue it in the outbox and keep the pending row.

Deleting an entry does this:

1. Remove the row optimistically.
2. Enqueue `deleteEntry` with `nextAttemptAt = now + 5 s`.
3. Show the toast "Entry deleted · Undo". Undo removes the outbox item and restores the row.
4. Deleting a still-pending entry removes its `logEntry` outbox item instead.

Other rules:

- Target change, target CRUD, and library CRUD are online-only. Show an inline error offline.
- Today totals include pending entries. Show a footnote: "Includes 1 meal waiting to sync".

---

## 7. Design system

### 7.1 Principles

- Liquid Glass belongs to the **navigation layer only**: tab bar, toolbars, the log accessory, floating buttons, toasts, sheet chrome. Content (ring card, entry rows, forms) uses solid grouped surfaces. The PWA used glass everywhere. Do not copy that.
- Use system components first: `List`, `Form`, `Section`, `.searchable`, `Menu`, `confirmationDialog`, `swipeActions`, `contextMenu`, `ContentUnavailableView`, `.refreshable`, sheets with detents.
- Use SF Symbols only. Use `.fontDesign(.rounded)` and `.monospacedDigit()` for all numbers.
- Use Dynamic Type text styles only. No fixed point sizes. Scale the ring with `@ScaledMetric`.
- Tap targets are at least 44×44 pt.

### 7.2 Colors

Add these to the asset catalog as color sets with light and dark variants. They are converted from the PWA HSL tokens in `src/style.css`. Check them by eye against the PWA.

| Token                          | Light           | Dark            | Use                                   |
| ------------------------------ | --------------- | --------------- | ------------------------------------- |
| `BrandPrimary` (magenta)       | `#D92B91`       | `#FF3DAB`       | tint, fat, ring end, primary buttons  |
| `BrandSecondary` (indigo)      | `#5A50E7`       | `#976BFF`       | protein, ring start                   |
| `BrandAccent` (orange / lilac) | `#FF8E4D`       | `#C7B8FF`       | carbs                                 |
| `Canvas`                       | `#F8F1F8`       | `#09050F`       | app background behind grouped content |
| `Surface`                      | `#FFFFFF`       | `#181023`       | cards and rows                        |
| `Ink`                          | `#261D35`       | system label    | primary text when not system          |
| `Track`                        | `#320773` @ 14% | `#C7B8FF` @ 14% | empty ring and bar tracks             |
| `Danger`                       | `#EC3642`       | `#D9323F`       | destructive, "over"                   |

- The app tint is `BrandPrimary`.
- The calorie ring uses an `AngularGradient` from `BrandSecondary` to `BrandPrimary`.
- Background: `Canvas` with a subtle `MeshGradient` of the three brand colors at low opacity at the top of Today and Auth only.
- Appearance setting (System / Light / Dark): `.preferredColorScheme` at the root, stored with `@AppStorage("appearance")`.

### 7.3 Shared components (DesignSystem/)

- `MacroRing(goal:eaten:)`: `Circle().trim` with round caps. The center shows calories left with `contentTransition(.numericText(value:))`, and "kcal left" or "kcal over". When over, the ring is full and an outer glow pulses once in `Danger`. VoiceOver: "640 of 2,100 calories eaten. 1,460 left."
- `MacroBar(title:goal:eaten:color:)`: title, remaining value with "left" or "over", a capsule bar, and "40 / 140 g eaten" in secondary text.
- `MacroLine`: "P 40g · C 70g · F 20g", reused in rows.
- `Toast`: a glass capsule overlay at the bottom with an optional action. It auto-dismisses after 4 s and is announced to VoiceOver.
- `GramsField`: a decimal field plus − and + buttons (`buttonRepeatBehavior(.enabled)`), with haptics.
- `Haptics`: use `.sensoryFeedback` modifiers. Do not create a manager class.

### 7.4 Motion

| Moment                            | Animation                                                                                                                                                                                                         |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ring and bars on appear or change | `.spring(duration: 0.8, bounce: 0.15)`. Numbers roll with `numericText`.                                                                                                                                          |
| Day change (swipe or chevron)     | Horizontal paging. Content uses `.transition(.push(from:))` by direction. `.sensoryFeedback(.selection)`.                                                                                                         |
| Open logger                       | Zoom transition from the log accessory or button (`matchedTransitionSource` + `.navigationTransition(.zoom)`).                                                                                                    |
| AI estimating                     | The composer border shows a slow moving `MeshGradient` shimmer. A sparkles symbol with `.symbolEffect(.variableColor.iterative)`. Stage text crossfades: "Uploading photo…", "Reading your meal…", "Finalizing…". |
| Estimate result                   | Item cards insert one by one (50 ms stagger), move + opacity.                                                                                                                                                     |
| Meal logged                       | Sheet dismisses. The new row inserts with a spring. The ring animates. `.sensoryFeedback(.success)`.                                                                                                              |
| Delete                            | System swipe. The toast slides up. Undo reinserts the row with a spring.                                                                                                                                          |
| Favorite                          | `symbolEffect(.bounce)` on the star.                                                                                                                                                                              |
| Suggestions refresh               | Old cards `.blurReplace` out, new cards in. Cards use `scrollTransition` scale and opacity.                                                                                                                       |
| Stepper / grams                   | `.sensoryFeedback(.increase/.decrease)`                                                                                                                                                                           |

Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): replace springs, push, and zoom with a 0.2 s opacity fade. Turn off the shimmer and the glow pulse.

---

## 8. Screens

The shell is a `TabView` with four tabs: **Today** (`sun.max`), **Suggestions** (`sparkles`), **Library** (`books.vertical`), **Settings** (`gearshape`).

- Log meal action: `tabViewBottomAccessory` with a glass bar: "+ Log meal · 1,460 kcal left". Tap opens the logger for the selected date.
- Use `.tabBarMinimizeBehavior(.onScrollDown)`.
- Today also has a toolbar `+` button.
- If an API name differs in iOS 26, use the closest native equivalent and report it.

### 8.1 Auth (signed out)

- Full-screen brand `MeshGradient` (slowly animated, static with Reduce Motion), the app name, and a one-line tagline.
- Buttons in order:
  1. `SignInWithAppleButton`: nonce flow, then `signInWithIdToken(provider: .apple)`.
  2. "Continue with Google": supabase-swift `signInWithOAuth(provider: .google, redirectTo: ezha://login-callback)`. It uses `ASWebAuthenticationSession`.
  3. "Continue with email" opens a sheet with a Sign in / Create account segmented control, email, password, and "Forgot password?" (`resetPasswordForEmail`, redirect `ezha://reset-password`).
- Handle `onOpenURL` → `supabase.auth.session(from:)` for OAuth and the recovery link. Recovery opens a "Set new password" sheet.
- Errors show inline under the form. Use `textContentType` `.username` / `.password` / `.newPassword` so AutoFill and passkey suggestions work.
- The PWA put an appearance picker on the auth page. Drop it. It lives in Settings.

### 8.2 Onboarding (new)

Show after sign-in when the user's only target has all zeros:

1. "Set your daily target". Four fields, prefilled 2100 / 140 / 220 / 70. A live hint: "Macros add up to N kcal" (4/4/9).
2. AI consent (section 9.4).
3. Finish → Today.
   Skip only the target step if the user already has a non-zero target.

### 8.3 Today

Top to bottom:

1. Navigation title = day label ("Today" / "Sat, Oct 4"), large.
   - Toolbar: a calendar button that opens a graphical `DatePicker` in a popover, limited to `...today`, with a "Today" button. When not on today, add a "Today" capsule button.
   - Swipe left/right on the content to change the day. The right swipe stops at today with a soft haptic bounce.
2. Target row: target icon, small caps "TODAY'S TARGET" or "DAY TARGET", "Basic · 2,100 kcal", chevron. Tap opens the Target sheet.
3. Summary card: `MacroRing` plus three `MacroBar`s (Protein = secondary, Carbs = accent, Fat = primary). Title "Remaining today" or "Remaining for this day". On narrow widths the ring sits above the bars. On wide widths they sit side by side. Use `ViewThatFits`.
4. "Logged meals" section with an entry count.
   - Row (collapsed): **640 kcal**, `MacroLine`, the entry title in secondary text, and a time on the right. A pending row shows a `clock.arrow.circlepath` badge, "Waiting to sync".
   - Tap opens the **Entry detail** sheet (medium/large): title, time · source label · "AI 80%". Item list with grams and macros. Photo thumbnail if `image_path` (signed URL, cached). Actions: "Log again" (copies the items to the selected date, new UUIDs), "Save as meal" (`save_meal`), and Delete.
   - Swipe trailing: Delete (no confirm, undo toast). Context menu: Log again, Save as meal, Delete.
   - Source labels: library → "Library", text → "AI: text", food_photo → "AI: photo", label_photo → "AI: label", unknown → "AI: photo" if `image_path`, else "AI: text".
5. Empty state: `ContentUnavailableView("Nothing logged yet", systemImage: "fork.knife", description: "Tap Log meal to add your first meal.")`.
6. Loading: redacted placeholders (`.redacted(reason: .placeholder)`) in the card and two rows. Show only when there is no cached bundle.
7. Error: an inline banner with a "Try again" button. Keep cached content visible.
8. `.refreshable` refetches the day and runs the outbox.

**Target sheet** (medium detent):

- List of targets: name, "2,100 kcal · P140 · C220 · F70", and a checkmark on the selected one.
- Select → if the day has entries, a `confirmationDialog` with the text from 5.10. Then `set_day_target`.
- "Add new target" opens the target editor sheet inline. Do not jump to the Settings tab.

### 8.4 Logger (sheet, `.large`)

The navigation title is "Log meal". The subtitle is the day label ("Today", "Oct 4"). Use `interactiveDismissDisabled` while estimating or saving.

Closing:

- Close saves the draft and dismisses.
- If the draft failed to save, show an alert ("Your draft could not be saved…") and do not dismiss.

Composer (top):

- Multiline `TextField("What did you eat?", axis: .vertical)` with the placeholder "e.g. 150g chicken, rice and a little olive oil". "(optional)" appears when a photo is attached.
- Attachment row of glass buttons:
  - **Camera**: a `UIImagePickerController` camera wrapper.
  - **Photos**: `PhotosPicker`, images only.
  - **Scan label**: `VNDocumentCameraViewController`. Take the first page. It sets "This is a nutrition label" on.
  - **Library**: pushes the Library picker inside the logger's `NavigationStack`.
- Photo preview: a rounded thumbnail with a remove (×) button. A "Nutrition label" toggle. When on, a "Grams eaten" decimal field (optional).
- Hide the Camera and Scan buttons when no camera is available (Simulator).

Estimating:

- Upload the image if needed, then stream `ai-estimate`. Show the stages from 7.4. "Cancel" stops the task.
- Errors show inline with "Try again".

Review (after an estimate or library additions):

- Heading "Review meal". Hint "Estimated nutrition. Adjust quantities before logging." when AI items exist.
- One card per item: name, `GramsField`, the live macro line, and delete (×). Also swipe to delete when the content is a `List`. Missing-nutrition note: "Nutrition is missing. Remove this item to log the rest of your meal."
- Label overrides (when the latest AI item came from a label): four macro fields and an "Apply" button (5.4).
- Totals line: "Total: 640 kcal · P 40g · C 70g · F 20g".
- "Save this meal to Library" toggle and a meal name field (5.7 suggested name).
- "Clear draft" (destructive, with confirmation).

Bottom bar (`safeAreaInset(edge: .bottom)`, glass):

- The stale-input note when needed.
- One primary `.glassProminent` button: "Estimate nutrition" or "Log meal · 640 kcal".
- On success: dismiss, success haptic, and the toast "Meal logged." When queued: "Saved on this device. Totals update after syncing." Add any partial-failure notice from 5.7.

Drafts:

- One draft per date. Save debounced 400 ms (max wait 1.2 s) on any change, and on `scenePhase` going to background.
- Restore on open. Clear after a successful log or on Clear draft.

### 8.5 Library picker (inside the logger)

- `.searchable`, a segmented filter (All / Foods / Meals / Favorites), and rows with a selection checkmark.
- Selecting a meal loads its ingredients (show a spinner on that row). If nutrition is missing → inline error "<name> has missing nutrition. Choose another item."
- Bottom button: "Add 3 items · 820 kcal". It appends the items to the logger (it never replaces existing items) and pops back.

### 8.6 Library tab

- Large title "Library". `.searchable("Search foods and meals")`. The filter is a segmented control in the list header (or `.searchScopes`). Toolbar `+` opens **Add food**.
- Row: name, subtitle (5.8), a favorite star if favorite, and a trailing "Log" capsule button.
  - Tap the row or Log → **Quick log sheet**.
  - Leading swipe: Favorite/Unfavorite. Trailing swipe: Delete (confirmation, because library items have no undo).
  - Context menu: Log, Favorite, Edit, Delete.
- Lists render lazily. Do not port the PWA's manual paging and "Show more".
- States: loading placeholders, empty library (`ContentUnavailableView` with an "Add food" button), search with no results (`ContentUnavailableView.search`), and error with retry.
- **Quick log sheet** (medium): name, quantity field with unit (g or portions) and stepper (food ±5 g, meal ±0.5 portion), live `MacroLine` + kcal, collapsible ingredient list for meals, and "Log to Today" or "Log to Oct 4". Success: dismiss, haptic, toast. Updates `last_used_at` through `log_food_entry`.
- **Food editor sheet**: name, unit type (Per 100 g / Per serving), serving grams and unit when per serving, then four macro fields under the header "Nutrition per 100 g", plus the live per-serving preview. Validation from 5.7.
- **Meal editor sheet** (new): name and an ingredient list (name, grams, macros). Edit or remove ingredients, add from library foods. Save with `save_meal`.
- **Add food sheet**: segmented **Photo** / **Manual**.
  - Photo: the same attachment buttons as the logger (no Library), "Estimate nutrition", then editable display macros, name, and "Save to Library".
  - Manual: the food editor fields.
  - Both run the duplicate check (5.7) with a `confirmationDialog`.

### 8.7 Suggestions tab

- A remaining macros header: four compact stat tiles (kcal, P, C, F). Show "as of 2 min ago" with a refresh button. It uses the selected date from `AppModel`, with the day label in the subtitle.
- Form card: Meal type segmented (Meal / Snack), Max prep `Stepper` 5–240 step 5 (shown as "20 min"; the field accepts 1–240), and notes `TextField(axis: .vertical)` with the placeholder "Restrictions or preferences, e.g. no peanuts, dairy-free".
- Primary button "Get suggestions" (glass prominent). After results, a "More" `Menu`: Other options / Regenerate by ingredients / Regenerate by time.
- Loading: three placeholder cards with the shimmer.
- Suggestion card: title, kcal capsule, description, `MacroLine`, the warning in `Danger` plus the hint, notes. The card action **"Log this"** (new) opens the logger with the description prefilled as "<title>: <description>". It does not auto-estimate. The user taps Estimate.
- Empty state (before the first request): a short "How it works" explanation with three bullet rows using SF Symbols. Do not use emoji.

### 8.8 Settings tab (`Form`)

1. **Daily targets**: a list (name, numbers). Tap to edit. Swipe to delete (disabled on the last target). "Add target".
2. **Appearance**: Picker System / Light / Dark.
3. **AI features**: a consent toggle (section 9.4) and a short text on what is sent and to whom.
4. **Sync**: shown only when the outbox is not empty. Lists pending items with their state and last error. "Retry now". "Discard" per item, with confirmation.
5. **Account**: email, "Sign out", and "Delete account" (destructive, two-step confirm, calls `delete-account`, then signs out).
6. **About**: version, privacy policy link.

---

## 9. Platform features

### 9.1 Widgets (EZHAWidgets)

- Data comes from `WidgetSnapshot` in the App Group. The widget makes no network calls.
- Timeline: one entry now, and one entry at the next local midnight with zero totals and the same goals. Policy `.atEnd`.
- Families:
  - `systemSmall`: ring with kcal left.
  - `systemMedium`: ring plus three bars.
  - `accessoryCircular`: `Gauge` of calories.
  - `accessoryRectangular`: kcal left plus a P/C/F line.
  - `accessoryInline`: "1,460 kcal left".
- Tap opens `ezha://today`. The medium widget also has a "Log" button that opens `ezha://log` (use a `Link`).
- Support tinted and clear Home Screen rendering modes (`widgetRenderingMode`, `widgetAccentable`).
- If the snapshot is older than today, show the new day with zero totals.

### 9.2 Control Center control

- `ControlWidgetButton` "Log meal" runs an `OpenIntent` that opens the logger.

### 9.3 App Intents (EZHA/Intents)

- `OpenLoggerIntent`: opens the app on the logger for today. Siri phrases: "Log a meal in \(.applicationName)", "Add food to \(.applicationName)".
- `CaloriesLeftIntent`: returns a dialog and a snippet view from the snapshot: "You have 1,460 kcal left. Protein 100 g, carbs 150 g, fat 50 g."
- `AppShortcutsProvider` registers both with SF Symbols.
- Stretch (do last, only if time allows): `LogSavedFoodIntent` with a `SavedFoodEntity` (an `EntityStringQuery` over the cached library). It logs the default quantity to today in the background.

### 9.4 Privacy and App Store

- **AI consent.** Before the first AI request, show a sheet: photos and descriptions are sent to our server and to OpenAI to estimate nutrition and suggest meals. Buttons "Allow" / "Not now". Store the answer. Without consent, the estimate, scan, and suggestion actions show the sheet again. Library and manual logging still work. Check the current App Store Review Guideline 5.1.2 text on third-party AI before release.
- `PrivacyInfo.xcprivacy`: declare `UserDefaults` API use (reason `CA92.1`) and collected data types (email, health and fitness data / food logs, photos, user ID). Purpose: app functionality. No tracking.
- Usage descriptions: `NSCameraUsageDescription` ("Take a photo of your meal or a nutrition label to estimate its nutrition."). `PhotosPicker` needs no photo library permission.
- Account deletion in Settings (8.8).
- Sign in with Apple is offered alongside Google (guideline 4.8).
- App icon: build a layered icon in Icon Composer from the brand gradient and the logo. Treat `public/logo.svg` in the PWA as a placeholder. Ship a clean placeholder icon and put "final icon art" on the handoff list.

---

## 10. Testing

### 10.1 Port these Vitest files to Swift Testing (`Packages/EZHAKit/Tests`)

| PWA test                                                                                                        | Swift test file                                                                  |
| --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `src/lib/day-navigation.test.ts`                                                                                | `DateKeyTests`                                                                   |
| `src/lib/macros.test.ts`                                                                                        | `MacrosTests`                                                                    |
| `src/features/add-log/log-meal-service.test.ts`                                                                 | `LogItemMathTests`, `EntryPayloadTests`                                          |
| `src/features/add-log/library-save-service.test.ts`                                                             | `LibraryDraftsTests`                                                             |
| `src/features/library/library-helpers.test.ts`                                                                  | `LibraryFilterTests`                                                             |
| `src/features/add-log/meal-input-helpers.test.ts`                                                               | Skip. The list-mode draft migration does not exist on iOS.                       |
| `src/services/day-summary-service.test.ts`, `day-summary-target-selection.test.ts`, `profile-bootstrap.test.ts` | Port the cases as SQL checks for `get_day` / `resolve_day_target` (section 4.3). |
| `src/query/keys.test.ts`, component tests                                                                       | Skip. They are web-only.                                                         |

### 10.2 Add

- `NumberInputTests`: comma decimal, spaces, empty, garbage.
- `EstimateParsingTests`: `totals` vs top-level macros, a missing `source` → error, an `error` field on HTTP 200 → error.
- `SSEParserTests`: split chunks, multi-line `data:`, unknown events ignored.
- `SuggestionRulesTests`: warning text for each macro, prep clamp.
- `OutboxTests` (in-memory `ModelContainer`): backoff schedule, network error keeps the item, success removes it, undo of a delayed delete.

### 10.3 Manual checks per phase (Simulator + one physical iPhone before release)

- VoiceOver on Today, Logger, Library: every control has a label. The ring reads as one element.
- Largest accessibility text size: no clipped text, and the ring and bars stack.
- Dark mode, Reduce Motion, Reduce Transparency, Increase Contrast.
- Airplane mode: log a library meal → pending row → back online → it syncs and the badge clears.
- Kill the app mid-draft → reopen the logger → the draft is restored, including the photo.
- Midnight rollover while the app is open on Today.

---

## 11. Phases (build in this order)

A phase is done when `swift format lint --recursive --strict .`, `xcodebuild … build test` (from Phase 2 on), and the phase checks pass. Then update `PROGRESS.md`, commit, and push to `origin main`. Then start the next phase.

Checks marked **(handoff)** need a physical device, a dashboard, or an account only the user has. Build the feature fully, verify everything you can in the Simulator, and add the check to the handoff list in `PROGRESS.md`. Do not stop for them.

**Phase 0 — Toolchain and backend baseline**

1. Toolchain: only the iOS 18.5 Simulator runtime is installed. Install the iOS 26 runtime (`xcodebuild -downloadPlatform iOS`) and create an iPhone Simulator on it. Start the container engine with `colima start`. This machine uses Colima, not Docker Desktop. If `supabase start` cannot reach Docker, set `DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`.
2. Copy `supabase/` from `~/Personal/ezha-pwa` into the repo.
3. Link the project, pull the schema, download `ai-suggestions` (4.3 item 1).
4. Fix the edge function status codes (4.3 item 2).

- Check: `supabase start` works. Functions run locally with `supabase functions serve`. A bad request returns 400.

**Phase 1 — Backend RPCs**

1. Migrations for 4.3 items 3–8 and 10. Edge function `delete-account` (item 9).
2. Run the SQL checks in 4.3 against local Supabase.
3. When they pass, apply the migrations to the remote project (`supabase db push`). Deploy the changed and new edge functions. All migrations must be additive. Never run `supabase db reset --linked`, and never drop or rewrite existing remote rows.

- Check: `supabase migration list` shows local and remote in sync. The deployed `ai-estimate` returns 400 for an empty request.
- (handoff) Configure the Apple and Google auth providers in the Supabase dashboard, and add `ezha://login-callback` and `ezha://reset-password` to the redirect URLs. Write the exact values the user needs (Services ID, bundle ID, redirect URL) into the handoff list.

**Phase 2 — Project skeleton**

1. Xcode project: app target, widget extension, local package `EZHAKit`, App Group, URL scheme, xcconfig secrets, the Sign in with Apple capability.
2. Asset catalog colors (7.2), accent color, placeholder app icon.
3. `SupabaseProvider` reading the URL and key from Info.plist. Crash early with a clear message if they are missing.

- Check: the app launches to a placeholder root view in light and dark mode.

**Phase 3 — Domain port**

1. Models and rules (section 5) in `EZHAKit/Domain`.
2. Tests from 10.1 and 10.2 (except the outbox tests).

- Check: all tests pass. Every rule in section 5 has at least one test.

**Phase 4 — Data and sync**

1. Feature clients (6.1) against the new RPCs.
2. `FileCache`, `NetworkMonitor`, `Outbox` with its processor, `DraftStore`, `SnapshotStore`.
3. Outbox tests.

- Check: an integration smoke test against local Supabase (`supabase start`): sign up a test user, log an entry, fetch the day.

**Phase 5 — Auth and onboarding**

1. 8.1 and 8.2, deep link handling, session restore at launch with no flash of the auth screen (show the brand background until the session check finishes).

- Check: email sign-up and sign-in work in the Simulator against local Supabase. Sign out returns to Auth. A new user sees onboarding. Session restore works after relaunch.
- (handoff) Sign in with Apple and Google on a device, after the providers are configured.

**Phase 6 — Shell and Today**

1. `TabView`, log accessory, `AppModel.selectedDate`, day boundary handling.
2. Today (8.3) with the ring, bars, entries, entry detail, swipe and undo delete, the target sheet, cache-first loading.

- Check: day swipe, calendar, target change with confirmation, delete and undo, pull to refresh, offline cached view.

**Phase 7 — Logger**

1. Composer, camera/photos/scan, image processing and upload, streaming estimate, review, label flow, save to library, drafts, offline queue.
2. Library picker (8.5).

- Check: every source combination in the 5.5 table produces the right `input_type`/`ai_source`. The stale-input gating works. The draft survives an app kill.

**Phase 8 — Library**

1. 8.6: list, search, filters, favorites, quick log, food editor, meal editor, add food (photo/manual), duplicate dialog.

- Check: a per-serving food defaults to its serving grams in quick log. A meal scales by portions. The duplicate flow works for both choices.

**Phase 9 — Suggestions**

1. 8.7 including "Log this".

- Check: the warning text matches 5.11. Changing the day clears the results.

**Phase 10 — Settings, privacy, account**

1. 8.8, AI consent gating (9.4), account deletion, the Sync section.

- Check: a deleted account cannot sign in again and its storage folder is gone.

**Phase 11 — Widgets and intents**

1. 9.1–9.3.

- Check: the widget extension builds, and every widget family renders in Xcode Previews with sample snapshots. Logging a meal in the Simulator writes a new `WidgetSnapshot`. `xcrun simctl openurl booted ezha://log` opens the logger.
- (handoff) The widget on the Home and Lock Screen, Siri "Log a meal in EZHA", and the Control Center control on a device.

**Phase 12 — Polish and release readiness**

1. Go through the motion table (7.4) and the Reduce Motion fallbacks.
2. Accessibility pass (10.3). Fix every finding.
3. Performance smoke test in the Simulator: Today with 30 entries scrolls smoothly, and a cold launch shows cached Today without a loading state. (handoff) Instruments run on a device.
4. Privacy manifest, usage strings, icon, launch screen (`Canvas` color).
5. End-to-end run in the Simulator against the **remote** backend with the test user: log by text, by photo, and from the library; change a target; delete and undo; get suggestions.
6. Install and launch the app on the connected iPhone (`xcodebuild` with the device destination, then `xcrun devicectl device install app` and `xcrun devicectl device process launch`). If no device is connected or signing fails, record the exact reason on the handoff list.

---

## 12. Intentional changes from the PWA

| PWA                                                                       | iOS                                                       | Why                                       |
| ------------------------------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------- |
| Client inserts entry + items, rolls back manually, then syncs the summary | `log_food_entry` RPC + summary trigger                    | Atomic, safe to retry, fewer round-trips  |
| `fetchDayBootstrap` (~7 calls + writes on read)                           | `get_day` RPC, read-only                                  | Fast, consistent day screen               |
| Client creates the profile and "Basic" target on first read               | `auth.users` trigger + onboarding with real targets       | New users start with useful goals         |
| Favorites/recents in `localStorage`                                       | `saved_foods.is_favorite`, `last_used_at`                 | Synced across devices                     |
| Delete with `window.confirm`                                              | Swipe delete + 5 s undo                                   | Faster, recoverable                       |
| Pending offline entries hidden                                            | Shown as pending rows, included in totals with a footnote | The user sees what they logged            |
| Calories ring shows 0 left when over                                      | Shows "N kcal over"                                       | Clearer                                   |
| Glass on every surface                                                    | Glass on the navigation layer only                        | iOS 26 design guidance                    |
| Non-streaming estimate                                                    | Streaming with stage progress and cancel                  | Feels faster                              |
| Center + tab button                                                       | Tab bar bottom accessory "Log meal · N kcal left"         | Native iOS 26 pattern, shows key info     |
| Saved meal recipes cannot be edited                                       | Meal editor + `save_meal`                                 | Follow-up from `docs/mobile-ux-review.md` |
| No password reset, no account deletion                                    | Both added                                                | Expected / required on iOS                |
| Suggestions are read-only                                                 | "Log this" prefills the logger                            | Closes the loop                           |
| Polls the day boundary every 60 s                                         | Day-changed notification + scene phase                    | No timers                                 |

---

## 13. Out of scope

- Barcode scanning and food databases.
- HealthKit.
- Live Activities.
- iPad-specific layouts beyond readable width.
- Localization beyond English. Still put every string in the String Catalog.
- Deleting entry photos from storage when an entry is deleted. Note it as a follow-up.
