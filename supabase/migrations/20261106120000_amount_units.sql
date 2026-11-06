-- Millilitres for drinks (PET-114).
-- Additive: the `grams` column keeps the item amount, and `unit` says what it measures.
-- For a 'ml' item, `grams` holds millilitres and macros are already scaled to that volume.
-- Older app builds and the PWA ignore `unit` and read the amount as grams.
-- Callers that send no unit store 'g'.

alter table public.food_entry_items
  add column if not exists unit text not null default 'g' check (unit in ('g', 'ml'));

alter table public.saved_meal_ingredients
  add column if not exists unit text not null default 'g' check (unit in ('g', 'ml'));

-- A saved food with amount_unit 'ml' stores its *_per_100g values per 100 ml,
-- and serving_size in millilitres. unit_type stays 'per_100g' or 'per_serving',
-- so older builds still decode the row.
alter table public.saved_foods
  add column if not exists amount_unit text not null default 'g' check (amount_unit in ('g', 'ml'));

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
    -- A retry of a call that already succeeded. Counts are not added twice.
    return;
  end if;

  -- Ordinality keeps the client's item order in created_at.
  insert into public.food_entry_items (
    id, entry_id, user_id, name, grams, unit, calories, protein, carbs, fat,
    ai_confidence, ai_notes, created_at
  )
  select coalesce(i.id, gen_random_uuid()), v_entry.id, v_uid, i.name, i.grams,
         coalesce(x.item->>'unit', 'g'),
         coalesce(i.calories, 0), coalesce(i.protein, 0), coalesce(i.carbs, 0), coalesce(i.fat, 0),
         i.ai_confidence, coalesce(i.ai_notes, ''),
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
    id, meal_id, user_id, name, grams, unit, calories, protein, carbs, fat, linked_food_id,
    created_at
  )
  select gen_random_uuid(), v_id, v_uid, i.name, i.grams, coalesce(x.item->>'unit', 'g'),
         coalesce(i.calories, 0), coalesce(i.protein, 0), coalesce(i.carbs, 0), coalesce(i.fat, 0),
         i.linked_food_id, now() + (x.ord * interval '1 microsecond')
    from jsonb_array_elements(coalesce(p_ingredients, '[]'::jsonb)) with ordinality as x(item, ord)
   cross join lateral jsonb_populate_record(null::public.saved_meal_ingredients, x.item) as i;

  return v_id;
end;
$$;
