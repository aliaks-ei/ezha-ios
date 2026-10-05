-- Adds saved foods library table with RLS.

create table if not exists public.saved_foods (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    unit_type text not null check (unit_type in ('per_100g', 'per_serving')),
    serving_size numeric,
    serving_unit text,
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index if not exists saved_foods_user_name_idx on public.saved_foods (user_id, name);
alter table public.saved_foods enable row level security;
drop policy if exists "Saved foods all" on public.saved_foods;
create policy "Saved foods all" on public.saved_foods
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create or replace function public.set_saved_foods_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;
drop trigger if exists saved_foods_updated_at on public.saved_foods;
create trigger saved_foods_updated_at
    before update on public.saved_foods
    for each row execute function public.set_saved_foods_updated_at();
