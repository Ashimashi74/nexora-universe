-- Finger soccer: shared custom teams (تیم‌های اختصاصی).
-- * A player who bought `fs_custom_team` (1000 gems) creates ONE team from their own round crest
--   (uploaded to nx-media/<uid>/...). The team joins the shared list every authenticated player reads.
-- * Every custom team plays at power 10 / accuracy 10.
-- * Each team gets its own gem catalog row `fs_team:cx_<hex>` at 250 gems (trigger below), so the existing
--   nx_buy_with_gems / inventory flow sells it. The owner is granted it free on creation and nx_buy_with_gems
--   never charges the owner; a second purchase returns "owned" without charging (existing behaviour).
-- Idempotent.
begin;

create table if not exists public.fs_custom_teams (
  id uuid primary key default gen_random_uuid(),
  team_id text generated always as ('cx_' || replace(id::text, '-', '')) stored,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 24),
  crest_url text not null check (crest_url like 'https://%'),
  crest_path text not null,
  power smallint not null default 10 check (power = 10),
  accuracy smallint not null default 10 check (accuracy = 10),
  price integer not null default 250 check (price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists fs_custom_teams_team_id_key on public.fs_custom_teams(team_id);
-- one team per account (the fs_custom_team entitlement is a single inventory item)
create unique index if not exists fs_custom_teams_owner_key on public.fs_custom_teams(owner_id);

alter table public.fs_custom_teams enable row level security;
drop policy if exists fs_custom_teams_read on public.fs_custom_teams;
create policy fs_custom_teams_read on public.fs_custom_teams for select to authenticated using (active);
revoke all on public.fs_custom_teams from anon, authenticated;
grant select on public.fs_custom_teams to authenticated;

-- keep a 250-gem catalog row per team (inactive when the team is)
create or replace function public._fs_custom_team_catalog() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into nx_catalog(item_id, price, currency, kind, name, team_kind, active)
  values ('fs_team:' || new.team_id, new.price, 'gems', 'team', new.name, 'custom', new.active)
  on conflict (item_id) do update
    set price = excluded.price, currency = 'gems', kind = 'team', name = excluded.name, team_kind = 'custom',
        active = excluded.active, updated_at = now();
  return new;
end $$;
drop trigger if exists fs_custom_teams_catalog on public.fs_custom_teams;
create trigger fs_custom_teams_catalog after insert or update on public.fs_custom_teams
  for each row execute function public._fs_custom_team_catalog();

create or replace function public._fs_custom_team_json(t public.fs_custom_teams) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', t.id, 'team_id', t.team_id, 'owner_id', t.owner_id, 'name', t.name,
    'crest_url', t.crest_url, 'power', t.power, 'accuracy', t.accuracy, 'price', t.price, 'active', t.active)
$$;

-- crest must be the caller's own object in nx-media and the url must point at it
create or replace function public._fs_custom_crest_ok(me uuid, p_path text, p_url text) returns boolean
language sql stable security definer set search_path = public, storage as $$
  select p_path is not null and p_url is not null
     and split_part(p_path, '/', 1) = me::text
     and position('..' in p_path) = 0
     and p_url like 'https://%'
     and position('/storage/v1/object/public/nx-media/' || p_path in p_url) > 0
     and exists (select 1 from storage.objects o where o.bucket_id = 'nx-media' and o.name = p_path)
$$;

create or replace function public.fs_create_custom_team(p_name text, p_crest_path text, p_crest_url text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); inv jsonb; nm text; t fs_custom_teams;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if nx_is_banned(me) then return jsonb_build_object('ok', false, 'error', 'banned'); end if;
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  select coalesce(data -> 'inv', '[]'::jsonb) into inv from nx_profiles where id = me for update;
  if not inv ? 'fs_custom_team' then return jsonb_build_object('ok', false, 'error', 'not_purchased'); end if;
  select * into t from fs_custom_teams where owner_id = me;
  if t.id is not null then
    return jsonb_build_object('ok', false, 'error', 'already_created', 'team', _fs_custom_team_json(t));
  end if;
  if not _fs_custom_crest_ok(me, p_crest_path, p_crest_url) then
    return jsonb_build_object('ok', false, 'error', 'bad_crest');
  end if;
  nm := btrim(coalesce(p_name, ''));
  if nm = '' then
    select btrim(coalesce(nullif(display_name, ''), nullif(username, ''), '')) into nm from profiles where id = me;
  end if;
  if coalesce(nm, '') = '' then nm := 'Custom Team'; end if;
  nm := left(nm, 24);
  insert into fs_custom_teams(owner_id, name, crest_url, crest_path)
  values (me, nm, p_crest_url, p_crest_path) returning * into t;
  if not inv ? ('fs_team:' || t.team_id) then
    update nx_profiles set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inv}', inv || to_jsonb('fs_team:' || t.team_id)),
      updated_at = now() where id = me;
  end if;
  return jsonb_build_object('ok', true, 'team', _fs_custom_team_json(t));
end $$;

-- owner changes the crest and / or the name (free)
create or replace function public.fs_update_custom_team(p_name text, p_crest_path text, p_crest_url text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t fs_custom_teams; nm text;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if nx_is_banned(me) then return jsonb_build_object('ok', false, 'error', 'banned'); end if;
  select * into t from fs_custom_teams where owner_id = me for update;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'no_team'); end if;
  if p_crest_path is not null then
    if not _fs_custom_crest_ok(me, p_crest_path, p_crest_url) then
      return jsonb_build_object('ok', false, 'error', 'bad_crest');
    end if;
    t.crest_path := p_crest_path; t.crest_url := p_crest_url;
  end if;
  nm := left(btrim(coalesce(p_name, '')), 24);
  if nm <> '' then t.name := nm; end if;
  update fs_custom_teams set name = t.name, crest_url = t.crest_url, crest_path = t.crest_path, updated_at = now()
   where id = t.id returning * into t;
  return jsonb_build_object('ok', true, 'team', _fs_custom_team_json(t));
end $$;

revoke all on function public.fs_create_custom_team(text, text, text) from public, anon;
revoke all on function public.fs_update_custom_team(text, text, text) from public, anon;
grant execute on function public.fs_create_custom_team(text, text, text) to authenticated;
grant execute on function public.fs_update_custom_team(text, text, text) to authenticated;
revoke all on function public._fs_custom_crest_ok(uuid, text, text) from public, anon, authenticated;
revoke all on function public._fs_custom_team_catalog() from public, anon, authenticated;

-- nx_buy_with_gems: unchanged except that the owner of a custom team is never charged for it.
create or replace function public.nx_buy_with_gems(p_item text)
returns jsonb language plpgsql security definer set search_path = public as $function$
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
  -- the owner of a shared custom team fields it free: grant, never charge
  if p_item like 'fs\_team:cx\_%' and exists (
      select 1 from fs_custom_teams where 'fs_team:' || team_id = p_item and owner_id = me) then
    update nx_profiles set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inv}', inv || to_jsonb(p_item)), updated_at = now()
     where id = me;
    select coalesce(gems, 0) into bal from profiles where id = me;
    return jsonb_build_object('ok', true, 'owned', true, 'own_team', true, 'gems', bal, 'price', 0, 'item', p_item);
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
end $function$;

commit;
