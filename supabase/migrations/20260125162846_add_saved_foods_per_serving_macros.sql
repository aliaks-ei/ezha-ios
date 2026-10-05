alter table public.saved_foods add column if not exists calories_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists protein_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists carbs_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists fat_per_100g numeric not null default 0;
alter table public.saved_foods add column if not exists calories_per_serving numeric not null default 0;
alter table public.saved_foods add column if not exists protein_per_serving numeric not null default 0;
alter table public.saved_foods add column if not exists carbs_per_serving numeric not null default 0;
alter table public.saved_foods add column if not exists fat_per_serving numeric not null default 0;
