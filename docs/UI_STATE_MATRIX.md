# NEXORA — UI STATE MATRIX
_Phase 0 deliverable. Required states per the master prompt §18, mapped to where each is implemented. `✓` = implemented in code; `△` = implemented for the common path, edge variants partial; `—` = not applicable / documented as backend-dependent._

## State model (shared primitives)
- `GlassPanel` / `LuxeGlass` — loaded content surface.
- `OnlineOnlyNotice(featureFa:, featureEn:)` — guest/offline feature gate with honest explanation.
- `luxeToast` — snackbar system.
- `AnixDialog` — confirmations, error/retry.
- Skeleton/loading: `LinearProgressIndicator` during auth submit; loading spinners on intro; world pages render real data from providers (no fake skeletons for local data).
- `Nx2Dock` — bottom navigation with active state.

## Per-screen matrix
| Screen / flow | Loading | Skeleton/partial | Loaded | Empty | No results | Offline | Backend unavailable | Permission denied | Session expired | Action in progress | Success | Failure + retry | Disabled/unavailable | Reconnecting/stale | Restricted/private | Overflow/pagination |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Boot / launch | ✓ (intro takes over) | — | ✓ | — | — | ✓ (offline-first) | ✓ | — | ✓ | — | — | — | — | ✓ | — | — |
| Intro cinematic | ✓ | — | ✓ | — | — | — | — | — | — | — | ✓ | ✓ (16 s guard, skip) | ✓ (reduced-motion/low-mem fallback) | — | — | — |
| Auth | ✓ (busy state) | — | ✓ | ✓ | — | ✓ (`network`) | ✓ (`not_configured`) | — | ✓ | ✓ (submit) | ✓ | ✓ (specific error mapping) | ✓ (signup disabled, weak password, rate limit) | — | — | — |
| Onboarding | ✓ | — | ✓ | ✓ (validation) | — | ✓ | — | — | — | ✓ | ✓ (award outcome) | ✓ | ✓ (guest offline-only notice) | — | — | — |
| Hub | ✓ | ✓ (live-rooms chip keeps last value) | ✓ | ✓ (no activity) | — | ✓ (guest offline) | ✓ (partial backend failure keeps last value) | — | — | ✓ (claim daily) | ✓ | ✓ | ✓ (no friends/rooms/events → sections hidden, not faked) | ✓ (30 s poll) | — | — |
| World directory | ✓ | — | ✓ | ✓ | ✓ (search) | ✓ | ✓ | — | — | — | — | — | ✓ (all items open real routes) | — | — | — |
| Nova Gallery | ✓ | — | ✓ | ✓ (designed empty state) | ✓ (explore) | ✓ | ✓ (public sharing needs server) | ✓ (media picker) | — | ✓ (publish) | ✓ (server response shown) | ✓ (upload failure) | ✓ (offline-only posting notice) | ✓ | ✓ (private profile) | ✓ (long feed) |
| Orbit Network | ✓ | — | ✓ | ✓ (no chats/contacts) | ✓ (search) | ✓ (`OnlineOnlyNotice`) | ✓ | ✓ (mic/cam) | ✓ (sign-in required) | ✓ (send) | ✓ (delivery states) | ✓ | ✓ (calls offline notice) | ✓ (reconnecting) | ✓ (blocked/muted) | ✓ (long chat) |
| Arcade | ✓ | — | ✓ | ✓ (no records) | ✓ (search) | ✓ (offline bots still play) | ✓ (online modes gated) | — | ✓ (online needs sign-in) | ✓ (matchmaking) | ✓ (result) | ✓ (retry/leave) | ✓ (online-only modes) | ✓ (reconnect/resume) | — | — |
| Game boards | ✓ | — | ✓ | — | — | ✓ (offline bots) | — | — | — | — | ✓ (result) | ✓ (leave confirm) | ✓ (mode unavailable) | ✓ (online stall watchdog) | — | — |
| Oracle | ✓ (thinking) | — | ✓ | ✓ (suggestions) | — | ✓ (on-device answers) | ✓ (`not_available_in_this_app`) | — | — | ✓ (action navigation) | ✓ (navigate) | ✓ (retry) | ✓ (honest offline limits) | — | — | — |
| Personal Orbit | ✓ | — | ✓ | ✓ (new user) | — | ✓ | ✓ (stats sync) | — | — | ✓ (equip/claim) | ✓ (award) | ✓ | ✓ (items need level) | ✓ | ✓ (blocked users) | ✓ (long lists) |
| Social Station | ✓ | — | ✓ | ✓ (empty discovery) | ✓ (search) | ✓ | ✓ | — | ✓ | ✓ (join) | ✓ | ✓ (join failure/closed) | ✓ (private/unavailable) | ✓ | ✓ (moderation) | — |
| Exchange | ✓ | — | ✓ | ✓ (empty category) | ✓ (search/filters) | ✓ | ✓ (server purchase) | — | — | ✓ (purchase) | ✓ (only after server confirm) | ✓ (retry) | ✓ (insufficient balance, level req) | — | — | — |
| Rooms | ✓ | — | ✓ | ✓ (no open rooms) | ✓ (search/filter) | ✓ | ✓ (`Could not reach the server`) | ✓ (mic) | ✓ (sign-in required) | ✓ (create/join) | ✓ (room created) | ✓ | ✓ (locked/full) | ✓ (reconnect) | ✓ (private) | — |
| Talk Room | ✓ (connecting) | — | ✓ | — | — | ✓ | ✓ (voice service unavailable) | ✓ (mic denied) | — | ✓ (leave/close) | ✓ | ✓ | ✓ (muted/listener) | ✓ (reconnecting) | ✓ (moderation) | — |
| Tournaments | ✓ | — | ✓ | ✓ | ✓ (search/filter) | ✓ | ✓ | — | ✓ | ✓ (register) | ✓ | ✓ (full/closed/not eligible) | ✓ (ineligible) | ✓ (reminders) | — | — |
| Leaderboards | ✓ | — | ✓ | ✓ | ✓ (search) | ✓ | ✓ (needs server) | — | ✓ | — | — | — | ✓ (unavailable notice) | — | — | — |
| Settings | ✓ | — | ✓ | — | — | ✓ | — | — | — | ✓ (toggles) | ✓ (persisted) | ✓ | ✓ (controls with no effect are not offered) | — | — | — |
| Account | ✓ | — | ✓ | — | — | ✓ | ✓ (`not_configured`) | — | ✓ (session expired) | ✓ (sign in/out) | ✓ | ✓ (specific auth errors) | ✓ (guest link) | ✓ (reconnect) | — | — |
| Sign out / delete | — | — | — | — | — | ✓ (offline sign-out) | ✓ | — | — | ✓ (confirm dialogs) | ✓ | ✓ (network errors leave UI consistent) | ✓ (delete truthful pending/success/failure) | — | — | — |
| Admin | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ (access denied page) | ✓ (force password) | ✓ (destructive confirms) | ✓ (server response) | ✓ | ✓ (unauthorized) | — | — | — |

## Cross-cutting rules
1. No fake counts/users/rooms/scores: empty sections are hidden or show a designed empty state with a relevant next action.
2. Every action shows the real server response; local-only actions are labelled.
3. Reduced motion and graphics quality gate animations/particles everywhere (`AppSettings.fancyEffects`, `reduceMotion`).
4. Persian/English: all states bilingual via `context.tx(fa, en)`; RTL/LTR correct.
5. Touch targets ≥44 dp on interactive state controls.
