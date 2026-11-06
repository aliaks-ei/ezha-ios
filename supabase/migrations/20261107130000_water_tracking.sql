-- Water tracking with a daily target (PET-116).
-- Additive: older app builds ignore the new columns, the new table, and the new RPCs.
-- All amounts are millilitres. Water never changes calories or macros.

-- A null water target means "no target": Today shows only the amount drunk.
alter table public.daily_targets
  add column if not exists water_target_ml numeric
  check (water_target_ml is null or water_target_ml > 0);

-- The day's snapshot of the water target, like calories_target and the other macro targets.
alter table public.daily_summaries
  add column if not exists water_target_ml numeric
  check (water_target_ml is null or water_target_ml > 0);

create table if not exists public.water_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  date date not null,
  amount_ml numeric not null check (amount_ml > 0 and amount_ml <= 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists water_entries_user_date_idx on public.water_entries (user_id, date);

alter table public.water_entries enable row level security;
drop policy if exists "Water entries all" on public.water_entries;
create policy "Water entries all" on public.water_entries
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop trigger if exists water_entries_updated_at on public.water_entries;
create trigger water_entries_updated_at
  before update on public.water_entries
  for each row execute function public.set_daily_targets_updated_at();

-- Creates or edits one water entry. Idempotent, so the offline outbox can retry it.
create or replace function public.save_water_entry(
  p_id uuid,
  p_date date,
  p_amount_ml numeric,
  p_created_at timestamptz default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_saved integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_id is null or p_date is null then
    raise exception 'Entry id and date are required' using errcode = '22023';
  end if;

  insert into public.water_entries (id, user_id, date, amount_ml, created_at)
  values (p_id, v_uid, p_date, p_amount_ml, coalesce(p_created_at, now()))
  on conflict (id) do update set
    date = excluded.date,
    amount_ml = excluded.amount_ml,
    created_at = excluded.created_at
  where public.water_entries.user_id = v_uid;

  get diagnostics v_saved = row_count;
  if v_saved = 0 then
    -- The id belongs to another user.
    raise exception 'Water entry not found' using errcode = 'P0002';
  end if;
end;
$$;

-- A new summary row takes the water target of its day target. A trigger, so this migration does
-- not redefine recompute_daily_summary (PET-115 fiber changes it too).
create or replace function public.daily_summaries_set_water_target()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.water_target_ml is null and new.daily_target_id is not null then
    select t.water_target_ml into new.water_target_ml
      from public.daily_targets t
     where t.id = new.daily_target_id;
  end if;
  return new;
end;
$$;

drop trigger if exists daily_summaries_set_water_target on public.daily_summaries;
create trigger daily_summaries_set_water_target
  before insert on public.daily_summaries
  for each row execute function public.daily_summaries_set_water_target();

create or replace function public.set_day_target(p_date date, p_target_id uuid, p_today date)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_target public.daily_targets;
  v_count integer;
  v_calories numeric;
  v_protein numeric;
  v_carbs numeric;
  v_fat numeric;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_target from public.daily_targets where id = p_target_id and user_id = v_uid;
  if v_target.id is null then
    raise exception 'Target not found' using errcode = 'P0002';
  end if;

  select count(*),
         round(coalesce(sum(e.calories), 0)),
         round(coalesce(sum(e.protein), 0)),
         round(coalesce(sum(e.carbs), 0)),
         round(coalesce(sum(e.fat), 0))
    into v_count, v_calories, v_protein, v_carbs, v_fat
    from public.food_entries e
   where e.user_id = v_uid and e.date = p_date;

  insert into public.daily_summaries (
    user_id, date, calories, protein, carbs, fat,
    calories_target, protein_target, carbs_target, fat_target, water_target_ml,
    has_data, daily_target_id, daily_target_name
  ) values (
    v_uid, p_date, v_calories, v_protein, v_carbs, v_fat,
    v_target.calories_target, v_target.protein_target, v_target.carbs_target, v_target.fat_target,
    v_target.water_target_ml,
    v_count > 0, v_target.id, v_target.name
  )
  on conflict (user_id, date) do update set
    calories = excluded.calories,
    protein = excluded.protein,
    carbs = excluded.carbs,
    fat = excluded.fat,
    calories_target = excluded.calories_target,
    protein_target = excluded.protein_target,
    carbs_target = excluded.carbs_target,
    fat_target = excluded.fat_target,
    water_target_ml = excluded.water_target_ml,
    has_data = excluded.has_data,
    daily_target_id = excluded.daily_target_id,
    daily_target_name = excluded.daily_target_name;

  if p_date = p_today then
    update public.profiles set active_target_id = v_target.id where user_id = v_uid;
  end if;
end;
$$;

-- New optional arguments: older builds call with 7 arguments and keep the water target as it is.
-- With p_update_water = true, p_water_ml sets the water target (null = no target).
drop function if exists public.save_daily_target(uuid, text, numeric, numeric, numeric, numeric, date);

create or replace function public.save_daily_target(
  p_id uuid,
  p_name text,
  p_calories numeric,
  p_protein numeric,
  p_carbs numeric,
  p_fat numeric,
  p_today date,
  p_water_ml numeric default null,
  p_update_water boolean default false
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_name = '' then
    raise exception 'Target name is required.' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.daily_targets (
      user_id, name, calories_target, protein_target, carbs_target, fat_target, water_target_ml
    )
    values (
      v_uid, v_name, coalesce(p_calories, 0), coalesce(p_protein, 0), coalesce(p_carbs, 0),
      coalesce(p_fat, 0), case when p_update_water then p_water_ml end
    )
    returning id into v_id;
  else
    update public.daily_targets
       set name = v_name,
           calories_target = coalesce(p_calories, 0),
           protein_target = coalesce(p_protein, 0),
           carbs_target = coalesce(p_carbs, 0),
           fat_target = coalesce(p_fat, 0),
           water_target_ml = case when p_update_water then p_water_ml else water_target_ml end
     where id = p_id and user_id = v_uid
    returning id into v_id;
    if v_id is null then
      raise exception 'Target not found' using errcode = 'P0002';
    end if;

    -- Today and later days follow the edit. Past days keep their numbers.
    update public.daily_summaries
       set calories_target = coalesce(p_calories, 0),
           protein_target = coalesce(p_protein, 0),
           carbs_target = coalesce(p_carbs, 0),
           fat_target = coalesce(p_fat, 0),
           water_target_ml = case when p_update_water then p_water_ml else water_target_ml end,
           daily_target_name = v_name
     where user_id = v_uid and daily_target_id = v_id and date >= p_today;
  end if;

  update public.profiles set active_target_id = v_id
   where user_id = v_uid and active_target_id is null;

  return v_id;
end;
$$;

create or replace function public.delete_daily_target(p_id uuid, p_today date)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_fallback public.daily_targets;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.daily_targets where id = p_id and user_id = v_uid) then
    raise exception 'Target not found' using errcode = 'P0002';
  end if;
  if (select count(*) from public.daily_targets where user_id = v_uid) <= 1 then
    raise exception 'At least one target is required.' using errcode = 'P0001';
  end if;

  delete from public.daily_targets where id = p_id and user_id = v_uid;

  select * into v_fallback from public.daily_targets
   where user_id = v_uid
   order by created_at, id
   limit 1;

  update public.profiles set active_target_id = v_fallback.id
   where user_id = v_uid and (active_target_id = p_id or active_target_id is null);

  -- Today and later days that used the deleted target move to the oldest remaining one.
  update public.daily_summaries
     set daily_target_id = v_fallback.id,
         daily_target_name = v_fallback.name,
         calories_target = v_fallback.calories_target,
         protein_target = v_fallback.protein_target,
         carbs_target = v_fallback.carbs_target,
         fat_target = v_fallback.fat_target,
         water_target_ml = v_fallback.water_target_ml
   where user_id = v_uid and daily_target_id = p_id and date >= p_today;
end;
$$;

-- get_day plus `water_target_ml` (null = no target) and `water` (the day's entries, newest
-- first). A wrapper, so get_day keeps whatever other migrations add to it (PET-115 fiber).
create or replace function public.get_day_with_water(p_date date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_summary public.daily_summaries;
  v_water_target numeric;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_summary from public.daily_summaries where user_id = v_uid and date = p_date;
  if v_summary.user_id is not null then
    v_water_target := v_summary.water_target_ml;
  else
    select t.water_target_ml into v_water_target from public.daily_targets t
     where t.id = public.resolve_day_target(v_uid, p_date) and t.user_id = v_uid;
  end if;

  return public.get_day(p_date) || jsonb_build_object(
    'water_target_ml', v_water_target,
    'water', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'id', w.id, 'user_id', w.user_id, 'date', w.date, 'amount_ml', w.amount_ml,
                 'created_at', w.created_at)
               order by w.created_at desc, w.id)
        from public.water_entries w
       where w.user_id = v_uid and w.date = p_date), '[]'::jsonb));
end;
$$;

revoke execute on function public.daily_summaries_set_water_target() from public, anon, authenticated;
revoke execute on function public.get_day_with_water(date) from public, anon;
grant execute on function public.get_day_with_water(date) to authenticated;
revoke execute on function public.save_water_entry(uuid, date, numeric, timestamptz) from public, anon;
revoke execute on function public.save_daily_target(uuid, text, numeric, numeric, numeric, numeric, date, numeric, boolean) from public, anon;
grant execute on function public.save_water_entry(uuid, date, numeric, timestamptz) to authenticated;
grant execute on function public.save_daily_target(uuid, text, numeric, numeric, numeric, numeric, date, numeric, boolean) to authenticated;
