-- Games project · admin powers v2 (2026-11-19): kick from rooms, end live matches, live match list, room member list,
-- chat mute mirror (the auth project's nx_admin_mute is the source; the admin app writes both). Permission checks are
-- server-side (nx_has_perm from the access-token claims / nx_staff), every action audited in nx_admin_audit.
create table if not exists public.nx_user_mutes (
  user_id uuid primary key,
  muted_until timestamptz,
  reason text,
  by uuid,
  updated_at timestamptz not null default now()
);
alter table public.nx_user_mutes enable row level security;
drop policy if exists nx_user_mutes_own on public.nx_user_mutes;
create policy nx_user_mutes_own on public.nx_user_mutes for select to authenticated using (user_id = auth.uid() or nx_has_perm('users'));

create or replace function public.nx_g_is_muted(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select muted_until > now() from nx_user_mutes where user_id = u), false)
$$;

create or replace function public.nx_admin_mute(p_user uuid, p_minutes integer, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare until timestamptz;
begin
  if not nx_has_perm('users') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_user = auth.uid() then return jsonb_build_object('ok', false, 'error', 'cannot_change_self'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_ban_owner'); end if;
  until := case when coalesce(p_minutes, 0) <= 0 then null else now() + make_interval(mins => least(p_minutes, 525600)) end;
  insert into nx_user_mutes(user_id, muted_until, reason, by) values (p_user, until, left(p_reason, 300), auth.uid())
  on conflict (user_id) do update set muted_until = excluded.muted_until, reason = excluded.reason, by = excluded.by, updated_at = now();
  -- muted players also lose the stage in every voice room
  if until is not null then
    update nx_room_members set muted = true where user_id = p_user;
  end if;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), case when until is null then 'unmute' else 'mute' end,
    p_user::text, jsonb_build_object('minutes', p_minutes, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'muted_until', until);
end $$;

create or replace function public.nx_admin_room_members(p_room uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'members', coalesce((select jsonb_agg(x order by x.joined_at) from (
    select m.user_id, m.role, m.joined_at, m.last_seen, m.muted, p.username
      from nx_room_members m left join profiles p on p.id = m.user_id where m.room_id = p_room) x), '[]'::jsonb));
end $$;

create or replace function public.nx_admin_kick(p_room uuid, p_user uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if nx_is_owner(p_user) and not nx_is_owner(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'cannot_ban_owner'); end if;
  delete from nx_room_members where room_id = p_room and user_id = p_user;
  delete from nx_room_players where room_id = p_room and user_id = p_user;
  delete from nx_room_game_players where room_id = p_room and user_id = p_user;
  update nx_rooms set updated_at = now() where id = p_room;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'kick', p_user::text,
    jsonb_build_object('room', p_room, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_admin_live_matches(p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'matches', coalesce((select jsonb_agg(x order by x.started_at desc) from (
    select id, room_id, game, names, scores, status, started_at, (settings ? 'tmatch') as tournament
      from nx_matches where status = 'playing'
     order by started_at desc limit greatest(1, least(coalesce(p_limit, 100), 300))) x), '[]'::jsonb));
end $$;

-- End a live match with no winner (not tournament matches: those use the tournament tools).
create or replace function public.nx_admin_end_match(p_match uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m nx_matches;
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if m.settings ? 'tmatch' then return jsonb_build_object('ok', false, 'error', 'tournament_room'); end if;
  if m.status <> 'playing' then return jsonb_build_object('ok', false, 'error', 'not_live'); end if;
  update nx_matches set status = 'finished', reason = 'admin_ended', winner_seats = '{}', ended_at = now() where id = p_match;
  if m.room_id is not null then
    update nx_rooms set status = case when status = 'playing' then 'lobby' else status end, updated_at = now() where id = m.room_id;
  end if;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'end_match', p_match::text,
    jsonb_build_object('reason', p_reason, 'game', m.game));
  return jsonb_build_object('ok', true);
end $$;

-- Room chat refuses muted players.
create or replace function public.nx_room_send_message(p_room uuid, p_text text) returns nx_room_messages
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); out_msg public.nx_room_messages;
begin
  if me is null or public.nx_room_member_role(p_room) is null then raise exception 'not a room member'; end if;
  if public.nx_g_is_muted(me) then raise exception 'muted'; end if;
  insert into public.nx_room_messages(room_id, author, text) values (p_room, me, btrim(p_text)) returning * into out_msg;
  update public.nx_room_members set last_seen = now() where room_id = p_room and user_id = me;
  update public.nx_rooms set updated_at = now() where id = p_room;
  return out_msg;
end $$;

revoke all on function public.nx_admin_mute(uuid, integer, text), public.nx_admin_room_members(uuid),
  public.nx_admin_kick(uuid, uuid, text), public.nx_admin_live_matches(integer), public.nx_admin_end_match(uuid, text) from public, anon;
grant execute on function public.nx_admin_mute(uuid, integer, text), public.nx_admin_room_members(uuid),
  public.nx_admin_kick(uuid, uuid, text), public.nx_admin_live_matches(integer), public.nx_admin_end_match(uuid, text) to authenticated;
grant execute on function public.nx_g_is_muted(uuid) to authenticated;
