drop policy if exists "Users can upload their food images" on storage.objects;
drop policy if exists "Users can read their food images" on storage.objects;
drop policy if exists "Users can delete their food images" on storage.objects;

create policy "Users can upload their food images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'food-images'
  and auth.uid() = (storage.foldername(name))[1]::uuid
);

create policy "Users can read their food images"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'food-images'
  and auth.uid() = (storage.foldername(name))[1]::uuid
);

create policy "Users can delete their food images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'food-images'
  and auth.uid() = (storage.foldername(name))[1]::uuid
);
;
