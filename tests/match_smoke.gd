extends Node
## Full offline match smoke test under the real autoloads + main.tscn (Nav, Store, Sfx, Supa, Data):
## human drag-shot via match.gd's touch handler, pause/resume/restart via Nav.back(), quality toggle,
## then bot-vs-bot to the end -> result.gd -> "play again" -> match again -> home. Reward maths incl. cup.
## Headless:  godot --headless --fixed-fps 60 --path . res://tests/match_smoke.tscn
## Shots:     NX_SHOTS=/abs/dir DISPLAY=:99 godot --rendering-driver opengl3 --resolution 1080x1920 --path . res://tests/match_smoke.tscn
const D := preload("res://src/core/data.gd")
const MatchScreen := preload("res://src/screens/match.gd")

var fails: Array = []
var shots_dir := ""
var render := false
var goal_seen := false
var events := {}

func _ready() -> void:
	render = DisplayServer.get_name() != "headless"
	shots_dir = OS.get_environment("NX_SHOTS")
	if shots_dir != "": DirAccess.make_dir_recursive_absolute(shots_dir)
	OS.set_environment("NX_START", "home")
	var main = load("res://src/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails.append(what)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call(): return true
		await get_tree().process_frame
	return cond.call()

func shot(name: String) -> void:
	if not render or shots_dir == "": return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/match_%s.png" % [shots_dir, name]
	img.save_png(p)
	print("  shot ", p)

func _run() -> void:
	await frames(30)
	var t0 := Time.get_ticks_msec()
	print("[smoke] renderer=", RenderingServer.get_current_rendering_method(), " display=", DisplayServer.get_name())
	# ---------------------------------------------------------------- reward maths (App.onFinish)
	var p0 := {"xp": 90, "coins": 100, "gems": 0, "trophies": 5, "played": 0, "wins": 0, "losses": 0, "draws": 0, "goalsFor": 0, "goalsAgainst": 0, "winStreak": 0, "bestStreak": 0, "cupsWon": 0}
	var lq := {"cfg": {"ai": true, "ai_lvl": 1}, "mode": "quick", "stage": 0}
	var f1 := MatchScreen.compute_finish(lq, p0, [3, 1])
	check(f1.reward.coins == 105 and f1.reward.xp == 75 and f1.reward.trophies == 30 and f1.level_up == 2 and f1.patch.coins == 305, "quick win lvl1 reward 105c/75xp/+30t, level-up bonus (%s)" % str(f1.reward))
	var f2 := MatchScreen.compute_finish(lq, p0, [0, 3])
	check(f2.reward.trophies == -8 and f2.patch.trophies == 0 and f2.patch.losses == 1, "loss -8 trophies clamped at 0")
	var lc := {"cfg": {"ai": true, "ai_lvl": 2}, "mode": "cup", "stage": 2}
	var f3 := MatchScreen.compute_finish(lc, p0, [3, 2])
	check(f3.cup.champion and f3.reward.coins == int(roundf(60 * 2.2 * 2 + 15)) + 400 and f3.patch.cupsWon == 1, "cup final win = champion +400 coins")
	var f4 := MatchScreen.compute_finish({"cfg": {"ai": false}, "mode": "local"}, p0, [1, 0])
	check(f4.reward == null, "local 2-player gives no reward")
	var rs := preload("res://src/screens/result.gd")
	var nl: Dictionary = rs.next_launch(D.build_launch("cup", UD.p(), {"lvl": 0, "stage": 0}), UD.p(), {"stage": 0, "won": true, "champion": false})
	check(nl.mode == "cup" and nl.stage == 1 and nl.cfg.ai_lvl == 1, "cup next stage via Data.build_launch")
	# ---------------------------------------------------------------- catalog / assets
	check(D.team_by_id("club0").name == "Persepolis" and D.team_by_id("gal19").name == "PINK" and D.team_by_id("lux0").name == "Lamborghini", "NX8 catalog ids/names (club0 Persepolis, gal19 PINK, lux0 Lamborghini)")
	check(D.team_img_path("nat59").begins_with("res://assets/nx8/") and D.team_img_path("vip3").begins_with("res://assets/g/"), "NX8 art + v4 fallback paths")
	var miss := 0
	for t in D.TEAMS:
		if D.team_tex(t.id) == null: miss += 1
	check(miss == 0, "every one of %d teams has a texture (missing %d)" % [D.TEAMS.size(), miss])
	check(D.ball_tex(0).resource_path.begins_with("res://assets/nx8/balls/") and D.ball_tex(20) != null and D.ball_thumb(3) != null, "NX8 balls b0-12 + v4 13-35")
	# ---------------------------------------------------------------- match: human input
	var played0 := int(UD.pv("played", 0))
	var l := D.build_launch("quick", UD.p(), {"lvl": 1, "rule": "g3", "tt": 15, "opp": D.team_by_id("club5"), "stage": 0})
	l["seed"] = 7
	Nav.go("match", l)
	check(await until(func(): return Nav.current == "match" and Nav.screen != null and Nav.screen.get("eng") != null, 120), "Nav.go(match) mounts match.gd")
	var m = Nav.screen
	m.match_event.connect(func(ev):
		events[ev.t] = int(events.get(ev.t, 0)) + 1
		if ev.t == "goal" and not ev.get("nogoal", false):
			if render and not goal_seen: m.steps = 1   # real-time around the first goal for the screenshot
			goal_seen = true)
	await frames(20)
	var eng: NxEngine = m.eng
	check(not eng.v4 and is_equal_approx(eng.pr, NxEngine.PR) and eng.pr >= 45.0, "engine runs the nx8 model by default (Godot PR %.0f)" % eng.pr)
	check(eng.phase == "aim" and eng.turn == 0, "human (team 0) to aim")
	if OS.get_environment("NX_SMOKE_PART") == "end":
		await _bots(m, eng, played0)
		return
	var disc: NxBody = null
	for b: NxBody in eng.bodies:
		if b.team == 0 and b != eng.ball: disc = b; break
	var sp: Vector2 = m.view.to_screen(Vector2(disc.x, disc.y))
	var bs: Vector2 = m.view.to_screen(Vector2(eng.ball.x, eng.ball.y))
	var dir := (sp - bs).normalized()
	_press(m, sp, true)
	check(eng.drag != null and eng.drag.b == disc, "touch press picks the disc via MatchView.to_world")
	for k in 12:
		_motion(m, sp + dir * (14.0 * (k + 1)))
		await frames(1)
	await frames(2)
	await shot("aim")
	_press(m, sp + dir * 168.0, false)
	await frames(1)
	check(eng.phase == "move" and eng.shots == 1, "release fires the shot")
	await frames(10)
	await shot("move")
	# pause / resume / restart through Android back
	Nav.back()
	await frames(25)
	check(m.paused and m.pause_layer != null, "Nav.back() opens the pause menu")
	await shot("pause")
	var bx := eng.ball.x
	await frames(30)
	check(eng.ball.x == bx, "engine frozen while paused")
	Nav.back()
	await frames(5)
	check(not m.paused, "Nav.back() resumes")
	UD.set_p({"quality": "low"})
	await frames(2)
	check(m.view.hq == false and m.view.quality == "low", "Store.quality low reaches MatchView.set_quality")
	UD.set_p({"quality": "high"})
	await frames(2)
	check(m.view.hq == true, "quality back to high")
	m._set_paused(true)
	await frames(3)
	m._restart()
	await frames(3)
	check(not m.paused and eng.score == [0, 0] and eng.shots == 0 and eng.phase == "aim", "شروع دوباره resets the match")
	await _bots(m, eng, played0)

func _bots(m, eng: NxEngine, played0: int) -> void:
	var t0 := Time.get_ticks_msec()
	var old_id: int = m.get_instance_id()
	# ---------------------------------------------------------------- bot vs bot to the end
	m.bots = true
	eng.ai_teams = [true, true]
	m.steps = 30 if render else 8
	var got := await until(func(): return goal_seen, 60 * 400)
	if got:
		await frames(22)
		await shot("goal")
	if render:
		# llvmpipe is too slow to render a whole bot match inside the tool timeout: finish it here (headless runs it for real)
		m.ended = true
		m._finish([eng.score[0] + 2, eng.score[1]])
	var res_ok := await until(func(): return Nav.current == "result", 60 * 600)
	check(res_ok, "bot match reaches the result screen (score %d:%d, events %s)" % [eng.score[0], eng.score[1], str(events)])
	check(int(UD.pv("played", 0)) == played0 + 1, "progression saved (played %d -> %d)" % [played0, int(UD.pv("played", 0))])
	if res_ok:
		await frames(45 if render else 90)
		await shot("result")
		var r = Nav.screen
		check(r.has_method("again") and r.get("out") in ["victory", "defeat", "draw"], "result.gd mounted (%s)" % str(r.get("out")))
		r.again()
		check(await until(func(): return Nav.current == "match" and Nav.screen != null and Nav.screen.get_instance_id() != old_id and Nav.screen.get("eng") != null, 120), "play again -> new match")
		await frames(20)
		Nav.back()
		await frames(10)
		Nav.screen._quit()
		check(await until(func(): return Nav.current == "home", 120), "خروج returns home")
	print("[smoke] events ", events)
	print("[smoke] %s  fails=%d  wall %d ms" % ["PASS" if fails.is_empty() else "FAIL", fails.size(), Time.get_ticks_msec() - t0])
	for f in fails: print("   - ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _press(m: Control, pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = pos
	m._on_touch(ev)

func _motion(m: Control, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	m._on_touch(ev)
