-- Dietary fiber, display only (PET-115). There is no fiber target.
-- Additive and nullable: null means unknown, never 0. Callers that send no fiber store null,
-- so older app builds keep working.
-- food_entries.fiber is the sum of the entry's known item values; the app reads the items
-- to tell a partial sum from a complete one.

alter table public.food_entries
  add column if not exists fiber numeric check (fiber >= 0);

alter table public.food_entry_items
  add column if not exists fiber numeric check (fiber >= 0);

alter table public.saved_meal_ingredients
  add column if not exists fiber numeric check (fiber >= 0);

-- Per 100 g (or per 100 ml when amount_unit is 'ml'), like the other *_per_100g columns.
alter table public.saved_foods
  add column if not exists fiber_per_100g numeric check (fiber_per_100g >= 0);
alter table public.saved_foods
  add column if not exists fiber_per_serving numeric check (fiber_per_serving >= 0);

-- Sum of the day's known entry values. Null when no entry has fiber.
alter table public.daily_summaries add column if not exists fiber numeric;

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
  v_fiber numeric;
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
         round(coalesce(sum(e.fat), 0)),
         -- Null when no entry has fiber: unknown, not 0.
         round(sum(e.fiber))
    into v_count, v_calories, v_protein, v_carbs, v_fat, v_fiber
    from public.food_entries e
   where e.user_id = p_user and e.date = p_date;

  select * into v_target from public.daily_targets
   where id = public.resolve_day_target(p_user, p_date);
  select * into v_profile from public.profiles where user_id = p_user;

  insert into public.daily_summaries (
    user_id, date, calories, protein, carbs, fat, fiber,
    calories_target, protein_target, carbs_target, fat_target,
    has_data, daily_target_id, daily_target_name
  ) values (
    p_user, p_date, v_calories, v_protein, v_carbs, v_fat, v_fiber,
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
    fiber = excluded.fiber,
    has_data = excluded.has_data;
end;
$$;

create or replace function public.log_food_entry(
  p_entry jsonb,
  p_items jsonb,
  p_used_food_ids uuid[] default '{}',
  p_time_slot text default null
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
    calories, protein, carbs, fat, fiber, ai_confidence, ai_source, ai_notes, created_at
  ) values (
    v_entry.id, v_uid, v_entry.date, coalesce(v_entry.input_type, 'text'), v_entry.input_text,
    v_entry.image_path,
    coalesce(v_entry.calories, 0), coalesce(v_entry.protein, 0),
    coalesce(v_entry.carbs, 0), coalesce(v_entry.fat, 0), v_entry.fiber,
    v_entry.ai_confidence, coalesce(v_entry.ai_source, 'unknown'),
    coalesce(v_entry.ai_notes, ''), coalesce(v_entry.created_at, now())
  )
  on conflict (id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    -- A retry of a call that already succeeded. Counts are not added twice.
    return;
  end if;

  -- Ordinality keeps the client's item order in created_at.
  insert into public.food_entry_items (
    id, entry_id, user_id, name, grams, unit, calories, protein, carbs, fat, fiber,
    ai_confidence, ai_notes, created_at
  )
  select coalesce(i.id, gen_random_uuid()), v_entry.id, v_uid, i.name, i.grams,
         coalesce(x.item->>'unit', 'g'),
         coalesce(i.calories, 0), coalesce(i.protein, 0), coalesce(i.carbs, 0), coalesce(i.fat, 0),
         i.fiber, i.ai_confidence, coalesce(i.ai_notes, ''),
         now() + (x.ord * interval '1 microsecond')
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) with ordinality as x(item, ord)
   cross join lateral jsonb_populate_record(null::public.food_entry_items, x.item) as i;

  update public.saved_foods
     set last_used_at = now(),
         uses_morning = uses_morning + case when p_time_slot = 'morning' then 1 else 0 end,
         uses_midday = uses_midday + case when p_time_slot = 'midday' then 1 else 0 end,
         uses_evening = uses_evening + case when p_time_slot = 'evening' then 1 else 0 end
   where user_id = v_uid and id = any(coalesce(p_used_food_ids, '{}'));
end;
$$;

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
    id, meal_id, user_id, name, grams, unit, calories, protein, carbs, fat, fiber, linked_food_id,
    created_at
  )
  select gen_random_uuid(), v_id, v_uid, i.name, i.grams, coalesce(x.item->>'unit', 'g'),
         coalesce(i.calories, 0), coalesce(i.protein, 0), coalesce(i.carbs, 0), coalesce(i.fat, 0),
         i.fiber, i.linked_food_id, now() + (x.ord * interval '1 microsecond')
    from jsonb_array_elements(coalesce(p_ingredients, '[]'::jsonb)) with ordinality as x(item, ord)
   cross join lateral jsonb_populate_record(null::public.saved_meal_ingredients, x.item) as i;

  return v_id;
end;
$$;

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
        'carbs', round(coalesce(sum(e.carbs), 0)), 'fat', round(coalesce(sum(e.fat), 0)),
        'fiber', round(sum(e.fiber)))
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
