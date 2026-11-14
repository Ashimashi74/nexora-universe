extends SceneTree
const D := preload("res://src/core/data.gd")
## Headless AI-vs-AI soak test for NxEngine.
##   /workspace/tools/godot --headless -s res://tests/bot_match.gd [-- classic] [-- n=20]
## Runs N matches (default 20) with large dt (0.05 s, the engine's own clamp) and prints scores, sim time, shots, wall time.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var classic := args.has("classic")
	var n := 20
	var from := 0
	for a in args:
		if a.begins_with("n="): n = int(a.substr(2))
		if a.begins_with("from="): from = int(a.substr(5))
	var tot_ms := 0
	var draws := 0
	var wins := [0, 0]
	var goals := 0
	var nogoals := 0
	var steps_total := 0
	var errors := 0
	for m in range(from, from + n):
		var cfg := {"field": m % D.FIELDS.size(), "ball": m % 36, "forms": [m % D.FORMS.size(), (m * 7 + 3) % D.FORMS.size()], "ai": true, "ai_lvl": m % 3,
			"limit": 3, "match_time": 180 if m % 4 == 3 else 0, "turn_time": 15, "vip": [false, m % 5 == 0], "first": m % 2,
			"stats": [{"power": 5.0, "accuracy": 5.0}, {"power": 8.0, "accuracy": 8.0}], "seed": 1000 + m, "classic": classic, "model": "v4" if classic else "nx8"}
		var e := NxEngine.new(cfg)
		e.ai_teams = [true, true]
		var t0 := Time.get_ticks_msec()
		var sim_t := 0.0
		var ended := false
		var hits_b := 0
		var shots := 0
		while sim_t < 1500.0:
			e.update(0.05)
			sim_t += 0.05
			steps_total += 1
			for ev in e.events:
				match ev.t:
					"end": ended = true
					"goal":
						if ev.nogoal: nogoals += 1
						else: goals += 1
					"hit":
						if ev.ball: hits_b += 1
					"shot": shots += 1
			e.events.clear()
			for b: NxBody in e.bodies:
				if is_nan(b.x) or is_nan(b.y) or b.x < e.Fl - 200 or b.x > e.Fr + 200 or b.y < e.Ft - e.DEPTH - 200 or b.y > e.Fb + e.DEPTH + 200:
					errors += 1
			if ended: break
		var ms := Time.get_ticks_msec() - t0
		tot_ms += ms
		var s: Array = e.score
		if s[0] == s[1]: draws += 1
		elif s[0] > s[1]: wins[0] += 1
		else: wins[1] += 1
		print("match %2d field=%-12s lvl=%d mode=%s  score %d:%d  sim %6.1fs  shots %3d  ballhits %3d  ended=%s  wall %d ms" % [m, e.f.id, cfg.ai_lvl, "t3" if cfg.match_time > 0 else "g3", s[0], s[1], sim_t, shots, hits_b, ended, ms])
	print("SUMMARY model=%s from=%d matches=%d  team0 wins=%d team1 wins=%d draws=%d goals=%d nogoal=%d  out-of-bounds/NaN=%d  total wall %d ms (%.3f ms per 50ms frame)" % ["v4" if classic else "nx8", from, n, wins[0], wins[1], draws, goals, nogoals, errors, tot_ms, float(tot_ms) / maxf(1, steps_total)])
	quit(0 if errors == 0 else 1)
