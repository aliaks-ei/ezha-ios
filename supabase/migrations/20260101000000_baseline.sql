-- Baseline for objects created in the dashboard before migrations were tracked.
-- Taken from `supabase db dump --linked` on 2026-10-05. Marked as applied on the
-- remote project, so it only runs on local and fresh databases.

create or replace function public.set_profiles_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create table if not exists public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    calories_target numeric not null default 0,
    protein_target numeric not null default 0,
    carbs_target numeric not null default 0,
    fat_target numeric not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    active_date date not null default current_date
);
create index if not exists profiles_updated_at_idx on public.profiles (updated_at);
drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
    before update on public.profiles
    for each row execute function public.set_profiles_updated_at();

create table if not exists public.food_entries (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    date date not null,
    input_type text not null check (input_type in ('photo', 'text', 'photo+text')),
    input_text text,
    image_path text,
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    ai_confidence numeric check (ai_confidence between 0 and 1),
    ai_source text not null default 'unknown'
        constraint food_entries_ai_source_check
        check (ai_source in ('food_photo', 'label_photo', 'text', 'unknown')),
    ai_notes text not null default '',
    created_at timestamptz not null default now()
);
create index if not exists food_entries_user_date_idx on public.food_entries (user_id, date);

create table if not exists public.daily_summaries (
    user_id uuid not null references auth.users(id) on delete cascade,
    date date not null,
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    calories_target numeric not null default 0,
    protein_target numeric not null default 0,
    carbs_target numeric not null default 0,
    fat_target numeric not null default 0,
    has_data boolean not null default true,
    created_at timestamptz not null default now(),
    primary key (user_id, date)
);
create index if not exists daily_summaries_user_date_idx on public.daily_summaries (user_id, date);

insert into storage.buckets (id, name, public)
values ('food-images', 'food-images', false)
on conflict (id) do nothing;
