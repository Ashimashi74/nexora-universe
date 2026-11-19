-- Games project · admin panel v3: post an admin notice into one room or broadcast it to every open room, change a
-- room's privacy / seats, and clear a room's chat. Permission 'rooms' (or 'announcements' for the broadcast); audited.

create or replace function public.nx_admin_room_message(p_room uuid, p_text text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text := btrim(coalesce(p_text, ''));
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if char_length(t) < 1 or char_length(t) > 500 then return jsonb_build_object('ok', false, 'error', 'bad_text'); end if;
  if not exists (select 1 from nx_rooms where id = p_room) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into nx_room_messages(room_id, author, text) values (p_room, auth.uid(), '📢 ' || t);
  update nx_rooms set updated_at = now() where id = p_room;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'room_message', p_room::text, jsonb_build_object('text', t));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_admin_rooms_broadcast(p_text text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text := btrim(coalesce(p_text, '')); n integer;
begin
  if not (nx_has_perm('rooms') or nx_has_perm('announcements')) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if char_length(t) < 1 or char_length(t) > 500 then return jsonb_build_object('ok', false, 'error', 'bad_text'); end if;
  insert into nx_room_messages(room_id, author, text)
  select id, auth.uid(), '📢 ' || t from nx_rooms where status in ('lobby', 'playing', 'open');
  get diagnostics n = row_count;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'rooms_broadcast', null, jsonb_build_object('text', t, 'rooms', n));
  return jsonb_build_object('ok', true, 'rooms', n);
end $$;

create or replace function public.nx_admin_room_update(p_room uuid, p_private boolean default null, p_seats integer default null,
                                                       p_title text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r nx_rooms;
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into r from nx_rooms where id = p_room for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_seats is not null and (p_seats < 2 or p_seats > 21) then return jsonb_build_object('ok', false, 'error', 'bad_seats'); end if;
  update nx_rooms set is_private = coalesce(p_private, is_private), seats = coalesce(p_seats, seats),
         title = coalesce(nullif(left(btrim(coalesce(p_title, '')), 60), ''), title), updated_at = now()
   where id = p_room;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'room_update', p_room::text,
    jsonb_build_object('private', p_private, 'seats', p_seats, 'title', p_title));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_admin_room_clear_chat(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  update nx_room_messages set deleted = true where room_id = p_room and not deleted;
  get diagnostics n = row_count;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'room_clear_chat', p_room::text, jsonb_build_object('messages', n));
  return jsonb_build_object('ok', true, 'messages', n);
end $$;

revoke all on function public.nx_admin_room_message(uuid, text), public.nx_admin_rooms_broadcast(text),
  public.nx_admin_room_update(uuid, boolean, integer, text), public.nx_admin_room_clear_chat(uuid) from public, anon;
grant execute on function public.nx_admin_room_message(uuid, text), public.nx_admin_rooms_broadcast(text),
  public.nx_admin_room_update(uuid, boolean, integer, text), public.nx_admin_room_clear_chat(uuid) to authenticated;
