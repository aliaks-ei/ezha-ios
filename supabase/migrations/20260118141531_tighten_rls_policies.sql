-- Restrict access to authenticated users and enforce ownership checks.

-- profiles
alter table public.profiles enable row level security;

drop policy if exists "Profiles insert" on public.profiles;
drop policy if exists "Profiles select" on public.profiles;
drop policy if exists "Profiles update" on public.profiles;

create policy "Profiles select own"
  on public.profiles
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Profiles insert own"
  on public.profiles
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Profiles update own"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- food_entries
alter table public.food_entries enable row level security;

drop policy if exists "Food entries all" on public.food_entries;

create policy "Food entries select own"
  on public.food_entries
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Food entries insert own"
  on public.food_entries
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Food entries update own"
  on public.food_entries
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Food entries delete own"
  on public.food_entries
  for delete
  to authenticated
  using (auth.uid() = user_id);

-- daily_summaries
alter table public.daily_summaries enable row level security;

drop policy if exists "Daily summaries all" on public.daily_summaries;

create policy "Daily summaries select own"
  on public.daily_summaries
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Daily summaries insert own"
  on public.daily_summaries
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Daily summaries update own"
  on public.daily_summaries
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Daily summaries delete own"
  on public.daily_summaries
  for delete
  to authenticated
  using (auth.uid() = user_id);
;
