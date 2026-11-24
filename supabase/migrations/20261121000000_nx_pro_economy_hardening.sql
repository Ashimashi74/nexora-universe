-- ANIX PRO · economy hardening (auth/core project). Forward-only; idempotent; never drops data.
--
-- 1. nx_award ignores the client's p_xp / p_coins. Amounts come from public.nx_reward_rules (exact event, or a
--    LIKE pattern such as 'game.%.win'). Unknown events grant nothing (reason 'unknown_event'). Per-rule daily /
--    weekly / lifetime caps, global 3000 XP/day and 1500 coins/day caps, idempotency key kept.
-- 2. nx_purchase only sells active, coin-priced items that exist in nx_catalog; the client price is never used.
-- 3. nx_import_local no longer imports coins; XP import capped at 2000 (once per account).
-- 4. Clients can no longer UPDATE profiles.coins / gems / xp / level / role ...: table-level UPDATE is revoked and only
--    cosmetic columns are re-granted. A BEFORE INSERT/UPDATE trigger also pins the economy columns for client roles
--    (defence in depth: a column-level REVOKE does not remove a table-level GRANT in Postgres).
-- 5. nx_profiles: the client still upserts its data blob, but a BEFORE INSERT/UPDATE trigger keeps the server-owned
--    parts (data->'inv' except free catalog items, data->'gems', imported, gems_welcome, gems_daily).
--
-- "Trusted" = the statement does not run as a client role (anon / authenticated), i.e. it runs inside a SECURITY
-- DEFINER function owned by postgres, or as service_role / postgres / supabase_admin; or the transaction-local GUC
-- nx.trusted = '1' (set by the definer functions below as an explicit marker).

-- ------------------------------------------------------------------------------------------------ trust helper
create or replace function public._nx_trusted() returns boolean
language sql stable set search_path = public as $$
  select current_user not in ('anon', 'authenticated')
      or coalesce(current_setting('nx.trusted', true), '') = '1'
      or coalesce(current_setting('nx.bridge', true), '') = '1'
$$;
-- Must stay SECURITY INVOKER: it inspects current_user of the caller. Executable by client roles because the guard
-- triggers below run as the client; it reveals nothing and grants nothing.
revoke all on function public._nx_trusted() from public;
grant execute on function public._nx_trusted() to anon, authenticated, service_role;

-- ------------------------------------------------------------------------------------------------ 1. reward rules
create table if not exists public.nx_reward_rules (
  event text primary key,                       -- exact event name, or a LIKE pattern when is_pattern
  xp int not null default 0,
  coins int not null default 0,
  daily_cap int,                                -- max grants of this rule per UTC day (null = no limit)
  weekly_cap int,                               -- max grants of this rule per ISO week (null = no limit)
  lifetime_cap int,                             -- max grants of this rule ever (null = no limit)
  is_pattern boolean not null default false,
  counts_to_cap boolean not null default true,  -- false: not limited by the global daily XP/coin caps
  active boolean default true,
  note text,
  updated_at timestamptz not null default now()
);
do $$ begin
  alter table public.nx_reward_rules add constraint nx_reward_rules_amounts_chk
    check (xp between 0 and 1000 and coins between 0 and 1000);
exception when duplicate_object then null; end $$;
alter table public.nx_reward_rules enable row level security;
drop policy if exists nx_reward_rules_read on public.nx_reward_rules;
create policy nx_reward_rules_read on public.nx_reward_rules for select to authenticated using (true);
revoke all on table public.nx_reward_rules from anon, authenticated;
grant select on table public.nx_reward_rules to authenticated;

alter table public.nx_xp_events add column if not exists rule text;
create index if not exists nx_xp_events_user_rule on public.nx_xp_events(user_id, rule, created_at);

-- Seed: the events the Flutter client actually sends (lib/**: ProfileService.award / _checkAchievements).
-- Amounts mirror what the client shows (so the wallet re-sync does not visibly claw back), but are now capped.
-- Existing rows are never overwritten (admins may tune them).
insert into public.nx_reward_rules(event, xp, coins, daily_cap, weekly_cap, lifetime_cap, is_pattern, counts_to_cap, note) values
  ('identity.created',        50,  0, null, null, 1,    false, true, 'onboarding_page.dart'),
  ('daily',                   25, 50, 1,    null, null, false, true, 'claimDaily; +10 coins per streak day (max 7) added server-side'),
  ('world.first_visit.%',     20, 10, null, null, 10,   true,  true, 'router.dart _WorldVisit (7 worlds)'),
  ('game.%.win',              60, 40, 25,   null, null, true,  true, 'ProfileService.recordGame (local / bot games)'),
  ('game.%.draw',             30, 15, 25,   null, null, true,  true, 'ProfileService.recordGame'),
  ('game.%.loss',             15,  5, 25,   null, null, true,  true, 'ProfileService.recordGame'),
  ('challenge.d_play3',       40, 30, 1,    null, null, false, true, 'personal_orbit challenges (daily)'),
  ('challenge.d_win1',        40, 35, 1,    null, null, false, true, 'personal_orbit challenges (daily)'),
  ('challenge.d_post1',       30, 20, 1,    null, null, false, true, 'personal_orbit challenges (daily)'),
  ('challenge.d_oracle2',     20, 15, 1,    null, null, false, true, 'personal_orbit challenges (daily)'),
  ('challenge.w_play15',     150,120, 1,    1,    null, false, true, 'personal_orbit challenges (weekly)'),
  ('challenge.w_win5',       160,140, 1,    1,    null, false, true, 'personal_orbit challenges (weekly)'),
  ('challenge.w_msg10',       90, 70, 1,    1,    null, false, true, 'personal_orbit challenges (weekly)'),
  ('challenge.w_shop1',       60,  0, 1,    1,    null, false, true, 'personal_orbit challenges (weekly)'),
  ('challenge.%',             80, 60, 1,    null, null, true,  true, 'arcade daily challenge: challenge.<id>.<day>'),
  ('nova.post',               12,  0, 10,   null, null, false, true, 'nova_composer.dart'),
  ('nova.story',               5,  0, 10,   null, null, false, true, 'nova_composer.dart'),
  ('oracle.ask',               3,  0, 20,   null, null, false, true, 'oracle_core_page.dart'),
  ('orbit.message',            2,  0, 50,   null, null, false, true, 'orbit_controller.dart'),
  ('orbit.create',            10,  0, 3,    null, null, false, true, 'orbit_sheets.dart'),
  ('social.create',           60, 10, 2,    null, null, false, true, 'community_create_sheet.dart'),
  ('social.tournament',       40, 15, 3,    null, null, false, true, 'tournament_bracket_view.dart'),
  -- achievements (lib/core/profile/achievements.dart coinReward), once per account, outside the daily caps
  ('achievement.identity',     0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.first_game',   0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.gamer',        0, 150, null, null, 1, false, false, 'achievement'),
  ('achievement.champion',     0, 150, null, null, 1, false, false, 'achievement'),
  ('achievement.crown',        0, 400, null, null, 1, false, false, 'achievement'),
  ('achievement.star_elite',   0, 200, null, null, 1, false, false, 'achievement'),
  ('achievement.all_games',    0, 250, null, null, 1, false, false, 'achievement'),
  ('achievement.explorer',     0, 120, null, null, 1, false, false, 'achievement'),
  ('achievement.daily',        0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.idea',         0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.team',         0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.decorator',    0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.creator',      0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.collector',    0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.chatter',      0,  50, null, null, 1, false, false, 'achievement'),
  ('achievement.summit',       0, 200, null, null, 1, false, false, 'achievement'),
  ('achievement.legend',       0, 500, null, null, 1, false, false, 'achievement'),
  ('achievement.arcade_rookie',0, 120, null, null, 1, false, false, 'achievement'),
  ('achievement.arcade_all',   0, 400, null, null, 1, false, false, 'achievement'),
  ('achievement.arcade_gold',  0, 200, null, null, 1, false, false, 'achievement'),
  ('achievement.arcade_daily', 0, 200, null, null, 1, false, false, 'achievement'),
  ('achievement.racer',        0, 150, null, null, 1, false, false, 'achievement'),
  ('achievement.grandmaster',  0, 250, null, null, 1, false, false, 'achievement'),
  ('achievement.survivor',     0, 250, null, null, 1, false, false, 'achievement')
on conflict (event) do nothing;

-- Server-side XP/coin award. Signature unchanged for client compatibility; p_xp / p_coins are ignored.
create or replace function public.nx_award(p_event text, p_xp int, p_coins int, p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  ev text := left(coalesce(p_event, ''), 120);
  day0 timestamptz := date_trunc('day', now());
  rl nx_reward_rules;
  today_xp int; today_coins int; n int; streak int := 0;
  gx int; gc int;
  r record;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_key is null or length(p_key) < 4 then raise exception 'bad key'; end if;
  perform set_config('nx.trusted', '1', true);
  select p.xp, p.coins into r from profiles p where p.id = me;
  if exists (select 1 from nx_xp_events x where x.user_id = me and x.idem_key = p_key) then
    return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', true,
                              'granted', 0, 'reason', 'duplicate');
  end if;
  if nx_is_banned(me) then
    return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', false,
                              'granted', 0, 'reason', 'banned');
  end if;
  if ev !~ '^[A-Za-z0-9_.:-]{1,120}$' then
    rl := null;
  else
    select * into rl from nx_reward_rules
     where coalesce(nx_reward_rules.active, true)
       and ((not nx_reward_rules.is_pattern and nx_reward_rules.event = ev)
            or (nx_reward_rules.is_pattern and ev like nx_reward_rules.event))
     order by nx_reward_rules.is_pattern, length(nx_reward_rules.event) desc
     limit 1;
  end if;
  if rl.event is null then
    return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', false,
                              'granted', 0, 'reason', 'unknown_event');
  end if;

  -- per-rule caps
  if rl.daily_cap is not null then
    select count(*) into n from nx_xp_events x where x.user_id = me and x.rule = rl.event and x.created_at >= day0;
    if n >= rl.daily_cap then
      return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', false,
                                'granted', 0, 'reason', 'rule_daily_cap');
    end if;
  end if;
  if rl.weekly_cap is not null then
    select count(*) into n from nx_xp_events x where x.user_id = me and x.rule = rl.event
       and x.created_at >= date_trunc('week', now());
    if n >= rl.weekly_cap then
      return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', false,
                                'granted', 0, 'reason', 'rule_weekly_cap');
    end if;
  end if;
  if rl.lifetime_cap is not null then
    select count(*) into n from nx_xp_events x where x.user_id = me and x.rule = rl.event;
    if n >= rl.lifetime_cap then
      return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', false,
                                'granted', 0, 'reason', 'rule_lifetime_cap');
    end if;
  end if;

  gx := greatest(0, rl.xp);
  gc := greatest(0, rl.coins);
  -- daily reward: streak bonus computed from the server's own history (+10 per consecutive day, max 7)
  if rl.event = 'daily' then
    streak := 1;
    while streak < 7 and exists (
      select 1 from nx_xp_events x
       where x.user_id = me and x.rule = 'daily'
         and x.created_at >= day0 - make_interval(days => streak)
         and x.created_at <  day0 - make_interval(days => streak - 1)) loop
      streak := streak + 1;
    end loop;
    gc := gc + least(streak, 7) * 10;
  end if;

  -- global daily caps (3000 XP, 1500 coins), achievements excluded
  if rl.counts_to_cap then
    select coalesce(sum(e.xp), 0), coalesce(sum(e.coins), 0) into today_xp, today_coins
      from nx_xp_events e
      left join nx_reward_rules rr on rr.event = e.rule
     where e.user_id = me and e.created_at >= day0 and coalesce(rr.counts_to_cap, true);
    gx := greatest(0, least(gx, 3000 - today_xp));
    gc := greatest(0, least(gc, 1500 - today_coins));
  end if;

  insert into nx_xp_events(user_id, idem_key, event, xp, coins, rule) values (me, p_key, ev, gx, gc, rl.event);
  if gx > 0 or gc > 0 then
    update profiles set xp = xp + gx, coins = coins + gc, level = level_for_xp(xp + gx) where id = me
      returning xp, coins into r;
  end if;
  if gx > 0 then insert into xp_events(user_id, amount, reason) values (me, gx, 'nexora:' || left(ev, 100)); end if;
  return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', gx, 'granted_coins', gc, 'dup', false,
                            'granted', gx + gc, 'reason', case when gx + gc > 0 then 'ok' else 'daily_cap' end);
end $$;

-- ------------------------------------------------------------------------------------------------ 2. purchase
-- Coins purchase: only active, coin-priced catalog items. p_price is ignored (kept for the signature).
create or replace function public.nx_purchase(p_item text, p_price int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); it nx_catalog; c int; inv jsonb;
begin
  if me is null then raise exception 'not signed in'; end if;
  perform set_config('nx.trusted', '1', true);
  if nx_is_banned(me) then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', false, 'coins', c, 'error', 'banned');
  end if;
  select * into it from nx_catalog where item_id = p_item;
  if it.item_id is null or not coalesce(it.active, true) or coalesce(it.currency, 'coins') <> 'coins'
     or p_item like 'fs_team:%' or it.price is null or it.price < 0 then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', false, 'coins', c, 'error', 'not_for_sale');
  end if;
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  select coalesce(data -> 'inv', '[]'::jsonb) into inv from nx_profiles where id = me for update;
  if jsonb_typeof(inv) <> 'array' then inv := '[]'::jsonb; end if;
  if inv ? p_item then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', true, 'coins', c, 'owned', true);
  end if;
  update profiles set coins = coins - it.price where id = me and coins >= it.price returning coins into c;
  if c is null then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', false, 'coins', c, 'error', 'insufficient_coins', 'price', it.price);
  end if;
  update nx_profiles set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inv}', inv || to_jsonb(p_item)), updated_at = now()
   where id = me;
  return jsonb_build_object('ok', true, 'coins', c, 'price', it.price);
end $$;

-- ------------------------------------------------------------------------------------------------ 3. import
-- One-time import of offline progress: no coins, at most 2000 XP. Signature unchanged.
create or replace function public.nx_import_local(p_xp int, p_coins int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); done boolean; r record;
begin
  if me is null then raise exception 'not signed in'; end if;
  perform set_config('nx.trusted', '1', true);
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  select imported into done from nx_profiles where id = me for update;
  if not done then
    update profiles set xp = greatest(xp, least(greatest(coalesce(p_xp, 0), 0), 2000)) where id = me;
    update profiles set level = level_for_xp(xp) where id = me;
    update nx_profiles set imported = true, updated_at = now() where id = me;
  end if;
  select xp, coins, username into r from profiles where id = me;
  return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'username', r.username, 'imported_now', not done);
end $$;

revoke all on function public.nx_award(text, int, int, text), public.nx_purchase(text, int),
  public.nx_import_local(int, int) from public, anon;
grant execute on function public.nx_award(text, int, int, text), public.nx_purchase(text, int),
  public.nx_import_local(int, int) to authenticated;

-- ------------------------------------------------------------------------------------------------ 4. profiles
-- Table-level UPDATE removed from client roles; only cosmetic columns the apps write directly are re-granted
-- (Flutter: bio, avatar_url, avatar_path — cloud_profile_sync.dart). username and the other cosmetic columns are listed
-- for the sibling app sharing this table (Flutter itself sets username via nx_set_username); each grant only happens if
-- the column exists. NOT granted: xp, coins, gems, level, role, is_guest, id.
revoke update on table public.profiles from anon, authenticated;
revoke insert on table public.profiles from anon;
do $$
declare col text;
begin
  foreach col in array array['username', 'bio', 'avatar', 'avatar_url', 'avatar_path', 'avatar_core', 'equipped', 'orbit_layout',
                             'orbit_theme', 'online_at', 'updated_at'] loop
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'profiles' and column_name = col) then
      execute format('grant update (%I) on table public.profiles to authenticated', col);
    end if;
  end loop;
end $$;

-- Defence in depth: client roles can never change the economy / role columns, whatever the grants say.
create or replace function public._nx_profiles_guard() returns trigger
language plpgsql set search_path = public as $$
declare j jsonb; o jsonb; k text;
begin
  if _nx_trusted() then return new; end if;
  j := to_jsonb(new);
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
    foreach k in array array['id', 'xp', 'coins', 'gems', 'level', 'role', 'is_guest'] loop
      if j ? k then j := jsonb_set(j, array[k], coalesce(o -> k, 'null'::jsonb)); end if;
    end loop;
  else
    if j ? 'xp' then j := jsonb_set(j, '{xp}', '0'); end if;
    if j ? 'coins' then j := jsonb_set(j, '{coins}', '0'); end if;
    if j ? 'gems' then j := jsonb_set(j, '{gems}', '0'); end if;
    if j ? 'level' then j := jsonb_set(j, '{level}', '1'); end if;
    if j ? 'role' then j := jsonb_set(j, '{role}', 'null'); end if;
  end if;
  new := jsonb_populate_record(new, j);
  return new;
end $$;
revoke all on function public._nx_profiles_guard() from public, anon, authenticated;
drop trigger if exists nx_profiles_guard_economy on public.profiles;
create trigger nx_profiles_guard_economy before insert or update on public.profiles
  for each row execute function public._nx_profiles_guard();

-- ------------------------------------------------------------------------------------------------ 5. nx_profiles
-- The client upserts nx_profiles (id, explorer_id, avatar_core, data, updated_at). Keep the server-owned parts:
--   data->'inv'  = OLD inventory ∪ (client inventory ∩ free, active catalog items)
--   data->'gems' = OLD value
--   imported, gems_welcome, gems_daily = OLD values (defaults on INSERT)
create or replace function public._nx_nx_profiles_guard() returns trigger
language plpgsql set search_path = public as $$
declare old_inv jsonb := '[]'::jsonb; new_inv jsonb; free_inv jsonb; d jsonb;
begin
  if _nx_trusted() then return new; end if;
  d := coalesce(new.data, '{}'::jsonb);
  if jsonb_typeof(d) <> 'object' then d := '{}'::jsonb; end if;
  new_inv := case when jsonb_typeof(d -> 'inv') = 'array' then d -> 'inv' else '[]'::jsonb end;
  select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into free_inv
    from jsonb_array_elements_text(new_inv) x
    join nx_catalog c on c.item_id = x
   where c.price = 0 and coalesce(c.active, true);
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.imported := old.imported;
    new.gems_welcome := old.gems_welcome;
    new.gems_daily := old.gems_daily;
    if jsonb_typeof(old.data -> 'inv') = 'array' then old_inv := old.data -> 'inv'; end if;
    select old_inv || coalesce(jsonb_agg(f), '[]'::jsonb) into new_inv
      from jsonb_array_elements(free_inv) f where not (old_inv @> jsonb_build_array(f));
    d := jsonb_set(d, '{inv}', new_inv);
    if old.data ? 'gems' then d := jsonb_set(d, '{gems}', old.data -> 'gems'); else d := d - 'gems'; end if;
  else
    new.imported := false;
    new.gems_welcome := false;
    new.gems_daily := null;
    d := jsonb_set(d, '{inv}', free_inv) - 'gems';
  end if;
  new.data := d;
  return new;
end $$;
revoke all on function public._nx_nx_profiles_guard() from public, anon, authenticated;
drop trigger if exists nx_profiles_guard_server_fields on public.nx_profiles;
create trigger nx_profiles_guard_server_fields before insert or update on public.nx_profiles
  for each row execute function public._nx_nx_profiles_guard();
