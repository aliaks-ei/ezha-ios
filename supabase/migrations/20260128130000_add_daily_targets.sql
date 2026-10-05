create table if not exists public.daily_targets (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    calories_target numeric not null default 0,
    protein_target numeric not null default 0,
    carbs_target numeric not null default 0,
    fat_target numeric not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
alter table public.profiles
    add column if not exists active_target_id uuid;
alter table public.daily_summaries
    add column if not exists daily_target_id uuid;
alter table public.daily_summaries
    add column if not exists daily_target_name text;
create index if not exists daily_targets_user_name_idx
    on public.daily_targets (user_id, name);
alter table public.daily_targets enable row level security;
drop policy if exists "Daily targets all" on public.daily_targets;
create policy "Daily targets all" on public.daily_targets
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create or replace function public.set_daily_targets_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;
drop trigger if exists daily_targets_updated_at on public.daily_targets;
create trigger daily_targets_updated_at
    before update on public.daily_targets
    for each row execute function public.set_daily_targets_updated_at();
insert into public.daily_targets (
    user_id,
    name,
    calories_target,
    protein_target,
    carbs_target,
    fat_target
)
select
    user_id,
    'Basic',
    calories_target,
    protein_target,
    carbs_target,
    fat_target
from public.profiles
where user_id not in (select user_id from public.daily_targets);
update public.profiles p
set active_target_id = t.id
from public.daily_targets t
where t.user_id = p.user_id
  and t.name = 'Basic'
  and p.active_target_id is null;
update public.daily_summaries ds
set daily_target_name = 'Basic',
    daily_target_id = t.id
from public.daily_targets t
where t.user_id = ds.user_id
  and t.name = 'Basic'
  and ds.daily_target_id is null;
