-- NEXORA lobby: host can change the room mode (1v1 / 2v2 / 3v3) from the room settings.
-- ADDITIVE: extends update_room with an optional p_mode; no existing call is affected.
--
-- When the mode shrinks, any player sitting in a slot that no longer exists is moved to
-- the spectator list (their seat is freed) so the teams stay consistent with room_size().

create or replace function public.update_room(p_room uuid, p_settings jsonb, p_name text default null, p_mode text default null)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; n int; old_n int; u uuid;
begin
  select * into r from rooms where id = p_room for update;
  if r.id is null or r.host <> auth.uid() or r.status <> 'waiting' then raise exception 'host only'; end if;
  if p_mode is not null and trim(p_mode) <> r.mode then
    if trim(p_mode) not in ('1v1','2v2','3v3') then raise exception 'bad mode'; end if;
    n := room_size(trim(p_mode));
    old_n := room_size(r.mode);
    -- free seats beyond the new size (move those players to the spectator list)
    if n < old_n then
      for u in
        select user_id from room_players
        where room_id = p_room and role = 'player' and team in (0,1) and slot >= n
      loop
        update room_players set role = 'spectator', team = null, slot = null, ready = false
        where room_id = p_room and user_id = u;
      end loop;
    end if;
    update rooms set mode = trim(p_mode), updated_at = now() where id = p_room;
  end if;
  update rooms set settings = coalesce(p_settings, settings),
    name = coalesce(nullif(trim(p_name),''), name),
    updated_at = now()
  where id = p_room;
end $$;

revoke all on function public.update_room(uuid, jsonb, text, text) from public, anon;
grant execute on function public.update_room(uuid, jsonb, text, text) to authenticated;
