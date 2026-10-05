-- RPCs, triggers, and columns for the iOS app (IMPLEMENTATION_GUIDE.md 4.3, items 3–8 and 10).
-- Additive only: the PWA keeps working.

-- 10. Synced favorites and recents.
alter table public.saved_foods add column if not exists is_favorite boolean not null default false;
alter table public.saved_foods add column if not exists last_used_at timestamptz;

-- 4. Server-side daily summary.

-- First non-null of: this day's summary target, the latest earlier summary target,
-- the profile's active target, the user's oldest target. Deleted targets are skipped.
create or replace function public.resolve_day_target(p_user uuid, p_date date)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select s.daily_target_id
       from public.daily_summaries s
       join public.daily_targets t on t.id = s.daily_target_id
      where s.user_id = p_user and s.date = p_date),
    (select s.daily_target_id
       from public.daily_summaries s
       join public.daily_targets t on t.id = s.daily_target_id
      where s.user_id = p_user and s.date < p_date
      order by s.date desc
      limit 1),
    (select p.active_target_id
       from public.profiles p
       join public.daily_targets t on t.id = p.active_target_id
      where p.user_id = p_user),
    (select t.id
       from public.daily_targets t
      where t.user_id = p_user
      order by t.created_at, t.id
      limit 1)
  );
$$;

-- Totals are the sum of the day's entries, rounded per macro. A new summary row
-- gets the resolved target snapshot. An existing row keeps its snapshot.
-- Security definer: it runs from the food_entries trigger, also during account
-- deletion cascades, when the auth.users row is already gone.
create or replace function public.recompute_daily_summary(p_user uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_calories numeric;
  v_protein numeric;
  v_carbs numeric;
  v_fat numeric;
  v_target public.daily_targets;
  v_profile public.profiles;
begin
  if not exists (select 1 from auth.users where id = p_user) then
    return;
  end if;

  select count(*),
         round(coalesce(sum(e.calories), 0)),
         round(coalesce(sum(e.protein), 0)),
         round(coalesce(sum(e.carbs), 0)),
         round(coalesce(sum(e.fat), 0))
    into v_count, v_calories, v_protein, v_carbs, v_fat
    from public.food_entries e
   where e.user_id = p_user and e.date = p_date;

  select * into v_target from public.daily_targets
   where id = public.resolve_day_target(p_user, p_date);
  select * into v_profile from public.profiles where user_id = p_user;

  insert into public.daily_summaries (
    user_id, date, calories, protein, carbs, fat,
    calories_target, protein_target, carbs_target, fat_target,
    has_data, daily_target_id, daily_target_name
  ) values (
    p_user, p_date, v_calories, v_protein, v_carbs, v_fat,
    coalesce(v_target.calories_target, v_profile.calories_target, 0),
    coalesce(v_target.protein_target, v_profile.protein_target, 0),
    coalesce(v_target.carbs_target, v_profile.carbs_target, 0),
    coalesce(v_target.fat_target, v_profile.fat_target, 0),
    v_count > 0, v_target.id, v_target.name
  )
  on conflict (user_id, date) do update set
    calories = excluded.calories,
    protein = excluded.protein,
    carbs = excluded.carbs,
    fat = excluded.fat,
    has_data = excluded.has_data;
end;
$$;

create or replace function public.food_entries_recompute_summary()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.recompute_daily_summary(old.user_id, old.date);
  end if;
  if tg_op = 'INSERT'
     or (tg_op = 'UPDATE' and (new.user_id, new.date) is distinct from (old.user_id, old.date)) then
    perform public.recompute_daily_summary(new.user_id, new.date);
  end if;
  return null;
end;
$$;

drop trigger if exists food_entries_recompute_summary on public.food_entries;
create trigger food_entries_recompute_summary
  after insert or update or delete on public.food_entries
  for each row execute function public.food_entries_recompute_summary();

-- 3. Atomic, idempotent logging.
create or replace function public.log_food_entry(
  p_entry jsonb,
  p_items jsonb,
  p_used_food_ids uuid[] default '{}'
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_entry public.food_entries;
  v_inserted integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  v_entry := jsonb_populate_record(null::public.food_entries, p_entry);
  if v_entry.id is null or v_entry.date is null then
    raise exception 'Entry id and date are required' using errcode = '22023';
  end if;

  insert into public.food_entries (
    id, user_id, date, input_type, input_text, image_path,
    calories, protein, carbs, fat, ai_confidence, ai_source, ai_notes, created_at
  ) values (
    v_entry.id, v_uid, v_entry.date, coalesce(v_entry.input_type, 'text'), v_entry.input_text,
    v_entry.image_path,
    coalesce(v_entry.calories, 0), coalesce(v_entry.protein, 0),
    coalesce(v_entry.carbs, 0), coalesce(v_entry.fat, 0),
    v_entry.ai_confidence, coalesce(v_entry.ai_source, 'unknown'),
    coalesce(v_entry.ai_notes, ''), coalesce(v_entry.created_at, now())
  )
  on conflict (id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    -- A retry of a call that already succeeded.
    return;
  end if;

  -- Ordinality keeps the client's item order in created_at.
  insert into public.food_entry_items (
    id, entry_id, user_id, name, grams, calories, protein, carbs, fat,
    ai_confidence, ai_notes, created_at
  )
  select coalesce(i.id, gen_random_uuid()), v_entry.id, v_uid, i.name, i.grams,
         coalesce(i.calories, 0), coalesce(i.protein, 0), coalesce(i.carbs, 0), coalesce(i.fat, 0),
         i.ai_confidence, coalesce(i.ai_notes, ''),
         now() + (x.ord * interval '1 microsecond')
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) with ordinality as x(item, ord)
   cross join lateral jsonb_populate_record(null::public.food_entry_items, x.item) as i;

  update public.saved_foods
     set last_used_at = now()
   where user_id = v_uid and id = any(coalesce(p_used_food_ids, '{}'));
end;
$$;

-- 5. One read per day screen.
create or replace function public.get_day(p_date date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_summary public.daily_summaries;
  v_target public.daily_targets;
  v_goals jsonb;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_summary from public.daily_summaries where user_id = v_uid and date = p_date;
  select * into v_target from public.daily_targets
   where id = public.resolve_day_target(v_uid, p_date) and user_id = v_uid;

  if v_summary.user_id is not null then
    v_goals := jsonb_build_object(
      'calories', round(v_summary.calories_target), 'protein', round(v_summary.protein_target),
      'carbs', round(v_summary.carbs_target), 'fat', round(v_summary.fat_target));
  elsif v_target.id is not null then
    v_goals := jsonb_build_object(
      'calories', round(v_target.calories_target), 'protein', round(v_target.protein_target),
      'carbs', round(v_target.carbs_target), 'fat', round(v_target.fat_target));
  else
    v_goals := '{"calories": 2100, "protein": 140, "carbs": 220, "fat": 70}'::jsonb;
  end if;

  return jsonb_build_object(
    'date', p_date,
    'target', case when v_target.id is null then null else to_jsonb(v_target) end,
    'goals', v_goals,
    'totals', (
      select jsonb_build_object(
        'calories', round(coalesce(sum(e.calories), 0)), 'protein', round(coalesce(sum(e.protein), 0)),
        'carbs', round(coalesce(sum(e.carbs), 0)), 'fat', round(coalesce(sum(e.fat), 0)))
        from public.food_entries e
       where e.user_id = v_uid and e.date = p_date),
    'targets', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.created_at, t.id)
        from public.daily_targets t
       where t.user_id = v_uid), '[]'::jsonb),
    'entries', coalesce((
      select jsonb_agg(
               to_jsonb(e) || jsonb_build_object('items', coalesce((
                 select jsonb_agg(to_jsonb(i) order by i.created_at, i.id)
                   from public.food_entry_items i
                  where i.entry_id = e.id), '[]'::jsonb))
               order by e.created_at desc, e.id)
        from public.food_entries e
       where e.user_id = v_uid and e.date = p_date), '[]'::jsonb)
  );
end;
$$;

-- 6. New-user bootstrap: a profile and one "Basic" target.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target uuid;
begin
  insert into public.profiles (user_id) values (new.id) on conflict (user_id) do nothing;
  if not exists (select 1 from public.daily_targets where user_id = new.id) then
    insert into public.daily_targets (user_id, name) values (new.id, 'Basic') returning id into v_target;
    update public.profiles set active_target_id = v_target
     where user_id = new.id and active_target_id is null;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_ezha on auth.users;
create trigger on_auth_user_created_ezha
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill existing users. Targets copy the legacy profile macros, like the PWA's ensureTargets.
insert into public.profiles (user_id)
select u.id from auth.users u
 where not exists (select 1 from public.profiles p where p.user_id = u.id);

insert into public.daily_targets (user_id, name, calories_target, protein_target, carbs_target, fat_target)
select p.user_id, 'Basic', p.calories_target, p.protein_target, p.carbs_target, p.fat_target
  from public.profiles p
 where not exists (select 1 from public.daily_targets t where t.user_id = p.user_id);

update public.profiles p
   set active_target_id = (
     select t.id from public.daily_targets t
      where t.user_id = p.user_id
      order by t.created_at, t.id
      limit 1)
 where p.active_target_id is null;

-- 7. Target RPCs. Dates come from the client; the server never computes "today".
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
    calories_target, protein_target, carbs_target, fat_target,
    has_data, daily_target_id, daily_target_name
  ) values (
    v_uid, p_date, v_calories, v_protein, v_carbs, v_fat,
    v_target.calories_target, v_target.protein_target, v_target.carbs_target, v_target.fat_target,
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
    has_data = excluded.has_data,
    daily_target_id = excluded.daily_target_id,
    daily_target_name = excluded.daily_target_name;

  if p_date = p_today then
    update public.profiles set active_target_id = v_target.id where user_id = v_uid;
  end if;
end;
$$;

create or replace function public.save_daily_target(
  p_id uuid,
  p_name text,
  p_calories numeric,
  p_protein numeric,
  p_carbs numeric,
  p_fat numeric,
  p_today date
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
    insert into public.daily_targets (user_id, name, calories_target, protein_target, carbs_target, fat_target)
    values (v_uid, v_name, coalesce(p_calories, 0), coalesce(p_protein, 0), coalesce(p_carbs, 0), coalesce(p_fat, 0))
    returning id into v_id;
  else
    update public.daily_targets
       set name = v_name,
           calories_target = coalesce(p_calories, 0),
           protein_target = coalesce(p_protein, 0),
           carbs_target = coalesce(p_carbs, 0),
           fat_target = coalesce(p_fat, 0)
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
         fat_target = v_fallback.fat_target
   where user_id = v_uid and daily_target_id = p_id and date >= p_today;
end;
$$;

-- 8. Atomic meals: create or rename, and replace all ingredients.
create or replace function public.save_meal(p_id uuid, p_name text, p_ingredients jsonb)
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
    raise exception 'Meal name is required.' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.saved_foods (user_id, name, unit_type, is_meal)
    values (v_uid, v_name, 'per_100g', true)
    returning id into v_id;
  else
    update public.saved_foods set name = v_name
     where id = p_id and user_id = v_uid and is_meal
    returning id into v_id;
    if v_id is null then
      raise exception 'Meal not found' using errcode = 'P0002';
    end if;
    delete from public.saved_meal_ingredients where meal_id = v_id and user_id = v_uid;
  end if;

  insert into public.saved_meal_ingredients (
    id, meal_id, user_id, name, grams, calories, protein, carbs, fat, linked_food_id, created_at
  )
  select gen_random_uuid(), v_id, v_uid, i.name, i.grams,
         coalesce(i.calories, 0), coalesce(i.protein, 0), coalesce(i.carbs, 0), coalesce(i.fat, 0),
         i.linked_food_id, now() + (x.ord * interval '1 microsecond')
    from jsonb_array_elements(coalesce(p_ingredients, '[]'::jsonb)) with ordinality as x(item, ord)
   cross join lateral jsonb_populate_record(null::public.saved_meal_ingredients, x.item) as i;

  return v_id;
end;
$$;

-- Internal functions are not callable through the API.
revoke execute on function public.recompute_daily_summary(uuid, date) from public, anon, authenticated;
revoke execute on function public.food_entries_recompute_summary() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.resolve_day_target(uuid, date) from public, anon;
revoke execute on function public.log_food_entry(jsonb, jsonb, uuid[]) from public, anon;
revoke execute on function public.get_day(date) from public, anon;
revoke execute on function public.set_day_target(date, uuid, date) from public, anon;
revoke execute on function public.save_daily_target(uuid, text, numeric, numeric, numeric, numeric, date) from public, anon;
revoke execute on function public.delete_daily_target(uuid, date) from public, anon;
revoke execute on function public.save_meal(uuid, text, jsonb) from public, anon;
