create table if not exists public.food_entry_items (
    id uuid primary key default gen_random_uuid(),
    entry_id uuid not null references public.food_entries(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    grams numeric not null check (grams > 0),
    calories numeric not null default 0,
    protein numeric not null default 0,
    carbs numeric not null default 0,
    fat numeric not null default 0,
    ai_confidence numeric check (ai_confidence between 0 and 1),
    ai_notes text not null default '',
    created_at timestamptz not null default now()
);
create index if not exists food_entry_items_entry_idx on public.food_entry_items (entry_id);
create index if not exists food_entry_items_user_idx on public.food_entry_items (user_id);
alter table public.food_entry_items enable row level security;
drop policy if exists "Food entry items all" on public.food_entry_items;
create policy "Food entry items all" on public.food_entry_items
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
