# NEXORA — DESIGN SYSTEM
_Single source of truth: `lib/core/theme/nx_theme.dart`, `lib/core/ui2/luxe.dart`, `lib/core/ui2/nx2_widgets.dart`. No per-world variant tokens — one grammar, seven world identities via accent tints only._

## 1. Color roles
### Identity ramp (main)
| Token | Hex | Role |
|---|---|---|
| `NxColors.navy` family | `#0B0A2A` | Primary identity background (cosmic deep) |
| `NxColors.indigo` family | `#1A1650` | Elevated identity surface |
| `Luxe.bg` / `Nx2.deep` | `#07080C` | Station Luxe near-black depth surface |
| `Nx2.night` | `#11100C` | Mid depth |
| `Nx2.plum` | `#1C1912` | Warm charcoal panel ramp |

### Accent & semantics
| Token | Hex | Role |
|---|---|---|
| `NxColors.gold` / `Nx2.gold` | `#D9B872` | Primary brand accent (champagne gold) |
| `NxColors.champagne` / `Luxe.gold2` | `#F6E7BD` | Light gold highlight, selected/owned |
| `NxColors.goldDeep` / `Luxe.gold3` | `#8A6A2C` | Gold shadow/border |
| Silver / brushed metal | structural | Borders, dividers, frames |
| Orange-coral action | `#FF9A3C` → `#FF4F8B` | Selected primary actions, focused highlights (used selectively) |
| `NxColors.success` | `#3DDC97` / `#4BE3A0` | Success |
| `NxColors.danger` | `#FF5A6E` / `#FF5A7A` | Destructive / errors |
| `NxColors.turquoise` | `#2EE6D6` | **Gameplay-only** (card suits, board pieces) — never app chrome |
| `NxColors.textDim` / `Luxe.mute` | `#99F4EAD2` | Secondary text |
| `NxColors.ink` / `Luxe.ink` | `#F4EAD2` | Primary text on dark |

Rule: color is used intentionally — no constant glowing borders, no generic electric-blue neon template. Contrast strong, hierarchy calm.

## 2. World palettes (`WorldPalette`)
Shared background ramp (`#07080C → #12110D → #07080C`); each world varies only its `primary` accent tint:
| World | Primary accent | Identity |
|---|---|---|
| Hub | gold `#D9B872` | Station Luxe — the signature |
| Nova Gallery | `#E7B7C9` | Soft rose social |
| Orbit Network | `#B8CBB0` | Cool silver-green messaging |
| Nexora Arcade | `#E5C07B` | Warm gold games |
| Oracle Core | `#C9B8E8` | Lilac companion |
| Personal Orbit | gold | Identity gold |
| Social Station | `#C7C0A8` | Muted gold-green communities |
| Nexora Exchange | gold | Marketplace gold |

## 3. Typography
| Family | Role | Notes |
|---|---|---|
| **Estedad** (bundled) | Persian UI | Default language `fa`; verified glyphs, Persian numerals, RTL |
| **ChakraPetch** (bundled) | English / technical labels | Latin small-caps labels, futuristic tone |
| **Lalezar** (bundled) | Decorative display only | Never for long text or forms |

Semantic roles: display (wordmark), title (w900, 18–26), body (w400–500, 13–14, height 1.4–1.45), label/caption (w600–700, 11–12, letterSpacing 1.2–2.2), button (w700). Mixed fa/en/numbers render with correct bidi ordering.

## 4. Spacing scale (`NxSpace` / `LuxeSpace`)
`4 (xs/sm) · 8 (sm) · 12 · 16 (md) · 20 · 24 (lg) · 32 (xl)` — layout spacing uses multiples; cards use 16 horizontal padding.

## 5. Radius scale (`NxRadius` / Luxe)
`10 (sm) · 16 (md) · 24–26 (lg, panels/cards) · 30 (sheets)` — one consistent shape language; chamfered NX2 frames for premium panels.

## 6. Elevation & shadow
- No permanent glow borders. Selective shadows: gold glow `alpha .35`, blur 28, spread −8 for hero cards only.
- Glass: `BackdropFilter` blur 14, `#13FFFFFF → #04FFFFFF` gradient, hairline gold border `#33D9B872`.

## 7. Motion (`NxMotion`)
| Token | Duration | Use |
|---|---|---|
| `fast` | 160 ms | presses, micro-interactions |
| `normal` | 280 ms | page transitions, tab changes |
| `slow` | 520 ms | cinematic reveals (skippable) |

Curve: `easeOutCubic` / `Cubic(.22,.8,.2,1)`. Respects `reducedMotion` and `fancyEffects` everywhere; station ring rotates gently, spacecraft drift — paused when offscreen/backgrounded.

## 8. Touch targets & safe areas
- Minimum 44–48 dp touch targets (buttons, dock, chips).
- `SafeArea` on all pages; bottom dock respects navigation bar; keyboard behavior via `TextInputAction`.
- Responsive: narrow phones (320 dp) → large phones/tablets (segmented controls wrap, grids reflow).

## 9. Component library (one source of truth)
- **Brand:** `AnixLogo` / `AnixBrand` (NX emblem + wordmark; visible label NEXORA).
- **Shell:** `NxWorldScaffold` (header, wallet chip, dock, palette tint), `Nx2Dock`, `Nx2Background`.
- **Identity:** `AnixFramedAvatar`, `UserAvatar`, profile mini-card, wallet chip (coins/gems), `XpBar`, rank emblems (`AnixRankEmblem`, tiers bronze→grandmaster).
- **Cards:** `AnixGameCard` + pedestal art, world portal card, room card, post card, tournament card, bracket nodes, rank rows.
- **Panels:** `GlassPanel`, `LuxeGlass`, gold-accent panels, `showAnixSheet` bottom sheets, `AnixDialog`.
- **Controls:** primary/secondary/ghost/destructive buttons (9-slice pack), `AnixSwitchTile`, `AnixCheckboxTile`, tabs, segmented controls, filter chips, search fields, sliders.
- **States:** skeleton/loading, designed empty states, error+retry, `OnlineOnlyNotice`, offline banner, reconnect state, permission explanation, `luxeToast`.
- **Overlays:** profile preview, world menu, search, notification panel, wallet, daily reward, mission detail, mode selector, invite/friend-picker, room wizard, member list, moderation, confirmations, report forms, share sheet, media picker, update/session/reconnect dialogs.

## 10. Accessibility
- TalkBack semantics on every interactive surface (`Semantics` labels, button roles).
- Logical focus order; sufficient contrast; text scaling without clipping.
- State never conveyed by color alone (icons + text).
- 3D/decorative art never carries essential information — list/text alternatives provided (Station directory, world pages).
- Reduced motion + quality profiles honored in every world and game.
