# NEXORA — ROUTE MAP
_Phase 0 deliverable. Every route, parent, deep link, access requirement and back behavior. Verified against `lib/app/router.dart` and `lib/app/auth_gate.dart`._

## Auth gate model
`NxAccess { needsAuth, guest, signedIn }` from `lib/app/auth_gate.dart`.
`isOnlineOnlyPath()` blocks **guests** from: `/social`, `/leaderboard`, `/online/*`, `/call/*`, `/tournaments*`, `/world/orbit_network`, `/world/social_station`, `/world/nova_gallery`.
Guest is offline-only; sign-in-required page explains this. Admin routes are guarded server-side (`AdminApi`), not by a client role label.

## Route table
| Route | Page | Parent / notes | Access | Back behavior |
|-------|------|----------------|--------|---------------|
| `/intro?next=` | IntroVideoPage | entry for first launch / after auth | public | skip/finish → `next` |
| `/auth` | AuthPage | sign-in/sign-up | public | → `/hub` or `/onboarding` |
| `/signin-required` | SignInRequiredPage | guest hit on protected feature | guest | → `/auth` |
| `/onboarding` | OnboardingPage | identity setup after auth/guest | public | → `/hub` |
| `/hub` | HubPage | root of authenticated app | any | Android back = exit (no sign-out) |
| `/station/:k` | LuxeStationPage | Hub → world directory | any | → `/hub` |
| `/rooms` | RoomsPage | Hub dock / menu | signed-in for live rooms | → `/hub` |
| `/room/:id?room=&action=` | TalkRoomPage / game lobby | rooms directory | signed-in | → `/rooms` |
| `/social` | (shared inbox/chat entry) | orbit entry | signed-in | → prior |
| `/rewards` | RewardsPage | Hub menu / Personal Orbit | any | → prior |
| `/settings` | SettingsPage | Hub menu / dock | any | → prior |
| `/account` | AccountPage | Settings / Personal Orbit | any | → prior |
| `/force-password` | ForcePasswordPage | privileged accounts | admin | → `/hub` after change |
| `/admin` | AdminPage | Settings (admin tile) | admin (server-checked) | → `/settings` |
| `/admin/oracle` | OracleConfigPage | Admin | admin + oracle perm | → `/admin` |
| `/oracle` | OracleCorePage | Hub menu / dock / buddy | any | → prior |
| `/world/:id` | World page | all seven worlds (`world_registry.dart`) | per-world gate | → `/hub` |
| `/online/:gameId` | OnlineLobbyPage | Arcade game → online | signed-in | → `/arcade/:gameId` |
| `/call/:chatId?call=&video=&title=` | OrbitCallPage | Orbit chats → call | signed-in | → conversation |
| `/leaderboard` | LeaderboardPage | Arcade / menu | signed-in | → prior |
| `/tournaments` | TournamentsPage | menu / hub | signed-in | → prior |
| `/tournaments/new` | TournamentWizardPage | admin | authorized | → `/tournaments` |
| `/tournaments/inbox` | TournamentInboxPage | menu | signed-in | → `/tournaments` |
| `/tournaments/join?code=` | join-by-code | invitations | signed-in | → `/tournaments` |
| `/t/:code` | join redirect | deep link | signed-in | → `/tournaments/:id` |
| `/tournaments/:id` | TournamentDetailPage | list/inbox | signed-in | → `/tournaments` |
| `/tournaments/:id/manage` | TournamentManagePage | detail (admin) | admin | → detail |
| `/tournaments/:id/edit` | TournamentWizardPage | manage | admin | → manage |
| `/arcade/:gameId` | GameSetupPage | Arcade lobby / hub game card | any | → `/world/nexora_arcade` |
| unknown | RouteNotFoundPage | fallback | any | → `/hub` |

## World routes (`/world/:id`)
`nova_gallery` · `orbit_network` · `nexora_arcade` · `oracle_core` · `personal_orbit` · `social_station` · `nexora_exchange` — single registry (`lib/worlds/world_registry.dart`) used by Hub, router, ORACLE and search.

## Deep links
- `nexora://t/<code>` — tournament join code (scheme preserved).
- `/<8-char>` — join-code redirect for bare codes.
- Login callback handling in router (email pre-fill into `/auth`).
- Notification-to-page navigation: each notification type maps to its real route (post, chat, room, tournament, reward).
- Invalid/expired invitation codes → error state on the join page (no silent success).

## Navigation rules implemented
- Active state on dock (`Nx2Tab`), correct selection after deep links.
- Back returns to prior context (e.g. room → game → back to the room).
- No duplicate root pages pushed onto the stack.
- Bottom nav hidden/adapted for full-screen gameplay, active calls, cinematic intro.
- Route guards for guest / signed-in / admin / feature-availability.
- `/station/:k` directory keeps every destination reachable in ≤3 taps from Hub.
