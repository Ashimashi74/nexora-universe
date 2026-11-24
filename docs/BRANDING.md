# NEXORA — BRANDING: ANIX → NEXORA NORMALIZATION
_Deliverable §7. Visible brand = NEXORA. Internal identifiers, package IDs, DB names, deep-link schemes, storage keys, migration names and release-asset names are intentionally retained (no compatibility break)._

## 1. Applied changes (user-facing strings)
| File | Before | After |
|---|---|---|
| `lib/app/app.dart` | app title `ANIX PRO` | `NEXORA` |
| `lib/app/router.dart` | call-page default title `ANIX PRO` | `NEXORA` |
| `lib/core/ui2/anix_brand.dart` | semantics label + fallback text `ANIX` | `NEXORA` |
| `lib/core/navigation/nexora_menu.dart` | menu title `ANIX HUB` / `هاب انیکس`; header `ANIX` | `NEXORA HUB` / `هاب نیکسورا`; `NEXORA` |
| `lib/worlds/world_registry.dart` | `ANIX ARCADE`/`آرکید انیکس`, `ANIX EXCHANGE`/`بازار انیکس` | `NEXORA ARCADE`/`آرکید نیکسورا`, `NEXORA EXCHANGE`/`بازار نیکسورا` |
| `lib/worlds/arcade/arcade_page.dart` | `آرکید ANIX` / `ANIX ARCADE` | `آرکید نیکسورا` / `NEXORA ARCADE` |
| `lib/worlds/nexora_exchange/exchange_page.dart` | `ANIX EXCHANGE` | `NEXORA EXCHANGE` |
| `lib/worlds/auth/auth_page.dart` | `ساخت حساب ANIX` / `ورود به ANIX` / `Create your ANIX account` / `Log in to ANIX` | NEXORA equivalents |
| `lib/worlds/auth/signin_required_page.dart` | `ANIX PRO` | `NEXORA` |
| `lib/worlds/onboarding/onboarding_page.dart` | `ورود به ANIX`, identity-across-worlds text, account-link text | NEXORA / `نیکسورا` |
| `lib/worlds/settings/settings_page.dart` | `درباره‌ی ANIX PRO 2`, feature list, footer tagline | `درباره‌ی نیکسورا ۲`, NEXORA, `NEXORA · YOUR UNIVERSE…` |
| `lib/core/catalog/catalog.dart` | `پرچم ANIX` / `ANIX Banner` | `پرچم نیکسورا` / `NEXORA Banner` |
| `lib/core/ui2/oracle_lines.dart` | buddy line "best ANIX player" | "best NEXORA player" |
| `lib/core/update/update_banner.dart` | `نسخه جدید ANIX` / `New ANIX update`, install-permission text | NEXORA |
| `lib/features/tournaments/data/models.dart` | fallback title `ANIX` | `NEXORA` |
| `lib/features/tournaments/tournament_watcher.dart` | fallback title `ANIX` | `NEXORA` |
| `lib/features/tournaments/ui/tournaments_page.dart` | `جام‌های انیکس` / `ANIX CUPS` | `جام‌های نیکسورا` / `NEXORA CUPS` |
| `lib/worlds/nova_gallery/ui/nova_composer.dart` | `هنر ANIX` / `ANIX art`, `کتابخانه‌ی هنری ANIX` | NEXORA art library |
| `lib/worlds/orbit_network/ui/orbit_chat_page.dart` | `اثر هنری ANIX` | `اثر هنری نیکسورا` |
| `lib/worlds/orbit_network/ui/orbit_bubbles.dart` | `ANIX ARCADE`, call-notice `سرور ANIX`, fallback `ANIX` | NEXORA |
| `lib/worlds/orbit_network/ui/orbit_tabs.dart` | `در ANIX پیدایم کن`, friends-online text | NEXORA |
| `lib/worlds/personal_orbit/ui/missions_tab.dart` | `دنیاهای ANIX` | `دنیاهای نیکسورا` |
| `lib/worlds/personal_orbit/ui/identity_tab.dart` | `ANIX Exchange` | `NEXORA Exchange` |
| `lib/worlds/rooms/rooms_page.dart` | fallback room title `ANIX` | `NEXORA` |
| `lib/worlds/social_station/ui/community_detail_page.dart` | invite text `on ANIX` | `on NEXORA` |
| `lib/games/billiards/ui/billiards_game.dart` | `ربات انیکس · آسان/معمولی/سخت` / `ANIX Bot` | `ربات نیکسورا` / `NEXORA Bot` |
| `lib/games/quiz/ui/quiz_view.dart` | `کوییز انیکس` / `ANIX Quiz`, `ربات انیکس` | `کوییز نیکسورا` / `NEXORA Quiz` |
| `lib/games/game_registry.dart` | Quiz `nameEn: 'ANIX Quiz'`, `nameFa: 'کوییز انیکس'` | `NEXORA Quiz` / `کوییز نیکسورا` |
| `lib/games/finger_soccer/ui/bm_view.dart` | `ANIX / MATCH LOBBY` | `NEXORA / MATCH LOBBY` |
| `lib/games/finger_soccer/core/bm_data.dart` | NX category label `انیکس` | `نیکسورا` |
| `lib/games/finger_soccer/intro/fs_shop.dart` | shop tab `انیکس` | `نیكسورا` → `نیکسورا` |
| `lib/worlds/oracle_core/core/oracle_brain.dart` | assistant self-description, offline-limit, station return, help text, system-prompt context | NEXORA |
| `lib/worlds/oracle_core/core/oracle_knowledge.dart` | world descriptions, arcade list, no-gambling, offline, universe intro | NEXORA / `نیکسورا` |
| `lib/worlds/oracle_core/persona/oracle_persona_data.dart` | tour welcome + tournaments tour title | `نیکسورا` |
| `test/games/finger_soccer_intro_pick_test.dart` | category assertion `انیکس` | `نیکسورا` |

## 2. Intentionally retained (internal / compatibility)
| Item | Why retained |
|---|---|
| Class names `AnixLogo`, `AnixKit`, `AnixSwitchTile`, `AnixDialog`, `AnixTier`, `AnixAssets`, `AnixBrand`, `showAnixSheet`, `AnixFramedAvatar`, `AnixGameCard`, `AnixRankEmblem`, `AnixCheckboxTile` | Internal identifiers — renaming would touch every call site with zero user impact |
| Asset paths `assets/ui/anix/*`, `assets/branding/anix_*.webp`, `assets/luxe/*` | Asset manifest entries in `pubspec.yaml` and `AppAssets`; file renames would break builds |
| `AppUpdater.apkName = 'ANIX-universal.apk'` and `tagPrefix = 'anix-'` | Match the GitHub release assets/tags the updater downloads from — renaming breaks the update flow |
| `debugPrint('ANIX …')` logs | Diagnostics, not user-facing |
| Comments/doc-comments referencing ANIX | Historical implementation notes; no user impact |
| `oracle_knowledge.dart` keyword alias list `['anix', 'انیکس', …]` | Intent-matching aliases so legacy inputs still resolve |
| Package ID `nexora`, Supabase project/table names, `nexora://` deep-link scheme, storage keys, migration names | Compatibility per the master prompt — never renamed |
| `test/worlds/nova_test.dart` hashtag fixture `#ANIX` | Test input for mention parsing, not user-facing |

## 3. Migration note
No data migration is required: the change is purely presentational (visible strings). Profile data, rooms, tournaments, storage keys and the two Supabase projects (core + games) are untouched.
