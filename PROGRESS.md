# EZHA iOS — Progress

## Status

Phase 2 — Project skeleton. Next step: create the Xcode project (app, widget extension, local package EZHAKit), xcconfig secrets, asset colors.

## Done

- Phase 0 — toolchain and backend baseline. Verified: iOS 26.4 runtime installed, Simulator "EZHA iPhone 17 Pro" (C22D5CFE-1BAC-4680-A204-4330F8E532A4) created, `supabase start` applies all migrations, `supabase db diff --linked --schema public,storage` reports no changes, `supabase migration list --linked` in sync, `supabase functions serve` returns 400 for `{}` and invalid JSON on `ai-estimate` and `ai-suggestions`.

- Phase 1 — backend RPCs. Verified: `supabase/tests/rpc_checks.sql` passes all 20 checks on local (`docker exec -i supabase_db_ezha-ios psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/rpc_checks.sql`); local `delete-account` run removed the user's storage folder and the user could not sign in again; `supabase db push` applied `20261005120000_ios_rpcs.sql`; `supabase migration list --linked` shows 11/11 in sync; functions deployed; deployed `ai-estimate` and `ai-suggestions` return 400 for `{}`; remote backfill left 0 of 8 users without a profile, target, or active target; remote `get_day` works for the test user.

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

## Handoff

1. Supabase dashboard › Authentication › URL Configuration › Redirect URLs: add `ezha://login-callback` and `ezha://reset-password`. Without them, Google sign-in and the password reset link fall back to the Site URL and do not open the app.
2. Supabase dashboard › Authentication › Sign In / Providers › Apple: turn it on and put `com.aliaksei.ezha` in "Client IDs". Native Sign in with Apple needs only the bundle ID; the Services ID and secret key are only for web OAuth.
3. Sign in with Apple needs a paid Apple Developer Program membership. The free Personal Team cannot sign the capability (see the Phase 12 device notes).
4. Google is already on for the PWA. No change needed beyond the redirect URL in step 1. The Google Cloud OAuth client must keep `https://eixwgqtyeaehczasvjup.supabase.co/auth/v1/callback` as an authorized redirect URI.

## Follow-ups

- `ai-estimate` checks the JWT only when the `VERIFY_JWT` secret is `true`, and platform `verify_jwt` is off. The remote has no `VERIFY_JWT` secret (checked with `supabase secrets list`), so text estimates work without sign-in. Fix: `supabase secrets set VERIFY_JWT=true`. Not done, because the guide does not ask for it.
- The deployed `ai-suggestions` source was not in any repo (downloaded from the project). It is now in `supabase/functions/ai-suggestions/`.
