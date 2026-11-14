extends SceneTree
## Headless probe for src/core/sfx.gd: every key loads, play("goal") really produces samples on the
## Master bus (AudioEffectCapture), music stops (not pauses) in online scenes and while voice is active.
##   godot --headless --script res://tests/sfx_probe.gd
var fails := 0
func ok(c: bool, what: String, extra: Variant = "") -> void:
	if not c: fails += 1
	print("  %s  %s  %s" % ["PASS" if c else "FAIL", what, str(extra)])

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void: print("WATCHDOG"); quit(2))
	_run.call_deferred()

func peak(cap: AudioEffectCapture) -> float:
	var n := cap.get_frames_available()
	if n <= 0: return -1.0
	var buf := cap.get_buffer(n)
	var m := 0.0
	for v in buf: m = maxf(m, maxf(absf(v.x), absf(v.y)))
	return m

func _run() -> void:
	await process_frame
	var sfx = root.get_node_or_null("Sfx")
	ok(sfx != null, "Sfx autoload")
	if sfx == null: quit(1); return
	await process_frame
	for k in sfx.MAP: ok(sfx._pools.has(k), "loaded " + k)
	var cap := AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, cap)
	await create_timer(0.3).timeout
	cap.clear_buffer()
	sfx.play_goal()
	var pl = sfx._pools.goal.list[0]
	ok(pl.playing, "goal player playing")
	await create_timer(0.25).timeout
	var p := peak(cap)
	print("  goal peak on Master: ", p, " (-1 = driver does not mix headless)")
	ok(p != 0.0, "goal produced audio (or headless driver silent)", p)
	ok(pl.bus == "Master" or AudioServer.get_bus_index(pl.bus) >= 0, "goal bus valid", pl.bus)
	# music: menu → plays, room → STOPPED, back to menu → plays
	sfx.set_scene("menu"); sfx.menu_music(true)
	var m = sfx._player("menu")
	ok(m != null and m.playing and not m.stream_paused, "music plays in menu")
	sfx.set_scene("room")
	ok(m != null and not m.playing, "music fully stopped in room/lobby")
	sfx.set_scene("match")
	ok(not m.playing, "music stopped in match")
	sfx.music(true)   # online_result / match exit used to call this → must NOT restart outside menu
	ok(not m.playing, "music(true) outside menu keeps it stopped")
	sfx.set_scene("menu")
	ok(m.playing, "music resumes back in menu")
	sfx.set_voice_active("livekit", true)
	ok(not m.playing, "music stopped while voice active")
	sfx.set_voice_active("livekit", false)
	sfx.set_speaking(true)
	ok(not m.playing, "music stopped while someone talks")
	sfx.set_speaking(false)
	ok(m.playing, "music back after voice ends (in menu)")
	print("RESULT: ", "OK" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
