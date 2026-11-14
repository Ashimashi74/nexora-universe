class_name NxEngine
extends RefCounted
## NEXORA physics engine.
## DEFAULT model "nx8": POOL (billiards) physics (Nov 2026): shots go exactly along the aim with speed linear in drag
##   length (SHOT_MAX), straight-line motion (no spin/curve), constant cloth friction (linear speed decay), discs 3x the ball's mass,
##   body contacts disc-disc E_BODY .95 / disc-ball E_DISC_BALL .70, light contacts softer, resolved at the time of impact, cushions E_CUSHION .85 with angle in = out,
##   adaptive substeps. Sizes: disc 0.128, ball ~0.07 of pitch width. Also used by online matches (host simulates).
## cfg.model = "v4": the previous line-by-line port of src/game/engine.ts (reference only).
## Fixed 240 Hz sub-stepping, impulse-based circle collisions with positional correction,
## rolling 3D ball rotation, render interpolation (prev -> current).
##
## Feel tweaks requested for the Godot build (all OFF when cfg.classic == true, which is bit-for-bit the TS engine):
## (v4 only)
##  * ball launch ramp: a struck ball eases up to its impulse velocity over LAUNCH_T (~75 ms) instead of jumping
##  * visual ball roll reduced to ROLL_VIS (35%) and visual spin to SPIN_VIS of the TS rate (render only, no physics effect)

const D := preload("res://src/core/data.gd")
const K := 1.27
const PR := 49.0           # piece radius: reference screenshot disc diameter = 0.128 x pitch width (767 px -> 98 px)
const PR_V4 := 49.0
const POST_R8 := 5.0
const BR := 27.0           # ball radius: diameter 54 px = ~0.07 x pitch width (767 px); user asked for a bigger ball (was 22)
const BR8 := 25.5
const RC := 70.0
const LMAX := 210.0
const STEP := 1.0 / 240.0
const POST_R := 8.0
const HV := 8.0
const PF1 := 430.0
const PF2 := 1.0
const PV0 := 520.0
const EPP := 0.68         # pieces bounce off each other a bit harder (more energy transfer)
const PCAP := 215.0       # higher cap on post-hit ball speed (livelier rebounds)
const BK := 1.9
const BF := 175.0
const BFV := 140.0
const BVMAX := 1750.0
const BSTOP := 26.0
const PK := 1.55
const PFL := 300.0
const PFV := 230.0
const PSTOP := 20.0
const WALL_VOUT := 820.0
const POST_VOUT := 900.0
# --- Godot feel tweaks ---
const LAUNCH_T := 0.075     # s, ball launch ramp duration
const LAUNCH_MIN := 0.6     # fraction of travel speed at the instant of the strike
const ROLL_VIS := 0.35
const SPIN_VIS := 0.25
# --- nx8 model: POOL (billiards) physics, Nov 2026 ---
# Every body is treated like a pool ball on cloth: straight lines, constant rolling friction (linear speed decay),
# near-elastic equal-mass collisions (centered hit stops the striker, cut shots split ~90°), cushions that mirror
# the angle (in = out) and keep 85% of the speed. Continuous collision (time-of-impact rewind) + adaptive substeps.
const PM := 36.0            # disc mass — foosball-style: discs are heavy/rigid, the ball is light.
                            # 18:1 vs the ball means a disc barely moves when it touches the ball
                            # (≈9% speed change) while the ball flies off with ≈1.6x the disc speed.
const BM := 2.0             # ball mass (light, billiard-like)
const DISC_DISC_K := 0.45   # fraction of the disc-disc impulse actually applied: discs shove each
                            # other a little (foosball figures) instead of bouncing like billiard balls
const SHOT_MAX := 1900.0    # disc launch speed at full drag (LMAX); scales LINEARLY with drag length
const DISC_VMAX := 2000.0   # max launch speed (power stats / VIP can push a shot up to here)
const V_SAFE := 4200.0      # numerical safety clamp: heavy disc (18x) at DISC_VMAX can launch the ball to
                            # ≈1.61x its speed ≈ 3220 px/s; margin above that
const FRICTION := 360.0     # rolling (cloth) friction: constant deceleration in px/s^2, same for discs and ball
const V_STOP := 6.0         # a body whose speed would drop below this stops (was 2.0; heavier, cleaner stop)
const V_SETTLE := 80.0      # below this speed friction is doubled so bodies settle instead of creeping/jiggling
const SETTLE_K := 2.0
const E_SOFT := 0.55        # restitution of very light body contacts (rises linearly to E_BODY at V_SOFT)
const V_SOFT := 240.0       # px/s normal approach speed at or above which contacts use the full E_BODY
const E_BODY := 0.95        # restitution disc-disc (unchanged)
const E_DISC_BALL := 0.70   # restitution disc-ball (was 0.95). With the 3:1 mass ratio, 0.95 launched the ball at 1.46x
                            # the disc's speed (~8 pitch lengths of roll) - a light, flying ball. 0.70 keeps a strong shot
                            # (ball leaves at 1.275x the disc speed) while the ball feels heavier and a ball hitting a disc
                            # thuds (disc gets 42%, ball rebounds 27%) instead of knocking it away.
const E_CUSHION := 0.85     # restitution off walls / goal frame / posts; tangential speed scaled the same -> angle in = angle out
const SUB_PX := 4.0         # max travel per substep (px): substeps chosen so no body moves more than this per substep
const SUB_MAX := 16
const ROLL_K := 0.6         # visual roll rate vs true rolling (render only)
# legacy names kept for any external readers
const E_WALL := E_CUSHION
const E_WALL_B := E_CUSHION
const E_DD := E_BODY
const E_DB := E_BODY
const BALL_VMAX := V_SAFE
const CORNER_NUDGE := 70.0  # px/s push out of a sharp corner for a body resting against both walls

const GOAL_COLS := [Color("#ffd23a"), Color("#ffffff"), Color("#3bd0ff"), Color("#ff4a7a"), Color("#7bff5a")]
const HIT_COLS := [Color("#ffffff"), Color("#9fe8ff"), Color("#5cb6ff")]

class Goal:
	var team: int
	var y: float
	var x1: float
	var x2: float
	var d: int
	func _init(t: int, _y: float, a: float, b: float, _d: int) -> void:
		team = t; y = _y; x1 = a; x2 = b; d = _d

class Particle:
	var x: float
	var y: float
	var vx: float
	var vy: float
	var l: float
	var m: float
	var r: float
	var c: Color
	var k: int
	var g: float

static func power_mul(p: float) -> float: return 0.72 + (minf(10, maxf(1, p)) - 1) / 9.0 * 0.72
static func aim_dev_deg(a: float) -> float: return (10 - minf(10, maxf(1, a))) / 9.0 * 4.0
static func aim_preview(a: float) -> float: return 0.45 + (minf(10, maxf(1, a)) - 1) / 9.0 * 0.75

var f: Dictionary
var F := {"l": 0.0, "r": 0.0, "t": 0.0, "b": 0.0}
var Fl := 0.0
var Fr := 0.0
var Ft := 0.0
var Fb := 0.0
var CX := 0.0
var CY := 0.0
var KY := 0.0
var goals: Array = []
var GG := {"w": 0.0, "h": 0.0, "x": 0.0}
var DEPTH := 120.0
var bodies: Array = []
var ball: NxBody
var parts: Array = []
var trail: Array = []       # Array[Vector3(x, y, a)]
var score := [0, 0]
var turn := 0
var phase := "aim"
var shots := 0
var idle := 0.0
var pause := 0.0
var kick := 0
var acc := 0.0
var slow := 0.0
var flash := 0.0
var cam := 0.0
var shake := [0.0, 0.0]
var ripple := [0.0, 0.0]
var ripple_x := [0.0, 0.0]
var mleft := 0.0
var tleft := 0.0
var sudden := false
var ai_t := 0.0
var ai_plan = null          # {b, dx, dy, l, t}
var drag = null             # {b, sx, sy, cx, cy, ai}
var events: Array = []
var cfg: Dictionary
var time := 0.0
var last_who := 0
var last_power := 0.0
var ai_teams := [false, false]
var rng := RandomNumberGenerator.new()
var classic := false
var v4 := false            # cfg.model == "v4" (old TS port)
var pr := PR
var _corners: Array = []    # [[cx, cy, sx, sy] x4] (TS order: tl, tr, bl, br)
var _cxl := 0.0
var _cxr := 0.0
var _cyt := 0.0
var _cyb := 0.0

# normalized cfg
var c_ai := false
var c_ai_lvl := 1
var c_limit := 3
var c_match_time := 0.0
var c_turn_time := 15.0
var c_vip := [false, false]
var c_forms := [0, 0]
var c_stats = null

func _init(_cfg: Dictionary) -> void:
	cfg = _cfg
	if cfg.has("seed"): rng.seed = int(cfg.seed)
	else: rng.randomize()
	classic = bool(cfg.get("classic", false))
	v4 = String(cfg.get("model", "v4" if classic else "nx8")) == "v4"
	if not v4: classic = false
	pr = PR_V4 if v4 else PR
	c_ai = bool(cfg.get("ai", false))
	c_ai_lvl = int(cfg.get("ai_lvl", cfg.get("aiLvl", 1)))
	c_limit = int(cfg.get("limit", 3))
	c_match_time = float(cfg.get("match_time", cfg.get("matchTime", 0)))
	c_turn_time = float(cfg.get("turn_time", cfg.get("turnTime", 15)))
	c_vip = cfg.get("vip", [false, false])
	c_forms = cfg.get("forms", [0, 0])
	c_stats = cfg.get("stats", null)
	var fi := int(cfg.get("field", 0))
	f = D.FIELDS[fi] if fi >= 0 and fi < D.FIELDS.size() else D.FIELDS[0]
	Fl = f.L + 4; Fr = f.R - 4; Ft = f.T + 4; Fb = f.B - 4
	F = {"l": Fl, "r": Fr, "t": Ft, "b": Fb}
	CX = (Fl + Fr) / 2.0; CY = (Ft + Fb) / 2.0; KY = f.cs
	var gi: Array = D.GS[f.gs]
	var gw: float = 2.0 * f.g / (gi[3] - gi[2])
	GG = {"w": gw, "h": gw * gi[1] / gi[0] * 1.28, "x": CX - f.g - gi[2] * gw}
	DEPTH = maxf(120.0, roundf(GG.h * 0.98))
	goals = [Goal.new(0, Ft, CX - f.g, CX + f.g, -1), Goal.new(1, Fb, CX - f.g, CX + f.g, 1)]
	_corners = [[Fl + RC, Ft + RC, 1.0, 1.0], [Fr - RC, Ft + RC, -1.0, 1.0], [Fl + RC, Fb - RC, 1.0, -1.0], [Fr - RC, Fb - RC, -1.0, -1.0]]
	_cxl = Fl + RC; _cxr = Fr - RC; _cyt = Ft + RC; _cyb = Fb - RC
	mleft = c_match_time; tleft = c_turn_time
	reset(int(cfg.get("first", 0)))

func _mk(x: float, y: float, team: int, r: float, m: float, id: int) -> NxBody:
	return NxBody.new(x, y, team, r, m, id)

func reset(kick_team: int) -> void:
	var Fw := Fr - Fl
	var Fh := Fb - Ft
	bodies = []; trail = []; parts = []; slow = 0.0; cam = 0.0
	for cm in 2:
		var sl: Array = D.slots(int(c_forms[cm]))
		for i in sl.size():
			var nx: float = sl[i][0]
			var ny: float = sl[i][1]
			var ins := pr + (10.0 if v4 else 6.0)
			var x := Fl + ins + nx * (Fw - 2 * ins)
			var y := (Ft + ny * Fh) if cm else (Fb - ny * Fh)
			bodies.append(_mk(x, y, cm, pr, 5.0 if v4 else PM, cm * 20 + i))
	ball = _mk(CX, KY, 2, BR if not v4 else 25.5, BM, 99)
	bodies.append(ball)
	turn = kick_team; phase = "aim"; drag = null; pause = 0.0; idle = 0.0; shots = 0
	tleft = c_turn_time; ai_t = 0.0; ai_plan = null
	events.append({"t": "turn", "team": turn})

func is_ai_turn() -> bool: return (c_ai and turn == 1) or bool(ai_teams[turn])
func can_control() -> bool: return phase == "aim" and not is_ai_turn()

# ---------- input ----------
func pick(x: float, y: float) -> bool:
	if not can_control(): return false
	var fb: NxBody = null
	var bd := 1e9
	for b in bodies:
		if b.team == turn and b != ball:
			var d := sqrt((x - b.x) * (x - b.x) + (y - b.y) * (y - b.y))
			if d < b.r + (34 if v4 else 30) and d < bd: fb = b; bd = d
	if fb == null: return false
	drag = {"b": fb, "sx": fb.x, "sy": fb.y, "cx": x, "cy": y, "ai": false}
	return true

func move(x: float, y: float) -> void:
	if drag != null and not drag.ai: drag.cx = x; drag.cy = y

func release() -> void:
	var d = drag
	if d == null or d.ai: return
	drag = null
	var dx: float = d.sx - d.cx
	var dy: float = d.sy - d.cy
	var l := sqrt(dx * dx + dy * dy)
	if l > 18 and phase == "aim": fire(d.b, dx, dy, l, true)

func cancel() -> void:
	if drag != null and not drag.ai: drag = null

func aim_info():
	var d = drag
	if d == null: return null
	var dx: float = d.sx - d.cx
	var dy: float = d.sy - d.cy
	var l := sqrt(dx * dx + dy * dy)
	if l < 18: return {"b": d.b, "p": 0.0, "ux": 0.0, "uy": 0.0}
	return {"b": d.b, "p": minf(l, LMAX) / LMAX, "ux": dx / l, "uy": dy / l}

func stats_of(team: int) -> Dictionary:
	if c_stats != null and c_stats.size() > team and c_stats[team] != null: return c_stats[team]
	return {"power": 5.0, "accuracy": 5.0}

func fire(b: NxBody, dx: float, dy: float, l: float, human := false) -> void:
	var p := minf(l, LMAX) / LMAX
	var team := b.team
	last_power = p
	var v := ((260 + 1085 * pow(p, 0.8)) * K * 1.32) if v4 else (SHOT_MAX * p)
	if c_stats != null: v *= power_mul(float(stats_of(team).power))
	elif c_vip[team]: v *= 1.16
	if not v4: v = minf(v, DISC_VMAX)
	var ux := dx / l
	var uy := dy / l
	# shot aim: human shots follow the aim arrow with a spread that depends on the
	# disc's accuracy stat (1★ ≈ ±4° … 10★ ≈ ±0°); AI stays perfectly mechanical.
	if human and c_stats != null:
		var dev := aim_dev_deg(float(stats_of(team).accuracy)) * PI / 180.0
		if dev > 0:
			var a := atan2(uy, ux) + (rng.randf() + rng.randf() - 1) * dev
			ux = cos(a); uy = sin(a)
	var vx := ux * v
	var vy := uy * v
	if v4: b.tvx = vx * 1.02; b.tvy = vy * 1.02; b.ramp = 0.06; b.vx = vx * 0.5; b.vy = vy * 0.5; b.boost = 0.22
	else: b.vx = vx; b.vy = vy; b.ramp = 0.0; b.boost = 0.0; b.tvx = 0.0; b.tvy = 0.0; b.spin = 0.0
	if not v4 and b.team != turn: turn = b.team
	phase = "move"; idle = 0.0; shots += 1; drag = null
	if v4: cam = maxf(cam, 0.18)   # nx8/Godot: no camera kick on shots (crisp, no shake)
	last_who = b.team
	events.append({"t": "shot", "team": b.team})

# ---------- simulation ----------
func _eN(bl: bool, vn: float) -> float:
	if not v4:
		return E_WALL_B if bl else E_WALL
	if bl: return minf(0.64 - 0.24 * clampf((vn - 270 * K) / (730 * K), 0, 1), WALL_VOUT * K / maxf(1, vn))
	return minf(0.72, WALL_VOUT * 1.4 * K / maxf(1, vn))

func _walls(b: NxBody) -> void:
	if b != ball and b.gout != null:
		var g0: Goal = b.gout
		var dq := g0.d * (b.y - g0.y)
		if dq > -b.r * 1.05: b.vy = -g0.d * 270 * K; b.vx *= 0.6
		else: b.vy = 0.0; b.vx *= 0.2; b.gout = null
	var bl := b == ball
	var r := b.r
	var vs := sqrt(b.vx * b.vx + b.vy * b.vy)
	if b.x - r < Fl:
		b.x = Fl + r
		if b.vx < 0:
			if bl and vs > 200: events.append({"t": "wall", "power": vs / 1800})
			b.vx *= -_eN(bl, -b.vx); b.spin += b.vy / r * (0.03 if v4 else 0.008)
	if b.x + r > Fr:
		b.x = Fr - r
		if b.vx > 0:
			if bl and vs > 200: events.append({"t": "wall", "power": vs / 1800})
			b.vx *= -_eN(bl, b.vx); b.spin -= b.vy / r * (0.03 if v4 else 0.008)
	for g: Goal in goals:
		var dp := g.d * (b.y - g.y)
		if dp <= -r: continue
		var lo := g.x1 + (0.0 if bl else r)
		var hi := g.x2 - (0.0 if bl else r)
		var inside: bool = (b.x > g.x1 and b.x < g.x2) if bl else (dp > 0 or (b.x >= lo and b.x <= hi))
		if inside:
			var gl := phase == "goal" and bl
			var eb := 0.2 if gl else _eN(bl, absf(b.vy))
			var back := g.y + g.d * DEPTH
			if not bl and dp > r * 0.3 and vs < 150 * K and b.gout == null: b.gout = g
			if dp + r > DEPTH:
				b.y = back - g.d * r; b.vy = -g.d * absf(b.vy) * eb
				if gl: b.vx *= 0.6
			if dp > (r * 0.6 if bl else 0.0):
				var ee := 0.3 if gl else _eN(bl, absf(b.vx))
				if b.x < g.x1 + r:
					b.x = g.x1 + r
					if b.vx < 0: b.vx *= -ee
				if b.x > g.x2 - r:
					b.x = g.x2 - r
					if b.vx > 0: b.vx *= -ee
		else:
			if bl and vs > 200 and g.d * b.vy > 0: events.append({"t": "wall", "power": vs / 1800})
			b.y = g.y - g.d * r
			if g.d * b.vy > 0: b.vy = -g.d * absf(b.vy) * _eN(bl, absf(b.vy))
			b.spin += g.d * b.vx / r * (0.03 if v4 else 0.008)
	if not v4:
		_corner_nudge(b)
		return
	# corners (only near the four rounded corners) — v4 reference model only; nx8/Godot pitch has sharp 90° corners
	if b.x > _cxl and b.x < _cxr: return
	if b.y > _cyt and b.y < _cyb: return
	for ci in 4:
		var cx: float = _cxl if (ci & 1) == 0 else _cxr
		var cy: float = _cyt if ci < 2 else _cyb
		var csx := 1.0 if (ci & 1) == 0 else -1.0
		var csy := 1.0 if ci < 2 else -1.0
		if (b.x - cx) * csx < 0 and (b.y - cy) * csy < 0:
			var dx := b.x - cx
			var dy := b.y - cy
			var d := sqrt(dx * dx + dy * dy)
			var lim := RC - r
			if d > lim and d > 0:
				var nx := dx / d
				var ny := dy / d
				var vn := b.vx * nx + b.vy * ny
				b.x = cx + nx * lim; b.y = cy + ny * lim
				if vn > 0:
					var ec := _eN(bl, vn)
					b.vx -= (1 + ec) * vn * nx; b.vy -= (1 + ec) * vn * ny

## sharp corners: the side walls and goal-line walls meet at 90°. A body resting jammed into a corner
## (touching both walls, nearly still) gets a small push along the inward diagonal so it never sticks there.
func _corner_nudge(b: NxBody) -> void:
	var r := b.r
	var gap := 1.5
	var at_l := b.x - r <= Fl + gap
	var at_r := b.x + r >= Fr - gap
	if not (at_l or at_r): return
	var at_t: bool = b.y - r <= Ft + gap and (b.x < goals[0].x1 or b.x > goals[0].x2)
	var at_b: bool = b.y + r >= Fb - gap and (b.x < goals[1].x1 or b.x > goals[1].x2)
	if not (at_t or at_b): return
	if b.vx * b.vx + b.vy * b.vy > 90.0 * 90.0: return
	var nx := 1.0 if at_l else -1.0
	var ny := 1.0 if at_t else -1.0
	b.vx = nx * CORNER_NUDGE; b.vy = ny * CORNER_NUDGE

func _post(b: NxBody, px: float, py: float) -> void:
	var dx := b.x - px
	var dy := b.y - py
	var d := sqrt(dx * dx + dy * dy)
	var m := b.r + POST_R
	if d >= m or d == 0: return
	var nx := dx / d
	var ny := dy / d
	var vn := b.vx * nx + b.vy * ny
	b.x = px + nx * m; b.y = py + ny * m
	if vn < 0:
		var kp := 1 + minf(0.62 - 0.14 * minf(1, -vn / (2000 * K)), POST_VOUT * K / maxf(1, -vn))
		b.vx -= kp * vn * nx; b.vy -= kp * vn * ny
		if b == ball: events.append({"t": "post", "power": -vn / 1800})
		if b == ball and -vn > 900 * K: cam = maxf(cam, 0.25)

func _hit(a: NxBody, b: NxBody) -> void:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var d := sqrt(dx * dx + dy * dy)
	var m := a.r + b.r
	if d >= m: return
	if d < 1e-4: dx = 1.0; dy = 0.0; d = 1.0
	var nx := dx / d
	var ny := dy / d
	var sm := a.im + b.im
	var isB := a == ball or b == ball
	var ka := 1.0 / HV if (isB and a != ball) else 1.0
	var kb := 1.0 / HV if (isB and b != ball) else 1.0
	if not isB:
		var sa := sqrt(a.vx * a.vx + a.vy * a.vy)
		var sb := sqrt(b.vx * b.vx + b.vy * b.vy)
		if sa > sb: kb = 0.85
		else: ka = 0.85
	var wa := a.im / sm * ka
	var wb := b.im / sm * kb
	if isB:
		if a == ball: wa = 1 - wb
		else: wb = 1 - wa
	var pen := maxf(m - d - 0.3, 0) * 0.9
	a.x -= nx * pen * wa; a.y -= ny * pen * wa; b.x += nx * pen * wb; b.y += ny * pen * wb
	a.vox = clampf(a.vox + nx * pen * wa, -9, 9); a.voy = clampf(a.voy + ny * pen * wa, -9, 9)
	b.vox = clampf(b.vox - nx * pen * wb, -9, 9); b.voy = clampf(b.voy - ny * pen * wb, -9, 9)
	var vn := (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
	if vn >= 0: return
	var e := 0.0
	if vn < -40 * K:
		if isB: e = (0.68 if v4 else 0.74) - 0.12 * minf(1.0, maxf(0.0, (-vn - 500 * K) / (1200 * K)))
		else: e = EPP
	var j := -(1 + e) * vn / sm
	var pa: NxBody = null
	if isB: pa = b if a == ball else a
	var pre := sqrt(pa.vx * pa.vx + pa.vy * pa.vy) if pa != null else 0.0
	a.vx -= j * nx * a.im * ka; a.vy -= j * ny * a.im * ka; b.vx += j * nx * b.im * kb; b.vy += j * ny * b.im * kb
	if pa != null and pre < 260 * K:
		var ps := sqrt(pa.vx * pa.vx + pa.vy * pa.vy)
		var cp := PCAP * K
		if ps > cp: pa.vx *= cp / ps; pa.vy *= cp / ps
	if vn < -120 * K:
		events.append({"t": "hit", "ball": isB, "power": -vn / 1900})
		if not isB and vn < -420 * K:
			var q := minf(1, -vn / (1500 * K))
			a.sq = maxf(a.sq, q * 0.5); b.sq = maxf(b.sq, q * 0.5)   # heavier discs: half the squash pulse
			cam = maxf(cam, q * 0.1)
		if isB and v4 and not classic: ball.lt = LAUNCH_T
	if isB:
		ball.spin += (1.0 if ball == b else -1.0) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / ball.r * (0.3 if v4 else 0.42)
		ball.spin = clampf(ball.spin, -34, 34)
		var pw := minf(1, -vn / (1700 * K))
		if pw > 0.2:
			var o := a if ball == b else b
			if v4:
				ball.sq = maxf(ball.sq, pw); o.sq = maxf(o.sq, pw * 0.7); cam = maxf(cam, pw * 0.4)
				burst((a.x + b.x) / 2, (a.y + b.y) / 2, int(roundf(6 + pw * 10)), 260 + pw * 300, HIT_COLS, 0.35, 2)
			else:
				ball.sq = maxf(ball.sq, pw * 0.6); o.sq = maxf(o.sq, pw * 0.25); cam = maxf(cam, pw * 0.35)
				if pw > 0.45:
					burst((a.x + b.x) / 2, (a.y + b.y) / 2, int(roundf(4 + pw * 8)), 200 + pw * 260, HIT_COLS, 0.3, 2)
	if not v4:
		# off-centre contacts make discs spin (visual + tiny; opposite senses for the two bodies)
		var tv := -ny * (b.vx - a.vx) + nx * (b.vy - a.vy)
		if a != ball: a.spin = clampf(a.spin - tv / a.r * 0.12, -18, 18)
		if b != ball: b.spin = clampf(b.spin - tv / b.r * 0.12, -18, 18)

## nx8 POOL contact: mass-weighted (disc PM=3, ball BM=1), near-elastic (E_BODY) impulse along the line of centres, resolved at the exact
## time of impact (the pair is rewound to the instant they touched, the impulse applied with the true contact normal,
## then advanced again), so centered hits transfer ~all speed and cut shots split at ~90° regardless of step size.
## No spin, no damping hacks, no speed caps beyond a numerical safety clamp.
func _cap(b: NxBody) -> void:
	var s2 := b.vx * b.vx + b.vy * b.vy
	if s2 > V_SAFE * V_SAFE:
		var k := V_SAFE / sqrt(s2)
		b.vx *= k; b.vy *= k

func _hit8(a: NxBody, b: NxBody, h: float) -> void:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var dd := dx * dx + dy * dy
	var m := a.r + b.r
	if dd >= m * m: return
	var rvx := b.vx - a.vx
	var rvy := b.vy - a.vy
	var dv := dx * rvx + dy * rvy          # < 0 while approaching
	var sm := a.im + b.im
	var isB := a == ball or b == ball
	var vn := 0.0
	if dv < 0.0:
		# continuous collision: rewind both bodies to the time of impact |d - rv*s| = m
		var vv := rvx * rvx + rvy * rvy
		var s := 0.0
		if vv > 1e-9:
			s = (dv + sqrt(maxf(0.0, dv * dv - vv * (dd - m * m)))) / vv
			s = clampf(s, 0.0, h)
		a.x -= a.vx * s; a.y -= a.vy * s; b.x -= b.vx * s; b.y -= b.vy * s
		dx = b.x - a.x; dy = b.y - a.y
		var d := sqrt(dx * dx + dy * dy)
		if d < 1e-4: dx = 0.0; dy = -1.0; d = 1.0
		var nx := dx / d
		var ny := dy / d
		vn = rvx * nx + rvy * ny
		if vn < 0.0:
			# light contacts thud instead of bouncing (less jiggle); real hits stay at E_BODY
			var e_full := E_DISC_BALL if isB else E_BODY
			var ee := e_full if -vn >= V_SOFT else lerpf(minf(E_SOFT, e_full), e_full, -vn / V_SOFT)
			var j := -(1.0 + ee) * vn / sm
			if not isB:
				# foosball: discs are rigid figures, disc-disc hits only nudge each other
				j *= DISC_DISC_K
			a.vx -= j * nx * a.im; a.vy -= j * ny * a.im; b.vx += j * nx * b.im; b.vy += j * ny * b.im
			_cap(a); _cap(b)
		a.x += a.vx * s; a.y += a.vy * s; b.x += b.vx * s; b.y += b.vy * s
	# any overlap left (bodies pushed together by a third body / a wall) is removed positionally, no velocity change
	dx = b.x - a.x; dy = b.y - a.y
	dd = dx * dx + dy * dy
	if dd < m * m:
		var d2 := sqrt(dd)
		var ux := 0.0
		var uy := -1.0
		if d2 > 1e-4: ux = dx / d2; uy = dy / d2
		var pen := m - d2
		a.x -= ux * pen * a.im / sm; a.y -= uy * pen * a.im / sm
		b.x += ux * pen * b.im / sm; b.y += uy * pen * b.im / sm
	if vn < -150:
		events.append({"t": "hit", "ball": isB, "power": -vn / 1900})
		if not isB and vn < -520:
			var q := minf(1, -vn / 1900.0)
			a.sq = maxf(a.sq, q * 0.5); b.sq = maxf(b.sq, q * 0.5)   # heavier discs: half the squash pulse
		if isB:
			var pw := minf(1, -vn / 2100.0)
			if pw > 0.2:
				var o := a if ball == b else b
				ball.sq = maxf(ball.sq, pw * 0.6); o.sq = maxf(o.sq, pw * 0.25)
				if pw > 0.45:
					burst((a.x + b.x) / 2, (a.y + b.y) / 2, int(roundf(4 + pw * 8)), 200 + pw * 260, HIT_COLS, 0.3, 2)

func _rotate(b: NxBody, wx: float, wy: float, wz: float, dt: float) -> void:
	var w := sqrt(wx * wx + wy * wy + wz * wz)
	var th := w * dt
	if th < 1e-7: return
	var ax := wx / w
	var ay := wy / w
	var az := wz / w
	var c := cos(th)
	var s := sin(th)
	var t := 1 - c
	var m0 := t * ax * ax + c
	var m1 := t * ax * ay - s * az
	var m2 := t * ax * az + s * ay
	var m3 := t * ax * ay + s * az
	var m4 := t * ay * ay + c
	var m5 := t * ay * az - s * ax
	var m6 := t * ax * az - s * ay
	var m7 := t * ay * az + s * ax
	var m8 := t * az * az + c
	var r0 := b.r0
	var r1 := b.r1
	var r2 := b.r2
	var r3 := b.r3
	var r4 := b.r4
	var r5 := b.r5
	var r6 := b.r6
	var r7 := b.r7
	var r8 := b.r8
	var n0 := m0 * r0 + m1 * r3 + m2 * r6
	var n1 := m0 * r1 + m1 * r4 + m2 * r7
	var n2 := m0 * r2 + m1 * r5 + m2 * r8
	b.r3 = m3 * r0 + m4 * r3 + m5 * r6; b.r4 = m3 * r1 + m4 * r4 + m5 * r7; b.r5 = m3 * r2 + m4 * r5 + m5 * r8
	b.r6 = m6 * r0 + m7 * r3 + m8 * r6; b.r7 = m6 * r1 + m7 * r4 + m8 * r7; b.r8 = m6 * r2 + m7 * r5 + m8 * r8
	var l0 := sqrt(n0 * n0 + n1 * n1 + n2 * n2)
	b.r0 = n0 / l0; b.r1 = n1 / l0; b.r2 = n2 / l0

## nx8 ball-only goal post: round post, cushion restitution, angle in = angle out about the contact normal
func _post8(b: NxBody, px: float, py: float) -> void:
	var dx := b.x - px
	var dy := b.y - py
	var d := sqrt(dx * dx + dy * dy)
	var m := b.r + POST_R8
	if d >= m or d == 0: return
	var nx := dx / d
	var ny := dy / d
	var vn := b.vx * nx + b.vy * ny
	b.x = px + nx * m; b.y = py + ny * m
	if vn < 0:
		# mirror the velocity about the tangent and scale the whole vector by E_CUSHION
		b.vx = E_CUSHION * (b.vx - 2.0 * vn * nx); b.vy = E_CUSHION * (b.vy - 2.0 * vn * ny)
		if b == ball:
			events.append({"t": "post", "power": -vn / 1800})

## cushion bounce on an axis-aligned wall: normal component reversed, whole velocity scaled by E_CUSHION
## (so the reflection angle equals the incidence angle), overshoot mirrored back.
func _cushion_x(b: NxBody, wall: float, side: float) -> void:
	# side = +1 for a wall on the left (body must stay at x >= wall), -1 for a wall on the right
	var over := (wall - b.x) * side
	if over <= 0.0: return
	if b.vx * side < 0.0:
		var vs := sqrt(b.vx * b.vx + b.vy * b.vy)
		if b == ball and vs > 200: events.append({"t": "wall", "power": vs / 1800})
		b.vx = -b.vx * E_CUSHION; b.vy *= E_CUSHION
		b.x = wall + side * over * E_CUSHION
	else:
		b.x = wall

func _cushion_y(b: NxBody, wall: float, side: float, ev := true) -> void:
	var over := (wall - b.y) * side
	if over <= 0.0: return
	if b.vy * side < 0.0:
		var vs := sqrt(b.vx * b.vx + b.vy * b.vy)
		if ev and b == ball and vs > 200: events.append({"t": "wall", "power": vs / 1800})
		b.vy = -b.vy * E_CUSHION; b.vx *= E_CUSHION
		b.y = wall + side * over * E_CUSHION
	else:
		b.y = wall

func _walls8(b: NxBody) -> void:
	if b != ball and b.gout != null:
		var g0: Goal = b.gout
		var dq := g0.d * (b.y - g0.y)
		if dq > -b.r * 1.05: b.vy = -g0.d * 270 * K; b.vx *= 0.6
		else: b.vy = 0.0; b.vx *= 0.2; b.gout = null
	var bl := b == ball
	var r := b.r
	_cushion_x(b, Fl + r, 1.0)
	_cushion_x(b, Fr - r, -1.0)
	var vs := sqrt(b.vx * b.vx + b.vy * b.vy)
	for g: Goal in goals:
		var dp := g.d * (b.y - g.y)
		if dp <= -r: continue
		var lo := g.x1 + (0.0 if bl else r)
		var hi := g.x2 - (0.0 if bl else r)
		var inside: bool = (b.x > g.x1 and b.x < g.x2) if bl else (dp > 0 or (b.x >= lo and b.x <= hi))
		if inside:
			# inside the goal mouth / net
			var gl := phase == "goal" and bl
			var back := g.y + g.d * DEPTH
			if not bl and dp > r * 0.3 and vs < 150 * K and b.gout == null: b.gout = g
			if dp + r > DEPTH:
				b.y = back - g.d * r
				if g.d * b.vy > 0:
					b.vy = -b.vy * (0.2 if gl else E_CUSHION)
					b.vx *= (0.6 if gl else E_CUSHION)
			if dp > (r * 0.6 if bl else 0.0):
				var ee := 0.3 if gl else E_CUSHION
				if b.x < g.x1 + r:
					b.x = g.x1 + r
					if b.vx < 0: b.vx = -b.vx * ee; b.vy *= (1.0 if gl else ee)
				if b.x > g.x2 - r:
					b.x = g.x2 - r
					if b.vx > 0: b.vx = -b.vx * ee; b.vy *= (1.0 if gl else ee)
		else:
			# goal-line cushion beside the mouth
			_cushion_y(b, g.y - g.d * r, -float(g.d))
	_corner_nudge(b)

## nx8 POOL step: adaptive substeps (no body travels more than SUB_PX per substep) + time-of-impact contacts
func _sim8(dt: float) -> void:
	# energy bound: with e <= 1 kinetic energy never grows, so no body can exceed sqrt(sum m v^2 / m_min) this step
	# (m = 1/im; with heavier discs this bounds the ball's post-hit speed too)
	var e2 := 0.0
	var mmin := 1e9
	for b: NxBody in bodies:
		var mb := 1.0 / maxf(b.im, 1e-6)
		e2 += mb * (b.vx * b.vx + b.vy * b.vy)
		mmin = minf(mmin, mb)
	var n := clampi(int(ceil(sqrt(e2 / mmin) * dt / SUB_PX)), 1, SUB_MAX)
	var h := dt / n
	for i in n:
		_sub8(h)
		if phase == "move":
			for g: Goal in goals:
				if ball.x > g.x1 and ball.x < g.x2 and ((ball.y < g.y - ball.r * 0.8) if g.d < 0 else (ball.y > g.y + ball.r * 0.8)):
					_scored(g.team)
					break

func _sub8(h: float) -> void:
	for b: NxBody in bodies:
		if b.vox != 0 or b.voy != 0:
			var q := 1 - minf(1, h * 15)
			b.vox *= q; b.voy *= q
			if absf(b.vox) < 0.04: b.vox = 0.0
			if absf(b.voy) < 0.04: b.voy = 0.0
		b.x += b.vx * h; b.y += b.vy * h
		var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
		if sp > 0:
			# cloth rolling friction: constant deceleration along the current direction (straight line, linear speed decay)
			var ns := sp - FRICTION * (SETTLE_K if sp < V_SETTLE else 1.0) * h
			if ns < V_STOP: b.vx = 0.0; b.vy = 0.0
			else:
				var k2 := minf(ns, V_SAFE) / sp
				b.vx *= k2; b.vy *= k2
		b.spin = 0.0
		if b == ball:
			b.sq *= 1 - 9 * h
			# visual rolling only (pure roll about the axis perpendicular to travel, no side spin)
			if b.vx != 0.0 or b.vy != 0.0:
				var roll := ROLL_K / b.r
				_rotate(b, -b.vy * roll, b.vx * roll, 0.0, h)
		_walls8(b)
	var n := bodies.size()
	for it in 2:
		for a in n:
			var ba: NxBody = bodies[a]
			for c in range(a + 1, n):
				var bc: NxBody = bodies[c]
				var mm := ba.r + bc.r
				var ddx := bc.x - ba.x
				if ddx >= mm or ddx <= -mm: continue
				var ddy := bc.y - ba.y
				if ddy >= mm or ddy <= -mm: continue
				_hit8(ba, bc, h if it == 0 else 0.0)
	if ball:
		for g: Goal in goals:
			_post8(ball, g.x1, g.y); _post8(ball, g.x2, g.y)
	for b: NxBody in bodies: _walls8(b)

func _sim(dt: float) -> void:
	if not v4: _sim8(dt); return
	for b: NxBody in bodies:
		if b.ramp > 0:
			var k := minf(1, dt / b.ramp)
			b.vx += (b.tvx - b.vx) * k; b.vy += (b.tvy - b.vy) * k; b.ramp -= dt
			if b.ramp <= 0: b.ramp = 0.0
		if b.vox != 0 or b.voy != 0:
			var q := 1 - minf(1, dt * 15)
			b.vox *= q; b.voy *= q
			if absf(b.vox) < 0.04: b.vox = 0.0
			if absf(b.voy) < 0.04: b.voy = 0.0
		var bl := b == ball
		if bl and b.lt > 0:
			# launch ramp: travel eases from LAUNCH_MIN up to the full struck velocity (smoothstep), velocity itself untouched
			var u := 1.0 - b.lt / LAUNCH_T
			var ls := LAUNCH_MIN + (1.0 - LAUNCH_MIN) * (u * u * (3.0 - 2.0 * u))
			b.x += b.vx * dt * ls; b.y += b.vy * dt * ls
			b.lt -= dt
			if b.lt < 0: b.lt = 0.0
		else:
			b.x += b.vx * dt; b.y += b.vy * dt
		var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
		if sp > 0:
			if bl:
				var ns := sp * exp(-BK * dt) - BF * K * minf(1, sp / (BFV * K)) * dt
				if ns < BSTOP * K: b.vx = 0.0; b.vy = 0.0; b.vox = 0.0; b.voy = 0.0
				else:
					ns = minf(ns, BVMAX * K)
					var k2 := ns / sp
					b.vx *= k2; b.vy *= k2
			else:
				var fb := 0.35 if b.boost > 0 else 1.0
				if b.boost > 0: b.boost -= dt
				var ns2 := sp * exp(-PK * fb * dt) - PFL * K * minf(1, sp / (PFV * K)) * fb * dt
				if ns2 < PSTOP * K and b.ramp <= 0: b.vx = 0.0; b.vy = 0.0
				else:
					ns2 = maxf(0, minf(ns2, 2800 * K))
					var k3 := ns2 / sp
					b.vx *= k3; b.vy *= k3
		if bl:
			var sp2 := sqrt(b.vx * b.vx + b.vy * b.vy)
			b.spin *= 1 - (1.05 if sp2 > 0 else 3.2) * dt
			if absf(b.spin) < 0.02: b.spin = 0.0
			var roll := 0.95 / b.r
			if sp2 > 0 or b.spin != 0:
				if classic: _rotate(b, -b.vy * roll, b.vx * roll, b.spin * 0.55, dt)
				else: _rotate(b, -b.vy * roll * ROLL_VIS, b.vx * roll * ROLL_VIS, b.spin * 0.55 * SPIN_VIS, dt)
			b.ang += b.spin * dt
		else:
			b.spin *= 1 - 4.2 * dt; b.ang += b.spin * dt
		b.sq *= 1 - 9 * dt
		_walls(b)
	var n := bodies.size()
	for it in 2:
		for a in n:
			var ba: NxBody = bodies[a]
			var ax := ba.x
			var ay := ba.y
			var ar := ba.r
			for c in range(a + 1, n):
				var bc: NxBody = bodies[c]
				# cheap reject (same result as the d >= m test inside _hit, without the sqrt/call)
				var mm := ar + bc.r
				var ddx := bc.x - ax
				if ddx >= mm or ddx <= -mm: continue
				var ddy := bc.y - ay
				if ddy >= mm or ddy <= -mm: continue
				_hit(ba, bc)
				ax = ba.x; ay = ba.y
	for g: Goal in goals:
		var gy := g.y
		var gx1 := g.x1
		var gx2 := g.x2
		for b: NxBody in bodies:
			var mp := b.r + POST_R
			if absf(b.y - gy) >= mp: continue
			if absf(b.x - gx1) < mp: _post(b, gx1, gy)
			if absf(b.x - gx2) < mp: _post(b, gx2, gy)
	for b: NxBody in bodies: _walls(b)
	if phase == "move":
		for g: Goal in goals:
			if ball.x > g.x1 and ball.x < g.x2 and ((ball.y < g.y - ball.r * 0.8) if g.d < 0 else (ball.y > g.y + ball.r * 0.8)):
				_scored(g.team)

func _scored(t: int) -> void:
	var nogoal := shots <= 1
	events.append({"t": "goal", "team": t, "nogoal": nogoal})
	if nogoal: phase = "goal"; pause = 1.4; kick = turn; return
	ripple[t] = 1.0; ripple_x[t] = ball.x; score[t] += 1; pause = 2.0 if v4 else 1.8; flash = 1.0; shake[t] = 0.6; phase = "goal"; kick = 1 - t
	slow = 1.1; cam = 1.4
	var g: Goal = goals[t]
	burst(ball.x, g.y, 80, 760, GOAL_COLS, 1.4, 1); burst(ball.x, g.y, 50, 520, GOAL_COLS, 1.8, 3)

func burst(x: float, y: float, n: int, sp: float, cols: Array, life: float, k := 0) -> void:
	if parts.size() > 420: return
	for i in n:
		var a := rng.randf() * PI * 2
		var v := sp * (0.3 + rng.randf())
		var p := Particle.new()
		p.x = x; p.y = y; p.vx = cos(a) * v; p.vy = sin(a) * v; p.l = life * (0.6 + rng.randf() * 0.6); p.m = life
		p.c = cols[i % cols.size()]; p.r = 2 + rng.randf() * 3.5; p.k = k; p.g = 600.0 if k == 3 else 0.0
		parts.append(p)

func _finish_turn() -> void:
	turn = 1 - turn; phase = "aim"; tleft = c_turn_time; ai_t = 0.0; ai_plan = null
	events.append({"t": "turn", "team": turn})

func _end() -> void:
	phase = "over"; events.append({"t": "end", "score": [score[0], score[1]]})

func time_up() -> bool: return c_match_time > 0 and not sudden and mleft <= 0

# ---------- main step (call once per frame) ----------
func update(rdt: float) -> void:
	var dt := minf(rdt, 0.05)
	time += dt
	if phase == "over": tick_fx(dt); return
	if c_match_time > 0 and not sudden and mleft > 0: mleft = maxf(0, mleft - dt)
	var ts := 1.0
	if slow > 0:
		slow -= dt
		ts = (0.3 + 0.7 * pow(1 - maxf(0, slow) / 1.1, 2)) if v4 else (0.32 + 0.68 * pow(1 - maxf(0, slow) / 1.1, 2))
	acc += dt * ts
	var n := 0
	var cap := 16 if v4 else 14
	while acc >= STEP:
		if n >= cap: n += 1; break
		n += 1
		for b: NxBody in bodies: b.px = b.x; b.py = b.y
		_sim(STEP); acc -= STEP
	if n > cap: acc = 0.0
	if phase == "move":
		var moving := false
		for b: NxBody in bodies:
			if b.vx != 0 or b.vy != 0 or (v4 and b.ramp > 0): moving = true; break
		idle = 0.0 if moving else idle + dt
		if idle > (0.15 if v4 else 0.25): _finish_turn()
	elif phase == "aim":
		if c_match_time > 0 and not sudden and mleft <= 0:
			if score[0] != score[1]: _end(); return
			sudden = true; events.append({"t": "clock"})
		if c_turn_time > 0:
			tleft -= dt
			if tleft <= 0:
				drag = null; ai_plan = null; _finish_turn()
				if not v4: tick_fx(dt); return
		if is_ai_turn(): _ai_tick(dt)
	elif phase == "goal":
		pause -= dt
		if pause <= 0:
			if c_match_time > 0:
				if sudden or (mleft <= 0 and score[0] != score[1]): _end()
				else:
					if mleft <= 0: sudden = true
					reset(kick)
			elif score[0] >= c_limit or score[1] >= c_limit: _end()
			else: reset(kick)
	tick_fx(dt)

## online clients: visual-only goal feedback (the host owns the score)
func fx_goal(t: int) -> void:
	ripple[t] = 1.0; ripple_x[t] = ball.x
	flash = 1.0; shake[t] = 0.6; cam = 1.4
	var g: Goal = goals[t]
	burst(ball.x, g.y, 80, 760, GOAL_COLS, 1.4, 1); burst(ball.x, g.y, 50, 520, GOAL_COLS, 1.8, 3)

func tick_fx(dt: float) -> void:
	flash = maxf(0, flash - dt * 2); cam = maxf(0, cam - dt * 3.2)
	shake[0] = maxf(0, shake[0] - dt); ripple[0] = maxf(0, ripple[0] - dt * 0.8); ripple[1] = maxf(0, ripple[1] - dt * 0.8); shake[1] = maxf(0, shake[1] - dt)
	var sp := sqrt(ball.vx * ball.vx + ball.vy * ball.vy) if ball else 0.0
	if ball and sp > 60: trail.append(Vector3(ball.x, ball.y, minf(1, sp / 900)))
	var k := 0
	for i in trail.size():
		var p: Vector3 = trail[i]
		p.z -= dt * (3.2 if v4 else 3.0)   # nx8: slower fade -> slightly longer ball trail at high speed
		if p.z > 0: trail[k] = p; k += 1
	trail.resize(k)
	var tmax := 40 if v4 else 54
	if trail.size() > tmax:
		var cut := trail.size() - tmax
		for i in tmax: trail[i] = trail[i + cut]
		trail.resize(tmax)
	for b: NxBody in bodies:
		if b != ball:
			if not v4 and b.sq != 0: b.sq = b.sq - dt * 5 if b.sq > 0.02 else 0.0
			var s := sqrt(b.vx * b.vx + b.vy * b.vy)
			if s > 140 * K: b.tr.append(Vector2(b.x, b.y))
			elif b.tr.size(): b.tr.pop_front()
			if b.tr.size() > 12: b.tr.pop_front()
	k = 0
	for i in parts.size():
		var p: Particle = parts[i]
		p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.965; p.vy = p.vy * 0.965 + p.g * dt; p.l -= dt
		if p.l > 0: parts[k] = p; k += 1
	parts.resize(k)

## interpolation factor for rendering between physics steps
func alpha() -> float: return clampf(acc / STEP, 0, 1)

# ---------- AI ----------
func _ai_tick(dt: float) -> void:
	if ai_plan == null:
		ai_t += dt
		if ai_t < 0.7 + rng.randf() * (0.5 if v4 else 0.7): return
		var p = _ai_decide()
		if p == null: return
		p["t"] = 0.0
		ai_plan = p
		drag = {"b": p.b, "sx": p.b.x, "sy": p.b.y, "cx": p.b.x, "cy": p.b.y, "ai": true}
		return
	var pl: Dictionary = ai_plan
	pl.t += dt
	var k := minf(1, pl.t / 0.75)
	var e := k * k * (3 - 2 * k)
	if drag != null: drag.cx = pl.b.x - pl.dx * pl.l * e; drag.cy = pl.b.y - pl.dy * pl.l * e
	if k >= 1:
		drag = null; ai_plan = null
		fire(pl.b, pl.dx * pl.l, pl.dy * pl.l, pl.l)

static func _seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var vx := bx - ax
	var vy := by - ay
	var l2 := vx * vx + vy * vy
	if l2 == 0: l2 = 1.0
	var t := ((px - ax) * vx + (py - ay) * vy) / l2
	t = clampf(t, 0, 1)
	var qx := px - (ax + vx * t)
	var qy := py - (ay + vy * t)
	return sqrt(qx * qx + qy * qy)

func _clear(p: NxBody, x: float, y: float) -> bool:
	for o: NxBody in bodies:
		if o == p or o == ball: continue
		if _seg_dist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6: return false
	return true

func _ai_decide():
	var me := turn
	var mine: Array = []
	for b: NxBody in bodies:
		if b.team == me and b != ball: mine.append(b)
	var og: Goal = goals[1 - me]
	var target: Goal = goals[1 if me == 1 else 0]
	var lvl := c_ai_lvl
	var sg: float = [0.14, 0.06, 0.016][lvl]
	var gw := (target.x2 - target.x1) / 2
	var cands: Array = []
	for p: NxBody in mine:
		for ox in [-0.55, 0.0, 0.55]:
			var Tx: float = CX + ox * gw
			var Ty := target.y
			var ux := Tx - ball.x
			var uy := Ty - ball.y
			var ul := sqrt(ux * ux + uy * uy)
			if ul == 0: ul = 1.0
			ux /= ul; uy /= ul
			var cx := ball.x - ux * (p.r + ball.r + 1)
			var cy := ball.y - uy * (p.r + ball.r + 1)
			var vx := cx - p.x
			var vy := cy - p.y
			var dist := sqrt(vx * vx + vy * vy)
			if dist < 8: continue
			vx /= dist; vy /= dist
			var al := vx * ux + vy * uy
			if al < 0.2 or not _clear(p, cx, cy): continue
			var blk := 0
			for o: NxBody in bodies:
				if o.team == me or o == ball: continue
				if _seg_dist(o.x, o.y, ball.x, ball.y, Tx, Ty) < ball.r + o.r + 6: blk += 1
			cands.append({"p": p, "dx": vx, "dy": vy, "sc": 100 * al - dist * 0.03 - blk * 28 + (25.0 if absf(ball.y - Ty) < 420 else 0.0), "dist": dist, "atk": 1, "i": cands.size()})
		var wx := ball.x - p.x
		var wy := ball.y - p.y
		var dist2 := sqrt(wx * wx + wy * wy)
		if dist2 > 8:
			wx /= dist2; wy /= dist2
			if _clear(p, ball.x, ball.y):
				var to_own := absf(wy) if (wy * (og.y - ball.y) > 0) else 0.0
				cands.append({"p": p, "dx": wx, "dy": wy, "sc": 10 - dist2 * 0.04 - to_own * 55, "dist": dist2, "atk": 0, "i": cands.size()})
	if cands.is_empty():
		var best: NxBody = null
		var bd := INF
		for p: NxBody in mine:
			var dd := sqrt((p.x - ball.x) * (p.x - ball.x) + (p.y - ball.y) * (p.y - ball.y))
			if dd < bd: bd = dd; best = p
		if best == null: return null
		var vx2 := ball.x - best.x
		var vy2 := ball.y - best.y
		var d2 := sqrt(vx2 * vx2 + vy2 * vy2)
		if d2 == 0: d2 = 1.0
		cands.append({"p": best, "dx": vx2 / d2, "dy": vy2 / d2, "sc": 0.0, "dist": d2, "atk": 0, "i": 0})
	# stable descending sort (JS Array.sort is stable)
	cands.sort_custom(func(a, b): return a.sc > b.sc or (a.sc == b.sc and a.i < b.i))
	var pool_n: int = mini([4, 2, 1][lvl], cands.size())
	var c: Dictionary = cands[int(floor(rng.randf() * pool_n))]
	var gauss := (rng.randf() + rng.randf() + rng.randf() - 1.5) * 1.15
	var ang := atan2(c.dy, c.dx) + gauss * sg
	var pw: float = minf(1, 0.66 + c.dist / 1000) if lvl == 2 else minf(1, 0.5 + c.dist / 1100)
	if lvl == 0: pw *= 0.7 + rng.randf() * 0.3
	if c.atk and lvl > 0: pw = maxf(pw, 0.78)
	return {"b": c.p, "dx": cos(ang), "dy": sin(ang), "l": maxf(0.3, pw) * LMAX}
