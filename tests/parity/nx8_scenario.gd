extends SceneTree
## Same deterministic scenario as nx8_harness.js, on NxEngine's default (nx8) model.
##   godot --headless -s res://tests/parity/nx8_scenario.gd -- <field> <frames>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var field := int(args[0]) if args.size() > 0 else 1
	var frames := int(args[1]) if args.size() > 1 else 3000
	var e := NxEngine.new({"field": field, "ball": 0, "forms": [0, 3], "ai": false, "ai_lvl": 1, "limit": 99, "match_time": 0, "turn_time": 0, "vip": [false, false], "first": 0, "seed": 1})
	var out: Array = []
	var shots := 0
	for f in frames:
		if e.phase == "aim":
			var best: NxBody = null
			var bd := 1e9
			for b: NxBody in e.bodies:
				if b.team == e.turn and b != e.ball:
					var d := sqrt((e.ball.x - b.x) * (e.ball.x - b.x) + (e.ball.y - b.y) * (e.ball.y - b.y))
					if d < bd: bd = d; best = b
			var ang := fmod(shots * 0.37, 0.5) - 0.25
			var a := atan2(e.ball.y - best.y, e.ball.x - best.x) + ang
			var l := NxEngine.LMAX * (0.55 + (shots % 5) * 0.11)
			e.fire(best, cos(a) * l, sin(a) * l, l); shots += 1
		var dt := ((f + 1) * 1000.0 / 60.0 - f * 1000.0 / 60.0) / 1000.0
		e.update(dt); e.events.clear()
		if f % 60 == 59:
			var row: Array = []
			for b: NxBody in e.bodies: row.append(b.x); row.append(b.y)
			row.append(e.score[0]); row.append(e.score[1]); row.append(shots)
			out.append(row)
	print("GEO:" + JSON.stringify({"F": e.F, "GG": e.GG, "DEPTH": e.DEPTH, "KY": e.KY}))
	print("JSON:" + JSON.stringify(out, "", false, true))
	quit()
