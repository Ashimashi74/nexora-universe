# NEXORA — SCREEN INVENTORY
_Phase 0 deliverable. Every screen, sub-screen, sheet, modal and overlay implemented in the Flutter app (Source A = functional truth). Routes reference `docs/ROUTE_MAP.md`._

Status legend: **Implemented** (real page with layout + data binding), **Shell** (route exists, page present, wiring partial), **Guarded** (route exists but requires auth/admin).

## 1. Entry lifecycle
| # | Screen | Route | Implementation | States |
|---|--------|-------|----------------|--------|
| 1 | App boot / loading | app root (`MaterialApp.router`) | `lib/app/app.dart` — music/SFX config, router; no blank screen (intro/hub take over) | loading |
| 2 | Intro cinematic (video) | `/intro?next=` | `lib/worlds/intro/intro_video_page.dart` — full-screen owner video, skip after 1 s, 16 s guard, continues to `next` | loading, skip, video-error fallback |
| 3 | Intro (orbital 3-step) | intro flow | `lib/worlds/intro/nexora_universe_intro.dart` — 3-step orbital scene, drag to orbit, skip | skip, reduced-motion |
| 4 | Auth / sign-in / sign-up | `/auth` | `lib/worlds/auth/auth_page.dart` — username/email + password, segmented sign-in/sign-up, show/hide password, inline validation, guest path | loading, invalid credentials, username taken, weak password, rate limit, signup disabled, network failure |
| 5 | Sign-in required | `/signin-required` | `lib/worlds/auth/signin_required_page.dart` — guest hitting a protected feature | — |
| 6 | Onboarding / identity | `/onboarding` | `lib/worlds/onboarding/onboarding_page.dart` — language pick, username, avatar pick, identity explanation, guest/online explanation | validation, award outcome |
| 7 | Route not found | unknown routes | `RouteNotFoundPage` in `lib/worlds/auth/signin_required_page.dart` | — |

## 2. App shell & navigation
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 8 | Global shell (header, wallet, dock) | all world pages | `NxWorldScaffold` (`lib/core/widgets/nx_widgets.dart`), `Nx2Dock` bottom navigation (`lib/core/ui2/nx2_widgets.dart`) |
| 9 | Universe / More menu | overlay (tap More) | `showNexoraMenu` (`lib/core/navigation/nexora_menu.dart`) — sections: Start, Play & compete, Connect & community, Identity & store, Help & settings |
| 10 | Hub / NEXORA Station | `/hub` | `lib/worlds/hub/hub_page.dart` — Station Luxe scene, brand, profile HUD, live-rooms chip, 3D ring of world cards (swipe/tap), dock |
| 11 | Station directory / world selector | `/station/:k` | `lib/worlds/hub/luxe_station_page.dart` + `luxe_worlds.dart` — 8 destination worlds with tabs and item grids, every item opens a real route |
| 12 | Hub search | `/hub` search overlay | `lib/worlds/hub/hub_search.dart` — search worlds/games/routes |
| 13 | Daily reward sheet | overlay (action `daily`) | claim flow via `ProfileService.claimDaily` + `showAwardOutcome` |

## 3. World 1 — Nova Gallery (social feed)
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 14 | Nova Gallery main (tabs) | `/world/nova_gallery` | `lib/worlds/nova_gallery/nova_gallery_page.dart` — tabs: Feed, Explore, Reels, Alerts, Profile |
| 15 | Feed tab | same | `NovaFeedTab` (`nova_tabs.dart`) — real local posts, like/comment/share/save |
| 16 | Explore tab | same | `NovaExploreTab` — search people/hashtags/posts |
| 17 | Reels tab | same | `NovaReelsTab` — motion-post viewer |
| 18 | Alerts tab | same | `NovaNotificationsTab` — local notifications |
| 19 | Profile tab | same | `NovaProfileTab` — personal social presence |
| 20 | Post detail | in-page | `_NovaPostPage` — post + comments |
| 21 | New post composer | overlay | `lib/worlds/nova_gallery/ui/nova_composer.dart` — media/asset picker, caption, publish |
| 22 | Art library sheet | overlay | art asset picker (`ArtCategory` tabs) |
| 23 | Story viewer | overlay | `lib/worlds/nova_gallery/ui/nova_story_viewer.dart` |
| 24 | Follow sheet | overlay | `lib/worlds/nova_gallery/ui/nova_follow.dart` |
| 25 | Post options sheet | overlay | edit/delete/report/save (`nova_post_card.dart`) |

## 4. World 2 — Orbit Network (messages/calls)
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 26 | Orbit Network main (tabs) | `/world/orbit_network` | `lib/worlds/orbit_network/orbit_network_page.dart` — tabs: Chats, Calls, Contacts |
| 27 | Chats tab | same | `OrbitChatsTab` — conversation list, search, pin/mute/delete, unread |
| 28 | Calls tab | same | `OrbitCallsTab` / `_OnlineCallsTab` / `_OfflineCallsTab` — call history (online) / honest offline notice |
| 29 | Contacts tab | same | `OrbitContactsTab` — friends/requests (online) / offline notice + Explorer ID share |
| 30 | Conversation detail | `/social` (shared inbox) + in-app | `OrbitMessageListPage` — messages, composer, reactions, delivery states |
| 31 | Message search | in-app | `OrbitMessageListPage(starredOnly:false)` search mode |
| 32 | Starred messages | in-app | `OrbitMessageListPage(starredOnly:true)` |
| 33 | New chat / group / channel | overlay | sheets in `orbit_network_page.dart` — private chat, new group, new channel |
| 34 | Contact profile preview | overlay | `lib/worlds/orbit_network/ui/orbit_sheets.dart` |
| 35 | Audio/video call | `/call/:chatId` | `lib/worlds/orbit_network/ui/orbit_call_page.dart` — LiveKit, token via backend, honest states |
| 36 | Chat sheets (media, art, report) | overlay | `orbit_sheets.dart`, `orbit_chat_page.dart` |

## 5. World 3 — Nexora Arcade (game center)
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 37 | Arcade lobby | `/world/nexora_arcade` | `lib/worlds/arcade/arcade_page.dart` — tabs: Games, Records; grouped game pedestals |
| 38 | Game detail / setup | `/arcade/:gameId` | `lib/worlds/arcade/game_setup_page.dart` — pedestal art, rules, mode (vs Bot / Local / Online), difficulty, seats |
| 39 | Host game (local/online) | in-app | `lib/worlds/arcade/game_host_page.dart` — host scaffold, exit control, result, XP |
| 40 | Online lobby | `/online/:gameId` | `lib/worlds/arcade/online/online_lobby_page.dart` — matchmaking, invite, ready |
| 41 | Online match | in-app | `lib/worlds/arcade/online/online_match_page.dart` — reconnect/resume, leave |
| 42 | Leaderboard | `/leaderboard` | `lib/worlds/arcade/online/leaderboard_page.dart` — per-game ranking (online) |
| 43 | Game boards (16 entry points) | in-app | `lib/games/<id>/ui/*` — full game UI per contract; board geometry LTR-wrapped |
| 44 | Solo arcade boards (10) | in-app | `lib/games/solo/ui/*` — action/puzzle boards with daily challenge + global board (online) |
| 45 | Finger Soccer intro flow | in-app | `lib/games/finger_soccer/intro/*` — team/badge, field, ball, formation, match format (1v1/2v2/3v3), score table |
| 46 | Finger Soccer shop | in-app | `fs_shop.dart` — club/nation/NX badges, kits, pucks |

## 6. World 4 — Oracle Core
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 47 | Oracle Core chat | `/oracle` | `lib/worlds/oracle_core/oracle_core_page.dart` — conversation, suggestions, moods, offline-honest replies |
| 48 | Oracle game help sheet | overlay | `lib/worlds/oracle_core/oracle_game_sheet.dart` — rules per game |
| 49 | Oracle tour / buddy | overlay + corner buddy | `lib/worlds/oracle_core/persona/oracle_tour.dart`, `lib/core/ui2/oracle_buddy.dart` |
| 50 | Oracle persona config (admin) | `/admin/oracle` | `lib/worlds/oracle_core/persona/oracle_config_page.dart` + `json_form_editor.dart` |

## 7. World 5 — Personal Orbit (profile)
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 51 | Personal Orbit main (tabs) | `/world/personal_orbit` | `lib/worlds/personal_orbit/personal_orbit_page.dart` — tabs: Identity, Missions, Wardrobe, My Space, Records |
| 52 | Identity tab | same | `identity_tab.dart` — profile, Explorer ID, edit, Exchange shortcut |
| 53 | Missions tab | same | `missions_tab.dart` — daily/weekly challenges, progress |
| 54 | Wardrobe tab | same | `wardrobe_tab.dart` — owned items, equip/unequip |
| 55 | My Space tab | same | `space_tab.dart` — personal room, decor placement |
| 56 | Records tab | same | `records_tabs.dart` — stats, achievements, activity |
| 57 | Avatar view | overlay | `avatar_view.dart` |
| 58 | Rewards page | `/rewards` | `lib/worlds/personal_orbit/rewards_page.dart` — daily reward, medals, achievements |

## 8. World 6 — Social Station (communities)
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 59 | Social Station main | `/world/social_station` | `lib/worlds/social_station/social_station_page.dart` — discover/joined |
| 60 | Community detail | in-app | `ui/community_detail_page.dart` — overview, members, events, tournaments, settings, invite text |
| 61 | Community create sheet | overlay | `ui/community_create_sheet.dart` |
| 62 | Community tabs | in-app | `ui/community_tabs.dart` |
| 63 | Tournament bracket view | in-app | `ui/tournament_bracket_view.dart` (community cups) |

## 9. World 7 — Nexora Exchange (marketplace)
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 64 | Exchange landing | `/world/nexora_exchange` | `lib/worlds/nexora_exchange/exchange_page.dart` — featured (date-rotated), category tabs, search |
| 65 | Category listings | same | tabs per `ItemCategory` (avatarGear, decor, puck, striker, cue, theme, frame, badge) |
| 66 | Item detail / purchase | overlay | item preview, price, owned/equipped, purchase via `ProfileService.purchase` (server-confirmed online) |
| 67 | Wallet / balance | shell | wallet chip in scaffold (coins/gems from ProfileService) |

## 10. Rooms & voice
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 68 | Rooms directory | `/rooms` | `lib/worlds/rooms/rooms_page.dart` — talk rooms + game lobbies, search/filter, join, Quick Play, create room |
| 69 | Create room wizard | overlay | title, game pick, public/private, capacity (within game rules via `room_capacity.dart`) |
| 70 | Talk Room stage | `/room/:id` | `lib/worlds/rooms/talk_room_page.dart` — speaker stage, audience, mic states, raise hand, chat, members, moderation (kick/transfer/close with confirmation) |
| 71 | Game room / lobby | `/room/:id` | same page in game mode — seats, ready, capacity, start (validated server-side) |
| 72 | Room voice states | in-room | connecting/connected/reconnecting/mic-denied/listening/speaking/muted/unavailable |

## 11. Competitive system
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 73 | Tournaments home | `/tournaments` | `lib/features/tournaments/ui/tournaments_page.dart` — tabs/filters, cards with real status |
| 74 | Tournament detail | `/tournaments/:id` | `tournament_detail_page.dart` — banner, format, participants, schedule, bracket, join/register |
| 75 | Bracket view | in-app | `lib/features/tournaments/ui/bracket_view.dart` — zoomable bracket, match nodes, byes |
| 76 | Create tournament wizard | `/tournaments/new` | `ui/admin/tournament_wizard_page.dart` (authorized) |
| 77 | Tournament manage | `/tournaments/:id/manage` | `ui/admin/tournament_manage_page.dart` — results, participants, moderation |
| 78 | Tournament edit | `/tournaments/:id/edit` | wizard in edit mode |
| 79 | Tournament inbox | `/tournaments/inbox` | `tournament_inbox_page.dart` — invitations/reminders |
| 80 | Join by code | `/tournaments/join?code=` + `/t/:code` + `nexora://t/<code>` | code entry → register |
| 81 | Leaderboards | `/leaderboard` | `leaderboard_page.dart` (see #42) |

## 12. Settings & account lifecycle
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 82 | Settings home | `/settings` | `lib/worlds/settings/settings_page.dart` — Sound & music, Graphics & motion, Language, Account & data, About |
| 83 | Account page | `/account` | `lib/worlds/settings/account_page.dart` — status card, sign in/register, Explorer ID, sync, sign out, delete |
| 84 | Sign-out confirmation | dialog | clears auth mode, preserves server data, routes to intro/auth |
| 85 | Delete identity | dialog + flow | `ProfileService.resetAll` + server deletion where supported; truthful states |
| 86 | Force password change | `/force-password` | `lib/features/admin/force_password_page.dart` (privileged) |

## 13. Admin & system surfaces
| # | Screen | Route | Implementation |
|---|--------|-------|----------------|
| 87 | Admin dashboard | `/admin` | `lib/features/admin/admin_page.dart` — guarded by `AdminApi` server check |
| 88 | Admin access / invite code | in Settings | `_AdminInviteTile` — redeem admin invitation code |
| 89 | Oracle config | `/admin/oracle` | see #50 |
| 90 | Update banner | overlay | `lib/core/update/update_banner.dart` — optional/mandatory update, install-permission state |
| 91 | Session / offline notices | overlay | `OnlineOnlyNotice`, reconnect banners in worlds |

## 14. Shared overlays (partial list — see component kit)
Profile preview sheet, world selection menu, search overlay, notification panel, wallet details, daily reward sheet, mission/achievement detail, game mode selector, game invite sheet, friend picker, room creation wizard, room invitation sheet, member list, room moderation sheet, leave/close/transfer/remove confirmations, tournament join/share sheets, item preview, purchase confirmation, report forms, block/mute confirmations, share sheet, media picker/preview, permission explanations, reconnect dialog, session-expired dialog, update dialogs, generic error/retry dialog, destructive confirmations, toast/snackbar (`luxeToast`), offline-only notice, feature-unavailable notice.

_Component sources: `lib/core/ui2/anix_kit.dart` (9-slice pack art), `lib/core/ui2/luxe.dart` (Station Luxe primitives), `lib/core/ui2/nx2_widgets.dart` (NX2 frames/buttons/dock), `lib/core/widgets/nx_widgets.dart` (shell/panels/states)._
