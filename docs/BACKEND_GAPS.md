# NEXORA — BACKEND-DEPENDENT CAPABILITIES (UNIMPLEMENTED / SERVER-GATED)
_Deliverable §9. Honest list of capabilities that are not yet real. The app never simulates them — it shows disabled states, `OnlineOnlyNotice`, or truthful "needs server" explanations. No fake data, no fake success._

## 1. Not implemented at all (no client path, no backend)
| Capability | Current UI treatment |
|---|---|
| **Server-side account deletion** | `ProfileService.resetAll()` clears the **local** copy only. No delete RPC/Edge Function exists in `supabase/`. The Settings "Delete identity and all data" action clears local data and is labelled as such; full server-side deletion (profile, social, messages, media, storage, games-project mirror) is **not yet implemented** and must be built server-side before it can be claimed. Documented as required backend work. |
| **Voice/video calls (LiveKit)** | Call screen exists (`/call/:chatId`) and requests tokens through the trusted `nx-call-token` Edge Function — but with no LiveKit server connected, calls do not connect. The UI shows honest connecting/denied/unavailable states; no call is simulated. |
| **Real-user messaging** | Orbit Network conversation UI is fully built; sending to real users requires the server. Offline builds show `OnlineOnlyNotice`. |
| **Public Nova Gallery sharing** | Posts/stories compose and save locally; public publishing to other users requires the server. |
| **Online matchmaking / real opponents** | Online lobby, match link and host-authoritative settlement are built against the games project; with no server they stay offline (bots / pass-and-play). |
| **Global leaderboards / tournament settlement** | Leaderboard and tournament pages are built; authoritative rankings/brackets require the server. Local stats always shown in Personal Orbit. |

## 2. Implemented client-side, gated on server availability
| Capability | Gate |
|---|---|
| Sign-in / sign-up (username/email + password) | `OnlineService` — `not_configured` state when no Supabase config |
| Cloud profile sync | `CloudProfileSync` — runs after sign-in; offline = local-only |
| Rooms (talk + game lobbies), capacity rules | `room_capacity.dart` mirrors server `nx_room_capacity`; local fallback when RPC absent |
| Tournaments (create/manage/brackets/inbox/join codes) | Tournament repository + watcher; needs games project |
| Exchange purchases | `ProfileService.purchase` — offline = local wallet; online = server-confirmed (server refuses insufficient balance; client undoes local spend) |
| Oracle AI | On-device knowledge base; `nx-oracle` Edge Function exists for server mode but the client answers offline and says so |
| Admin panel / Oracle persona config | `AdminApi` server-checked; client role labels are never trusted |
| Updates | `AppUpdater` reads GitHub releases (`anix-*` tags, `ANIX-universal.apk` asset) |

## 3. Two-Supabase split (preserved, not collapsed)
- **Core project** (auth project): auth, profiles, social (follows/friend requests), Nova, chat, Oracle, admin, tournaments API.
- **Games project**: rooms, matchmaking, matches, leaderboards, tournament engine — no own auth; receives the auth project's access token.
- JWT, RLS and Edge Function boundaries preserved (`supabase/functions/nx-login`, `nx-call-token`, `nx-oracle`; games functions under `supabase/games/`). No service-role credentials or secrets in the client.

## 4. Required backend work before full deletion claim
1. `delete_account` RPC/Edge Function on the core project (auth + profiles + social + Nova + chat cascade).
2. Games-project mirror cleanup RPC (`nx_profiles` mirror, rooms, match history, leaderboard rows).
3. Media/storage cleanup policy (uploaded avatars/post media).
4. Client: call the deletion flow, show pending/success/failure truthfully — until then the UI only clears local data and says so.
