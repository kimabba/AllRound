-- Club intro photos

alter table public.clubs
  add column if not exists intro_image_urls text[] not null default '{}';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'clubs_intro_image_urls_max'
      and conrelid = 'public.clubs'::regclass
  ) then
    alter table public.clubs
      add constraint clubs_intro_image_urls_max
      check (
        array_length(intro_image_urls, 1) is null
        or array_length(intro_image_urls, 1) <= 5
      );
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'club-intro-images',
  'club-intro-images',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists club_intro_images_public_read on storage.objects;
create policy club_intro_images_public_read on storage.objects
for select
using (bucket_id = 'club-intro-images');

drop policy if exists club_intro_images_owner_insert on storage.objects;
create policy club_intro_images_owner_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'club-intro-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists club_intro_images_owner_update on storage.objects;
create policy club_intro_images_owner_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'club-intro-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'club-intro-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists club_intro_images_owner_delete on storage.objects;
create policy club_intro_images_owner_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'club-intro-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
