-- Username + password accounts (no e-mail code). The client asks whether a username is free before signing up;
-- the answer never reveals who owns a name or any e-mail. Login by username goes through the nx-login Edge Function.
create or replace function public.nx_username_available(p_username text) returns boolean
 language sql stable security definer set search_path to 'public' as $$
  select lower(btrim(coalesce(p_username, ''))) ~ '^[a-z0-9_.]{3,20}$'
     and not exists(select 1 from public.profiles where lower(username) = lower(btrim(p_username))) $$;
revoke all on function public.nx_username_available(text) from public;
grant execute on function public.nx_username_available(text) to anon, authenticated;
