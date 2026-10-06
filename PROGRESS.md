# EZHA iOS — Progress

## Status

Phase 12 — Polish and release readiness. Next step: motion and Reduce Motion pass, accessibility pass (VoiceOver labels, largest text, contrast), performance smoke test (30 entries, cold launch from cache), privacy manifest, end-to-end run against the remote backend, then device install.

## Done

- Phase 0 — toolchain and backend baseline. Verified: iOS 26.4 runtime installed, Simulator "EZHA iPhone 17 Pro" (C22D5CFE-1BAC-4680-A204-4330F8E532A4) created, `supabase start` applies all migrations, `supabase db diff --linked --schema public,storage` reports no changes, `supabase migration list --linked` in sync, `supabase functions serve` returns 400 for `{}` and invalid JSON on `ai-estimate` and `ai-suggestions`.

- Phase 1 — backend RPCs. Verified: `supabase/tests/rpc_checks.sql` passes all 20 checks on local (`docker exec -i supabase_db_ezha-ios psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/rpc_checks.sql`); local `delete-account` run removed the user's storage folder and the user could not sign in again; `supabase db push` applied `20261005120000_ios_rpcs.sql`; `supabase migration list --linked` shows 11/11 in sync; functions deployed; deployed `ai-estimate` and `ai-suggestions` return 400 for `{}`; remote backfill left 0 of 8 users without a profile, target, or active target; remote `get_day` works for the test user.

- Phase 2 — project skeleton. Verified: `swift format lint --recursive --strict .` clean; `xcodebuild -scheme EZHA -destination 'platform=iOS Simulator,name=EZHA iPhone 17 Pro' build test` succeeded; app launched in the Simulator in light and dark mode and showed the placeholder root view with the Supabase host read from Info.plist.

- Phase 3 — domain port. Verified: lint clean; `xcodebuild … build test` ran 52 Swift Testing tests in 10 suites, all passed. Rules 5.1–5.9 and 5.11 have tests. 5.10 (last target, target change) is covered by the SQL checks; 5.12 (image resize) gets its test with the image code in Phase 7.

- Phase 4 — data and sync. Verified: lint clean; `xcodebuild … build test` ran 59 tests in 11 suites (7 new `OutboxTests`), all passed; a scratch Swift executable using the live clients against local Supabase signed up a user, saved a target, added a food, logged an entry twice (one entry kept), fetched the day (totals 260 kcal, goals 2100), found the duplicate food, saved a meal, deleted the entry, and deleted the account.

- Phase 5 — auth and onboarding. Verified: lint clean; `xcodebuild … build test` 59/59 passed; a scratch XCUITest against local Supabase signed up by email, saw onboarding (target prefilled 2100/140/220/70, "Macros add up to 2070 kcal"), allowed AI, reached the signed-in shell, relaunched into the signed-in shell with no auth screen, signed out to Auth, and signed back in without onboarding. Screenshots of Auth checked in light and dark mode.

- Phase 6 — shell and Today. Verified: lint clean; `xcodebuild … build test` 59/59 passed; scratch XCUITest `TodayTests` against local Supabase with a seeded user passed: Today shows the seeded meals, swipe right goes to yesterday and back, swipe forward stops at today, the calendar popover opens, choosing "Cut" asks for confirmation and updates the target row, swipe delete hides the row with an "Undo" toast, Undo restores it, a second delete reaches the server after 5 s, pull to refresh shows a server-side entry, and a relaunch against an unreachable server shows cached Today with the "Try again" banner. Screenshots checked in light and dark mode.

- Phase 7 — logger. Verified: lint clean; `xcodebuild … build test` 61/61 passed (new `ImageProcessingTests`: 3000×2000 becomes 1400×933 and GPS is removed); scratch XCUITest `LoggerTests` against local Supabase with a mock OpenAI server passed: text estimate with the consent sheet, the stale-input note and "Estimate nutrition" after editing the text, re-estimate and log; library-only log; photo-only log (Photos picker); photo + text as a nutrition label with 50 g eaten (442 kcal/100 g became 221 kcal); text + library. The server rows were `text/text`, `text/library`, `photo/food_photo` with an image path, `photo+text/label_photo` with an image path, and a `text/text` entry that includes the Oats library item. A draft with text and a photo survived an app kill.

- Phase 8 — library. Verified: lint clean; `xcodebuild … build test` 61/61 passed; scratch XCUITest `LibraryTests` against local Supabase passed: a per-serving food (150 g cup) opens quick log at 150 g / 90 kcal and logs; a saved meal opens at 1 portion / 328 kcal, + makes 1.5 portions / 492 kcal and logs (server rows "Greek yogurt cup" 90 and "Overnight oats" 492); adding "oats" asks about the existing "Oats", Update existing keeps one food with the new 400 kcal; adding "OATS" with Create new makes a second; leading swipe favorites and the Favorites filter shows only it; the context menu Edit renames a meal; Add food › Photo estimates and saves "Chicken and rice". Screenshots checked in light and dark mode.

- Phase 9 — suggestions. Verified: lint clean; `xcodebuild … build test` 61/61 passed; scratch XCUITest `SuggestionsTests` against local Supabase and the mock passed: with 460/20/50/20 remaining, the cards show "Exceeds calories by 190 kcal, protein by 25 g, carbs by 10 g, fat by 2 g" and "Exceeds protein by 12 g" with the hint; More › Other options regenerates; "Log this" opens the logger with "Turkey wrap: Whole wheat wrap with turkey and salad." and the primary button still says Estimate; switching to yesterday clears the results. Screenshots checked in light and dark mode.

- Phase 10 — settings, privacy, account. Verified: lint clean; `xcodebuild … build test` 61/61 passed; scratch XCUITest `SettingsTests` against local Supabase passed: add and swipe-delete a target, appearance switch, then a relaunch against an unreachable server logged a library meal offline ("Saved on this device…" toast, a "Waiting to sync" row, the "Includes 1 meal waiting to sync" footnote, and a Settings › Sync row), and a relaunch online synced it (badge gone, server row present). Delete account with the two-step confirmation returned to Auth; the same email could no longer sign in; `psql` showed 0 storage objects under the user's folder and 0 auth, entry, and food rows.

- Phase 11 — widgets and intents. Verified: lint clean; `xcodebuild … build test` 61/61 passed (app and widget extension build); a scratch unit-test target compiled `EZHAWidgets/CaloriesWidget.swift` and rendered all five families (small, medium, circular, rectangular, inline) in light and dark mode, under and over goal, with `ImageRenderer`; scratch XCUITest `WidgetLinkTests` passed: a quick log wrote `widget-snapshot.json` in the App Group container (totals 1,020 kcal = 640 seeded + 380 logged), `ezha://log` opened the logger from the Library tab, and `ezha://today` returned to today.

## Decisions

- No `SUPABASE_DB_PASSWORD` in the shell. The Supabase CLI (2.119) works without it: it creates a temporary login role through the Management API.
- `supabase db pull` refused: the remote already had 9 migrations in its history with no local files. Used `supabase migration fetch --linked` to get them, so the remote history was not repaired or reverted.
- Those 9 migrations do not create `profiles`, `food_entries`, `daily_summaries`, or the `food-images` bucket (made in the dashboard). Added `20260101000000_baseline.sql` from `supabase db dump --linked`, and marked it applied on the remote with `supabase migration repair --status applied` (one history row, no SQL run).
- Schema audit: RLS is on for all 7 public tables, every policy is `auth.uid() = user_id`. Bucket `food-images` is private; its select/insert/delete policies check `auth.uid() = (storage.foldername(name))[1]::uuid`. There is no update policy (not needed, uploads use `upsert: false`). All FKs to `auth.users` and from `food_entry_items.entry_id` / `saved_meal_ingredients.meal_id` cascade. `date` columns are type `date`. No new FK migration needed.
- Edge function status codes: 400 bad input, 401 auth, 502 model errors, and 500 for missing server config (the guide does not name a code for that). Streaming errors stay as SSE `error` events, since the 200 status is already sent.
- Both deployed functions have `verify_jwt = false` and check the token in code. Kept that in `supabase/config.toml` so deploys do not change behavior.

- `resolve_day_target` skips target ids that no longer exist in `daily_targets` (no FK on `daily_summaries.daily_target_id`).
- `recompute_daily_summary` and its trigger function are `security definer` and return early if the `auth.users` row is gone, so account deletion cascades do not fail. They are not callable through the API.
- `recompute_daily_summary` falls back to the legacy profile macros when no target resolves, like the PWA's `buildDailySummaryForDate`.
- `delete_daily_target` uses `p_today`: summaries on today and later that pointed at the deleted target move to the oldest remaining target. Past days keep their snapshot.
- `log_food_entry` accepts `created_at` in `p_entry`, so entries queued offline keep the time they were logged. Items get `now()` plus their index in microseconds, so `get_day` returns them in client order.
- Backfill copies the legacy profile macros into the new "Basic" target (like the PWA's `ensureTargets`). New users get zeros, as the guide says.
- RPCs are not executable by `anon`.
- Remote test user: `ezha-ios-test@example.com`, credentials in `.local/test-user.env`.
- The Xcode project is generated by XcodeGen from `project.yml` (installed at /opt/homebrew/bin/xcodegen). `EZHA.xcodeproj` is committed too. Sources use synced folders, so new files need no regeneration; run `xcodegen generate` only after editing `project.yml`.
- Brand color sets live in `Packages/EZHAKit/Sources/EZHAKit/Resources/Theme.xcassets` (exposed as `Color.brandPrimary` and so on), so the app and the widget share one copy. The app catalog keeps `AccentColor`, `Canvas` (needed by the launch screen), and `AppIcon`. `Ink` dark is `#FFFFFF` (system label in dark mode).
- Placeholder icon: the PWA logo path on the brand gradient, with dark and tinted variants, as a single-size 1024 PNG app icon set (not an Icon Composer file).
- `SUPABASE_URL` in xcconfig is written as `https:/$()/…`, because xcconfig treats `//` as a comment.
- Debug builds accept `EZHA_SUPABASE_URL` and `EZHA_SUPABASE_ANON_KEY` environment overrides (`SIMCTL_CHILD_` prefix with `simctl launch`), to test against local Supabase without a rebuild.
- `.swift-format` is the default configuration from `swift format dump-configuration` (2 spaces, 100 columns). Build with the default DerivedData location: a DerivedData folder inside the repo makes the lint scan dependency sources.
- Entry totals in `EntryPayload.build` are the sum of the saved rows. The PWA summed all log items, so an item with no name still counted in the total but was not saved. The rows sum keeps the entry and its items consistent.
- `SSEParser` takes raw text chunks and splits lines itself. `URLSession.AsyncBytes.lines` drops empty lines, and SSE blocks end with an empty line, so the client reads bytes and feeds whole lines.
- `LibraryFilter.sorted` uses `localizedStandardCompare` for names (case-insensitive, natural number order).
- The serving unit defaults to "serving" when empty (guide 5.7). The PWA stored null.
- `AnalyzeGate.logBlockReason` adds "Add at least one item with grams before logging." when there is no valid item (the guide asks to require one but gives no text).
- Logger item builders keep the PWA notes ("Added from library food", "Added from saved meal"). The missing-nutrition note is "Missing nutrition" instead of the PWA's "[PLACEHOLDER] …" text.
- Edge functions are called with `URLSession` directly (`FunctionCaller`), not `supabase.functions`, to stream bytes and apply the 401 rule (refresh once, retry once, else sign out with "Your session expired. Please log in again.").
- `PendingMutation` has two fields beyond the guide: `entityId` (the entry id, to find a pending log for undo and pending deletes) and `dateKey` (to merge pending rows into the right day).
- Outbox runs stop at the first network error (the rest would fail too). Other errors keep the item with `lastError`, back off, and the run continues with the next item.
- RPC parameters use one dictionary-based `RPCParams` encoder. Optional values encode as JSON null.
- supabase-swift 2.55.3 API names matched the guide: `signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken:nonce:))`, `signInWithOAuth(provider:redirectTo:)` (ASWebAuthenticationSession variant), `session(from:)`, `resetPasswordForEmail(_:redirectTo:)`, `authStateChanges`. Client option `emitLocalSessionAsInitialSession: true` is set, as the library now asks.
- Debug-only environment overrides `EZHA_SUPABASE_URL` / `EZHA_SUPABASE_ANON_KEY` also work for `swift run` on macOS.
- UI checks run through a scratch XCUITest target that is not committed: a second XcodeGen spec in the session scratchpad includes `project.yml` and adds `EZHAUITests`. The guide lists no UI tests in section 10.
- Onboarding shows when the user's only target is all zeros. The consent step is skipped when consent was already decided on this device. Existing users with real targets skip onboarding and see the consent sheet before their first AI action.
- AI consent is stored per device in `UserDefaults` (`aiConsent`: undecided / allowed / declined).
- The Auth screen uses white title text and a black Sign in with Apple button in both modes, because the brand gradient is bright in both.
- `NSAllowsLocalNetworking` is on so the Simulator can reach local Supabase over http.
- Sign-out clears the file cache and the widget snapshot. Drafts and the outbox are handled in Settings (Phase 10).
- Logging always goes through the outbox (enqueue, then run at once). Success refetches the day; any failure leaves the pending row. This gives one code path for online and offline logging.
- Pending deletes are outbox items, so a deleted row stays hidden across relaunches until the delete syncs. Undo removes the item. Deleting a still-pending entry drops its `logEntry` item, and Undo queues it again.
- The day swipe gesture is on the target row, the summary card, and the empty state, not on entry rows, because entry rows use the trailing swipe for Delete.
- When a day was never loaded and the device is offline, a pending entry still shows with the goals of the latest cached earlier day.
- `DateKey` is `Identifiable` in EZHAKit (used for `.sheet(item:)`), because the lint forbids retroactive conformances.
- Entry detail "Log again" keeps the source entry's `input_type`, `ai_source`, text, and photo path; only ids, date, and time are new.
- No zoom transition for the logger sheet. Dismissing a `.navigationTransition(.zoom)` sheet whose `matchedTransitionSource` is in `tabViewBottomAccessory` crashes with a UIKit assertion in `-[UIView _morphPreviewFromCurrentState:…]` on iOS 26.4. The sheet uses the standard animation.
- The Simulator on iOS 26.4 reports a camera (`UIImagePickerController.isSourceTypeAvailable(.camera)` and `VNDocumentCameraViewController.isSupported` are true), so Camera and Scan label show there. The code still hides them when the API says no camera.
- Local AI tests use a scratch mock of the OpenAI Responses API (`OPENAI_BASE_URL=http://host.lima.internal:8787/v1` in a scratch env file for `supabase functions serve`). The real model runs only on the remote project.
- The logger sends `text`, `imagePath`, and `inputType` to `ai-estimate`; it does not send the library items as `items`. Library items stay as they are, and a new estimate replaces only AI items (5.4).
- A new photo gets a new entry id, so the storage path `<user_id>/<entry_id>.jpg` stays unique with `upsert: false`. An "already exists" upload error reuses that path.
- Label overrides edit the first AI item when the latest estimate came from a label.
- Attachment buttons are an icon over a short label in one row, falling back to a horizontal scroll at large text sizes.
- Confirmation dialogs pass their data through `presenting:`. Reading `@State` inside a dialog or sheet action is unsafe: dismissing clears the binding first. This fixed two bugs (AI consent "Allow" did nothing, duplicate "Update existing" did nothing).
- Add food › Photo uploads the photo under a random UUID name (`<user_id>/<uuid>.jpg`), because there is no entry. A non-label photo saves its display macros as per 100 g, like the PWA's `buildPhotoLibraryDraft`.
- The meal editor edits ingredients as logger items (per 100 g), so changing grams scales the macros. New ingredients come from saved foods at their default grams.
- Library deletes use a confirmation dialog and have no undo (guide 8.6).
- "Log this" fills the logger text only when the day's draft has no text, so an existing draft is not overwritten.
- Warnings compare against the remaining macros at the time of the request, like the PWA.
- The privacy policy row reads `PRIVACY_POLICY_URL` (Info.plist from `Config/Shared.xcconfig`) and is hidden while empty, because there is no policy URL yet.
- Sign out with pending outbox items asks first ("N changes waiting to sync will be lost"), then clears the outbox, drafts, caches, and the widget snapshot.
- Delete account uses a confirmation dialog, then an alert ("This cannot be undone."), as the two steps.
- The Sync section shows each item's last error, or "Waiting to sync", or the next retry time and attempt count.
- `OpenLoggerIntent` has `supportedModes = .foreground` and is compiled into the app and the widget extension (the control needs the type). In the app it calls a handler the app installs; anywhere else it sets an App Group flag that the app reads when it becomes active. I did not use `OpenURLIntent` because I could not confirm it opens a custom URL scheme.
- The widget view is split into `CaloriesWidgetView` (reads `widgetFamily`) and `CaloriesWidgetContent(entry:family:)`, because `widgetFamily` is read-only and the families were checked by rendering the content view offscreen.
- The stretch `LogSavedFoodIntent` is done: `SavedFoodEntity` with an `EntityStringQuery` over the cached library. It logs the default quantity (food default grams, or 1 portion of a meal whose ingredients are cached), falls back to the outbox when offline, and adds the macros to the widget snapshot.
- Siri phrases for "Calories left": "Calories left in EZHA", "How many calories are left in EZHA".

## Handoff

1. Supabase dashboard › Authentication › URL Configuration › Redirect URLs: add `ezha://login-callback` and `ezha://reset-password`. Without them, Google sign-in and the password reset link fall back to the Site URL and do not open the app.
2. Supabase dashboard › Authentication › Sign In / Providers › Apple: turn it on and put `com.aliaksei.ezha` in "Client IDs". Native Sign in with Apple needs only the bundle ID; the Services ID and secret key are only for web OAuth.
3. Sign in with Apple needs a paid Apple Developer Program membership. The free Personal Team cannot sign the capability (see the Phase 12 device notes).
4. Google is already on for the PWA. No change needed beyond the redirect URL in step 1. The Google Cloud OAuth client must keep `https://eixwgqtyeaehczasvjup.supabase.co/auth/v1/callback` as an authorized redirect URI.
6. Set `PRIVACY_POLICY_URL` in `Config/Shared.xcconfig` once a privacy policy is published (App Store requirement). Write `https:/$()/` for `https://`.
5. On the iPhone, after steps 1–3: sign in with Apple and with Google, and confirm both land on Today (or onboarding for a new account).

## Follow-ups

- `ai-estimate` checks the JWT only when the `VERIFY_JWT` secret is `true`, and platform `verify_jwt` is off. The remote has no `VERIFY_JWT` secret (checked with `supabase secrets list`), so text estimates work without sign-in. Fix: `supabase secrets set VERIFY_JWT=true`. Not done, because the guide does not ask for it.
- The deployed `ai-suggestions` source was not in any repo (downloaded from the project). It is now in `supabase/functions/ai-suggestions/`.
