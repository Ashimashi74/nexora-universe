-- ANIX gems (الماس) + gem shop + finger-soccer team prices + admin economy/shop/player powers (auth project).
-- Idempotent; never drops data. Apply with the other migrations (see scripts/apply_supabase_live.sh).
--
-- * public.profiles.gems is the balance (server-owned; clients can only read it). A ledger (nx_gem_tx) records every
--   change made through these RPCs.
-- * nx_catalog gets a currency ('coins' | 'gems'), an active flag and a display name. Finger-soccer teams are
--   'fs_team:<team id>' rows priced in gems: Persepolis, Esteghlal and Iran are free, every other team 150..500 gems by
--   strength (same formula as lib/core/economy/gem_shop.dart defaultTeamPrice). Admins with the new 'shop' permission
--   edit prices; the seed below never overwrites a price that already exists.
-- * nx_buy_with_gems: price from the catalog only (never from the client), atomic deduct + unlock.
-- * nx_purchase (coins) refuses gem-priced items, so a gem item can't be bought with coins or a client price.

alter table public.profiles add column if not exists gems integer not null default 0;
do $$ begin
  alter table public.profiles add constraint profiles_gems_nonneg check (gems >= 0) not valid;
exception when duplicate_object then null; end $$;

alter table public.nx_catalog add column if not exists currency text not null default 'coins';
alter table public.nx_catalog add column if not exists active boolean not null default true;
alter table public.nx_catalog add column if not exists kind text not null default 'item';
alter table public.nx_catalog add column if not exists name text;
alter table public.nx_catalog add column if not exists updated_at timestamptz not null default now();
do $$ begin
  alter table public.nx_catalog add constraint nx_catalog_currency_chk check (currency in ('coins', 'gems'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.nx_catalog add constraint nx_catalog_price_chk check (price >= 0 and price <= 1000000) not valid;
exception when duplicate_object then null; end $$;

alter table public.nx_profiles add column if not exists gems_welcome boolean not null default false;
alter table public.nx_profiles add column if not exists gems_daily date;

create table if not exists public.nx_gem_tx (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta integer not null,
  balance integer not null,
  reason text not null,
  item text,
  actor uuid,
  created_at timestamptz not null default now()
);
create index if not exists nx_gem_tx_user_time on public.nx_gem_tx(user_id, created_at desc);
alter table public.nx_gem_tx enable row level security;
drop policy if exists nx_gem_tx_read on public.nx_gem_tx;
create policy nx_gem_tx_read on public.nx_gem_tx for select to authenticated using (user_id = auth.uid());

-- Team prices (gems). Free teams are priced 0 (always unlocked).
insert into public.nx_catalog(item_id, price, currency, kind, name) values
  ('fs_team:club0', 440, 'gems', 'team', 'Real Madrid'),
  ('fs_team:club1', 440, 'gems', 'team', 'Barcelona'),
  ('fs_team:club2', 440, 'gems', 'team', 'Manchester City'),
  ('fs_team:club3', 340, 'gems', 'team', 'Manchester United'),
  ('fs_team:club4', 400, 'gems', 'team', 'Liverpool'),
  ('fs_team:club5', 370, 'gems', 'team', 'Arsenal'),
  ('fs_team:club6', 340, 'gems', 'team', 'Chelsea'),
  ('fs_team:club7', 400, 'gems', 'team', 'Bayern Munich'),
  ('fs_team:club8', 340, 'gems', 'team', 'Borussia Dortmund'),
  ('fs_team:club9', 400, 'gems', 'team', 'Paris Saint-Germain'),
  ('fs_team:club10', 370, 'gems', 'team', 'Inter Milan'),
  ('fs_team:club11', 340, 'gems', 'team', 'AC Milan'),
  ('fs_team:club12', 370, 'gems', 'team', 'Juventus'),
  ('fs_team:club13', 370, 'gems', 'team', 'Atletico Madrid'),
  ('fs_team:club14', 310, 'gems', 'team', 'Ajax'),
  ('fs_team:club15', 310, 'gems', 'team', 'Benfica'),
  ('fs_team:club16', 280, 'gems', 'team', 'Porto'),
  ('fs_team:club17', 280, 'gems', 'team', 'Boca Juniors'),
  ('fs_team:club18', 310, 'gems', 'team', 'River Plate'),
  ('fs_team:club19', 280, 'gems', 'team', 'Flamengo'),
  ('fs_team:club20', 280, 'gems', 'team', 'Al Nassr'),
  ('fs_team:club21', 310, 'gems', 'team', 'Al Hilal'),
  ('fs_team:club22', 310, 'gems', 'team', 'Roma'),
  ('fs_team:club23', 250, 'gems', 'team', 'Besiktas'),
  ('fs_team:club24', 340, 'gems', 'team', 'Tottenham'),
  ('fs_team:club25', 280, 'gems', 'team', 'Marseille'),
  ('fs_team:club26', 340, 'gems', 'team', 'Napoli'),
  ('fs_team:club27', 310, 'gems', 'team', 'Sporting CP'),
  ('fs_team:club28', 280, 'gems', 'team', 'Sevilla'),
  ('fs_team:club29', 250, 'gems', 'team', 'Valencia'),
  ('fs_team:club30', 280, 'gems', 'team', 'PSV'),
  ('fs_team:club31', 340, 'gems', 'team', 'Newcastle'),
  ('fs_team:club32', 0, 'gems', 'team', 'Persepolis'),
  ('fs_team:club33', 0, 'gems', 'team', 'Esteghlal'),
  ('fs_team:club34', 280, 'gems', 'team', 'Inter Miami'),
  ('fs_team:club35', 250, 'gems', 'team', 'Wolfsburg'),
  ('fs_team:club36', 280, 'gems', 'team', 'Shakhtar Donetsk'),
  ('fs_team:club37', 250, 'gems', 'team', 'Celtic'),
  ('fs_team:club38', 210, 'gems', 'team', 'Rangers'),
  ('fs_team:club39', 280, 'gems', 'team', 'Monaco'),
  ('fs_team:nat0', 440, 'gems', 'team', 'Argentina'),
  ('fs_team:nat1', 400, 'gems', 'team', 'Brazil'),
  ('fs_team:nat2', 440, 'gems', 'team', 'France'),
  ('fs_team:nat3', 400, 'gems', 'team', 'Germany'),
  ('fs_team:nat4', 400, 'gems', 'team', 'Portugal'),
  ('fs_team:nat5', 440, 'gems', 'team', 'Spain'),
  ('fs_team:nat6', 370, 'gems', 'team', 'Italy'),
  ('fs_team:nat7', 400, 'gems', 'team', 'England'),
  ('fs_team:nat8', 370, 'gems', 'team', 'Netherlands'),
  ('fs_team:nat9', 340, 'gems', 'team', 'Belgium'),
  ('fs_team:nat10', 340, 'gems', 'team', 'Uruguay'),
  ('fs_team:nat11', 280, 'gems', 'team', 'Sweden'),
  ('fs_team:nat12', 280, 'gems', 'team', 'Poland'),
  ('fs_team:nat13', 310, 'gems', 'team', 'Denmark'),
  ('fs_team:nat14', 370, 'gems', 'team', 'Croatia'),
  ('fs_team:nat15', 310, 'gems', 'team', 'Switzerland'),
  ('fs_team:nat16', 280, 'gems', 'team', 'Mexico'),
  ('fs_team:nat17', 280, 'gems', 'team', 'USA'),
  ('fs_team:nat18', 340, 'gems', 'team', 'Japan'),
  ('fs_team:nat19', 310, 'gems', 'team', 'South Korea'),
  ('fs_team:nat20', 250, 'gems', 'team', 'Australia'),
  ('fs_team:nat21', 280, 'gems', 'team', 'Senegal'),
  ('fs_team:nat22', 340, 'gems', 'team', 'Morocco'),
  ('fs_team:nat23', 250, 'gems', 'team', 'Tunisia'),
  ('fs_team:nat24', 250, 'gems', 'team', 'Egypt'),
  ('fs_team:nat25', 210, 'gems', 'team', 'Iceland'),
  ('fs_team:nat26', 0, 'gems', 'team', 'Iran'),
  ('fs_team:nat27', 210, 'gems', 'team', 'Qatar'),
  ('fs_team:nat28', 210, 'gems', 'team', 'Saudi Arabia'),
  ('fs_team:nat29', 340, 'gems', 'team', 'Colombia'),
  ('fs_team:nat30', 150, 'gems', 'team', 'Lebanon'),
  ('fs_team:lux0', 500, 'gems', 'team', 'Louis Vuitton'),
  ('fs_team:lux1', 500, 'gems', 'team', 'Chanel'),
  ('fs_team:lux2', 500, 'gems', 'team', 'Gucci'),
  ('fs_team:lux3', 500, 'gems', 'team', 'Hermes'),
  ('fs_team:lux4', 500, 'gems', 'team', 'Prada'),
  ('fs_team:lux5', 500, 'gems', 'team', 'Dior'),
  ('fs_team:lux6', 500, 'gems', 'team', 'Versace'),
  ('fs_team:lux7', 500, 'gems', 'team', 'Rolex'),
  ('fs_team:lux8', 500, 'gems', 'team', 'Cartier'),
  ('fs_team:lux9', 500, 'gems', 'team', 'Fendi'),
  ('fs_team:lux10', 500, 'gems', 'team', 'Valentino'),
  ('fs_team:lux11', 500, 'gems', 'team', 'Burberry'),
  ('fs_team:lux12', 500, 'gems', 'team', 'Saint Laurent'),
  ('fs_team:lux13', 500, 'gems', 'team', 'Swarovski'),
  ('fs_team:car0', 500, 'gems', 'team', 'Lamborghini'),
  ('fs_team:car1', 500, 'gems', 'team', 'Ferrari'),
  ('fs_team:car2', 500, 'gems', 'team', 'Rolls-Royce'),
  ('fs_team:car3', 500, 'gems', 'team', 'Mercedes-Benz'),
  ('fs_team:car4', 500, 'gems', 'team', 'BMW'),
  ('fs_team:car5', 500, 'gems', 'team', 'Porsche'),
  ('fs_team:car6', 500, 'gems', 'team', 'Maserati'),
  ('fs_team:car7', 500, 'gems', 'team', 'Aston Martin'),
  ('fs_team:car8', 500, 'gems', 'team', 'Bentley'),
  ('fs_team:car9', 500, 'gems', 'team', 'Bugatti'),
  ('fs_team:car10', 500, 'gems', 'team', 'Lexus'),
  ('fs_team:car11', 500, 'gems', 'team', 'Cadillac'),
  ('fs_team:car12', 500, 'gems', 'team', 'McLaren'),
  ('fs_team:car13', 500, 'gems', 'team', 'Tesla'),
  ('fs_team:spt0', 500, 'gems', 'team', 'Nike'),
  ('fs_team:spt1', 500, 'gems', 'team', 'Adidas'),
  ('fs_team:spt2', 500, 'gems', 'team', 'Puma'),
  ('fs_team:spt3', 500, 'gems', 'team', 'Under Armour'),
  ('fs_team:spt4', 500, 'gems', 'team', 'New Balance'),
  ('fs_team:spt5', 500, 'gems', 'team', 'Reebok'),
  ('fs_team:spt6', 500, 'gems', 'team', 'Jordan'),
  ('fs_team:spt7', 500, 'gems', 'team', 'Asics'),
  ('fs_team:spt8', 500, 'gems', 'team', 'Wilson'),
  ('fs_team:spt9', 500, 'gems', 'team', 'Speedo'),
  ('fs_team:spt10', 500, 'gems', 'team', 'Converse'),
  ('fs_team:spt11', 500, 'gems', 'team', 'Vans'),
  ('fs_team:spt12', 500, 'gems', 'team', 'NBA'),
  ('fs_team:spt13', 500, 'gems', 'team', 'Umbro'),
  ('fs_team:barca_gold', 500, 'gems', 'team', 'Barcelona Gold')
on conflict (item_id) do nothing;

-- New admin permission 'shop' (prices / shop items).
create or replace function public.nx_admin_perm_list() returns text[] language sql immutable as $$
  select array['users', 'currency', 'tournaments', 'moderation', 'rooms', 'announcements', 'oracle', 'admins', 'shop']
$$;

-- ---------------------------------------------------------------------------------------------------------- player
-- Balance + one-time welcome gems (200) for every non-guest account.
create or replace function public.nx_wallet() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid(); r record; anon boolean;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select coalesce(is_anonymous, false) into anon from auth.users where id = me;
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  if not coalesce(anon, true) and not nx_is_banned(me)
     and exists (select 1 from nx_profiles where id = me and not gems_welcome) then
    update nx_profiles set gems_welcome = true, updated_at = now() where id = me and not gems_welcome;
    if found then
      update profiles set gems = coalesce(gems, 0) + 200 where id = me returning gems into r;
      if r.gems is not null then
        insert into nx_gem_tx(user_id, delta, balance, reason) values (me, 200, r.gems, 'welcome');
      end if;
    end if;
  end if;
  select xp, coins, coalesce(gems, 0) as gems, level into r from profiles where id = me;
  return jsonb_build_object('ok', true, 'xp', r.xp, 'coins', r.coins, 'gems', r.gems, 'level', r.level);
end $$;

-- Daily free gems: 10 a day (once per UTC day), non-guests only.
create or replace function public.nx_daily_gems() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid(); bal integer; anon boolean; today date := (now() at time zone 'utc')::date;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if nx_is_banned(me) then return jsonb_build_object('ok', false, 'error', 'banned'); end if;
  select coalesce(is_anonymous, false) into anon from auth.users where id = me;
  if coalesce(anon, true) then return jsonb_build_object('ok', false, 'error', 'account_required'); end if;
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  update nx_profiles set gems_daily = today, updated_at = now()
   where id = me and (gems_daily is null or gems_daily < today);
  if not found then
    select coalesce(gems, 0) into bal from profiles where id = me;
    return jsonb_build_object('ok', true, 'granted', 0, 'gems', bal, 'already', true);
  end if;
  update profiles set gems = coalesce(gems, 0) + 10 where id = me returning gems into bal;
  insert into nx_gem_tx(user_id, delta, balance, reason) values (me, 10, bal, 'daily');
  return jsonb_build_object('ok', true, 'granted', 10, 'gems', bal);
end $$;

-- Buy a gem-priced catalog item (finger-soccer team, ...). Price comes from nx_catalog only.
create or replace function public.nx_buy_with_gems(p_item text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); it nx_catalog; inv jsonb; bal integer;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if nx_is_banned(me) then return jsonb_build_object('ok', false, 'error', 'banned'); end if;
  select * into it from nx_catalog where item_id = p_item;
  if it.item_id is null or it.currency <> 'gems' or not it.active then
    select coalesce(gems, 0) into bal from profiles where id = me;
    return jsonb_build_object('ok', false, 'error', 'not_for_sale', 'gems', bal);
  end if;
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  select coalesce(data -> 'inv', '[]'::jsonb) into inv from nx_profiles where id = me for update;
  if inv ? p_item then
    select coalesce(gems, 0) into bal from profiles where id = me;
    return jsonb_build_object('ok', true, 'owned', true, 'gems', bal);
  end if;
  if it.price > 0 then
    update profiles set gems = gems - it.price where id = me and coalesce(gems, 0) >= it.price returning gems into bal;
    if bal is null then
      select coalesce(gems, 0) into bal from profiles where id = me;
      return jsonb_build_object('ok', false, 'error', 'insufficient_gems', 'gems', bal, 'price', it.price);
    end if;
    insert into nx_gem_tx(user_id, delta, balance, reason, item) values (me, -it.price, bal, 'purchase', p_item);
  else
    select coalesce(gems, 0) into bal from profiles where id = me;
  end if;
  update nx_profiles set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inv}', inv || to_jsonb(p_item)), updated_at = now()
   where id = me;
  return jsonb_build_object('ok', true, 'gems', bal, 'price', it.price, 'item', p_item);
end $$;

-- Coins purchase: gem-priced or inactive catalog items (and any 'fs_team:' id) are not sold for coins.
create or replace function public.nx_purchase(p_item text, p_price int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); it nx_catalog; cat int; c int; d jsonb;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into it from nx_catalog where item_id = p_item;
  if p_item like 'fs_team:%' or (it.item_id is not null and (it.currency = 'gems' or not it.active)) then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', false, 'coins', c, 'error', 'not_for_sale');
  end if;
  cat := it.price;
  if cat is null then
    if p_price is null or p_price < 1 or p_price > 5000 then raise exception 'bad price'; end if;
    cat := p_price;
  end if;
  select data into d from nx_profiles where id = me;
  if d is not null and (d->'inv') ? p_item then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', true, 'coins', c, 'owned', true);
  end if;
  update profiles set coins = coins - cat where id = me and coins >= cat returning coins into c;
  if c is null then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', false, 'coins', c);
  end if;
  insert into nx_profiles(id, data) values (me, jsonb_build_object('inv', jsonb_build_array(p_item)))
  on conflict (id) do update set
    data = jsonb_set(coalesce(nx_profiles.data, '{}'::jsonb), '{inv}', coalesce(nx_profiles.data->'inv', '[]'::jsonb) || to_jsonb(p_item)),
    updated_at = now();
  return jsonb_build_object('ok', true, 'coins', c, 'price', cat);
end $$;

-- ----------------------------------------------------------------------------------------------------------- admin
-- Grant (+) / take (-) coins and gems: permission 'currency' (the owner-only nx_owner_grant stays). Non-owners are
-- capped at 100000 per call. Balances never go below zero; every change is audited + in the gem ledger.
create or replace function public.nx_admin_grant_wallet(p_user uuid, p_coins integer, p_gems integer,
                                                        p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('currency'); c int := coalesce(p_coins, 0); gm int := coalesce(p_gems, 0);
        cap int := case when nx_is_owner(auth.uid()) then 10000000 else 100000 end; r record;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if abs(c) > cap or abs(gm) > cap then return jsonb_build_object('ok', false, 'error', 'amount_too_large'); end if;
  if c = 0 and gm = 0 then return jsonb_build_object('ok', false, 'error', 'zero_amount'); end if;
  update profiles set coins = coins + c, gems = coalesce(gems, 0) + gm
   where id = p_user and coins + c >= 0 and coalesce(gems, 0) + gm >= 0 returning coins, gems into r;
  if not found then
    if not exists (select 1 from profiles where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance');
  end if;
  if gm <> 0 then
    insert into nx_gem_tx(user_id, delta, balance, reason, actor) values (p_user, gm, r.gems, 'admin:' || left(coalesce(p_reason, ''), 80), auth.uid());
  end if;
  perform _nx_owner_log('grant', p_user, jsonb_build_object('coins', c, 'gems', gm, 'reason', p_reason,
                                                             'balance_coins', r.coins, 'balance_gems', r.gems));
  return jsonb_build_object('ok', true, 'coins', r.coins, 'gems', r.gems);
end $$;

-- Set exact balances / XP (null = leave as is): permission 'currency'.
create or replace function public.nx_admin_set_wallet(p_user uuid, p_coins integer default null, p_gems integer default null,
                                                      p_xp integer default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('currency'); old record; r record;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if coalesce(p_coins, 0) < 0 or coalesce(p_gems, 0) < 0 or coalesce(p_xp, 0) < 0
     or coalesce(p_coins, 0) > 100000000 or coalesce(p_gems, 0) > 100000000 or coalesce(p_xp, 0) > 100000000 then
    return jsonb_build_object('ok', false, 'error', 'bad_amount'); end if;
  if nx_is_owner(p_user) and not nx_is_owner(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select coins, coalesce(gems, 0) as gems, xp into old from profiles where id = p_user for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  update profiles set coins = coalesce(p_coins, coins), gems = coalesce(p_gems, gems), xp = coalesce(p_xp, xp),
         level = level_for_xp(coalesce(p_xp, xp))
   where id = p_user returning coins, gems, xp, level into r;
  if r.gems <> old.gems then
    insert into nx_gem_tx(user_id, delta, balance, reason, actor) values (p_user, r.gems - old.gems, r.gems, 'admin_set', auth.uid());
  end if;
  perform _nx_owner_log('set_wallet', p_user, jsonb_build_object('from', to_jsonb(old), 'coins', r.coins, 'gems', r.gems,
                                                                  'xp', r.xp, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'coins', r.coins, 'gems', r.gems, 'xp', r.xp, 'level', r.level);
end $$;

-- Full player view: account, wallet, flags, staff, inventory/equipped, profile blob summary, gem ledger, audit trail.
create or replace function public.nx_admin_player(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare g text := _nx_admin_guard('users'); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if not exists (select 1 from auth.users where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select jsonb_build_object(
    'ok', true,
    'id', u.id, 'email', u.email, 'guest', coalesce(u.is_anonymous, false), 'created_at', u.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'username', p.username, 'xp', coalesce(p.xp, 0), 'level', coalesce(p.level, 1), 'coins', coalesce(p.coins, 0),
    'gems', coalesce(p.gems, 0),
    'role', case when nx_is_owner(u.id) then 'owner' else coalesce(s.role, 'player') end,
    'perms', coalesce((select perms from nx_admin_perms a where a.user_id = u.id), '{}'),
    'banned', coalesce(f.banned, false), 'ban_reason', f.ban_reason,
    'muted_until', case when f.muted_until > now() then f.muted_until end,
    'inv', coalesce(n.data -> 'inv', '[]'::jsonb),
    'equipped', coalesce(n.data -> 'equipped', '{}'::jsonb),
    'bio', coalesce(n.data ->> 'bio', ''),
    'stats', coalesce(n.data -> 'stats', '{}'::jsonb),
    'gem_tx', coalesce((select jsonb_agg(t order by t.created_at desc) from (
        select delta, balance, reason, item, created_at from nx_gem_tx where user_id = u.id
        order by created_at desc limit 40) t), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(a order by a.created_at desc) from (
        select action, data, created_at, actor from nx_owner_audit where target = u.id
        order by created_at desc limit 40) a), '[]'::jsonb))
  into res
  from auth.users u
  left join profiles p on p.id = u.id
  left join nx_staff s on s.user_id = u.id
  left join nx_account_flags f on f.user_id = u.id
  left join nx_profiles n on n.id = u.id
  where u.id = p_user;
  return res;
end $$;

-- Replace a player's whole inventory (item ids) and/or patch profile fields (bio, portrait, equipped):
-- permission 'currency' for inventory, 'users' for profile fields.
create or replace function public.nx_admin_set_inventory(p_user uuid, p_items text[], p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('currency'); clean jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if not exists (select 1 from profiles where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if cardinality(coalesce(p_items, '{}')) > 2000 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  if exists (select 1 from unnest(coalesce(p_items, '{}')) x where x !~ '^[A-Za-z0-9_.:-]{1,64}$') then
    return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
  select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into clean from unnest(coalesce(p_items, '{}')) x;
  insert into nx_profiles(id, data) values (p_user, '{}'::jsonb) on conflict (id) do nothing;
  update nx_profiles set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inv}', clean), updated_at = now() where id = p_user;
  perform _nx_owner_log('set_inventory', p_user, jsonb_build_object('count', jsonb_array_length(clean), 'reason', p_reason));
  return jsonb_build_object('ok', true, 'inv', clean);
end $$;

create or replace function public.nx_admin_edit_profile(p_user uuid, p_patch jsonb, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('users'); k text; d jsonb := '{}'::jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if nx_is_owner(p_user) and not nx_is_owner(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if not exists (select 1 from profiles where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  for k in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if k not in ('bio', 'portrait', 'orbitTheme', 'equipped') then
      return jsonb_build_object('ok', false, 'error', 'bad_field'); end if;
  end loop;
  if p_patch ? 'bio' then d := d || jsonb_build_object('bio', left(coalesce(p_patch ->> 'bio', ''), 300)); end if;
  if p_patch ? 'portrait' then d := d || jsonb_build_object('portrait', left(coalesce(p_patch ->> 'portrait', ''), 64)); end if;
  if p_patch ? 'orbitTheme' then d := d || jsonb_build_object('orbitTheme', left(coalesce(p_patch ->> 'orbitTheme', ''), 64)); end if;
  if p_patch ? 'equipped' and jsonb_typeof(p_patch -> 'equipped') = 'object' then
    d := d || jsonb_build_object('equipped', p_patch -> 'equipped'); end if;
  insert into nx_profiles(id, data) values (p_user, '{}'::jsonb) on conflict (id) do nothing;
  update nx_profiles set data = coalesce(data, '{}'::jsonb) || d, updated_at = now() where id = p_user;
  perform _nx_owner_log('edit_profile', p_user, jsonb_build_object('fields', d, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

-- Banned players (permission 'users').
create or replace function public.nx_admin_banned(p_limit integer default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard('users');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true, 'users', coalesce((select jsonb_agg(x order by x.banned_at desc nulls last) from (
    select f.user_id as id, p.username, f.ban_reason, f.banned_at from nx_account_flags f left join profiles p on p.id = f.user_id
     where f.banned limit greatest(1, least(coalesce(p_limit, 200), 1000))) x), '[]'::jsonb));
end $$;

-- Shop / catalog management (permission 'shop').
create or replace function public.nx_admin_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard('shop');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true, 'items', coalesce((select jsonb_agg(to_jsonb(c) order by c.kind, c.item_id)
    from nx_catalog c), '[]'::jsonb));
end $$;

create or replace function public.nx_admin_set_price(p_item text, p_price integer, p_currency text default 'gems',
                                                     p_active boolean default true, p_name text default null,
                                                     p_kind text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('shop'); it text := btrim(coalesce(p_item, '')); old nx_catalog;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if it !~ '^[A-Za-z0-9_.:-]{1,64}$' then return jsonb_build_object('ok', false, 'error', 'bad_item'); end if;
  if p_price is null or p_price < 0 or p_price > 1000000 then return jsonb_build_object('ok', false, 'error', 'bad_price'); end if;
  if coalesce(p_currency, '') not in ('coins', 'gems') then return jsonb_build_object('ok', false, 'error', 'bad_currency'); end if;
  select * into old from nx_catalog where item_id = it;
  insert into nx_catalog(item_id, price, currency, active, name, kind, updated_at)
  values (it, p_price, p_currency, coalesce(p_active, true), p_name,
          coalesce(p_kind, case when it like 'fs_team:%' then 'team' else 'item' end), now())
  on conflict (item_id) do update set price = excluded.price, currency = excluded.currency, active = excluded.active,
    name = coalesce(excluded.name, nx_catalog.name), kind = coalesce(p_kind, nx_catalog.kind), updated_at = now();
  perform _nx_owner_log('set_price', null, jsonb_build_object('item', it, 'price', p_price, 'currency', p_currency,
    'active', coalesce(p_active, true), 'previous', to_jsonb(old)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_admin_delete_item(p_item text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('shop');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  delete from nx_catalog where item_id = p_item;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_owner_log('delete_item', null, jsonb_build_object('item', p_item));
  return jsonb_build_object('ok', true);
end $$;

-- Grants. Admin RPCs are callable by signed-in users and re-check permissions inside.
revoke all on function public.nx_wallet(), public.nx_daily_gems(), public.nx_buy_with_gems(text),
  public.nx_admin_grant_wallet(uuid, integer, integer, text), public.nx_admin_set_wallet(uuid, integer, integer, integer, text),
  public.nx_admin_player(uuid), public.nx_admin_set_inventory(uuid, text[], text), public.nx_admin_edit_profile(uuid, jsonb, text),
  public.nx_admin_banned(integer), public.nx_admin_catalog(),
  public.nx_admin_set_price(text, integer, text, boolean, text, text), public.nx_admin_delete_item(text) from public, anon;
grant execute on function public.nx_wallet(), public.nx_daily_gems(), public.nx_buy_with_gems(text),
  public.nx_admin_grant_wallet(uuid, integer, integer, text), public.nx_admin_set_wallet(uuid, integer, integer, integer, text),
  public.nx_admin_player(uuid), public.nx_admin_set_inventory(uuid, text[], text), public.nx_admin_edit_profile(uuid, jsonb, text),
  public.nx_admin_banned(integer), public.nx_admin_catalog(),
  public.nx_admin_set_price(text, integer, text, boolean, text, text), public.nx_admin_delete_item(text) to authenticated;
