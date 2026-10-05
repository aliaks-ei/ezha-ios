alter table public.food_entries drop constraint if exists food_entries_ai_source_check;
alter table public.food_entries
    add constraint food_entries_ai_source_check
    check (ai_source in ('food_photo', 'label_photo', 'text', 'unknown', 'library'));
