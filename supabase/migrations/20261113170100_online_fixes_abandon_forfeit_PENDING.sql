-- NOT APPLIED (changes existing behaviour; needs the owner's OK).
-- Closes the "losing host cancels the match" hole for clients that still call abandon_match directly
-- (old builds, or anyone calling the REST endpoint): a host abandoning a running non-bot match against
-- opponents who are still connected now forfeits instead of wiping it. Scores are unknown here, so the
-- forfeit is recorded 0:1 / 1:0 for the opponents. Apply after the client calls host_forfeit on quit.
create or replace function public.abandon_match(p_match uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare m matches; host_team int; opp uuid[]; begin
  select * into m from matches where id=p_match;
  if m.id is null then return; end if;
  if not exists(select 1 from rooms where id=m.room_id and host=auth.uid()) then raise exception 'host only'; end if;
  if m.status='live' and not m.bots and m.started_at < now() - interval '15 seconds'
     and coalesce(current_setting('nexora.no_forfeit', true), '') <> '1' then
    host_team := case when auth.uid() = any(m.team_a) then 0 when auth.uid() = any(m.team_b) then 1 else -1 end;
    opp := case host_team when 0 then m.team_b when 1 then m.team_a else '{}'::uuid[] end;
    if host_team <> -1 and exists(select 1 from room_players p where p.room_id=m.room_id and p.user_id = any(opp)
                                  and p.last_seen > now() - interval '30 seconds') then
      perform report_match(p_match, case when host_team=0 then 0 else 1 end, case when host_team=0 then 1 else 0 end, null);
      return;
    end if;
  end if;
  update matches set status='abandoned', ended_at=now() where id=p_match and status='live';
  if found then
    perform _refund_stakes(p_match);
    update tournament_matches set status='ready' where id=m.tournament_match_id and status='live';
  end if;
  update rooms set status='waiting', current_match=null, updated_at=now() where id=m.room_id and current_match=p_match;
  update room_players set ready=false where room_id=m.room_id; end $function$;
-- NOTE: host_forfeit/claim_host_lost call abandon_match only for the "no active opponents" case, so they
-- keep working unchanged with this version.
