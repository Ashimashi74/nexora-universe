extends Node
## Sound + haptics — port of src/sound.ts. Autoload name: Sfx.
## Sfx.play(key, vol, pair) one-shots (pooled so rapid hits never cut each other; 45 ms rate limit per key,
## 60 ms per key+pair for collision sounds), Sfx.play_goal() goal stinger (+ kick-off whistle on the restart),
## Sfx.crowd(on) crossfading stadium ambience, Sfx.haptic(kind), Sfx.apply_prefs() (reads Store.p).
##
## Match sounds (user-provided, res://assets/sfx/):
##  hitb  disc→ball: random BallHit-01/02/03 / hit_ball, volume + slight pitch by impact power
##  hitp  disc→disc: hit_piece            post  ball→post/goal frame: ballHitsThePost
##  wall  ball→side wall: the ball-hit set, quieter
##  whistle  startWistle (kick-off, and again on the restart after every goal)
##  final    gameIsFinishedWistle         crowd  crowd-02 / crowd-03 looped with a crossfade, low volume
##  goal     goal.wav horn + roar (goalHappened-01) + goalAnnounce a beat later
##
## Background music (the main-menu track) policy:
##  - plays ONLY in the main-menu shell (scene "menu": home/team/play/shop/profile tabs and the offline
##    screens opened from them);
##  - fully STOPPED (player.stop(), not paused/ducked) in every online screen (hub, lobby, rooms,
##    online match/result, tournaments, social…), in matches and the intro, and while voice chat is
##    connected / the mic is on / anyone is speaking;
##  - resumes (from where it stopped) only when the user is back in the main menu.
## The scene follows Nav.screen_changed automatically; screens never need to manage it. The legacy
## calls music(on) / menu_music(on) / set_scene(s) still work (menu_music(false) = user/intro mute).

# key: [file, volume, pool size]
const MAP := {
	"ui": ["select.wav", 0.55, 2], "hitp": ["hit_piece.mp3", 0.7, 4], "goal": ["goal.wav", 1.0, 2],
	# disc hits ball: a random variant each time (RANDOM below), two players per variant
	"hitb": [BALL_HITS, 0.9, 8],
	"post": ["ballHitsThePost.mp3", 0.85, 2], "roar": ["goalHappened-01.mp3", 0.7, 1], "whistle": ["startWistle.mp3", 0.8, 2],
	"final": ["gameIsFinishedWistle.mp3", 0.8, 1],
	# stadium ambience: two tracks crossfaded back-to-back (see _crowd_tick)
	"crowd": [["crowd-02.mp3", "crowd-03.mp3"], 0.22, 2],
	# ball bounces off a side wall: same set, quieter
	"wall": [BALL_HITS, 0.45, 4],
	"music": ["music.mp3", 0.35, 1], "ready": ["nx_ready.mp3", 0.7, 1], "chat": ["nx_chat.mp3", 0.55, 2], "join": ["nx_join.mp3", 0.6, 1],
	"leave": ["nx_leave.mp3", 0.5, 1], "win": ["nx_win.mp3", 0.8, 1], "lose": ["nx_lose.mp3", 0.75, 1], "tick": ["nx_tick.mp3", 0.45, 2],
	# goal announcer voice (user-provided), played after the stinger horn
	"goalAnnounce": ["goalAnnounce.mp3", 0.85, 1],
	# main-menu background track (user-provided menu_music.mp3; falls back to music.mp3 when absent)
	"menu": ["menu_music.mp3", 0.35, 1],
}
const BALL_HITS := ["BallHit-01.mp3", "BallHit-02.mp3", "BallHit-03.mp3", "hit_ball.wav"]
const LOOPS := ["music", "menu"]
const RANDOM := ["hitb", "wall"]
const IMPACT := ["hitb", "hitp", "wall", "post"]   # volume (and pitch, except post) follow impact power
const PAIR_MS := 60                                # min gap per collision pair (key + pair id)
const CROWD_FADE := 2.5                            # crossfade seconds between ambience tracks
## user sound files live in assets/sfx/; UI/menu sounds stay in assets/g/sfx/
const DIRS := ["res://assets/sfx/", "res://assets/g/sfx/"]
const DIR := "res://assets/g/sfx/"
## screens where music is allowed (main-menu shell); online / match screens always stop it
const MENU_SCREENS := ["home", "team", "play", "shop", "profile", "settings", "setup", "daily", "chest", "result", "account"]
const ONLINE_SCREENS := ["hub", "lobby", "ranks", "tournaments", "challenges", "online_result", "arena", "online_match",
	"social", "chat", "club", "public_profile", "oracle"]
const SILENT_SCREENS := ["match", "online_match", "intro"]
const GOAL_DUCK_S := 2.2

var enabled := {"sound": true, "music": true, "haptics": true, "volume": 1.0}
var scene := "menu"           # menu | room (= online) | match
var screen := ""              # last Nav screen
var menu_on := true           # menu_music(on): false while the intro / user switched it off for a screen
var _pools := {}              # key -> {list:[AudioStreamPlayer], i:int}
var _last := {}               # key -> msec
var _voices := {}             # voice ids active (livekit session, speaking, external)
var _music_pos := 0.0         # resume position of the menu track
var _crowd_duck_until := 0    # msec: crowd lowered while the goal stinger plays
var _crowd_on := false        # crowd(on) requested (match running)
var _crowd_cur := 0           # index of the crowd player currently in front
var _crowd_x := 1.0           # crossfade progress 0..1 (1 = settled on _crowd_cur)
var _restart_eng: WeakRef = null   # engine watched after a goal, for the restart whistle
var _restart_t0 := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in MAP:
		var files: Variant = MAP[k][0]
		var farr: Array = files if files is Array else [files]
		var n := maxi(int(MAP[k][2]), farr.size())
		var loop_on: bool = k in LOOPS
		var list: Array = []
		for i in n:
			var file: String = farr[i % farr.size()]
			var path := _path(file)
			if k == "menu" and not ResourceLoader.exists(path): path = DIR + "music.mp3"
			if not ResourceLoader.exists(path):
				push_warning("Sfx: missing " + path)
				continue
			var st = load(path)
			if st == null:
				push_warning("Sfx: cannot load " + path)
				continue
			if k == "crowd" and "loop" in st:
				st = st.duplicate(); st.loop = false   # crossfaded by hand, never hard-looped
			if loop_on:
				st = st.duplicate()
				if "loop" in st: st.loop = true
				if st is AudioStreamWAV: st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			var pl := AudioStreamPlayer.new()
			pl.name = "%s_%d" % [k, i]
			pl.stream = st
			pl.bus = &"Master"
			pl.volume_db = linear_to_db(float(MAP[k][1]))
			pl.process_mode = Node.PROCESS_MODE_ALWAYS
			pl.set_meta("v", i % farr.size())
			add_child(pl)
			list.append(pl)
		if not list.is_empty(): _pools[k] = {"list": list, "i": 0}
	var st_node = get_node_or_null("/root/Store")
	if st_node and st_node.has_signal("changed"): st_node.changed.connect(apply_prefs)
	call_deferred("_hook_voice")
	call_deferred("_hook_nav")
	call_deferred("apply_prefs")
	_rng.randomize()

func _path(file: String) -> String:
	for d in DIRS:
		if ResourceLoader.exists(d + file): return d + file
	return DIRS[0] + file

func _process(dt: float) -> void:
	if _crowd_duck_until > 0 and Time.get_ticks_msec() >= _crowd_duck_until:
		_crowd_duck_until = 0
		_crowd_volume()
	if _crowd_on: _crowd_tick(dt)
	if _restart_eng != null: _restart_tick()

# ---------------------------------------------------------------- hooks
func _hook_voice() -> void:
	var v = get_node_or_null("/root/Voice")
	if v == null: return
	if v.has_signal("state_changed") and not v.state_changed.is_connected(_on_voice_state):
		v.state_changed.connect(_on_voice_state)
	elif v.has_signal("active"):
		v.active.connect(func(on: bool): set_voice_active("livekit", on))
	if v.get("state") is Dictionary: _on_voice_state(v.state)

## Voice.state → music off while connecting/connected, mic on, or anybody speaking
func _on_voice_state(st: Dictionary) -> void:
	var s := str(st.get("status", "off"))
	set_voice_active("livekit", s == "on" or s == "connecting" or bool(st.get("mic", false)))
	var sp: Variant = st.get("speaking")
	set_speaking(sp is Array and not (sp as Array).is_empty())

func _hook_nav() -> void:
	var n = get_node_or_null("/root/Nav")
	if n and n.has_signal("screen_changed") and not n.screen_changed.is_connected(on_screen):
		n.screen_changed.connect(on_screen)
		if str(n.get("current")) != "": on_screen(str(n.current))

## Called on every Nav screen change (also callable directly).
func on_screen(name: String) -> void:
	screen = name
	if name in SILENT_SCREENS: scene = "match" if name != "intro" else "intro"
	elif name in ONLINE_SCREENS: scene = "room"
	elif name in ["home", "team", "play", "shop", "profile"]: scene = "menu"
	# other screens (result, account, sheets, modals) keep the scene they were opened from
	_apply_music()

func apply_prefs() -> void:
	var st = get_node_or_null("/root/Store")
	if st == null or not (st.get("p") is Dictionary) or st.p.is_empty(): return
	var p: Dictionary = st.p
	enabled = {"sound": bool(p.get("sound", true)), "music": bool(p.get("music", true)), "haptics": bool(p.get("haptics", true)), "volume": clampf(float(p.get("volume", 1.0)), 0.0, 1.0)}
	_crowd_sync()
	_apply_music()

func _player(k: String) -> AudioStreamPlayer:
	var pool = _pools.get(k)
	if pool == null or pool.list.is_empty(): return null
	return pool.list[0]

# ---------------------------------------------------------------- one-shots
func play(k: String, vol := 1.0, pair: Variant = "") -> void:
	if k == "final": _restart_eng = null   # full time: no restart whistle
	if k == "goal":
		play_goal()
		return
	if k == "roar" and Time.get_ticks_msec() - int(_last.get("roar_skip", -100000)) < 150:
		return   # the goal stinger plays its own roar
	_play(k, vol, str(pair))

func _play(k: String, vol := 1.0, pair := "") -> bool:
	if not enabled.sound or enabled.volume <= 0: return false
	var pool = _pools.get(k)
	if pool == null or pool.list.is_empty(): return false
	var now := Time.get_ticks_msec()
	var tk := k + "|" + pair if k in IMPACT else k
	var gap := PAIR_MS if k in IMPACT else 45
	if k != "goal" and now - int(_last.get(tk, -100000)) < gap: return false
	_last[tk] = now
	var pl := _pick(k, pool)
	var g := maxf(0.15, vol)
	if k in IMPACT: g = lerpf(0.18, 1.0, pow(clampf(vol, 0.0, 1.0), 0.6))
	pl.volume_db = linear_to_db(maxf(0.0001, minf(1.0, float(MAP[k][1]) * g * enabled.volume)))
	pl.pitch_scale = _rng.randf_range(0.94, 1.06) if k in IMPACT and k != "post" else 1.0
	pl.stop()
	pl.play(0.0)
	return true

## next player of a pool: a free one (so overlapping hits ring out), random variant for RANDOM keys
func _pick(k: String, pool: Dictionary) -> AudioStreamPlayer:
	var list: Array = pool.list
	if k in RANDOM:
		var nv := 0
		for p in list: nv = maxi(nv, int(p.get_meta("v", 0)) + 1)
		var want := _rng.randi_range(0, maxi(0, nv - 1))
		var fallback: AudioStreamPlayer = null
		for p: AudioStreamPlayer in list:
			if p.playing: continue
			if int(p.get_meta("v", 0)) == want: return p
			if fallback == null: fallback = p
		if fallback: return fallback
	else:
		for j in list.size():
			var p: AudioStreamPlayer = list[(pool.i + j) % list.size()]
			if not p.playing:
				pool.i = (pool.i + j + 1) % list.size()
				return p
	var pl: AudioStreamPlayer = list[pool.i]
	pool.i = (pool.i + 1) % list.size()
	return pl

## Goal stinger: goal horn at full level + crowd roar a beat later, crowd loop ducked so it is heard.
## Safe to call twice for the same goal within 150 ms (second call ignored). Old code that also calls
## play("roar") right after play("goal") is handled (that roar is skipped, the stinger plays its own).
func play_goal() -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last.get("goal", -100000)) < 150: return
	if not _play("goal", 1.0): return
	_last["roar_skip"] = now
	_crowd_duck_until = now + int(GOAL_DUCK_S * 1000)
	_crowd_volume()
	get_tree().create_timer(0.12, true, false, true).timeout.connect(func() -> void:
		_last.erase("roar")
		_play("roar", 1.0))
	get_tree().create_timer(0.55, true, false, true).timeout.connect(func() -> void:
		_last.erase("goalAnnounce")
		_play("goalAnnounce", 1.0))
	_watch_restart()

## after a goal: whistle when the engine of the running match goes back to "aim" (kick-off restart);
## nothing when the match ends instead (phase "over" / final whistle / crowd off).
func _watch_restart() -> void:
	_restart_eng = null
	var e: Object = _find_engine(get_tree().root, 0)
	if e == null: return
	_restart_eng = weakref(e)
	_restart_t0 = Time.get_ticks_msec()

func _find_engine(n: Node, depth: int) -> Object:
	if depth > 12: return null
	var e: Variant = n.get("eng")
	if e is Object and is_instance_valid(e) and "phase" in e and e.has_method("reset"): return e
	for c in n.get_children():
		var r := _find_engine(c, depth + 1)
		if r != null: return r
	return null

func _restart_tick() -> void:
	var e: Object = _restart_eng.get_ref()
	var age := Time.get_ticks_msec() - _restart_t0
	if e == null or age > 10000 or str(e.phase) == "over":
		_restart_eng = null
		return
	if age > 500 and str(e.phase) == "aim":
		_restart_eng = null
		_last.erase("whistle")
		_play("whistle", 1.0)

# ---------------------------------------------------------------- loops
func crowd(on: bool) -> void:
	_crowd_on = on
	if not on: _restart_eng = null
	_crowd_sync()

## start / stop the ambience to match crowd(on) + the sound setting
func _crowd_sync() -> void:
	var pool = _pools.get("crowd")
	if pool == null: return
	var want: bool = _crowd_on and enabled.sound and enabled.volume > 0
	var any := false
	for p: AudioStreamPlayer in pool.list: any = any or p.playing
	if not want:
		for p: AudioStreamPlayer in pool.list: p.stop()
		return
	if not any:
		_crowd_cur = _rng.randi_range(0, pool.list.size() - 1)
		_crowd_x = 1.0
		_crowd_volume()
		var pl: AudioStreamPlayer = pool.list[_crowd_cur]
		var ln: float = pl.stream.get_length() if pl.stream else 0.0
		pl.play(_rng.randf_range(0.0, maxf(0.0, ln * 0.5)))   # random start so it never sounds identical
	else: _crowd_volume()

## crossfade to the other ambience track CROWD_FADE s before the front one ends
func _crowd_tick(dt: float) -> void:
	var pool = _pools.get("crowd")
	if pool == null or not enabled.sound or enabled.volume <= 0: return
	var list: Array = pool.list
	var cur: AudioStreamPlayer = list[_crowd_cur]
	if _crowd_x >= 1.0:
		var ln: float = cur.stream.get_length() if cur.stream else 0.0
		if not cur.playing or (ln > CROWD_FADE * 2 and cur.get_playback_position() >= ln - CROWD_FADE):
			var prev := _crowd_cur
			_crowd_cur = (_crowd_cur + 1) % list.size()
			_crowd_x = 0.0 if prev != _crowd_cur and cur.playing else 1.0
			var nx: AudioStreamPlayer = list[_crowd_cur]
			if prev != _crowd_cur or not nx.playing: nx.play(0.0)
			_crowd_volume()
		return
	_crowd_x = minf(1.0, _crowd_x + dt / CROWD_FADE)
	_crowd_volume()
	if _crowd_x >= 1.0:
		for i in list.size():
			if i != _crowd_cur: (list[i] as AudioStreamPlayer).stop()

func _crowd_volume() -> void:
	var pool = _pools.get("crowd")
	if pool == null: return
	var duck := 0.35 if _crowd_duck_until > 0 else 1.0
	var base: float = float(MAP.crowd[1]) * float(enabled.volume) * duck
	for i in pool.list.size():
		# equal-power crossfade: front track fades in, the others fade out
		var g := sin(_crowd_x * PI * 0.5) if i == _crowd_cur else cos(_crowd_x * PI * 0.5)
		(pool.list[i] as AudioStreamPlayer).volume_db = linear_to_db(maxf(0.0001, base * g))

## legacy: background music on/off. It never starts music outside the main menu.
func music(on: bool) -> void: menu_music(on)

func menu_music(on: bool) -> void:
	menu_on = on
	_apply_music()

func set_scene(s: String) -> void:
	if s == "ui": s = "menu"
	if scene == s: return
	scene = s
	_apply_music()

## true while voice is active for `id` (Voice is hooked automatically; others may add their own ids)
func set_voice_active(id: String, on: bool) -> void:
	var had := _voices.has(id)
	if on: _voices[id] = true
	else: _voices.erase(id)
	if had != on: _apply_music()

## anybody speaking in voice chat (Voice.state.speaking non-empty) → music off
func set_speaking(on: bool) -> void:
	set_voice_active("speaking", on)

func music_allowed() -> bool:
	return menu_on and enabled.sound and enabled.music and enabled.volume > 0 and scene == "menu" and _voices.is_empty()

func _apply_music() -> void:
	var pl := _player("menu")
	if pl == null: return
	if not music_allowed():
		if pl.playing:
			_music_pos = pl.get_playback_position()
			pl.stop()
		pl.stream_paused = false
		return
	pl.volume_db = linear_to_db(maxf(0.0001, float(MAP.menu[1]) * enabled.volume))
	pl.stream_paused = false
	if not pl.playing:
		var len_s: float = pl.stream.get_length() if pl.stream else 0.0
		pl.play(_music_pos if _music_pos < len_s - 1.0 else 0.0)

func music_playing() -> bool:
	var pl := _player("menu")
	return pl != null and pl.playing

func audio_state() -> Dictionary: return {"scene": scene, "screen": screen, "voice": not _voices.is_empty(), "music": music_playing()}

# ---------------------------------------------------------------- haptics
func haptic(kind := "light") -> void:
	if not enabled.haptics: return
	if not (OS.has_feature("android") or OS.has_feature("ios")): return
	match kind:
		"heavy": Input.vibrate_handheld(55, 1.0)
		"medium": Input.vibrate_handheld(30, 0.7)
		"success": Input.vibrate_handheld(45, 0.8)
		_: Input.vibrate_handheld(15, 0.4)
