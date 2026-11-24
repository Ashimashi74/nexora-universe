-- NEXORA GAMES project (eyzafhrefnqlwcjpcdyg) · tournaments: launch hardening (2026-11-23).
-- Idempotent: only CREATE OR REPLACE FUNCTION + grants. Apply once to the GAMES project (supabase/games/migrations).
--
-- 1. Entry fees of "unlimited" accounts are no longer added to the escrow (they were never charged, so the pool
--    minted coins/gems out of nothing); refunds of those entries no longer touch the escrow either.
-- 2. Wallet deltas from fees, refunds and prizes carry a reason (nx.reason) for the auth-project bridge.
-- 3. Payout: unchanged maths and idempotency keys; skips players without a mirror row instead of writing a ledger
--    line that pays nobody; no zero house-fee lines.
-- 4. Cancel also ends the games that are still being played (no orphan 'playing' rooms, nothing re-enters the engine).
-- 5. Check-in: a manual "draw now" / "start now" before the check-in window opened no longer throws out every
--    registered player; waitlisted players may check in and take places freed by approved players who did not.
-- 6. Disqualification: removing a player after the draw (drawn / live) is supported. Their open matches become
--    walkovers, future matches they would be seated in become walkovers automatically, the running game is ended.
-- 7. A game whose two phones disagree (nx_matches.status = 'disputed') becomes a tournament dispute instead of being
--    auto-accepted 3 minutes later as a no-winner game.
-- 8. Organizer match tools accept best-of 1..15 (same range as the wizard / nx_t_save).
-- 9. nx_t_code_peek: shows what an invite code / deep link joins (title, fees) before anything is charged.


CREATE OR REPLACE FUNCTION public._nx_t_charge(p_t uuid, p_user uuid, p_coins integer, p_gems integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lid bigint; ok uuid; unl boolean := nx_unlimited(p_user);
        k text := case when unl then 'ufee:' else 'fee:' end || p_t || ':' || p_user || ':'
                  || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
        kd text := case when unl then 'entry_fee_unlimited' else 'entry_fee' end;
begin
  if coalesce(p_coins, 0) = 0 and coalesce(p_gems, 0) = 0 then return 0; end if;
  if not unl then
    perform set_config('nx.reason', 'tournament_entry_fee', true);
    update profiles set coins = coins - p_coins, gems = coalesce(gems, 0) - p_gems
     where id = p_user and coins >= p_coins and coalesce(gems, 0) >= p_gems returning id into ok;
    if ok is null then return null; end if;
  end if;
  if p_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'coins', -p_coins, k || ':c') returning id into lid;
  end if;
  if p_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'gems', -p_gems, k || ':g') returning id into lid;
  end if;
  -- only real money goes into the escrow (an unlimited account pays nothing, so nothing may be paid out for it)
  if not unl then
    update nx_tournaments set escrow_coins = escrow_coins + p_coins, escrow_gems = escrow_gems + p_gems where id = p_t;
  end if;
  return lid;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_refund(p_t uuid, p_user uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e nx_t_entries; got boolean := false; unl boolean; kd text;
begin
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or (e.paid_coins = 0 and e.paid_gems = 0) then return false; end if;
  unl := coalesce((select kind = 'entry_fee_unlimited' from nx_t_ledger where id = e.fee_ref), false);
  kd := case when unl then 'refund_unlimited' else 'refund' end;
  if e.paid_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'coins', e.paid_coins, 'refund:coins:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      if not unl then
        perform set_config('nx.reason', 'tournament_refund', true);
        update profiles set coins = coins + e.paid_coins where id = p_user;
        update nx_tournaments set escrow_coins = greatest(0, escrow_coins - e.paid_coins) where id = p_t;
      end if;
      got := true;
    end if;
  end if;
  if e.paid_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'gems', e.paid_gems, 'refund:gems:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      if not unl then
        perform set_config('nx.reason', 'tournament_refund', true);
        update profiles set gems = coalesce(gems, 0) + e.paid_gems where id = p_user;
        update nx_tournaments set escrow_gems = greatest(0, escrow_gems - e.paid_gems) where id = p_t;
      end if;
      got := true;
    end if;
  end if;
  update nx_t_entries set paid_coins = 0, paid_gems = 0, updated_at = now() where tournament_id = p_t and user_id = p_user;
  if got then
    perform _nx_t_notify(p_user, p_t, null, 'refund', jsonb_build_object('coins', e.paid_coins, 'gems', e.paid_gems,
                         'reason', p_reason, 'unlimited', unl), 'refund:' || coalesce(e.fee_ref::text, p_user::text));
  end if;
  return got;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_payout(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; dist int[]; tc int; tg int; r record; pool int;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.paid_out then return; end if;
  perform set_config('nx.reason', 'tournament_prize', true);
  select coalesce(array_agg(v::numeric::int order by o), array[60, 30, 10]) into dist
    from jsonb_array_elements_text(case when jsonb_typeof(t.prize -> 'dist') = 'array' then t.prize -> 'dist' else '[60,30,10]'::jsonb end)
         with ordinality as x(v, o);
  tc := _nx_t_prize_total(_nx_t_cfg_int(t.prize, 'fixed_coins', 0), t.escrow_coins, _nx_t_cfg_int(t.prize, 'pool_pct', 0),
                          _nx_t_cfg_int(t.prize, 'fee_pct', 0));
  tg := _nx_t_prize_total(_nx_t_cfg_int(t.prize, 'fixed_gems', 0), t.escrow_gems, _nx_t_cfg_int(t.prize, 'pool_pct', 0),
                          _nx_t_cfg_int(t.prize, 'fee_pct', 0));
  for r in select s.user_id, min(s.place) as place, sum(s.amount)::int as amount from _nx_t_split(p_t, tc, dist) s group by s.user_id loop
    continue when r.amount <= 0;
    if not exists (select 1 from profiles where id = r.user_id) then
      perform _nx_t_audit(p_t, null, 'payout_skipped_no_profile', jsonb_build_object('user', r.user_id, 'coins', r.amount));
      continue;
    end if;
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, place, idem_key)
    values (p_t, r.user_id, 'payout', 'coins', r.amount, r.place, 'payout:' || p_t || ':' || r.user_id || ':coins')
    on conflict (idem_key) do nothing;
    if found then
      update profiles set coins = coins + r.amount where id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'prize', jsonb_build_object('coins', r.amount, 'place', r.place),
                           'prize:coins:' || p_t);
    end if;
  end loop;
  for r in select s.user_id, min(s.place) as place, sum(s.amount)::int as amount from _nx_t_split(p_t, tg, dist) s group by s.user_id loop
    continue when r.amount <= 0;
    if not exists (select 1 from profiles where id = r.user_id) then
      perform _nx_t_audit(p_t, null, 'payout_skipped_no_profile', jsonb_build_object('user', r.user_id, 'gems', r.amount));
      continue;
    end if;
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, place, idem_key)
    values (p_t, r.user_id, 'payout', 'gems', r.amount, r.place, 'payout:' || p_t || ':' || r.user_id || ':gems')
    on conflict (idem_key) do nothing;
    if found then
      update profiles set gems = coalesce(gems, 0) + r.amount where id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'prize', jsonb_build_object('gems', r.amount, 'place', r.place),
                           'prize:gems:' || p_t);
    end if;
  end loop;
  -- the rest of the escrow (house fee + the part not in the pool) is released to the house in the ledger
  pool := t.escrow_coins;
  if pool > 0 and pool - least(pool, greatest(0, tc - _nx_t_cfg_int(t.prize, 'fixed_coins', 0))) > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, null, 'house_fee', 'coins', pool - least(pool, greatest(0, tc - _nx_t_cfg_int(t.prize, 'fixed_coins', 0))),
            'house:' || p_t || ':coins') on conflict (idem_key) do nothing;
  end if;
  if t.escrow_gems > 0
     and t.escrow_gems - least(t.escrow_gems, greatest(0, tg - _nx_t_cfg_int(t.prize, 'fixed_gems', 0))) > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, null, 'house_fee', 'gems',
            t.escrow_gems - least(t.escrow_gems, greatest(0, tg - _nx_t_cfg_int(t.prize, 'fixed_gems', 0))),
            'house:' || p_t || ':gems') on conflict (idem_key) do nothing;
  end if;
  update nx_tournaments set paid_out = true, escrow_coins = 0, escrow_gems = 0, updated_at = now() where id = p_t;
  perform _nx_t_audit(p_t, null, 'payout', jsonb_build_object('coins', tc, 'gems', tg, 'dist', to_jsonb(dist)));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_cancel(p_t uuid, p_reason text, p_actor uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; r record; gm record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status in ('finished', 'cancelled') then return; end if;
  for r in select user_id from nx_t_entries where tournament_id = p_t and (paid_coins > 0 or paid_gems > 0) loop
    perform _nx_t_refund(p_t, r.user_id, 'cancelled');
  end loop;
  -- games still being played end now; marking them accepted first keeps them out of the engine
  for gm in select g.game_match from nx_t_games g join nx_t_matches m on m.id = g.tmatch
             where m.tournament_id = p_t and not g.accepted loop
    update nx_t_games set accepted = true, source = 'cancelled' where game_match = gm.game_match;
    update nx_matches set status = 'abandoned', reason = 'tournament_cancelled', ended_at = now()
     where id = gm.game_match and status = 'playing';
  end loop;
  update nx_t_matches set status = 'void', result_note = 'cancelled', updated_at = now()
   where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
  update nx_tournaments set status = 'cancelled', cancel_reason = left(p_reason, 200), finished_at = now(), updated_at = now()
   where id = p_t;
  update nx_t_jobs set done_at = now(), last_error = 'cancelled' where tournament_id = p_t and done_at is null;
  perform _nx_t_notify_all(p_t, 'cancelled', jsonb_build_object('reason', p_reason), 'cancelled:' || p_t,
                           array['approved', 'pending', 'waitlist']);
  perform _nx_t_audit(p_t, p_actor, 'cancelled', jsonb_build_object('reason', p_reason));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_draw(p_t uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; n int; players uuid[]; g int; a int; i int; grp int; r record; maxr int := 0; rr int;
        win text; purge boolean := false;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status not in ('registering', 'closed') then return; end if;
  -- check-in: approved players who did not check in are left out (fee refunded) - but only once the check-in
  -- window (10 minutes before the start) has opened. An organizer's early "draw now" / "start now" sets
  -- nx.t_checkin_window = 'closed' and everybody registered plays.
  if _nx_t_cfg_bool(t.config, 'checkin', false) then
    win := coalesce(current_setting('nx.t_checkin_window', true), '');
    purge := case win when 'open' then true when 'closed' then false
                      else now() >= t.start_at - interval '10 minutes' end;
  end if;
  if purge then
    for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'approved' and checked_in_at is null loop
      perform _nx_t_refund(p_t, r.user_id, 'no_checkin');
      update nx_t_entries set status = 'no_checkin', note = 'no_checkin', updated_at = now()
       where tournament_id = p_t and user_id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'no_checkin', '{}'::jsonb, 'nocheckin:' || p_t);
    end loop;
    -- places freed that way go to waitlisted players who checked in, first come first served
    select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
    for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'waitlist' and checked_in_at is not null
              order by created_at loop
      exit when n >= t.capacity;
      update nx_t_entries set status = 'approved', updated_at = now() where tournament_id = p_t and user_id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'promoted', '{}'::jsonb, 'promo:' || p_t || ':' || r.user_id);
      n := n + 1;
    end loop;
  end if;
  select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
  if n < greatest(2, t.min_players) then
    perform _nx_t_cancel(p_t, 'not_enough_players', p_actor);
    return;
  end if;
  -- whoever did not make it (pending approval / waitlist) gets the fee back
  for r in select user_id from nx_t_entries where tournament_id = p_t and status in ('pending', 'waitlist') loop
    perform _nx_t_refund(p_t, r.user_id, 'not_drawn');
    update nx_t_entries set status = 'rejected', note = 'not_drawn', updated_at = now()
     where tournament_id = p_t and user_id = r.user_id;
    perform _nx_t_notify(r.user_id, p_t, null, 'rejected', jsonb_build_object('reason', 'not_drawn'), 'notdrawn:' || p_t);
  end loop;
  if t.seed is null then
    t.seed := floor(random() * 2147483646)::bigint + 1;
    update nx_tournaments set seed = t.seed where id = p_t;
  end if;
  select array_agg(user_id order by
           case when t.seeding = 'manual' then coalesce(seed, 100000) else 0 end,
           case when t.seeding = 'rating' then -rating else 0 end,
           md5(t.seed::text || user_id::text))
    into players from nx_t_entries where tournament_id = p_t and status = 'approved';
  for i in 1..n loop
    update nx_t_entries set seed = i, group_no = null where tournament_id = p_t and user_id = players[i];
  end loop;
  delete from nx_t_matches where tournament_id = p_t;
  if t.format in ('single_elim', 'two_legs') then
    perform _nx_t_gen_se(p_t, players, 'main', 0, 0);
  elsif t.format = 'double_elim' then
    perform _nx_t_gen_de(p_t, players);
  elsif t.format = 'round_robin' then
    perform _nx_t_gen_rr(p_t, players, null, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'RR', 'main');
  elsif t.format = 'groups_ko' then
    g := greatest(1, least(_nx_t_cfg_int(t.config, 'groups', 2), n / 2));
    for i in 1..n loop
      -- snake: 1..g, g..1, ...
      grp := case when ((i - 1) / g) % 2 = 0 then ((i - 1) % g) + 1 else g - ((i - 1) % g) end;
      update nx_t_entries set group_no = grp where tournament_id = p_t and user_id = players[i];
    end loop;
    for grp in 1..g loop
      rr := _nx_t_gen_rr(p_t, (select array_agg(user_id order by seed) from nx_t_entries
                                where tournament_id = p_t and status = 'approved' and group_no = grp),
                         grp, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'G', 'groups');
    end loop;
    update nx_tournaments set stage = 'groups' where id = p_t;
  elsif t.format = 'swiss' then
    perform _nx_t_swiss_round(p_t, 1);
  end if;
  update nx_tournaments set status = 'drawn', drawn_at = now(), updated_at = now() where id = p_t;
  perform _nx_t_notify_all(p_t, 'drawn', '{}'::jsonb, 'drawn:' || p_t);
  perform _nx_t_audit(p_t, p_actor, 'drawn', jsonb_build_object('seed', t.seed, 'players', n, 'seeding', t.seeding));
end $function$
;

CREATE OR REPLACE FUNCTION public._nx_t_run_job(j nx_t_jobs)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; m nx_t_matches;
begin
  select * into t from nx_tournaments where id = j.tournament_id;
  if t.id is null or t.status in ('finished', 'cancelled', 'draft') then return; end if;
  case j.kind
    when 'open_reg' then
      update nx_tournaments set status = 'registering', updated_at = now() where id = t.id and status = 'scheduled';
    when 'close_reg' then
      update nx_tournaments set status = 'closed', updated_at = now() where id = t.id and status = 'registering';
    when 'checkin_open' then
      if t.status in ('registering', 'closed') then
        perform _nx_t_notify_all(t.id, 'checkin_open', jsonb_build_object('start_at', t.start_at), 'checkin:' || t.id,
                                 array['approved', 'waitlist']);
      end if;
    when 'draw' then
      if _nx_t_cfg_bool(t.config, 'checkin', false) then return; end if;
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_draw(t.id);
    when 'start' then
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_start(t.id);
    when 'remind_start' then
      if t.status in ('registering', 'closed', 'drawn') then
        perform _nx_t_notify_all(t.id, 'starting_soon', jsonb_build_object('start_at', t.start_at), 'soon:' || t.id);
      end if;
    when 'remind_match' then
      select * into m from nx_t_matches where id = j.ref;
      if m.id is not null and m.status = 'scheduled' and m.p1 is not null and m.p2 is not null then
        perform _nx_t_notify(m.p1, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
        perform _nx_t_notify(m.p2, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
      end if;
    else
      null;
  end case;
end $function$
;

create or replace function public.nx_t_checkin(p_t uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select * into t from nx_tournaments where id = p_t;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = me for update;
  if e.user_id is null or e.status not in ('approved', 'waitlist') then return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  if not _nx_t_cfg_bool(t.config, 'checkin', false) then return jsonb_build_object('ok', true, 'checkin', false); end if;
  if e.checked_in_at is not null then return jsonb_build_object('ok', true, 'checked_in_at', e.checked_in_at); end if;
  if t.status not in ('registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'checkin_closed'); end if;
  if now() < t.start_at - interval '10 minutes' then
    return jsonb_build_object('ok', false, 'error', 'checkin_not_open', 'opens_at', t.start_at - interval '10 minutes'); end if;
  update nx_t_entries set checked_in_at = now(), updated_at = now() where tournament_id = p_t and user_id = me;
  perform _nx_t_audit(p_t, me, 'checked_in', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'checked_in_at', now(), 'status', e.status);
end $$;

CREATE OR REPLACE FUNCTION public.nx_t_admin(p_t uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; r record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  -- an early manual draw/start happens before anybody could check in: nobody is thrown out for not checking in
  perform set_config('nx.t_checkin_window',
                     case when now() >= t.start_at - interval '10 minutes' then 'open' else 'closed' end, true);
  case p_action
    when 'publish' then
      if t.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
      update nx_tournaments set status = case when reg_open_at <= now() then 'registering' else 'scheduled' end,
             published_at = now(), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'open_reg' then
      if t.status <> 'scheduled' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'registering', reg_open_at = least(reg_open_at, now()), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'close_reg' then
      if t.status <> 'registering' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'closed', reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             updated_at = now() where id = p_t;
      update nx_t_jobs set done_at = now() where idem_key = 'close_reg:' || p_t and done_at is null;
    when 'draw', 'redraw' then
      if p_action = 'redraw' then
        if t.status <> 'drawn' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
        delete from nx_t_matches where tournament_id = p_t;
        update nx_tournaments set status = 'closed', seed = null, stage = 'main' where id = p_t;
      elsif t.status not in ('registering', 'closed') then
        return jsonb_build_object('ok', false, 'error', 'bad_status');
      end if;
      update nx_tournaments set reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())) where id = p_t;
      perform _nx_t_draw(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t) and done_at is null;
    when 'start' then
      if t.status not in ('registering', 'closed', 'drawn') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set
             reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())),
             start_at = greatest(reg_open_at + interval '1 second', least(start_at, now())) where id = p_t;
      perform _nx_t_start(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t, 'start:' || p_t, 'remind_start:' || p_t)
         and done_at is null;
      perform _nx_t_reschedule(p_t);
    when 'pause' then
      update nx_tournaments set paused = true, updated_at = now() where id = p_t;
    when 'resume' then
      update nx_tournaments set paused = false, updated_at = now() where id = p_t;
      for r in select id from nx_t_matches where tournament_id = p_t and status = 'ready_check' loop
        update nx_t_matches set ready_deadline = now() + make_interval(secs => _nx_t_cfg_int(t.config, 'ready_seconds', 300))
         where id = r.id;
      end loop;
    when 'cancel' then
      perform _nx_t_cancel(p_t, coalesce(nullif(p_reason, ''), 'cancelled_by_organizer'), me);
    when 'finish' then
      if t.status <> 'live' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_t_matches set status = 'void', result_note = 'closed_by_organizer', updated_at = now()
       where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
      perform _nx_t_finish(p_t);
    when 'delete' then
      if t.status <> 'draft' or exists (select 1 from nx_t_ledger where tournament_id = p_t) then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_tournaments where id = p_t;
      return jsonb_build_object('ok', true, 'deleted', true);
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(p_t, me, 'admin_' || p_action, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'status', (select status from nx_tournaments where id = p_t));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_check(p_m uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; t nx_tournaments; at timestamptz; d1 boolean; d2 boolean;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'pending' or not (m.p1_set and m.p2_set) then return; end if;
  if m.p1 is null or m.p2 is null then
    -- a disqualified player does not advance through a bye either (nobody advances; the next opponent gets a bye)
    if not _nx_t_gen_on() and exists (select 1 from nx_t_entries where tournament_id = m.tournament_id
                                       and user_id = coalesce(m.p1, m.p2) and status = 'removed') then
      perform _nx_t_complete(m.id, null, null, false, 'bye', 'disqualified');
    else
      perform _nx_t_complete(m.id, coalesce(m.p1, m.p2), null, false, 'bye', 'bye');
    end if;
    return;
  end if;
  -- a disqualified (removed after the draw) player loses every match they are seated in by walkover
  if not _nx_t_gen_on() then
    d1 := exists (select 1 from nx_t_entries where tournament_id = m.tournament_id and user_id = m.p1 and status = 'removed');
    d2 := exists (select 1 from nx_t_entries where tournament_id = m.tournament_id and user_id = m.p2 and status = 'removed');
    if d1 and d2 then
      perform _nx_t_complete(m.id, null, null, false,
                             case when m.bracket in ('W', 'L', 'GF', 'GF2', 'P3') then 'walkover' else 'void' end, 'disqualified');
      return;
    elsif d1 then
      perform _nx_t_complete(m.id, m.p2, m.p1, false, 'walkover', 'disqualified');
      return;
    elsif d2 then
      perform _nx_t_complete(m.id, m.p1, m.p2, false, 'walkover', 'disqualified');
      return;
    end if;
  end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  at := greatest(_nx_t_planned(t, m.tslot), now());
  update nx_t_matches set status = 'scheduled', scheduled_at = at, updated_at = now() where id = m.id;
  if at - interval '10 minutes' > now() + interval '1 minute' then
    perform _nx_t_job('remind_match', t.id, m.id, at - interval '10 minutes', 'remind_match:' || m.id);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_on_match_end()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w uuid;
begin
  if not (new.settings ? 'tmatch') or old.status <> 'playing' or new.status = 'playing' then return new; end if;
  begin
    update nx_rooms set status = 'closed', updated_at = now() where id = new.room_id;
    if array_length(new.winner_seats, 1) = 1 then w := new.players[new.winner_seats[1] + 1]; end if;
    update nx_t_games set ended_at = now(), srv_winner = w, srv_s_home = coalesce(new.scores[1], 0),
           srv_s_away = coalesce(new.scores[2], 0) where game_match = new.id;
    if new.status = 'disputed' then
      -- the phones disagreed about this game: an organizer decides (never auto-accepted as a no-winner game)
      perform _nx_t_dispute((select g.tmatch from nx_t_games g where g.game_match = new.id and not g.accepted), null,
                            'game_reports_disagree');
    elsif coalesce(new.reason, '') like 'forfeit%' or new.status = 'abandoned' then
      perform _nx_t_game_result(new.id, w, coalesce(new.scores[1], 0), coalesce(new.scores[2], 0), 'forfeit');
    else
      perform _nx_t_try_accept(new.id, false);
    end if;
  exception when others then
    insert into nx_t_audit(tournament_id, action, data)
    values ((new.settings ->> 'tournament')::uuid, 'error_match_end', jsonb_build_object('match', new.id, 'error', sqlerrm));
  end;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_admin_match(p_m uuid, p_action text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_t_matches; t nx_tournaments; w uuid; l uuid; dr boolean; d record; mid uuid;
        np1 uuid; np2 uuid;
begin
  if p_action = 'add' then
    select * into t from nx_tournaments where id = (p ->> 'tournament_id')::uuid for update;
  else
    select * into m from nx_t_matches where id = p_m for update;
    select * into t from nx_tournaments where id = m.tournament_id for update;
  end if;
  if t.id is null or not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  case p_action
    when 'result' then
      w := nullif(p ->> 'winner', '')::uuid;
      dr := coalesce((p ->> 'draw')::boolean, false);
      if not dr and (w is null or not (w = m.p1 or w = m.p2)) then return jsonb_build_object('ok', false, 'error', 'bad_winner'); end if;
      if dr and m.bracket in ('W', 'L', 'GF', 'GF2', 'P3') then return jsonb_build_object('ok', false, 'error', 'knockout_needs_winner'); end if;
      l := case when w = m.p1 then m.p2 when w = m.p2 then m.p1 end;
      if m.status in ('done', 'walkover') then
        if not _nx_t_downstream_free(m.id) then return jsonb_build_object('ok', false, 'error', 'downstream_started'); end if;
        update nx_t_matches set winner = w, loser = l, is_draw = dr, status = 'done',
               w1 = coalesce((p ->> 'w1')::int, w1), w2 = coalesce((p ->> 'w2')::int, w2),
               g1 = coalesce((p ->> 'g1')::int, g1), g2 = coalesce((p ->> 'g2')::int, g2),
               result_note = 'admin:' || coalesce(p ->> 'note', ''), updated_at = now() where id = m.id;
        if w is distinct from m.winner then
          -- re-seat the corrected players downstream
          for d in select id, status from nx_t_matches where id in (m.win_to, m.lose_to) loop
            update nx_t_matches set status = 'pending', ready_deadline = null, p1_ready = false, p2_ready = false where id = d.id;
          end loop;
          if m.win_to is not null then perform _nx_t_put(m.win_to, m.win_slot, w); end if;
          if m.lose_to is not null then perform _nx_t_put(m.lose_to, m.lose_slot, l); end if;
          if m.bracket = 'GF' then
            update nx_t_matches set status = 'pending', p1 = null, p2 = null, p1_set = false, p2_set = false
             where tournament_id = t.id and bracket = 'GF2';
            perform _nx_t_propagate(m.id);
          end if;
        end if;
        perform _nx_t_notify(m.p1, t.id, m.id, 'result_corrected', jsonb_build_object('winner', w), 'fix:' || m.id || ':' || clock_timestamp());
        perform _nx_t_notify(m.p2, t.id, m.id, 'result_corrected', jsonb_build_object('winner', w), 'fix:' || m.id || ':' || clock_timestamp());
      else
        if m.p1 is null or m.p2 is null then return jsonb_build_object('ok', false, 'error', 'players_unknown'); end if;
        update nx_t_matches set w1 = coalesce((p ->> 'w1')::int, w1), w2 = coalesce((p ->> 'w2')::int, w2),
               g1 = coalesce((p ->> 'g1')::int, g1), g2 = coalesce((p ->> 'g2')::int, g2) where id = m.id;
        if m.game_match is not null then
          update nx_t_games set accepted = true, winner = w, source = 'admin' where game_match = m.game_match;
          update nx_matches set status = 'abandoned', reason = 'admin', ended_at = now() where id = m.game_match and status = 'playing';
        end if;
        perform _nx_t_complete(m.id, w, l, dr, 'done', 'admin:' || coalesce(p ->> 'note', ''));
      end if;
    when 'replay' then
      if m.status not in ('disputed', 'playing', 'ready_check', 'scheduled') or m.p1 is null or m.p2 is null then
        return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      if m.game_match is not null then
        update nx_t_games set accepted = true, source = 'void_replay' where game_match = m.game_match;
        update nx_matches set status = 'abandoned', reason = 'replay', ended_at = now() where id = m.game_match and status = 'playing';
      end if;
      update nx_t_matches set status = 'scheduled', game_match = null, updated_at = now() where id = m.id;
      if t.status = 'live' then perform _nx_t_open_ready(m.id); end if;
    when 'edit' then
      if m.status not in ('pending', 'scheduled', 'ready_check') or m.games > 0 then
        return jsonb_build_object('ok', false, 'error', 'already_started'); end if;
      np1 := case when p ? 'p1' then nullif(p ->> 'p1', '')::uuid else m.p1 end;
      np2 := case when p ? 'p2' then nullif(p ->> 'p2', '')::uuid else m.p2 end;
      if (np1 is not null and not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np1 and status = 'approved'))
         or (np2 is not null and not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np2 and status = 'approved'))
         or (np1 = np2) then
        return jsonb_build_object('ok', false, 'error', 'bad_players'); end if;
      update nx_t_matches set p1 = np1, p2 = np2,
             p1_set = p1_set or p ? 'p1', p2_set = p2_set or p ? 'p2',
             best_of = case when (p ->> 'best_of')::int between 1 and 15 then (p ->> 'best_of')::int else best_of end,
             status = 'pending', ready_deadline = null, p1_ready = false, p2_ready = false, updated_at = now()
       where id = m.id;
      perform _nx_t_check(m.id);
      if p ? 'scheduled_at' then
        update nx_t_matches set scheduled_at = greatest((p ->> 'scheduled_at')::timestamptz, now()) where id = m.id and status = 'scheduled';
        -- the 10-minute reminder follows the new time
        select * into m from nx_t_matches where id = m.id;
        if m.status = 'scheduled' and m.scheduled_at - interval '10 minutes' > now() + interval '1 minute' then
          perform _nx_t_job('remind_match', t.id, m.id, m.scheduled_at - interval '10 minutes', 'remind_match:' || m.id);
        end if;
      end if;
    when 'add' then
      if t.format <> 'custom' then return jsonb_build_object('ok', false, 'error', 'custom_only'); end if;
      if t.status not in ('drawn', 'live') then return jsonb_build_object('ok', false, 'error', 'draw_first'); end if;
      np1 := nullif(p ->> 'p1', '')::uuid; np2 := nullif(p ->> 'p2', '')::uuid;
      if np1 is null or np2 is null or np1 = np2
         or not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np1 and status = 'approved')
         or not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np2 and status = 'approved') then
        return jsonb_build_object('ok', false, 'error', 'bad_players'); end if;
      mid := _nx_t_new_match(t, 'main', 'C', greatest(1, coalesce((p ->> 'round')::int, 1)),
                             coalesce((select count(*) from nx_t_matches where tournament_id = t.id and bracket = 'C'
                                        and round = greatest(1, coalesce((p ->> 'round')::int, 1))), 0)::int,
                             greatest(1, coalesce((p ->> 'round')::int, 1)), null,
                             case when (p ->> 'best_of')::int between 1 and 15 then (p ->> 'best_of')::int else 1 end,
                             left(p ->> 'label', 40));
      update nx_t_matches set p1 = np1, p2 = np2, p1_set = true, p2_set = true where id = mid;
      perform _nx_t_check(mid);
      if p ? 'scheduled_at' then
        update nx_t_matches set scheduled_at = greatest((p ->> 'scheduled_at')::timestamptz, now()) where id = mid and status = 'scheduled';
      end if;
      perform _nx_t_audit(t.id, me, 'match_add', jsonb_build_object('match', mid, 'p', p));
      return jsonb_build_object('ok', true, 'id', mid);
    when 'delete' then
      if t.format <> 'custom' or m.games > 0 or m.status not in ('pending', 'scheduled', 'ready_check') then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_t_matches where id = m.id;
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(t.id, me, 'match_' || p_action, jsonb_build_object('match', p_m, 'p', p));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_remove_entry(p_t uuid, p_user uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; r record; n int := 0;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('scheduled', 'registering', 'closed', 'drawn', 'live') then
    return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or e.status not in ('pending', 'approved', 'waitlist') then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if t.status in ('scheduled', 'registering', 'closed') or e.status <> 'approved' then
    -- before the draw: removed with a full refund, the waitlist moves up
    perform _nx_t_refund(p_t, p_user, 'removed');
    update nx_t_entries set status = 'removed', note = p_note, decided_by = me, updated_at = now() where tournament_id = p_t and user_id = p_user;
    perform _nx_t_notify(p_user, p_t, null, 'rejected', jsonb_build_object('note', p_note, 'removed', true), 'rm:' || p_t || ':' || p_user);
    if e.status = 'approved' then perform _nx_t_fill_from_waitlist(p_t); end if;
    perform _nx_t_audit(p_t, me, 'removed', jsonb_build_object('user', p_user, 'note', p_note));
    return jsonb_build_object('ok', true);
  end if;
  -- after the draw: disqualification. The entry fee stays in the pool; every open match is a walkover for the opponent,
  -- and matches the player would reach later are walkovers too (_nx_t_check).
  update nx_t_entries set status = 'removed', note = coalesce(nullif(p_note, ''), 'disqualified'), decided_by = me, updated_at = now()
   where tournament_id = p_t and user_id = p_user;
  perform _nx_t_notify(p_user, p_t, null, 'disqualified', jsonb_build_object('note', p_note), 'dq:' || p_t || ':' || p_user);
  perform _nx_t_audit(p_t, me, 'disqualified', jsonb_build_object('user', p_user, 'note', p_note));
  for r in select id, game_match from nx_t_matches
            where tournament_id = p_t and (p1 = p_user or p2 = p_user) and p1 is not null and p2 is not null
              and status in ('pending', 'scheduled', 'ready_check', 'playing', 'disputed')
            order by round, idx loop
    if r.game_match is not null then
      update nx_t_games set accepted = true, source = 'disqualified' where game_match = r.game_match and not accepted;
      update nx_matches set status = 'abandoned', reason = 'disqualified', ended_at = now()
       where id = r.game_match and status = 'playing';
    end if;
    perform _nx_t_complete(r.id, (select case when x.p1 = p_user then x.p2 else x.p1 end from nx_t_matches x where x.id = r.id),
                           p_user, false, 'walkover', 'disqualified');
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'disqualified', true, 'walkovers', n);
end $function$;

create or replace function public.nx_t_code_peek(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); chk jsonb; t nx_tournaments; st text;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  chk := _nx_t_check_code(me, null, p_code);
  if not (chk ->> 'ok')::boolean then return chk; end if;
  select * into t from nx_tournaments where id = (chk ->> 'tournament_id')::uuid;
  if t.id is null or t.status = 'draft' then return jsonb_build_object('ok', false, 'error', 'bad_code'); end if;
  select status into st from nx_t_entries where tournament_id = t.id and user_id = me;
  return jsonb_build_object('ok', true, 'tournament_id', t.id, 'title', t.title, 'game', t.game, 'status', t.status,
    'fee_coins', t.fee_coins, 'fee_gems', t.fee_gems, 'start_at', t.start_at, 'my_status', st,
    'requires_approval', t.reg_mode in ('approval', 'code_approval') or coalesce((chk ->> 'requires_approval')::boolean, false));
end $$;
revoke all on function public.nx_t_code_peek(text) from public, anon;
grant execute on function public.nx_t_code_peek(text) to authenticated;
