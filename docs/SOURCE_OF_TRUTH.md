# NEXORA — SOURCE-OF-TRUTH MATRIX
_Required by master prompt §1. Feature | Existing Flutter page/service/route | Existing backend capability | Current state | New UI page(s) | Work required | Test._

## Legend
State: **Live** (works offline) · **Server-gated** (built, needs backend) · **Partial** · **Missing**.

| Feature | Flutter page / service / route | Backend capability | Current state | UI page(s) | Work required | Test |
|---|---|---|---|---|---|---|
| Boot / loading | `app.dart` + `/intro` | updater (GitHub releases) | Live | Intro video, orbital intro | none (done) | `app_updater_test.dart` |
| Auth (username/email+password) | `AuthPage` `/auth`, `OnlineService` | Supabase auth + `nx-login` fn | Server-gated (offline builds `not_configured`) | Auth page, sign-in-required | none (done) | auth flow tests in CI |
| Guest entry | `AuthPage` guest path, `auth_gate.dart` | none (offline-only, by design) | Live | Guest route + accurate notice | none (done) | guest access tests |
| Onboarding / identity | `OnboardingPage` `/onboarding`, `ProfileService` | local store; cloud sync after sign-in | Live (local) / Server-gated (sync) | Onboarding | none (done) | onboarding tests |
| Global shell / navigation | `NxWorldScaffold`, `Nx2Dock`, `nexora_menu.dart` | — | Live | Shell, Universe menu | none (done) | navigation tests |
| Hub / Station | `HubPage` `/hub`, `LuxeStationPage` `/station/:k` | live-rooms count from games project | Live (rooms chip server-gated) | Hub, directory | none (done) | hub navigation tests |
| Nova Gallery | `nova_gallery_page.dart` tabs, `NovaRepository` | local store; public sharing needs server | Live (local) / Server-gated (public) | Feed/Explore/Reels/Alerts/Profile, composer, story viewer | none (done) | `nova_test.dart` |
| Orbit Network | `orbit_network_page.dart`, `OrbitRepository` | chat/calls need server + LiveKit | Server-gated | Chats/Calls/Contacts, conversation, call page | none (done) | orbit tests in CI |
| Calls | `OrbitCallPage` `/call/:chatId`, `nx-call-token` fn | LiveKit (not connected in this build) | Missing (honest states) | Call screen | backend LiveKit | call permission tests |
| Nexora Arcade | `arcade_page.dart`, `game_setup_page.dart`, `game_host_page.dart` | games project (matchmaking) | Live (bots/local) / Server-gated (online) | Lobby, setup, host, 26 boards | none (done) | `test/games/*` |
| Online match | `online_lobby_page.dart`, `online_match_page.dart`, `net_link.dart` | games project | Server-gated | Lobby, match, reconnect | backend | match link tests |
| Leaderboards | `leaderboard_page.dart` | games project | Server-gated | Leaderboard | backend | leaderboard tests |
| Oracle Core | `oracle_core_page.dart`, `oracle_brain.dart`, `oracle_knowledge.dart` | `nx-oracle` fn (optional) | Live (on-device) | Chat, game help, tour, buddy | none (done) | oracle tests |
| Personal Orbit | `personal_orbit_page.dart` tabs, `ProfileService` | local + cloud sync | Live (local) / Server-gated (sync) | Identity/Missions/Wardrobe/Space/Records, rewards | none (done) | profile tests |
| Social Station | `social_station_page.dart`, `SocialRepository` | communities need server | Server-gated | Discover/detail/create | backend publish | community tests |
| Nexora Exchange | `exchange_page.dart`, `exchange_rules.dart`, `ProfileService.purchase` | catalogue + server purchase | Live (local wallet) / Server-gated (server purchase) | Landing, categories, item detail | none (done) | exchange tests |
| Rooms | `rooms_page.dart`, `room_capacity.dart` | `nx_room_capacity` RPC, `nx_rooms` | Server-gated (local fallback) | Directory, create wizard | none (done) | room lifecycle tests |
| Talk Rooms / voice | `talk_room_page.dart`, `voice_connect.dart` | LiveKit (not connected) | Server-gated | Room stage, moderation | backend LiveKit | voice permission tests |
| Tournaments | `features/tournaments/*` | games project engine | Server-gated | Home/detail/bracket/wizard/manage/inbox/join | backend | tournament tests |
| Admin | `admin_page.dart`, `admin_access.dart`, `force_password_page.dart` | `AdminApi` server check | Server-gated | Dashboard, force password, Oracle config | none (done) | admin tests |
| Settings | `settings_page.dart`, `AppSettings` | local store | Live | Full settings center | none (done) | settings tests |
| Account / sign-out | `account_page.dart`, `OnlineService` | auth | Live (sign-out) | Account page, confirmations | none (done) | account tests |
| Account deletion | `ProfileService.resetAll()` | **none** | **Missing** (local-only; documented) | Delete dialog (truthful) | **backend deletion RPC** | deletion tests |
| Notifications | Nova alerts tab, `TournamentWatcher`, update banner | push (Android) not integrated | Partial (local) | Notification surfaces | push integration (future) | notification tests |
| Deep links | `router.dart` (`nexora://t/<code>`, `/<8-char>`, login callback) | — | Live | Join-code, callbacks | none (done) | deep-link tests |
| Not-found | `RouteNotFoundPage` | — | Live | Not-found page | none (done) | route tests |

## Key audit conclusions
1. **26 games registered** (9 + 7 + 10); the 16 entry files are the multiplayer subset — README's 26 is correct.
2. **Billiards and Pool8 stay separate** (different rules/engines).
3. **Guest is offline-only** — UI explains this accurately; no fake online access.
4. **Sign-out ≠ deletion** — deletion is local-only until the backend flow exists (`docs/BACKEND_GAPS.md`).
5. **No secrets in client** — LiveKit tokens via `nx-call-token` Edge Function; two Supabase projects preserved.
6. **Baseline build limitation** — no Flutter SDK in the audit sandbox; `analyze`/`test`/Android build run in CI (Flutter 3.27.1).
