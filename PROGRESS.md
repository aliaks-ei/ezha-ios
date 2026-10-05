# EZHA iOS — Progress

## Status

Phase 1 — Backend RPCs. Next step: write migrations for guide 4.3 items 3–8 and 10, then run the SQL checks against local Supabase.

## Done

- Phase 0 — toolchain and backend baseline. Verified: iOS 26.4 runtime installed, Simulator "EZHA iPhone 17 Pro" (C22D5CFE-1BAC-4680-A204-4330F8E532A4) created, `supabase start` applies all migrations, `supabase db diff --linked --schema public,storage` reports no changes, `supabase migration list --linked` in sync, `supabase functions serve` returns 400 for `{}` and invalid JSON on `ai-estimate` and `ai-suggestions`.

## Decisions

- No `SUPABASE_DB_PASSWORD` in the shell. The Supabase CLI (2.119) works without it: it creates a temporary login role through the Management API.
- `supabase db pull` refused: the remote already had 9 migrations in its history with no local files. Used `supabase migration fetch --linked` to get them, so the remote history was not repaired or reverted.
- Those 9 migrations do not create `profiles`, `food_entries`, `daily_summaries`, or the `food-images` bucket (made in the dashboard). Added `20260101000000_baseline.sql` from `supabase db dump --linked`, and marked it applied on the remote with `supabase migration repair --status applied` (one history row, no SQL run).
- Schema audit: RLS is on for all 7 public tables, every policy is `auth.uid() = user_id`. Bucket `food-images` is private; its select/insert/delete policies check `auth.uid() = (storage.foldername(name))[1]::uuid`. There is no update policy (not needed, uploads use `upsert: false`). All FKs to `auth.users` and from `food_entry_items.entry_id` / `saved_meal_ingredients.meal_id` cascade. `date` columns are type `date`. No new FK migration needed.
- Edge function status codes: 400 bad input, 401 auth, 502 model errors, and 500 for missing server config (the guide does not name a code for that). Streaming errors stay as SSE `error` events, since the 200 status is already sent.
- Both deployed functions have `verify_jwt = false` and check the token in code. Kept that in `supabase/config.toml` so deploys do not change behavior.

## Handoff

- (none yet)

## Follow-ups

- `ai-estimate` checks the JWT only when the `VERIFY_JWT` secret is `true`, and platform `verify_jwt` is off. The remote has no `VERIFY_JWT` secret (checked with `supabase secrets list`), so text estimates work without sign-in. Fix: `supabase secrets set VERIFY_JWT=true`. Not done, because the guide does not ask for it.
- The deployed `ai-suggestions` source was not in any repo (downloaded from the project). It is now in `supabase/functions/ai-suggestions/`.
