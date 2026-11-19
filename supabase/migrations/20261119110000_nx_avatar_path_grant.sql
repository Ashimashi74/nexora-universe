-- Profile photo upload: the app saves avatar_url AND avatar_path, but authenticated users could only update
-- avatar_url, so every photo save failed with 403. Allow avatar_path, restricted to the user's own storage folder.
grant update (avatar_path) on public.profiles to authenticated;
alter table public.profiles drop constraint if exists profiles_avatar_path_own;
alter table public.profiles add constraint profiles_avatar_path_own
  check (avatar_path is null or avatar_path like (id::text || '/%')) not valid;
