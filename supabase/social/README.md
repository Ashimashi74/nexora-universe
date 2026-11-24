# NEXORA Social Media Supabase Project (`SOCIAL_SUPABASE_URL`)

The Social Media stack (Feed & Stories / Nova Gallery, Direct & Group Messages / Orbit Network, Communities / Social Station, User Profiles, Follows, and Real-time Notifications) runs through the dedicated `OnlineService.social` client configured via:

- `--dart-define=SOCIAL_SUPABASE_URL=...`
- `--dart-define=SOCIAL_SUPABASE_ANON_KEY=...`

## Live Project Mapping (`ashikakero-collab` · `usedtcaxbxkkpkpttmke`)

The Supabase organization `ashikakero-collab` (`usedtcaxbxkkpkpttmke`) is on the Free Plan (2 active projects max), split cleanly by domain:

1. **Social & Auth Project (`eisstodgncimypdawisy`)**: `profiles`, `follows`, `nx_follow_requests`, `nx_posts`, `nx_post_likes`, `nx_post_comments`, `nx_post_saves`, `nx_chats`, `nx_chat_members`, `nx_messages`, `nx_communities`, `nx_social_notifications`, storage buckets (`avatars`, `nx-media`, `nx-chat-media`), and Edge Functions (`nx-call-token`, `nx-login`).
2. **Games & Multiplayer Project (`eyzafhrefnqlwcjpcdyg` · `nexora-games`)**: `nx_rooms`, `nx_room_players`, `nx_matches`, `nx_match_moves`, matchmaking queues, tournaments, and low-latency Realtime match channels.

If the organization upgrades past the 2-project Free Tier limit and provisions a dedicated 3rd project for Social:
1. Enable Asymmetric / Third-Party Auth trusting `https://eisstodgncimypdawisy.supabase.co/auth/v1`.
2. Apply the social schema migrations (`supabase/migrations/20261115000200_nx_social.sql`, `20261119000100_nx_chat_media.sql`, `20261124210000_nx_social_v2_profiles_directory_username.sql`).
3. Update `SOCIAL_SUPABASE_URL` and `SOCIAL_SUPABASE_ANON_KEY` in `.github/workflows/android.yml` (and `SOCIAL_SUPABASE_URL` / `SOCIAL_SUPABASE_ANON_KEY` secrets on `nx-call-token`). Zero Dart code changes are needed.
