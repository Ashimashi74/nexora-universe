-- NEXORA social: profile likes (hearts) — additive to the existing follows.
-- Table guards against duplicate likes, RLS keeps writes to the liker,
-- and profile_like_stats gives each profile its like count (mirrors the profile_stats pattern).

create table if not exists public.profile_likes (
  liker uuid not null references auth.users(id) on delete cascade,
  liked uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (liker, liked)
);

create or replace view public.profile_like_stats as
  select liked as id, count(*)::int as likes
  from public.profile_likes
  group by liked;

alter table public.profile_likes enable row level security;

drop policy if exists profile_likes_select on public.profile_likes;
create policy profile_likes_select on public.profile_likes for select using (true);

drop policy if exists profile_likes_insert on public.profile_likes;
create policy profile_likes_insert on public.profile_likes for insert with check (auth.uid() = liker);

drop policy if exists profile_likes_delete on public.profile_likes;
create policy profile_likes_delete on public.profile_likes for delete using (auth.uid() = liker);

revoke all on table public.profile_likes from public, anon;
grant select, insert, delete on table public.profile_likes to authenticated;

revoke all on table public.profile_like_stats from public, anon;
grant select on table public.profile_like_stats to authenticated, anon;
