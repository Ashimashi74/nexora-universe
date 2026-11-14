-- NEXORA online reliability fixes (ADDITIVE ONLY: two new functions, nothing existing is changed).
-- Applied to project eisstodgncimypdawisy on 2026-11-13.
--
-- 1) claim_host_lost(match, score_a, score_b)
--    The host's app died / lost network mid-match. Before this, the match stayed 'live' for up to 40 min
--    (the other players keep heartbeating the room, so _sweep_rooms never abandons it) and the room was
--    stuck in 'playing'. Any player still in the room may call this once the host has been silent for
--    30 s: the caller becomes host; if the host's opponents are still here the host's team FORFEITS
--    (result recorded through report_match, winner forced to lead by ≥1, scores = last snapshot the
--    caller saw, clamped 0..30); otherwise the match is abandoned (stakes refunded) like abandon_match.
-- 2) host_forfeit(match, score_a, score_b)
--    What the host's quit button should call instead of abandon_match: a host that is losing can no
--    longer wipe a running ranked match. With active opponents and >15 s played, the host's team loses;
--    otherwise (bots / nobody to play against / just started) it is a plain abandon.

create or replace function public.claim_host_lost(p_match uuid, p_score_a integer default 0, p_score_b integer default 0)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare m matches; r rooms; me uuid := auth.uid(); host_team int; sa int; sb int; host_seen timestamptz; opp uuid[]; res jsonb;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from matches where id = p_match for update;
  if m.id is null or m.status <> 'live' then raise exception 'match not live'; end if;
  select * into r from rooms where id = m.room_id for update;
  if r.id is null then raise exception 'room not found'; end if;
  if not exists(select 1 from room_players where room_id = r.id and user_id = me) then raise exception 'not in this match'; end if;
  if r.host = me then raise exception 'not allowed'; end if;
  select last_seen into host_seen from room_players where room_id = r.id and user_id = r.host;
  if host_seen is not null and host_seen > now() - interval '30 seconds' then raise exception 'host still online'; end if;
  host_team := case when r.host = any(m.team_a) then 0 when r.host = any(m.team_b) then 1 else -1 end;
  update rooms set host = me, updated_at = now() where id = r.id;
  sa := least(greatest(coalesce(p_score_a, 0), 0), 30);
  sb := least(greatest(coalesce(p_score_b, 0), 0), 30);
  opp := case host_team when 0 then m.team_b when 1 then m.team_a else '{}'::uuid[] end;
  if host_team = -1 or m.bots or not exists(
      select 1 from room_players p where p.room_id = r.id and p.user_id = any(opp) and p.last_seen > now() - interval '30 seconds') then
    perform abandon_match(p_match);
    return jsonb_build_object('outcome', 'abandoned');
  end if;
  if host_team = 0 then sb := greatest(sb, sa + 1); else sa := greatest(sa, sb + 1); end if;
  res := report_match(p_match, sa, sb, null);
  return res || jsonb_build_object('outcome', 'forfeit', 'score_a', sa, 'score_b', sb);
end $function$;

create or replace function public.host_forfeit(p_match uuid, p_score_a integer default 0, p_score_b integer default 0)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare m matches; r rooms; me uuid := auth.uid(); host_team int; sa int; sb int; opp uuid[]; res jsonb;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from matches where id = p_match for update;
  if m.id is null then return jsonb_build_object('outcome', 'none'); end if;
  select * into r from rooms where id = m.room_id;
  if r.host is distinct from me then raise exception 'host only'; end if;
  if m.status <> 'live' then return jsonb_build_object('outcome', 'none'); end if;
  host_team := case when me = any(m.team_a) then 0 when me = any(m.team_b) then 1 else -1 end;
  opp := case host_team when 0 then m.team_b when 1 then m.team_a else '{}'::uuid[] end;
  if host_team = -1 or m.bots or m.started_at > now() - interval '15 seconds' or not exists(
      select 1 from room_players p where p.room_id = r.id and p.user_id = any(opp) and p.last_seen > now() - interval '30 seconds') then
    perform abandon_match(p_match);
    return jsonb_build_object('outcome', 'abandoned');
  end if;
  sa := least(greatest(coalesce(p_score_a, 0), 0), 30);
  sb := least(greatest(coalesce(p_score_b, 0), 0), 30);
  if host_team = 0 then sb := greatest(sb, sa + 1); else sa := greatest(sa, sb + 1); end if;
  res := report_match(p_match, sa, sb, null);
  return res || jsonb_build_object('outcome', 'forfeit', 'score_a', sa, 'score_b', sb);
end $function$;

revoke all on function public.claim_host_lost(uuid, integer, integer) from public, anon;
revoke all on function public.host_forfeit(uuid, integer, integer) from public, anon;
grant execute on function public.claim_host_lost(uuid, integer, integer) to authenticated;
grant execute on function public.host_forfeit(uuid, integer, integer) to authenticated;
