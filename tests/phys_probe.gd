extends SceneTree
## Headless physics probe: measures shot travel distance / time / peak speed for discs and the ball.
## Run: godot --headless --path . -s res://tests/phys_probe.gd

const D := preload("res://src/core/data.gd")
const EngineS := preload("res://src/game/engine.gd")

func _mk_engine():
	var e = EngineS.new({"seed": 1, "turn_time": 0, "forms": [0, 0]})
	return e

func _clear_except(e, keep: Array) -> void:
	var nb: Array = []
	for b in e.bodies:
		if keep.has(b): nb.append(b)
	e.bodies = nb

func _run_until_stop(e, watch: Array, max_t := 12.0) -> Dictionary:
	var t := 0.0
	var peak := {}
	var start := {}
	var stop_t := {}
	var path := {}
	for b in watch:
		peak[b] = 0.0; start[b] = Vector2(b.x, b.y); stop_t[b] = -1.0; path[b] = 0.0
	var last := {}
	for b in watch: last[b] = Vector2(b.x, b.y)
	var max_step := 0.0
	while t < max_t:
		e.update(1.0 / 60.0); t += 1.0 / 60.0
		var all_stop := true
		for b in watch:
			var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
			peak[b] = maxf(peak[b], sp)
			var p := Vector2(b.x, b.y)
			var stepd: float = p.distance_to(last[b])
			path[b] += stepd
			if b == e.ball: max_step = maxf(max_step, stepd)
			last[b] = p
			if sp > 0: all_stop = false; stop_t[b] = -1.0
			elif stop_t[b] < 0: stop_t[b] = t
		if all_stop and t > 0.1: break
	var out := {}
	for b in watch:
		out[b] = {"path": snappedf(path[b], 0.1), "disp": snappedf(start[b].distance_to(Vector2(b.x, b.y)), 0.1), "t": snappedf(stop_t[b], 0.01), "peak": snappedf(peak[b], 0.1)}
	out["ball_max_px_per_frame"] = snappedf(max_step, 0.1)
	return out

func _initialize() -> void:
	var e0 = _mk_engine()
	print("PR=", EngineS.PR, " BR=", EngineS.BR, " pitch W=", e0.Fr - e0.Fl, " L=", e0.Fb - e0.Ft)
	_kickoff_check()
	# A: free disc shot, full and half power, straight up the left channel
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d, e.ball])
		e.ball.x = e.Fr - 60; e.ball.y = e.Ft + 300
		d.x = e.Fl + 120; d.y = e.Fb - 150; d.px = d.x; d.py = d.y
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -1.0 * pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d])
		print("FREE_DISC p=", pw, " ", r[d])
	# B: disc hits ball head-on at full and half power
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d, e.ball])
		var bx: float = e.Fl + 200.0
		d.x = bx; d.y = e.Fb - 120; d.px = d.x; d.py = d.y
		e.ball.x = bx; e.ball.y = d.y - d.r - e.ball.r - 60; e.ball.px = e.ball.x; e.ball.py = e.ball.y
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d, e.ball])
		var walls := 0
		for ev in e.events:
			if ev.t == "wall": walls += 1
		print("DISC->BALL p=", pw, " ball_walls=", walls, " disc ", r[d], " ball ", r[e.ball], " maxstep ", r["ball_max_px_per_frame"])
	for gapk in [0.7, 0.4]:
		_gap_case(gapk)
	_open_case()
	_aim_case()
	_pool_cases()
	quit(0)

func _open(e) -> void:
	# remove the walls (pitch "infinitely" large) to measure pure glide distance / time
	e.Fl = -1e6; e.Fr = 1e6; e.Ft = -1e6; e.Fb = 1e6
	for g in e.goals: g.y = 1e6 * (-1 if g.d < 0 else 1); g.x1 = -10.0; g.x2 = 10.0

func _open_case() -> void:
	var L := 1323.0
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d])
		_open(e)
		d.x = 0; d.y = 0; d.px = 0; d.py = 0
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d])
		print("OPEN_DISC p=", pw, " ", r[d], " = ", snappedf(r[d].path / L, 0.01), " L")
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = null
		for b in e.bodies:
			if b != e.ball and b.team == 0: d = b; break
		_clear_except(e, [d, e.ball])
		_open(e)
		d.x = 0; d.y = 0; d.px = 0; d.py = 0
		e.ball.x = 0; e.ball.y = -(d.r + e.ball.r + 60); e.ball.px = e.ball.x; e.ball.py = e.ball.y
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _run_until_stop(e, [d, e.ball])
		print("OPEN_DISC->BALL p=", pw, " ball ", r[e.ball], " = ", snappedf(r[e.ball].path / L, 0.01), " L")

func _kickoff_check() -> void:
	# formations x kickoff: min clearance ball<->disc and disc<->disc (negative = overlap)
	var worst_b := 1e9
	var worst_d := 1e9
	for fi in D.FORMS.size():
		for kt in 2:
			var e = EngineS.new({"seed": 1, "turn_time": 0, "forms": [fi, fi], "first": kt})
			for i in e.bodies.size():
				for j in range(i + 1, e.bodies.size()):
					var a = e.bodies[i]
					var b = e.bodies[j]
					var cl: float = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.r - b.r
					if a == e.ball or b == e.ball: worst_b = minf(worst_b, cl)
					else: worst_d = minf(worst_d, cl)
	print("KICKOFF forms=", D.FORMS.size(), " min ball-disc clearance=", snappedf(worst_b, 0.1), " min disc-disc clearance=", snappedf(worst_d, 0.1))

func _gap_case(gapk: float) -> void:
	# C: ball driven hard into a 2-disc wall with a gap of 1.2 ball diameters: does it split / pass?
	var e = _mk_engine()
	var mine: Array = []
	var opp: Array = []
	for b in e.bodies:
		if b == e.ball: continue
		if b.team == 0: mine.append(b)
		else: opp.append(b)
	var sh = mine[0]
	var w1 = opp[0]
	var w2 = opp[1]
	_clear_except(e, [sh, w1, w2, e.ball])
	var cx: float = e.Fl + 250.0
	var gap: float = e.ball.r * 2.0 * float(gapk)
	w1.x = cx - gap / 2 - w1.r; w2.x = cx + gap / 2 + w2.r; w1.y = e.CY; w2.y = e.CY
	e.ball.x = cx; e.ball.y = e.CY + 260
	sh.x = cx; sh.y = e.ball.y + sh.r + e.ball.r + 40
	for b in e.bodies: b.px = b.x; b.py = b.y
	e.turn = 0; e.phase = "aim"
	e.fire(sh, 0.0, -e.LMAX, e.LMAX, true)
	var r := _run_until_stop(e, [sh, w1, w2, e.ball])
	print("GAP gap=", snappedf(gap, 0.1), " ball_end_y_rel_wall=", snappedf(e.ball.y - e.CY, 0.1), " passed=", e.ball.y < e.CY - e.ball.r, " w1 moved=", r[w1].disp, " w2 moved=", r[w2].disp, " ball ", r[e.ball])

func _aim_case() -> void:
	# D: aim accuracy: fire at 37 deg with max accuracy stats off/on -> measured direction
	var e2 = EngineS.new({"seed": 7, "turn_time": 0, "forms": [0, 0], "stats": [{"power": 5, "accuracy": 1}, {"power": 5, "accuracy": 1}]})
	var dd = null
	for b in e2.bodies:
		if b != e2.ball and b.team == 0: dd = b; break
	_clear_except(e2, [dd, e2.ball])
	e2.ball.x = e2.Fr - 40; e2.ball.y = e2.Ft + 60
	dd.x = e2.CX; dd.y = e2.CY + 300
	var ang := deg_to_rad(-60.0)
	e2.turn = 0; e2.phase = "aim"
	e2.fire(dd, cos(ang) * 150, sin(ang) * 150, 150, true)
	for i in 3: e2.update(1.0 / 60.0)
	print("AIM requested=-60.0 got=", snappedf(rad_to_deg(atan2(dd.vy, dd.vx)), 0.01))

# ---------------------------------------------------------------- POOL checks (Nov 2026)
func _first_disc(e):
	for b in e.bodies:
		if b != e.ball and b.team == 0: return b
	return null

func _opp_disc(e):
	for b in e.bodies:
		if b != e.ball and b.team == 1: return b
	return null

## step the raw simulation until `tgt` starts moving; returns striker velocity just before and both velocities just after
func _impact(e, st, tgt, max_steps := 4000) -> Dictionary:
	var pre := Vector2(st.vx, st.vy)
	for i in max_steps:
		pre = Vector2(st.vx, st.vy)
		e._sim(e.STEP)
		if tgt.vx != 0.0 or tgt.vy != 0.0:
			# let the contact finish (second solver pass / same step) then read
			return {"pre": pre, "st": Vector2(st.vx, st.vy), "tg": Vector2(tgt.vx, tgt.vy)}
	return {}

func _pool_cases() -> void:
	var L := 1323.0
	_mass_cases()
	print("--- POOL ---  FRICTION=", EngineS.FRICTION, " px/s^2  E_BODY=", EngineS.E_BODY, " E_CUSHION=", EngineS.E_CUSHION, " SHOT_MAX=", EngineS.SHOT_MAX)
	# 1. straight lines: disc and ball launched at odd angles in an open field; max lateral deviation from the launch line
	for who in ["disc", "ball"]:
		for deg in [-60.0, -17.0, 33.0]:
			var e = _mk_engine()
			var d = _first_disc(e)
			var body = d if who == "disc" else e.ball
			_clear_except(e, [body])
			_open(e)
			body.x = 0; body.y = 0
			var a := deg_to_rad(deg)
			var u := Vector2(cos(a), sin(a))
			e.phase = "move"
			body.vx = u.x * 1900.0; body.vy = u.y * 1900.0
			var dev := 0.0
			var t := 0
			while (body.vx != 0 or body.vy != 0) and t < 240 * 20:
				e._sim(e.STEP); t += 1
				var pp := Vector2(body.x, body.y)
				dev = maxf(dev, absf(pp.x * u.y - pp.y * u.x))
			var fin := rad_to_deg(Vector2(body.x, body.y).angle())
			print("STRAIGHT ", who, " aim=", deg, " end_dir=", snappedf(fin, 0.0001), " max_lateral_dev_px=", snappedf(dev, 0.00001))
	# aim exactness through fire() (human shot, with accuracy stats present)
	for deg in [-60.0, -101.0, -147.5]:
		var e = EngineS.new({"seed": 3, "turn_time": 0, "forms": [0, 0], "stats": [{"power": 5, "accuracy": 1}, {"power": 5, "accuracy": 1}]})
		var d = _first_disc(e)
		_clear_except(e, [d])
		_open(e)
		d.x = 0; d.y = 0
		e.turn = 0; e.phase = "aim"
		var a := deg_to_rad(deg)
		e.fire(d, cos(a) * 150, sin(a) * 150, 150, true)
		print("AIM fire() requested=", deg, " got=", snappedf(rad_to_deg(atan2(d.vy, d.vx)), 0.0001))
	# 2. centered hits: striker at 1200 px/s into a resting target, head-on
	for kind in ["disc->ball", "disc->disc", "ball->disc"]:
		var e = _mk_engine()
		var d = _first_disc(e)
		var o = _opp_disc(e) if kind != "disc->ball" else e.ball
		var st = d
		var tg = o
		if kind == "ball->disc": st = e.ball; tg = d
		_clear_except(e, [st, tg])
		_open(e)
		tg.x = 0; tg.y = 0
		st.x = 0; st.y = st.r + tg.r + 30
		e.phase = "move"
		st.vx = 0.0; st.vy = -1200.0
		var r := _impact(e, st, tg)
		print("CENTER ", kind, " v_in=", snappedf(r.pre.length(), 0.1), " target_out=", snappedf(r.tg.length(), 0.1), " (", snappedf(100.0 * r.tg.length() / r.pre.length(), 0.1), "%)  striker_left=", snappedf(r.st.length(), 0.1), " (", snappedf(100.0 * r.st.length() / r.pre.length(), 0.1), "%)  target_dir=", snappedf(rad_to_deg(r.tg.angle()), 0.01))
	# 3. cut shots: line of centres at 30 deg (and 45/60) to the striker's path
	for kind in ["disc->ball", "disc->disc"]:
		for cut in [30.0, 45.0, 60.0]:
			var e = _mk_engine()
			var d = _first_disc(e)
			var tg = e.ball if kind == "disc->ball" else _opp_disc(e)
			_clear_except(e, [d, tg])
			_open(e)
			var m: float = d.r + tg.r
			tg.x = 0; tg.y = 0
			d.x = -m * sin(deg_to_rad(cut)); d.y = 200.0
			e.phase = "move"
			d.vx = 0.0; d.vy = -1200.0
			var r := _impact(e, d, tg)
			var split := rad_to_deg(absf(r.st.angle_to(r.tg)))
			var tdir := rad_to_deg(absf(Vector2(0, -1).angle_to(r.tg)))
			print("CUT ", kind, " cut=", cut, " target_dir_from_path=", snappedf(tdir, 0.01), " striker_dir_from_path=", snappedf(rad_to_deg(absf(Vector2(0, -1).angle_to(r.st))), 0.01), " split=", snappedf(split, 0.01), " target_speed%=", snappedf(100.0 * r.tg.length() / r.pre.length(), 0.1), " striker_speed%=", snappedf(100.0 * r.st.length() / r.pre.length(), 0.1))
	# 4. cushions: angle in vs angle out (measured from the wall normal), side wall and goal-line wall
	for who in ["ball", "disc"]:
		for inc in [20.0, 45.0, 70.0]:
			var e = _mk_engine()
			var d = _first_disc(e)
			var body = d if who == "disc" else e.ball
			_clear_except(e, [body])
			body.x = e.Fl + body.r + 150; body.y = e.CY
			var a := deg_to_rad(inc)
			e.phase = "move"
			body.vx = -cos(a) * 1200.0; body.vy = -sin(a) * 1200.0
			var vin := Vector2(body.vx, body.vy)
			var t := 0
			var bounced := false
			while t < 2000:
				var pre := Vector2(body.vx, body.vy)
				e._sim(e.STEP); t += 1
				if body.vx > 0: 
					var vo := Vector2(body.vx, body.vy)
					var ain := rad_to_deg(atan2(absf(pre.y), absf(pre.x)))
					var aout := rad_to_deg(atan2(absf(vo.y), absf(vo.x)))
					print("CUSHION side ", who, " in=", snappedf(ain, 0.01), " out=", snappedf(aout, 0.01), " speed_kept%=", snappedf(100.0 * vo.length() / pre.length(), 0.1))
					bounced = true
					break
			if not bounced: print("CUSHION side ", who, " inc=", inc, " NO BOUNCE")
	# goal-line cushion (beside the goal mouth)
	var eg = _mk_engine()
	var bd = eg.ball
	_clear_except(eg, [bd])
	bd.x = eg.Fl + 90; bd.y = eg.Ft + 200
	eg.phase = "move"
	var ag := deg_to_rad(35.0)
	bd.vx = sin(ag) * 1000.0; bd.vy = -cos(ag) * 1000.0
	for t in 2000:
		var pre := Vector2(bd.vx, bd.vy)
		eg._sim(eg.STEP)
		if bd.vy > 0:
			print("CUSHION goal-line ball in=", snappedf(rad_to_deg(atan2(absf(pre.x), absf(pre.y))), 0.01), " out=", snappedf(rad_to_deg(atan2(absf(bd.vx), absf(bd.vy))), 0.01), " speed_kept%=", snappedf(100.0 * Vector2(bd.vx, bd.vy).length() / pre.length(), 0.1))
			break
	# 5. roll distance / time in an open field (no cushions): disc via fire(), ball struck by a centered full/half/quarter shot
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = _first_disc(e)
		_clear_except(e, [d])
		_open(e)
		d.x = 0; d.y = 0
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var v0: float = absf(d.vy)
		var t := 0
		var tail := 0.0
		while (d.vx != 0 or d.vy != 0) and t < 240 * 30:
			e._sim(e.STEP); t += 1
		print("ROLL disc p=", pw, " v0=", snappedf(v0, 0.1), " dist=", snappedf(-d.y, 0.1), "px = ", snappedf(-d.y / L, 0.01), " pitch lengths, time=", snappedf(t * e.STEP, 0.01), "s, lateral=", snappedf(d.x, 0.0001))
	for pw in [1.0, 0.5, 0.25]:
		var e = _mk_engine()
		var d = _first_disc(e)
		_clear_except(e, [d, e.ball])
		_open(e)
		d.x = 0; d.y = 0
		e.ball.x = 0; e.ball.y = -(d.r + e.ball.r + 1)
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var y0: float = e.ball.y
		var t := 0
		var vb := 0.0
		while (d.vx != 0 or d.vy != 0 or e.ball.vx != 0 or e.ball.vy != 0) and t < 240 * 30:
			e._sim(e.STEP); t += 1
			vb = maxf(vb, absf(e.ball.vy))
		print("ROLL ball (centered hit) p=", pw, " ball_v0=", snappedf(vb, 0.1), " dist=", snappedf(y0 - e.ball.y, 0.1), "px = ", snappedf((y0 - e.ball.y) / L, 0.01), " L, all stopped after ", snappedf(t * e.STEP, 0.01), "s, disc moved ", snappedf(-d.y, 0.1), "px, ball lateral=", snappedf(e.ball.x, 0.0001))
	# stop cleanliness: speed over the last 0.5 s of a half-power roll (no creeping tail)
	var es = _mk_engine()
	var ds = _first_disc(es)
	_clear_except(es, [ds])
	_open(es)
	ds.x = 0; ds.y = 0
	es.turn = 0; es.phase = "aim"
	es.fire(ds, 0.0, -0.5 * es.LMAX, 0.5 * es.LMAX, true)
	var hist: Array = []
	while ds.vx != 0 or ds.vy != 0:
		hist.append(absf(ds.vy)); es._sim(es.STEP)
	var n: int = hist.size()
	print("STOP half shot: speed 0.5s/0.25s/0.1s/last step before stop = ", snappedf(hist[n - 120], 0.1), " / ", snappedf(hist[n - 60], 0.1), " / ", snappedf(hist[n - 24], 0.1), " / ", snappedf(hist[n - 1], 0.1), " px/s -> 0")
	# 6. tunnelling: max-speed ball at a resting disc (grazing) and at a wall; fast disc through a 1-ball gap
	for off in [0.0, 60.0, 74.0]:
		var e = _mk_engine()
		var d = _first_disc(e)
		_clear_except(e, [d, e.ball])
		_open(e)
		d.x = off; d.y = 0
		e.ball.x = 0; e.ball.y = 900
		e.phase = "move"
		e.ball.vx = 0.0; e.ball.vy = -2950.0
		var hit := false
		var minc := 1e9
		for t in 240 * 3:
			e._sim(e.STEP)
			minc = minf(minc, Vector2(d.x - e.ball.x, d.y - e.ball.y).length() - d.r - e.ball.r)
			if d.vx != 0 or d.vy != 0: hit = true
		print("TUNNEL ball@2950 vs disc offset=", off, " (touch if <76) hit=", hit, " min_gap_px=", snappedf(minc, 0.01))
	var ew = _mk_engine()
	_clear_except(ew, [ew.ball])
	ew.ball.x = ew.CX; ew.ball.y = ew.CY
	ew.phase = "move"
	ew.ball.vx = -2950.0; ew.ball.vy = 0.0
	var minx := 1e9
	for t in 240 * 2:
		ew._sim(ew.STEP)
		minx = minf(minx, ew.ball.x - ew.ball.r - ew.Fl)
	print("TUNNEL ball@2950 into side wall: min distance rim->wall=", snappedf(minx, 0.01), " (never < 0 = no tunnelling)")

## heavier discs (Nov 14 2026): ball hitting a resting disc, light contacts, full disc shot into the ball
func _mass_cases() -> void:
	print("--- MASS --- disc PM=", EngineS.PM, " ball BM=", EngineS.BM, " (ratio ", EngineS.PM / EngineS.BM, ")  V_SAFE=", EngineS.V_SAFE)
	for vin in [1800.0, 900.0, 300.0, 120.0]:
		var e = _mk_engine()
		var d = _first_disc(e)
		_clear_except(e, [d, e.ball])
		_open(e)
		d.x = 0; d.y = 0
		e.ball.x = 0; e.ball.y = d.r + e.ball.r + 2
		e.phase = "move"
		e.ball.vx = 0.0; e.ball.vy = -vin
		var r := _impact(e, e.ball, d)
		var t := 0
		while (d.vx != 0 or d.vy != 0 or e.ball.vx != 0 or e.ball.vy != 0) and t < 240 * 20:
			e._sim(e.STEP); t += 1
		print("MASS ball->disc v_in=", vin, " disc_out=", snappedf(r.tg.length(), 0.1), " (", snappedf(100.0 * r.tg.length() / r.pre.length(), 0.1), "%) ball_back=", snappedf(r.st.length(), 0.1), " disc pushed ", snappedf(Vector2(d.x, d.y).length(), 0.1), "px")
	for pw in [1.0, 0.5]:
		var e = _mk_engine()
		var d = _first_disc(e)
		_clear_except(e, [d, e.ball])
		_open(e)
		d.x = 0; d.y = 0
		e.ball.x = 0; e.ball.y = -(d.r + e.ball.r + 30)
		e.turn = 0; e.phase = "aim"
		e.fire(d, 0.0, -pw * e.LMAX, pw * e.LMAX, true)
		var r := _impact(e, d, e.ball)
		print("MASS disc->ball p=", pw, " disc_in=", snappedf(r.pre.length(), 0.1), " ball_out=", snappedf(r.tg.length(), 0.1), " (", snappedf(100.0 * r.tg.length() / r.pre.length(), 0.1), "%) disc_keeps=", snappedf(r.st.length(), 0.1), " (", snappedf(100.0 * r.st.length() / r.pre.length(), 0.1), "%)")
