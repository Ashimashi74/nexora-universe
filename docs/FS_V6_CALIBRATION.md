# Finger soccer v6 calibration (2026-11-20)

Source: two owner screen recordings of the reference game (480x800, 15.08 fps, 6:03 and 1:27; both sides
power 10 / accuracy 10, so what they show is the MAXIMUM). Frames were read with ffmpeg / OpenCV; the ball was
tracked with a low-saturation blob detector (99.6 % of gameplay frames in recording A), discs with Hough circles
and by hand. Pixels below are recording pixels; "w" = one playing width of the pitch.

## Measured

| Quantity | Value | Note |
|---|---|---|
| Playing width | 313 px | red touchlines, x 82..395 |
| Disc / ball diameter | 40 px (0.128 w) / 18 px (0.058 w) | ANIX: 0.12 w / 0.056 w (unchanged) |
| Ball roll, slow (< 300 px/s) | linear drag 0.98 /s | 2 clean 1.5-2.1 s rolls, rms 2.9 px |
| Ball roll, fast | same law within noise | 10 rolls, rms 11 px (capture jitter: one 15 fps frame = 44-86 px at speed) |
| Hardest ball, first 0.2 s | 1431 px/s = **4.57 w/s** | next hardest 1020-1120 px/s (3.3-3.6 w/s) |
| Disc shot onto the ball (example) | >= 1150 px/s (3.7 w/s), ball leaves at ~1180 px/s | B 9.30 s |
| Goal banner ("Goal!") | ~2.0 s, pieces keep rolling | B 9.9-11.9 s |
| Pieces back to kickoff | ~1.0 s glide (not a jump) | B 12.2-13.2 s |
| End of match | pieces leave at 00:00, then "جدول امتیازات" 20 s countdown ("N ثانیه تا بازگشت به جمع"), then the room's result screen | B 61-83 s |

ANIX before v6 on screen (kBmSimRate .85 included), power 10 full pull: ball 4.74 w/s over its first 0.2 s, slow ball
decay 0.98 /s (matches), disc felt unchanged since v4.

## Chosen constants

| Constant | Before | v6 | Why |
|---|---|---|---|
| `kBmLaunch` | 2.04 | **1.97** | power-10 full pull = 4.58 w/s ball over 0.2 s (target 4.57) |
| `BmEngine.powerShare(p)` | - | `strikeOf(p)/strikeOf(10)` | 10 = 1 (the video), 9 .925, 8 .85, 7 .775, 6 .70, 5 .626, 4 .55, 3 .476, 2 .401, 1 .326 (the reference's own Japan 2 / PSG 10 ratio) |
| Accuracy | 10 = exact aim | unchanged | the 10/10 recordings shoot exactly where aimed |
| `kBmGoalHold` | 1.8 s | **2.0 s** | goal banner time |
| `kBmResetGlide` | (teleport) | **1.0 s** | render-only glide home; input and turn clock wait |
| Goal banner animation | 1800 ms | 2000 ms | = hold |
| `kFsScoreTableSeconds` | - | **20** | end-of-match table; host result after it (`GameResult.holdMs`) |
| Match ball | Gold Spin (0) | **Classic (4)** | owner's reference ball art, rolled by the 3D ball renderer (one turn per 2*pi*r rolled, flat studio light); new pref key `bm.ball.v6` |
| Ball friction, disc felt, rails, `kBmSimRate` | unchanged | unchanged | already match the recordings on screen |

Tests: `test/games/finger_soccer_v6_test.dart` (power-10 ball speed 4.57 +- 0.12 w/s, power scale, classic ball,
goal hold + glide, mirrored-phone sync, score table).

## v6.1: HUD, one-minute toast, score table (from recording B frames 0-66 s)

| Reference | ANIX |
|---|---|
| Score banner: white score plates either side of a yellow hexagonal clock on a dark strip, names beside it | `BmScoreBanner` (bm_view.dart) in the existing scoreboard; team chips keep name + orange turn bar (crest dropped on narrow chips, it is on every disc) |
| Last minute: banner pulses yellow -> red (01:00 yellow, 00:58 red, 00:56 yellow) | `bmClockRed`: 4 s pulse over the last 60 s, solid red once the time is up and in golden goal |
| Clock counts down 01:00 -> 00:00 | kept the ANIX count-up clock (owner decision v3), now `mm:ss` with Persian digits in Farsi |
| "یک دقیقه تا پایان بازی": dark rounded pill beside the bar handle, ~3 s | `BmMinuteToast`, `kBmMinuteToastSeconds = 3`, fired once when the clock enters the last minute (not on a rejoin inside it, not in golden goal) |
| Score table rows: player avatar, name, grey points pill (room points, e.g. 175 / 0) | one row per player (team games: every seat) with the player's avatar (ANIX portrait or photo; online avatars sent on the live channel `fs_av`), and the match points = the side's goals (ANIX has no room points) |

Fixed on the way: the score table never appeared in a running match (it was a `build()` child changed only from the
ticker); the formation button no longer sits over the table; English countdown line keeps LTR order; the classic ball
keeps its patches readable while rolling (one light blur tap instead of up to three).
Tests: `test/games/finger_soccer_v61_test.dart` (clock colour, banner, bot match toast + table rows with avatars, local
match, online 1v1 and 3v3 rows + avatar exchange). Render shots: `final/finger_soccer_last_minute.png`,
`final/finger_soccer_score_table.png`, `intro/score_table.png`.
