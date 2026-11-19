-- Admin powers v2 (2026-11-19): mute/unmute, item/team grants, force rename, temporary password reset, user reports,
-- announcement edit, user detail. Every RPC is SECURITY DEFINER and checks the caller's permission server-side through
-- _nx_admin_guard (owner = everything; admins only their perms; nobody while a password change is pending); all audited.

alter table public.nx_account_flags add column if not exists muted_until timestamptz;
alter table public.nx_account_flags add column if not exists mute_reason text;

create or replace function public.nx_is_muted(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select muted_until > now() from nx_account_flags where user_id = u), false)
$$;
grant execute on function public.nx_is_muted(uuid) to authenticated;

-- Mute (chat / posting) for p_minutes (0 or null = unmute). Owner and the caller themself are never muted.
create or replace function public.nx_admin_mute(p_user uuid, p_minutes integer, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('users'); until timestamptz;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_user = auth.uid() then return jsonb_build_object('ok', false, 'error', 'cannot_change_self'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_ban_owner'); end if;
  if nx_is_admin_any(p_user) and not nx_is_owner(auth.uid()) then
    return jsonb_build_object('ok', false, 'error', 'cannot_ban_admin'); end if;
  until := case when coalesce(p_minutes, 0) <= 0 then null
                else now() + make_interval(mins => least(p_minutes, 525600)) end;
  insert into nx_account_flags(user_id, muted_until, mute_reason) values (p_user, until, left(p_reason, 300))
  on conflict (user_id) do update set muted_until = excluded.muted_until, mute_reason = excluded.mute_reason, updated_at = now();
  perform _nx_owner_log(case when until is null then 'unmute' else 'mute' end, p_user,
                        jsonb_build_object('minutes', p_minutes, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'muted_until', until);
end $$;

-- Give / take an item (store item id, finger-soccer team id, piece set ...) in the player's cloud inventory.
create or replace function public.nx_admin_grant_item(p_user uuid, p_item text, p_grant boolean default true,
                                                      p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('currency'); it text := btrim(coalesce(p_item, '')); inv jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if it = '' or length(it) > 64 or it !~ '^[A-Za-z0-9_.:-]+$' then return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
  if not exists (select 1 from profiles where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into nx_profiles(id, data) values (p_user, '{}'::jsonb) on conflict (id) do nothing;
  select coalesce(data -> 'inv', '[]'::jsonb) into inv from nx_profiles where id = p_user for update;
  inv := (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(inv) e where e <> to_jsonb(it));
  if coalesce(p_grant, true) then inv := inv || to_jsonb(it); end if;
  update nx_profiles set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inv}', inv), updated_at = now() where id = p_user;
  perform _nx_owner_log(case when coalesce(p_grant, true) then 'grant_item' else 'take_item' end, p_user,
                        jsonb_build_object('item', it, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'inv', inv);
end $$;

-- Force a new username (3..20 chars, unique).
create or replace function public.nx_admin_rename(p_user uuid, p_name text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('users'); n text := btrim(coalesce(p_name, '')); old text;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if char_length(n) < 3 or char_length(n) > 20 then return jsonb_build_object('ok', false, 'error', 'bad_name'); end if;
  if nx_is_owner(p_user) and not nx_is_owner(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  select username into old from profiles where id = p_user for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if exists (select 1 from profiles where lower(username) = lower(n) and id <> p_user) then
    return jsonb_build_object('ok', false, 'error', 'name_taken'); end if;
  update profiles set username = n, updated_at = now() where id = p_user;
  perform _nx_owner_log('rename', p_user, jsonb_build_object('from', old, 'to', n, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'username', n);
end $$;

-- Set a temporary password (8..72 chars) and force a change at next sign-in; open sessions are revoked.
create or replace function public.nx_admin_reset_password(p_user uuid, p_temp text) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare g text := _nx_admin_guard('users');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if char_length(coalesce(p_temp, '')) < 8 or char_length(p_temp) > 72 then
    return jsonb_build_object('ok', false, 'error', 'weak_password'); end if;
  if p_user = auth.uid() then return jsonb_build_object('ok', false, 'error', 'cannot_change_self'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  if nx_is_admin_any(p_user) and not nx_is_owner(auth.uid()) then
    return jsonb_build_object('ok', false, 'error', 'cannot_ban_admin'); end if;
  update auth.users set encrypted_password = extensions.crypt(p_temp, extensions.gen_salt('bf')), updated_at = now()
   where id = p_user;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into nx_account_flags(user_id, must_change_password) values (p_user, true)
  on conflict (user_id) do update set must_change_password = true, updated_at = now();
  delete from auth.sessions where user_id = p_user;
  delete from auth.refresh_tokens where user_id = p_user::text;
  perform _nx_owner_log('reset_password', p_user, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

-- Player reports (any signed-in player may report a user / message / room; admins with 'moderation' review them).
create table if not exists public.nx_user_reports (
  id bigserial primary key,
  reporter uuid not null default auth.uid(),
  target_user uuid,
  kind text not null default 'user' check (kind in ('user', 'message', 'post', 'room', 'match', 'other')),
  target_id text,
  reason text not null check (char_length(reason) between 2 and 500),
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  note text,
  handled_by uuid,
  handled_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.nx_user_reports enable row level security;
drop policy if exists nx_user_reports_own on public.nx_user_reports;
create policy nx_user_reports_own on public.nx_user_reports for select to authenticated using (reporter = auth.uid());

create or replace function public.nx_report_user(p_target uuid, p_kind text, p_target_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if (select count(*) from nx_user_reports where reporter = auth.uid() and created_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  insert into nx_user_reports(reporter, target_user, kind, target_id, reason)
  values (auth.uid(), p_target, coalesce(nullif(p_kind, ''), 'user'), left(p_target_id, 120), left(btrim(p_reason), 500));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_admin_reports(p_status text default 'open', p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard('moderation');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true, 'reports', coalesce((select jsonb_agg(x order by x.created_at desc) from (
    select r.*, pr.username as reporter_name, pt.username as target_name
      from nx_user_reports r left join profiles pr on pr.id = r.reporter left join profiles pt on pt.id = r.target_user
     where p_status is null or p_status = '' or r.status = p_status
     order by r.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 300))) x), '[]'::jsonb));
end $$;

create or replace function public.nx_admin_report_set(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('moderation');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_status not in ('open', 'resolved', 'dismissed') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  update nx_user_reports set status = p_status, note = left(p_note, 300), handled_by = auth.uid(), handled_at = now()
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_owner_log('report_' || p_status, null, jsonb_build_object('report', p_id, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

-- Edit a live announcement (global notice) in place.
create or replace function public.nx_admin_announce_edit(p_id bigint, p_title text, p_body text, p_hours integer default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('announcements');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if char_length(btrim(coalesce(p_title, ''))) < 1 then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  update nx_announcements set title = left(btrim(p_title), 120), body = left(coalesce(p_body, ''), 2000),
         expires_at = case when p_hours is null then expires_at else now() + make_interval(hours => greatest(1, least(p_hours, 8760))) end
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_owner_log('announce_edit', null, jsonb_build_object('id', p_id, 'title', p_title));
  return jsonb_build_object('ok', true);
end $$;

-- User search now also returns the mute state.
create or replace function public.nx_owner_users(p_q text default '', p_limit integer default 50, p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard('users'); q text := lower(trim(coalesce(p_q, ''))); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select u.id, p.username, u.email, coalesce(u.is_anonymous, false) as guest, u.created_at, u.last_sign_in_at,
           coalesce(p.coins, 0) as coins, coalesce(p.gems, 0) as gems, coalesce(p.xp, 0) as xp, coalesce(p.level, 1) as level,
           case when nx_is_owner(u.id) then 'owner' else coalesce(s.role, 'player') end as role,
           coalesce(s.unlimited, false) as unlimited,
           coalesce(f.banned, false) as banned, f.ban_reason,
           case when f.muted_until > now() then f.muted_until end as muted_until, f.mute_reason,
           coalesce((select perms from nx_admin_perms a where a.user_id = u.id), '{}') as perms
      from auth.users u
      left join profiles p on p.id = u.id
      left join nx_staff s on s.user_id = u.id
      left join nx_account_flags f on f.user_id = u.id
     where q = '' or lower(coalesce(p.username, '')) like '%' || q || '%' or lower(coalesce(u.email, '')) like '%' || q || '%'
           or u.id::text like q || '%'
     order by u.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0))) x;
  return jsonb_build_object('ok', true, 'users', res);
end $$;

CREATE OR REPLACE FUNCTION public.nx_send_message(p_chat uuid, p_kind text, p_text text, p_payload jsonb DEFAULT '{}'::jsonb, p_reply_to uuid DEFAULT NULL::uuid)
 RETURNS nx_messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text; r text; m nx_messages;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if nx_is_muted(auth.uid()) then raise exception 'muted'; end if;
  select kind into k from nx_chats where id = p_chat;
  r := nx_chat_role(p_chat);
  if k is null or r is null then raise exception 'not_member'; end if;
  if k = 'channel' and r not in ('owner','admin') then raise exception 'channel_admins_only'; end if;
  if p_kind not in ('text','art','shared','invite','call','photo','audio','file') then raise exception 'bad_kind'; end if;
  if p_kind = 'text' and coalesce(trim(p_text),'') = '' then raise exception 'empty'; end if;
  if p_kind in ('photo','audio','file') and coalesce(p_payload->>'path','') = '' then raise exception 'missing_media'; end if;
  if p_kind in ('photo','audio','file') and length(coalesce(p_payload->>'name','')) > 255 then raise exception 'bad_media_name'; end if;
  if p_kind in ('photo','audio','file') and (
       split_part(p_payload->>'path','/',1) <> auth.uid()::text
       or split_part(p_payload->>'path','/',2) <> 'chat'
       or split_part(p_payload->>'path','/',3) <> p_chat::text
     ) then raise exception 'media_path_forbidden'; end if;
  insert into nx_messages(chat_id, author, author_name, kind, text, payload, reply_to)
    values (p_chat, auth.uid(), _nx_name(auth.uid()), p_kind, left(trim(coalesce(p_text,'')),4000), coalesce(p_payload,'{}'), p_reply_to)
    returning * into m;
  update nx_chats set last_msg_at = m.created_at where id = p_chat;
  update nx_chat_members set last_read_at = m.created_at where chat_id = p_chat and user_id = auth.uid();
  return m;
end $function$;

revoke all on function public.nx_admin_mute(uuid, integer, text), public.nx_admin_grant_item(uuid, text, boolean, text),
  public.nx_admin_rename(uuid, text, text), public.nx_admin_reset_password(uuid, text),
  public.nx_admin_reports(text, integer), public.nx_admin_report_set(bigint, text, text),
  public.nx_admin_announce_edit(bigint, text, text, integer), public.nx_report_user(uuid, text, text, text) from public, anon;
grant execute on function public.nx_admin_mute(uuid, integer, text), public.nx_admin_grant_item(uuid, text, boolean, text),
  public.nx_admin_rename(uuid, text, text), public.nx_admin_reset_password(uuid, text),
  public.nx_admin_reports(text, integer), public.nx_admin_report_set(bigint, text, text),
  public.nx_admin_announce_edit(bigint, text, text, integer), public.nx_report_user(uuid, text, text, text) to authenticated;
