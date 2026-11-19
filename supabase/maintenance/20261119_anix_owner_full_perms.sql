-- ONE-OFF MAINTENANCE (not run by CI), applied live on 2026-11-19 to the auth project (eisstodgncimypdawisy).
-- ANIX release: the account ashkanshams252525@gmail.com is the app owner (super-admin) with every admin permission.
-- It already had nx_staff.role = 'owner' (unlimited) and profiles.role = 'owner'; this adds an explicit full
-- permission row (additive only; owner implies every permission anyway). No password is set or stored here:
-- the account signs in with its own password via Supabase Auth.
do $$
declare uid uuid := (select id from auth.users where lower(email) = 'ashkanshams252525@gmail.com');
begin
  if uid is null then raise exception 'owner account not found'; end if;
  insert into public.nx_staff(user_id, role, granted_by, unlimited) values (uid, 'owner', null, true)
    on conflict (user_id) do nothing;
  insert into public.nx_admin_perms(user_id, perms, unlimited_gems, gem_budget, granted_by, updated_at)
    values (uid, public.nx_admin_perm_list(), true, null, null, now())
    on conflict (user_id) do nothing;
  insert into public.nx_owner_audit(actor, action, target, data)
    values (null, 'set_perms', uid, '{"via":"maintenance","note":"ANIX release: explicit full permission row for owner account (additive)"}');
end $$;
