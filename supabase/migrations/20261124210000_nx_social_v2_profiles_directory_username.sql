-- Social v2: rich user profile preview, universal explorer search & directory, reliable username saving + bridge sync.

create or replace function public._nx_user_card(p_user uuid)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'display_name', coalesce(nullif(p.display_name, ''), p.username),
    'avatar', coalesce(p.avatar, 'club0'),
    'avatar_url', nullif(coalesce(p.avatar_url, ''), ''),
    'bio', coalesce(p.bio, ''),
    'level', coalesce(p.level, 1),
    'xp', coalesce(p.xp, 0),
    'online_at', p.online_at,
    'is_private', p.is_private,
    'is_following', exists (select 1 from follows f where f.follower = auth.uid() and f.followee = p.id),
    'follows_me', exists (select 1 from follows f where f.follower = p.id and f.followee = auth.uid()),
    'is_pending', exists (select 1 from nx_follow_requests q where q.requester = auth.uid() and q.target = p.id and q.status = 'pending'),
    'is_me', p.id = auth.uid()
  )
  from profiles p
  where p.id = p_user;
$function$;

create or replace function public.nx_social_profile(p_user uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  r record;
  me uuid := auth.uid();
  v boolean;
  ex_id text;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if p_user is null then raise exception 'bad_user'; end if;
  select p.* into r from profiles p where p.id = p_user;
  if not found then raise exception 'profile_not_found'; end if;
  select np.explorer_id into ex_id from nx_profiles np where np.id = p_user;
  v := public.nx_social_can_view(p_user);
  return jsonb_build_object(
    'id', r.id,
    'explorer_id', coalesce(ex_id, ''),
    'username', coalesce(r.username, ''),
    'display_name', coalesce(r.display_name, ''),
    'avatar', coalesce(r.avatar, 'club0'),
    'avatar_url', nullif(coalesce(r.avatar_url, ''), ''),
    'bio', coalesce(r.bio, ''),
    'website', coalesce(r.website, ''),
    'location', coalesce(r.location, ''),
    'level', coalesce(r.level, 1),
    'xp', coalesce(r.xp, 0),
    'wins', coalesce(r.wins, 0),
    'losses', coalesce(r.losses, 0),
    'draws', coalesce(r.draws, 0),
    'trophies', coalesce(r.trophies, 0),
    'league', coalesce(r.league, 'bronze'),
    'is_private', r.is_private,
    'created_at', r.created_at,
    'last_active', r.online_at,
    'followers', (select count(*)::int from follows f where f.followee = r.id),
    'following', (select count(*)::int from follows f where f.follower = r.id),
    'posts', (select count(*)::int from nx_posts x where x.author = r.id and x.kind = 'post'),
    'is_me', r.id = me,
    'is_following', exists (select 1 from follows f where f.follower = me and f.followee = r.id),
    'follows_me', exists (select 1 from follows f where f.follower = r.id and f.followee = me),
    'is_pending', exists (select 1 from nx_follow_requests q where q.requester = me and q.target = r.id and q.status = 'pending'),
    'is_blocked', public._nx_blocked(me, r.id),
    'can_view', v,
    'pending_requests', case when r.id = me then (select count(*)::int from nx_follow_requests q where q.target = me and q.status = 'pending') else 0 end
  );
end $function$;

create or replace function public.nx_social_search(p_q text, p_limit integer default 30)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  with q as (
    select lower(trim(regexp_replace(coalesce(p_q, ''), '[%_\\@]', '', 'g'))) s
  ),
  matched as (
    select p.id, p.username, p.online_at, q.s
    from profiles p
    cross join q
    left join nx_profiles np on np.id = p.id
    where p.id <> auth.uid()
      and not public._nx_blocked(auth.uid(), p.id)
      and (
        char_length(q.s) = 0
        or lower(p.username) like '%' || q.s || '%'
        or lower(coalesce(p.display_name, '')) like '%' || q.s || '%'
        or lower(coalesce(np.explorer_id, '')) like '%' || q.s || '%'
      )
    order by
      case when char_length(q.s) > 0 and lower(p.username) = q.s then 0
           when char_length(q.s) > 0 and lower(p.username) like q.s || '%' then 1
           else 2 end,
      p.online_at desc nulls last,
      lower(p.username) asc
    limit least(greatest(coalesce(p_limit, 30), 1), 60)
  )
  select coalesce(jsonb_agg(public._nx_user_card(m.id)), '[]'::jsonb)
  from matched m;
$function$;

create or replace function public.nx_set_username(p_name text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
  n text := trim(coalesce(p_name, ''));
begin
  if me is null then raise exception 'not signed in'; end if;
  if char_length(n) < 3 or char_length(n) > 20 then return 'bad_length'; end if;
  if n !~ '^[A-Za-z0-9_.]+$' then return 'bad_chars'; end if;
  if exists (select 1 from profiles where lower(username) = lower(n) and id <> me) then
    return 'taken';
  end if;
  perform set_config('nx.trusted', '1', true);
  update profiles
     set username = n,
         updated_at = now()
   where id = me;
  begin
    perform public.nx_bridge_push_profile(me);
  exception when others then
    null;
  end;
  return 'ok';
end $function$;

grant execute on function public._nx_user_card(uuid) to authenticated;
grant execute on function public.nx_social_profile(uuid) to authenticated;
grant execute on function public.nx_social_search(text, integer) to authenticated;
grant execute on function public.nx_set_username(text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['follows', 'nx_follow_requests', 'nx_social_notifications'] loop
    if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
