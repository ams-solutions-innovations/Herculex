-- Cloud Photo Storage for progress photos and custom food/meal photos.
--
-- Bucket `user-photos` is private. Objects are organized by user folder:
-- `<user_id>/<photo_category>/<uuid>.jpg`
--
-- Row Level Security enforces that authenticated users can only view, upload,
-- update, and delete their own files.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-photos',
  'user-photos',
  false,
  10485760, -- 10 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- RLS policies for storage.objects on the user-photos bucket
create policy "Users can view their own photos"
  on storage.objects for select
  using (
    bucket_id = 'user-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users can upload their own photos"
  on storage.objects for insert
  with check (
    bucket_id = 'user-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users can update their own photos"
  on storage.objects for update
  using (
    bucket_id = 'user-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'user-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users can delete their own photos"
  on storage.objects for delete
  using (
    bucket_id = 'user-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
