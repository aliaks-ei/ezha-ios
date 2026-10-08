-- Library "Usual now": count logs of each saved food per local time of day.
-- The client sends the slot, because the server does not know the user's time zone.
-- Additive: callers without p_time_slot keep working and count nothing.

alter table public.saved_foods
  add column if not exists uses_morning integer not null default 0,
  add column if not exists uses_midday integer not null default 0,
  add column if not exists uses_evening integer not null default 0;

drop function if exists public.log_food_entry(jsonb, jsonb, uuid[]);

create function public.log_food_entry(
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
     set last_used_at = now(),
         uses_morning = uses_morning + case when p_time_slot = 'morning' then 1 else 0 end,
         uses_midday = uses_midday + case when p_time_slot = 'midday' then 1 else 0 end,
         uses_evening = uses_evening + case when p_time_slot = 'evening' then 1 else 0 end
   where user_id = v_uid and id = any(coalesce(p_used_food_ids, '{}'));
end;
$$;

revoke execute on function public.log_food_entry(jsonb, jsonb, uuid[], text) from public, anon;
