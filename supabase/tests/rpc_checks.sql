-- SQL checks for the iOS RPCs (IMPLEMENTATION_GUIDE.md 4.3 and 10.1).
-- Run against local Supabase after `supabase db reset`:
--   docker exec -i supabase_db_ezha-ios psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/rpc_checks.sql
-- Everything runs in one transaction and rolls back.

begin;

create function pg_temp.as_user(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.check(p_ok boolean, p_name text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then
    raise exception 'FAILED: %', p_name;
  end if;
  raise notice 'ok: %', p_name;
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (instance_id, id, aud, role, email)
values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'a@test.local'),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'b@test.local');

-- New-user bootstrap.
select pg_temp.check(
  (select count(*) from public.daily_targets where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and name = 'Basic' and calories_target = 0) = 1
  and (select active_target_id is not null from public.profiles where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'new user gets a profile and one Basic target with zeros');

set local role authenticated;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');

-- Onboarding sets real numbers on the Basic target.
select public.save_daily_target(
  (select id from public.daily_targets where name = 'Basic'), 'Basic', 2000, 150, 200, 60, '2026-10-05');

-- log_food_entry twice with the same id.
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000001", "date": "2026-10-03", "input_type": "text", "input_text": "rice, chicken",
    "calories": 600.4, "protein": 40.2, "carbs": 70.4, "fat": 10.4, "ai_source": "text", "ai_notes": "x"}',
  '[{"name": "rice", "grams": 200, "calories": 260, "protein": 5, "carbs": 56, "fat": 1},
    {"name": "chicken", "grams": 150, "calories": 340.4, "protein": 35.2, "carbs": 14.4, "fat": 9.4}]');
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000001", "date": "2026-10-03", "input_type": "text",
    "calories": 600.4, "protein": 40.2, "carbs": 70.4, "fat": 10.4, "ai_source": "text"}',
  '[{"name": "rice", "grams": 200, "calories": 260, "protein": 5, "carbs": 56, "fat": 1},
    {"name": "chicken", "grams": 150, "calories": 340.4, "protein": 35.2, "carbs": 14.4, "fat": 9.4}]');
select pg_temp.check(
  (select count(*) from public.food_entries where id = 'e0000000-0000-0000-0000-000000000001') = 1
  and (select count(*) from public.food_entry_items where entry_id = 'e0000000-0000-0000-0000-000000000001') = 2,
  'log_food_entry twice with the same id keeps one entry and its 2 items');
select pg_temp.check(
  (select array_agg(name order by created_at) from public.food_entry_items
    where entry_id = 'e0000000-0000-0000-0000-000000000001') = array['rice', 'chicken'],
  'items keep the client order');

-- Log, delete, log on two dates. Summaries match the entries.
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000002", "date": "2026-10-03", "input_type": "text", "calories": 100, "protein": 1, "carbs": 2, "fat": 3, "ai_source": "text"}',
  '[{"name": "apple", "grams": 180, "calories": 100, "protein": 1, "carbs": 2, "fat": 3}]');
delete from public.food_entries where id = 'e0000000-0000-0000-0000-000000000002';
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000003", "date": "2026-10-04", "input_type": "text", "calories": 250.6, "protein": 10.5, "carbs": 30, "fat": 8, "ai_source": "library"}',
  '[{"name": "oats", "grams": 60, "calories": 250.6, "protein": 10.5, "carbs": 30, "fat": 8}]');
select pg_temp.check(
  (select count(*) from public.daily_summaries s
     where s.date in ('2026-10-03', '2026-10-04')
       and s.calories = (select round(coalesce(sum(calories), 0)) from public.food_entries e where e.date = s.date)
       and s.protein = (select round(coalesce(sum(protein), 0)) from public.food_entries e where e.date = s.date)
       and s.carbs = (select round(coalesce(sum(carbs), 0)) from public.food_entries e where e.date = s.date)
       and s.fat = (select round(coalesce(sum(fat), 0)) from public.food_entries e where e.date = s.date)
       and s.has_data) = 2,
  'daily_summaries totals match the sum of entries on two dates');
select pg_temp.check(
  (select calories from public.daily_summaries where date = '2026-10-03') = 600,
  'deleting an entry lowers the summary');

-- A day target set before logging is kept (PWA: preserves the selected day target).
select public.save_daily_target(null, 'Cut', 1800, 160, 150, 55, '2026-10-05');
select public.set_day_target('2026-10-01', (select id from public.daily_targets where name = 'Cut'), '2026-10-05');
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000004", "date": "2026-10-01", "input_type": "text", "calories": 300, "protein": 20, "carbs": 30, "fat": 10, "ai_source": "text"}',
  '[]');
select pg_temp.check(
  (select daily_target_name = 'Cut' and calories_target = 1800 and calories = 300
     from public.daily_summaries where date = '2026-10-01'),
  'logging keeps the day target snapshot');
select pg_temp.check(
  (select daily_target_name = 'Basic' from public.daily_summaries where date = '2026-10-03'),
  'set_day_target changes only its own day');
select pg_temp.check(
  (select active_target_id = (select id from public.daily_targets where name = 'Basic') from public.profiles),
  'set_day_target on a past day does not change the active target');

-- get_day for a date with no data takes goals from the latest earlier target.
select public.set_day_target('2026-10-04', (select id from public.daily_targets where name = 'Cut'), '2026-10-05');
select pg_temp.check(
  (select (d -> 'goals') = '{"calories": 1800, "protein": 160, "carbs": 150, "fat": 55}'::jsonb
      and jsonb_array_length(d -> 'entries') = 0
      and d -> 'target' ->> 'name' = 'Cut'
      and jsonb_array_length(d -> 'targets') = 2
      and (d -> 'totals') = '{"calories": 0, "protein": 0, "carbs": 0, "fat": 0}'::jsonb
     from public.get_day('2026-10-05') d),
  'get_day with no data uses the latest earlier target');
select pg_temp.check(
  (select (d -> 'totals' ->> 'calories')::int = 600
      and jsonb_array_length(d -> 'entries') = 1
      and jsonb_array_length(d -> 'entries' -> 0 -> 'items') = 2
      and d -> 'goals' ->> 'calories' = '2000'
     from public.get_day('2026-10-03') d),
  'get_day returns entries with items and the summary goals');

-- Setting today's target changes the active target.
select public.set_day_target('2026-10-05', (select id from public.daily_targets where name = 'Cut'), '2026-10-05');
select pg_temp.check(
  (select active_target_id = (select id from public.daily_targets where name = 'Cut') from public.profiles),
  'set_day_target on today sets the active target');

-- Editing a target refreshes today and later, not past days.
select public.save_daily_target((select id from public.daily_targets where name = 'Cut'), 'Cut', 1700, 160, 150, 55, '2026-10-05');
select pg_temp.check(
  (select calories_target from public.daily_summaries where date = '2026-10-05') = 1700
  and (select calories_target from public.daily_summaries where date = '2026-10-04') = 1800,
  'save_daily_target refreshes today but keeps past days');

-- Deleting the active target moves active to the oldest remaining target.
select public.delete_daily_target((select id from public.daily_targets where name = 'Cut'), '2026-10-05');
select pg_temp.check(
  (select active_target_id = (select id from public.daily_targets where name = 'Basic') from public.profiles)
  and (select daily_target_name = 'Basic' and calories_target = 2000 from public.daily_summaries where date = '2026-10-05')
  and (select daily_target_name = 'Cut' from public.daily_summaries where date = '2026-10-04'),
  'delete_daily_target resets the active target and today, past days keep their snapshot');

-- The last target cannot be deleted.
do $$
begin
  perform public.delete_daily_target((select id from public.daily_targets where name = 'Basic'), '2026-10-05');
  raise exception 'FAILED: deleting the last target did not raise';
exception when others then
  if sqlerrm not like 'At least one target is required.%' then
    raise;
  end if;
  raise notice 'ok: delete_daily_target on the last target raises';
end;
$$;

-- save_meal creates, renames, and replaces ingredients. log_food_entry marks foods as used.
insert into public.saved_foods (id, user_id, name, unit_type, calories_per_100g)
values ('f0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Rice', 'per_100g', 130);
select public.save_meal(null, 'Bowl', '[{"name": "Rice", "grams": 200, "calories": 260, "protein": 5, "carbs": 56, "fat": 1, "linked_food_id": "f0000000-0000-0000-0000-000000000001"}, {"name": "Egg", "grams": 50, "calories": 70, "protein": 6, "carbs": 0, "fat": 5}]');
select public.save_meal((select id from public.saved_foods where name = 'Bowl'), 'Big bowl', '[{"name": "Rice", "grams": 300, "calories": 390, "protein": 7, "carbs": 84, "fat": 1}]');
select pg_temp.check(
  (select count(*) from public.saved_meal_ingredients i join public.saved_foods m on m.id = i.meal_id
    where m.name = 'Big bowl' and m.is_meal and i.grams = 300) = 1
  and (select count(*) from public.saved_meal_ingredients) = 1,
  'save_meal renames and replaces all ingredients');
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000005", "date": "2026-10-05", "input_type": "text", "calories": 130, "ai_source": "library"}',
  '[{"name": "Rice", "grams": 100, "calories": 130}]', array['f0000000-0000-0000-0000-000000000001']::uuid[]);
select pg_temp.check(
  (select last_used_at is not null from public.saved_foods where name = 'Rice'),
  'log_food_entry sets last_used_at for used foods');
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000006", "date": "2026-10-05", "input_type": "text", "calories": 130, "ai_source": "library"}',
  '[{"name": "Rice", "grams": 100, "calories": 130}]', array['f0000000-0000-0000-0000-000000000001']::uuid[], 'evening');
select public.log_food_entry(
  '{"id": "e0000000-0000-0000-0000-000000000006", "date": "2026-10-05", "input_type": "text", "calories": 130, "ai_source": "library"}',
  '[{"name": "Rice", "grams": 100, "calories": 130}]', array['f0000000-0000-0000-0000-000000000001']::uuid[], 'evening');
select pg_temp.check(
  (select (uses_morning, uses_midday, uses_evening) = (0, 0, 1) from public.saved_foods where name = 'Rice'),
  'log_food_entry counts the time slot once per entry, and not without a slot');

-- As user B, A's rows are invisible.
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000002');
select pg_temp.check(
  (select count(*) from public.food_entries) = 0
  and (select count(*) from public.food_entry_items) = 0
  and (select count(*) from public.daily_summaries) = 0
  and (select count(*) from public.saved_foods) = 0
  and (select count(*) from public.saved_meal_ingredients) = 0
  and (select count(*) from public.daily_targets) = 1
  and (select count(*) from public.profiles) = 1
  and (select jsonb_array_length(d -> 'entries') = 0 from public.get_day('2026-10-03') d),
  'user B reads zero rows of user A');
do $$
begin
  perform public.set_day_target('2026-10-05',
    (select id from public.daily_targets where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'), '2026-10-05');
  raise exception 'FAILED: user B used a target of user A';
exception when others then
  if sqlerrm not like 'Target not found%' then
    raise;
  end if;
  raise notice 'ok: user B cannot apply user A''s target';
end;
$$;

-- Anonymous callers cannot use the RPCs.
reset role;
set local role anon;
do $$
begin
  perform public.get_day('2026-10-05');
  raise exception 'FAILED: anon called get_day';
exception when insufficient_privilege then
  raise notice 'ok: anon cannot call get_day';
end;
$$;

-- Deleting a user with entries cascades without the summary trigger failing.
reset role;
delete from auth.users where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.check(
  (select count(*) from public.food_entries where user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0
  and (select count(*) from public.daily_summaries where user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0
  and (select count(*) from public.profiles where user_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0,
  'deleting a user removes all of their rows');

rollback;
