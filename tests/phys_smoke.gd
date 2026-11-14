extends SceneTree
## Lightweight physics-only smoke test (no theme / UI / class-cache needed):
## runs AI-vs-AI matches on the new stretched fields and foosball disc physics,
## checking goals, out-of-bounds and NaN.
const D := preload("res://src/core/data.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var ES = load("res://src/game/engine.gd")
	var n := 10
	var errors := 0
	var goals := 0
	var nogoals := 0
	var shots := 0
	var ballhits := 0
	var finals := 0
	for m in n:
		var cfg := {"field": m % D.FIELDS.size(), "ball": m % 36, "forms": [m % 6, (m * 7 + 3) % 6], "ai": true, "ai_lvl": m % 3,
			"limit": 3, "match_time": 180 if m % 4 == 3 else 0, "turn_time": 15, "vip": [false, m % 5 == 0], "first": m % 2,
			"stats": [{"power": 4.0 + (m % 5), "accuracy": 5.0}, {"power": 4.0 + ((m * 3) % 7), "accuracy": 6.0}],
			"seed": 5000 + m}
		var e = ES.new(cfg)
		e.ai_teams = [true, true]
		var sim_t := 0.0
		var ended := false
		while sim_t < 1500.0:
			e.update(0.05)
			sim_t += 0.05
			for ev in e.events:
				match String(ev.get("t", "")):
					"end": ended = true
					"goal":
						if ev.get("nogoal", false): nogoals += 1
						else: goals += 1
					"hit":
						if ev.get("ball", false): ballhits += 1
					"shot": shots += 1
			e.events.clear()
			for b in e.bodies:
				if is_nan(b.x) or is_nan(b.y) or b.x < e.Fl - 250 or b.x > e.Fr + 250 or b.y < e.Ft - e.DEPTH - 250 or b.y > e.Fb + e.DEPTH + 250:
					errors += 1
			if ended:
				break
		if ended: finals += 1
		var s: Array = e.score
		print("match %2d field=%-12s score %d:%d  goals=%d shots=%d ballhits=%d  sim=%.0fs" % [m, e.f.id, s[0], s[1], s[0] + s[1], shots, ballhits, sim_t])
	print("SUMMARY matches=%d finals=%d goals=%d nogoal=%d shots=%d ballhits=%d out-of-bounds/NaN=%d" % [n, finals, goals, nogoals, shots, ballhits, errors])
	quit(1 if errors > 0 or finals < n - 1 else 0)
