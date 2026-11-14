extends Control
## Online match — host-authoritative netcode on top of NxEngine + MatchView (port of OnlineMatch.tsx).
##
##  HOST   runs the real simulation (NxEngine.update) at display rate, applies remote shot inputs and
##         broadcasts compact snapshots: 20–30 Hz while anything moves, 2 Hz at rest, immediately on
##         events (shot, goal, turn, clock, end). Events ride inside snapshots.
##  OTHERS (players + spectators) never simulate: they buffer snapshots, estimate the host clock offset
##         and render ~1.7 snapshot intervals in the past, interpolating every disc + ball (120 ms
##         extrapolation when starved). Events fire when playback reaches them.
##
##  CONTROL RULE (2v2 / 3v3): turns alternate between teams like offline. Within a team the humans rotate:
##  the k-th turn of team T belongs to slot (k-1) mod teamSize. A disconnected player is skipped; a team
##  with nobody connected is played by the bot. The controller may flick ANY disc of their team.
##
##  Hardening over RN: every game message carries the match id (stale messages from an earlier match in
##  the same room are dropped), duplicate/out-of-order snapshots are dropped/sorted, shot requests are
##  resent (same seq, host dedupes by seq+phase) if no ack arrives, host absence is detected from
##  presence + snapshot silence, the host abandons cleanly on quit / screen exit.
##
## Nav params: {room_id, match_id, link?: RoomLink, before?: profile dict}
## Exits: Nav.go("online_result", {o: outcome, room_id, before, link})
##        Nav.go("lobby", {room_id, skip_match: match_id, why: "quit"|"hostLost"|"aborted", link})

const TAU_ := TAU
const LMAX := 210.0
const HOST_SILENCE := 8.0
const FIRST_SNAP_WAIT := 12.0
## after HOST_SILENCE we ask the server to settle the match (it agrees once the host is 30 s silent there);
## give up and go back to the lobby after this much total silence
const HOST_GIVE_UP := 60.0
## our own link may be down this long before we give up (the host keeps simulating meanwhile)
const SELF_OFFLINE_GIVE_UP := 45.0

var link: Variant = null          # RoomLink
var match_id := ""
var room_id := ""
var params := {}
var me := ""
var room0: Dictionary = {}
var is_host := false
var cfg: Dictionary = {}
var eng: Variant = null           # NxEngine
var start := {}                   # {my_team (-1 = spectator), names, teams (team dicts), team_ids, ranked}
var flipped := false
var done := "no"                  # no | ended | finished | aborted
var view: Node2D = null           # MatchView (or fallback renderer)
var _view_is_mv := false

# host state
var hs := {"turn_count": [0, 0], "seq": 0, "ctrl": "", "last_send": 0.0, "q": 0, "evs": [], "t0": 0.0, "last_aim": 0.0}
# client state
var cs := {"buf": [], "offs": [], "applied": -1, "last_recv": 0.0, "pending_shot": 0.0, "shot": null, "res": null,
	"end_at": 0.0, "prev": PackedFloat64Array(), "ctrl": "", "seq": 0, "got": false, "host_gone_at": 0.0,
	"claim_at": 0.0, "claiming": false, "off_at": 0.0}
var co := {"mine": false, "touched": false, "power": 0.0, "last_tip": 0.0, "misses": 0, "turn_n": 0, "reminded": -1}
var _local: Variant = null        # {b, sx, sy} while my finger is down
var _unsub: Callable
var _t0 := 0.0
var _tick_at := -1
var _hud := {}
var _my_turn_prev := false
var _oracle: Script = null

# HUD nodes
var _touch: Control
var _score_l: Label
var _clock_l: Label
var _name_l: Array = []
var _logo_ring: Array = []
var _turn_l: Label
var _turn_pill: PanelContainer
var _turn_bar_bg: ColorRect
var _turn_bar: ColorRect
var _banner: VBoxContainer
var _banner_t: Label
var _banner_s: Label
var _wait: Control
var _quit_layer: Control
var _chat_layer: Control
var _chat_btn: Control
var _unread_dot: Label
var _ping: Control
var _spect_l: Label
var _ui_bits: Script = null

# ======================================================================== setup
func setup(p: Dictionary) -> void:
	params = p
	match_id = str(p.get("match_id", ""))
	room_id = str(p.get("room_id", ""))
	link = p.get("link")
	if link == null or not is_instance_valid(link):
		link = Supa.link_for(room_id)
	if link == null:
		var oui: Script = _try_load("res://src/online/oui.gd")
		if oui:
			var l: Variant = oui.get("link")
			if l != null and is_instance_valid(l):
				link = l
	if link and room_id == "":
		room_id = str(link.id)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if link == null or not (link.state.room is Dictionary) or match_id == "":
		_toast("این مسابقه هنوز آماده نیست")
		_exit.call_deferred("aborted")
		return
	me = str(link.me)
	room0 = (link.state.room as Dictionary).duplicate(true)
	is_host = str(room0.get("host", "")) == me
	_t0 = _now()
	hs.t0 = _now()
	cs.last_recv = _now()
	_ui_bits = _try_load("res://src/online/ui_bits.gd")
	_oracle = _try_load("res://src/oracle/coach.gd")
	_build_cfg()
	_build_view()
	_build_hud()
	_unsub = link.on_game(_on_msg)
	if not link.changed.is_connected(_on_link_changed):
		link.changed.connect(_on_link_changed)
	if Supa.has_signal("app_resumed"):
		Supa.app_resumed.connect(_on_resumed)
	_oracle_call("set_scene", ["match"])
	var sfx := _sfx_node()
	if sfx:
		sfx.play("whistle")
		if sfx.has_method("set_scene"):
			sfx.set_scene("match")
		sfx.crowd(true)
		sfx.music(false)
	_nav_chrome(false)

func leave() -> void:
	_teardown()

func _exit_tree() -> void:
	_teardown()

var _torn := false
func _teardown() -> void:
	if _torn:
		return
	_torn = true
	if _unsub.is_valid():
		_unsub.call()
	if link and is_instance_valid(link) and link.changed.is_connected(_on_link_changed):
		link.changed.disconnect(_on_link_changed)
	if Supa.has_signal("app_resumed") and Supa.app_resumed.is_connected(_on_resumed):
		Supa.app_resumed.disconnect(_on_resumed)
	var sfx := _sfx_node()
	if sfx:
		sfx.crowd(false)
	# host leaving the screen mid-match ends it for everyone (forfeit if opponents are here, else abandon)
	if is_host and done == "no" and link and is_instance_valid(link) and match_id != "":
		done = "aborted"
		_send({"k": "abort"})
		_host_quit_rpc()

# ======================================================================== config
static func cfg_from_room(room: Dictionary) -> Dictionary:
	var s: Dictionary = room.get("settings", {}) if room.get("settings") is Dictionary else {}
	var time: float = max(0.0, _num(s.get("time"), 0))
	var goals: int = max(1, int(_num(s.get("goals"), 3)))
	var turn_v: Variant = s.get("turn")
	var turn_t: float = 0.0 if (turn_v != null and _num(turn_v, -1) == 0) else max(5.0, _num(turn_v, 15))
	var nf: int = Data.FIELDS.size()
	return {
		"field": clampi(int(_num(s.get("field"), 0)), 0, nf - 1), "ball": clampi(int(_num(s.get("ball"), 0)), 0, 35),
		"forms": [0, 0], "ai": false, "ai_lvl": 1, "limit": 99 if time > 0 else goals, "match_time": time,
		"turn_time": turn_t, "vip": [false, false], "first": 0,
	}

static func rule_label(s: Dictionary) -> String:
	if _num(s.get("time"), 0) > 0:
		return "%s دقیقه" % NX.fa(round(_num(s.get("time"), 0) / 60.0))
	return "تا %s گل" % NX.fa(int(_num(s.get("goals"), 3)) if _num(s.get("goals"), 0) > 0 else 3)

static func _num(v: Variant, d: float) -> float:
	if v is int or v is float:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return float(v)
	return d

static func disc_of(p: Variant) -> String:
	if not (p is Dictionary):
		return "club0"
	if p.get("disc_id"):
		return str(p.disc_id)
	var pr: Variant = p.get("profiles")
	if pr is Dictionary:
		if pr.get("equipped_disc"):
			return str(pr.equipped_disc)
		if pr.get("avatar"):
			return str(pr.avatar)
	return "club0"

static func team_of(players: Array, t: int) -> Array:
	var out: Array = []
	for p in players:
		if p is Dictionary and str(p.get("role", "")) == "player" and p.get("team") != null and int(p.team) == t:
			out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(_num(a.get("slot"), 0)) < int(_num(b.get("slot"), 0)))
	return out

## RN teamOfAvatar: team dict whose id or team_key matches
static func team_of_avatar(key: String) -> Dictionary:
	for t in Data.TEAMS:
		if str(t.id) == key or Data.team_key(t) == key:
			return t
	return Data.TEAMS[0]

func _disc_stats(id: String) -> Dictionary:
	if Supa.discs:
		return Supa.discs.stats(id)
	return {"power": 6.0, "accuracy": 6.0}

func _build_cfg() -> void:
	var players: Array = link.state.players
	cfg = cfg_from_room(room0)
	var t0 := team_of(players, 0)
	var t1 := team_of(players, 1)
	cfg["stats"] = [_disc_stats(disc_of(t0[0] if t0.size() else null)), _disc_stats(disc_of(t1[0] if t1.size() else null))]
	var tm0 := team_of_avatar(disc_of(t0[0] if t0.size() else null))
	var tm1 := team_of_avatar(disc_of(t1[0] if t1.size() else null))
	cfg["teams"] = [str(tm0.id), str(tm1.id)]
	eng = NxEngine.new(cfg)
	var my_team := -1
	for p in players:
		if str(p.get("user_id", "")) == me and str(p.get("role", "")) == "player" and p.get("team") != null and (int(p.team) == 0 or int(p.team) == 1):
			my_team = int(p.team)
	var nm := func(t: Array, d: String) -> String:
		var n := d
		if t.size() and t[0].get("profiles") is Dictionary and str(t[0].profiles.get("username", "")) != "":
			n = str(t[0].profiles.username)
		return n + (" +%s" % NX.fa(t.size() - 1) if t.size() > 1 else "")
	start = {"my_team": my_team, "names": [nm.call(t0, "آبی"), nm.call(t1, "قرمز")], "teams": [tm0, tm1],
		"team_ids": [str(tm0.id), str(tm1.id)], "ranked": bool(room0.get("ranked", false))}
	flipped = my_team == 1

func _name_of(uid: String) -> String:
	if uid == "":
		return "ربات"
	for p in link.state.players:
		if str(p.get("user_id", "")) == uid:
			var pr: Variant = p.get("profiles")
			if pr is Dictionary and str(pr.get("username", "")) != "":
				return str(pr.username)
	return "…"

# ======================================================================== view
func _build_view() -> void:
	var vs := get_viewport_rect().size
	var top_m: float = NX.safe_top + 240.0
	var bot_m: float = NX.safe_bottom + 190.0
	var mv_script: Script = _try_load("res://src/game/match_view.gd")
	if mv_script:
		view = mv_script.new()
		_view_is_mv = true
		var opts := {"teams": start.team_ids, "ball": cfg.ball, "field": cfg.field, "flipped": flipped, "online": true,
			"top_margin": bot_m if flipped else top_m, "bottom_margin": top_m if flipped else bot_m, "size": vs, "fx": true}
		if view.has_method("setup"):
			view.setup(eng, opts)
		else:
			for k in ["engine", "eng"]:
				if k in view:
					view.set(k, eng)
			if "flipped" in view:
				view.set("flipped", flipped)
	else:
		view = _FallbackView.new()
		view.eng = eng
		view.flipped = flipped
	add_child(view)
	# touch layer (below HUD)
	_touch = Control.new()
	_touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch.gui_input.connect(_on_touch)
	add_child(_touch)

func _world(pos: Vector2) -> Vector2:
	if _view_is_mv and view.has_method("to_world"):
		var p := pos
		# MatchView handles the 180° flip itself when it exposes `flipped`; otherwise mirror here
		if flipped and not ("flipped" in view):
			p = get_viewport_rect().size - pos
		var w: Variant = view.to_world(p)
		return w if w is Vector2 else Vector2.ZERO
	return (view as _FallbackView).to_world(pos)

# ======================================================================== HUD
func _build_hud() -> void:
	var vs := get_viewport_rect().size
	var top: float = NX.safe_top + 24.0
	# --- score board
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, top)
	bar.size = Vector2(vs.x - 48, 146)
	bar.add_theme_constant_override("separation", 20)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var qb := _round_btn("✕", func() -> void: _show_quit(true))
	bar.add_child(qb)
	var board := Kit.glass(NX.CYAN, false, 18.0)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(0, 146)
	bar.add_child(board)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(row)
	var left_t := 1 if flipped else 0
	var right_t := 1 - left_t
	row.add_child(_side(left_t, false))
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_l = Kit.title("0 : 0", 62, Color.WHITE)
	_score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_score_l)
	_clock_l = Kit.label("", 24, NX.DIM, true)
	_clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_clock_l)
	row.add_child(mid)
	row.add_child(_side(right_t, true))
	# --- turn timer bar
	_turn_bar_bg = ColorRect.new()
	_turn_bar_bg.color = Color(1, 1, 1, 0.08)
	_turn_bar_bg.position = Vector2(160, top + 156)
	_turn_bar_bg.size = Vector2(vs.x - 200, 10)
	_turn_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_bar_bg.visible = float(cfg.turn_time) > 0
	add_child(_turn_bar_bg)
	_turn_bar = ColorRect.new()
	_turn_bar.size = _turn_bar_bg.size
	_turn_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_bar_bg.add_child(_turn_bar)
	# --- whose turn + spectators + ping
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 20)
	trow.position = Vector2(0, top + 180)
	trow.size = Vector2(vs.x, 76)
	trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(trow)
	_turn_pill = PanelContainer.new()
	_turn_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_l = Kit.label("", 31, NX.TEXT, true)
	_turn_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_pill.add_child(_turn_l)
	trow.add_child(_turn_pill)
	if int(start.my_team) < 0:
		_spect_l = Kit.label("", 26, NX.RED, true)
		var sp := Kit.chip("", NX.RED)
		sp.get_child(0).queue_free()
		sp.add_child(_spect_l)
		trow.add_child(sp)
	if not is_host:
		_ping = _make_ping()
		trow.add_child(_ping)
	# --- banner
	_banner = VBoxContainer.new()
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.size = Vector2(vs.x, 300)
	_banner.position = Vector2(0, vs.y * 0.38 - 60)
	_banner.pivot_offset = _banner.size / 2
	_banner.modulate.a = 0
	_banner_t = Kit.title("", 140, Color.WHITE)
	_banner_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_s = Kit.label("", 34, NX.GOLD, true)
	_banner_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_t)
	_banner.add_child(_banner_s)
	add_child(_banner)
	# --- waiting overlay
	_wait = _overlay()
	var wl := Kit.label("در حال اتصال به میزبان…", 39, NX.TEXT, true)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(_wait.get_child(0) as CenterContainer).add_child(wl)
	_wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait.visible = not is_host
	add_child(_wait)
	# --- bottom controls: chat + voice
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 20)
	bot.position = Vector2(40, vs.y - NX.safe_bottom - 150)
	bot.size = Vector2(vs.x - 80, 130)
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot)
	_chat_btn = Kit.icon_button(Data.ui2("c_mega"), _toggle_chat, 64.0)
	_unread_dot = Kit.label("", 22, Color.WHITE, true)
	_unread_dot.position = Vector2(-6, -6)
	_unread_dot.visible = false
	var dot_bg := ColorRect.new()
	dot_bg.color = NX.RED
	dot_bg.size = Vector2(40, 40)
	dot_bg.show_behind_parent = true
	dot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unread_dot.add_child(dot_bg)
	_chat_btn.add_child(_unread_dot)
	bot.add_child(_chat_btn)
	if bool(room0.get("voice", false)):
		bot.add_child(_make_voice())
	# --- chat panel
	_chat_layer = _make_chat()
	_chat_layer.visible = false
	add_child(_chat_layer)
	# --- quit dialog
	_quit_layer = _overlay()
	_quit_layer.visible = false
	var qp := Kit.glass(NX.CYAN, true)
	qp.custom_minimum_size = Vector2(min(900.0, vs.x * 0.86), 0)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 30)
	qp.add_child(qv)
	var qt := Kit.title("خروج از بازی؟", 52)
	qt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qv.add_child(qt)
	var msg := "تو میزبانی؛ با خروج تو بازی برای همه لغو می‌شود." if is_host else ("تماشای بازی را ترک می‌کنی." if int(start.my_team) < 0 else "بازی بدون تو ادامه پیدا می‌کند و ربات جای تو بازی می‌کند.")
	var ql := Kit.label(msg, 34, NX.DIM)
	ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qv.add_child(ql)
	qv.add_child(Kit.button("ادامه‌ی بازی", func() -> void: _show_quit(false)))
	qv.add_child(Kit.button_small("خروج", _do_quit, "danger"))
	(_quit_layer.get_child(0) as CenterContainer).add_child(qp)
	add_child(_quit_layer)
	_update_turn_style(false)

func _side(t: int, right: bool) -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 14)
	if right:
		h.layout_direction = Control.LAYOUT_DIRECTION_RTL
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.custom_minimum_size = Vector2(100, 100)
	var logo := Kit.img(Data.team_tex(str(start.team_ids[t])), 84.0)
	ring.add_child(logo)
	h.add_child(ring)
	_logo_ring.resize(2)
	_logo_ring[t] = ring
	var nl := Kit.label(start.names[t], 31, NX.DIM, true)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.clip_text = true
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(nl)
	_name_l.resize(2)
	_name_l[t] = nl
	return h

func _round_btn(txt: String, cb: Callable) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(114, 114)
	p.add_theme_stylebox_override("panel", NX.box(Color(0.03, 0.047, 0.133, 0.88), 36, 3, NX.LINE))
	var l := Kit.label(txt, 42, NX.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	Kit.tap(p, cb)
	return p

func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0.008, 0.016, 0.055, 0.72)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(c)
	return o

func _make_ping() -> Control:
	if _ui_bits and _ui_bits.get_script_constant_map().has("PingBadge"):
		return _ui_bits.get_script_constant_map()["PingBadge"].new(link)
	var l := Kit.label("— ms", 26, NX.DIM, true)
	l.set_meta("ping_label", true)
	return l

func _make_voice() -> Control:
	if _ui_bits and _ui_bits.get_script_constant_map().has("VoiceBar"):
		return _ui_bits.get_script_constant_map()["VoiceBar"].new(room_id, true, true)
	# minimal mic button over the Voice autoload
	var v := get_node_or_null("/root/Voice")
	var b := _round_btn("🎙", func() -> void:
		if v == null:
			return
		var st: Dictionary = v.state if v.get("state") is Dictionary else {}
		var s := str(st.get("status", "off"))
		if s == "off" or s == "error":
			link.voice_join()
		elif s == "on":
			v.set_mic(not bool(st.get("mic", false))))
	return b

func _make_chat() -> Control:
	var vs := get_viewport_rect().size
	var holder := Kit.glass(NX.CYAN, false, 20.0)
	holder.position = Vector2(40, vs.y - NX.safe_bottom - 170 - 740)
	holder.size = Vector2(vs.x - 80, 720)
	holder.custom_minimum_size = holder.size
	if _ui_bits and _ui_bits.get_script_constant_map().has("ChatPanel"):
		var cp: Control = _ui_bits.get_script_constant_map()["ChatPanel"].new(link, true)
		cp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		holder.add_child(cp)
		return holder
	var v := VBoxContainer.new()
	holder.add_child(v)
	var lst := Kit.label("", 30, NX.TEXT)
	lst.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lst.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lst.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lst.set_meta("chat_list", true)
	lst.name = "ChatList"
	v.add_child(lst)
	var h := HBoxContainer.new()
	var le := LineEdit.new()
	le.max_length = 200
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(t: String) -> void:
		link.send_chat(t)
		le.text = "")
	h.add_child(le)
	h.add_child(Kit.button_small("ارسال", func() -> void:
		link.send_chat(le.text)
		le.text = ""))
	v.add_child(h)
	return holder

func _toggle_chat() -> void:
	_chat_layer.visible = not _chat_layer.visible
	link.chat_open = _chat_layer.visible
	if _chat_layer.visible:
		link.mark_read()
	_on_link_changed()

func _on_link_changed() -> void:
	if link == null or not is_instance_valid(link):
		return
	var un := int(link.state.unread)
	_unread_dot.visible = un > 0 and not _chat_layer.visible
	_unread_dot.text = NX.fa(min(9, un))
	if _spect_l:
		var n := 0
		for p in link.state.players:
			if str(p.get("role", "")) == "spectator" and link.state.online.has(str(p.get("user_id", ""))):
				n += 1
		_spect_l.text = "زنده · %s تماشاگر" % NX.fa(n)
	if _ping and _ping.has_meta("ping_label"):
		var r: Variant = link.state.rtt
		var col: Color = NX.DIM if r == null else (NX.GREEN if int(r) < 80 else (NX.GOLD if int(r) < 150 else NX.RED))
		(_ping as Label).text = "— ms" if r == null else "%d ms" % int(r)
		(_ping as Label).add_theme_color_override("font_color", col)
	var cl := _chat_layer.find_child("ChatList", true, false) if _chat_layer else null
	if cl is Label:
		var lines: Array = []
		for c in link.state.chat.slice(max(0, link.state.chat.size() - 10)):
			lines.append("%s: %s" % [c.get("name", ""), c.get("text", "")])
		(cl as Label).text = "\n".join(lines)

func _show_quit(on: bool) -> void:
	_quit_layer.visible = on

func _banner_show(t: String, s: String, c: Color) -> void:
	_banner_t.text = t
	_banner_t.add_theme_color_override("font_shadow_color", c)
	_banner_t.add_theme_constant_override("shadow_outline_size", 24)
	_banner_s.text = s
	_banner_s.add_theme_color_override("font_color", c)
	_banner_s.visible = s != ""
	_banner.scale = Vector2(0.3, 0.3)
	_banner.modulate.a = 0
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(_banner, "scale", Vector2(1.25, 1.25), 0.3)
	tw.parallel().tween_property(_banner, "modulate:a", 0.0, 0.3)

func _update_turn_style(my_turn: bool) -> void:
	var tc: Color = NX.CYAN if int(eng.turn) == 0 else NX.RED
	var sb := NX.box(Color(tc.r, tc.g, tc.b, 0.2) if my_turn else Color(0.024, 0.04, 0.118, 0.85), 36, 3, Color(tc.r, tc.g, tc.b, 0.67))
	sb.content_margin_left = 40; sb.content_margin_right = 40; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	_turn_pill.add_theme_stylebox_override("panel", sb)
	_turn_bar.color = tc
	for t in 2:
		var on := int(eng.turn) == t
		var col: Color = NX.CYAN if t == 0 else NX.RED
		var rb := NX.box(Color("#050816"), 50, 5 if on else 3, col if on else Color(1, 1, 1, 0.15))
		if on:
			rb.shadow_color = Color(col.r, col.g, col.b, 0.8)
			rb.shadow_size = 18
		(_logo_ring[t] as PanelContainer).add_theme_stylebox_override("panel", rb)
		(_name_l[t] as Label).add_theme_color_override("font_color", Color.WHITE if on else NX.DIM)

# ======================================================================== wire format
static func enc_ev(e: Dictionary) -> Array:
	match str(e.t):
		"hit": return [0, 1 if e.get("ball") else 0, int(round(float(e.power) * 100))]
		"wall": return [1, int(round(float(e.power) * 100))]
		"post": return [2, int(round(float(e.power) * 100))]
		"goal": return [3, int(e.team), 1 if e.get("nogoal") else 0]
		"turn": return [4, int(e.team)]
		"shot": return [5, int(e.team)]
		"end": return [6, int(e.score[0]), int(e.score[1])]
	return [7]

static func dec_ev(a: Array) -> Dictionary:
	var k := int(a[0]) if a.size() > 0 else 7
	var g := func(i: int) -> float: return float(a[i]) if a.size() > i else 0.0
	match k:
		0: return {"t": "hit", "ball": g.call(1) != 0, "power": g.call(2) / 100.0}
		1: return {"t": "wall", "power": g.call(1) / 100.0}
		2: return {"t": "post", "power": g.call(1) / 100.0}
		3: return {"t": "goal", "team": int(g.call(1)), "nogoal": g.call(2) != 0}
		4: return {"t": "turn", "team": int(g.call(1))}
		5: return {"t": "shot", "team": int(g.call(1))}
		6: return {"t": "end", "score": [int(g.call(1)), int(g.call(2))]}
	return {"t": "clock"}

func _send(m: Dictionary) -> void:
	if link and is_instance_valid(link):
		m["mid"] = match_id
		link.send_game(m)

# ======================================================================== events → feedback
## goal sound: exactly one Sfx.play_goal() per goal on every client (host and guests; 1.2 s guard against a re-sent event)
var _goal_ms := -100000
func _goal_sound(sfx: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _goal_ms < 1200: return
	_goal_ms = now
	if sfx == null: return
	if sfx.has_method("play_goal"): sfx.play_goal()
	else:
		sfx.play("goal"); sfx.play("roar")

func _on_event(ev: Dictionary) -> void:
	var t := str(ev.t)
	var sfx := _sfx_node()
	if t == "shot":
		co.mine = (hs.ctrl if is_host else cs.ctrl) == me
		co.touched = false
		if is_host and co.mine:
			co.power = float(eng.last_power)
	elif t == "hit" and ev.get("ball"):
		co.touched = true
	elif t == "turn":
		co.turn_n += 1
		if co.mine and not co.touched:
			co.misses += 1
			var tip: Variant = _oracle_call("coach_miss", [co.power, co.misses])
			if tip is String and tip != "" and _now() - co.last_tip > 18.0:
				co.last_tip = _now()
				_oracle_call("coach", [tip, "focus" if co.power > 0.9 else "idea"])
		co.mine = false
	if sfx == null:
		pass
	elif t == "hit":
		sfx.play("hitb" if ev.get("ball") else "hitp", float(ev.power))
		if float(ev.power) > 0.35:
			sfx.haptic("medium" if float(ev.power) > 0.7 else "light")
	elif t == "wall":
		sfx.play("wall", float(ev.power))
	elif t == "post":
		sfx.play("post", float(ev.power))
		sfx.haptic("medium")
	elif t == "shot":
		sfx.haptic("light")
	if t == "goal":
		if ev.get("nogoal"):
			_banner_show("گل مردود", "با ضربه‌ی اول نمی‌شه گل زد", NX.DIM)
		else:
			co.touched = true
			_goal_sound(sfx)
			if sfx:
				sfx.haptic("heavy")
			var tm := int(ev.team)
			_banner_show("گل!", start.names[tm], NX.CYAN if tm == 0 else NX.RED)
			if not is_host:
				eng.fx_goal(tm)
			if tm == int(start.my_team):
				_oracle_call("react", ["goal"])
	elif t == "clock":
		_banner_show("گل طلایی", "گل بعدی برنده‌ست", NX.GOLD)
	elif t == "end" and done == "no":
		done = "ended"
		if sfx:
			sfx.play("final")
			sfx.crowd(false)
		if is_host:
			_host_report(ev.score)
		else:
			cs.end_at = _now()

# ======================================================================== host: result
func _host_report(score: Array) -> void:
	_send_snap(true)
	var dur := int(round(_now() - float(hs.t0)))
	var d: Variant = null
	var ok := false
	for i in 3:
		var r: Dictionary = await Supa.call_rpc("report_match", {"p_match": match_id, "p_score_a": int(score[0]), "p_score_b": int(score[1]), "p_duration": dur})
		if r.ok:
			d = int(r.data.get("rating_delta", 0)) if r.data is Dictionary else 0
			ok = true
			break
		if str(r.raw).to_lower().contains("not live"):
			break
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree():
			return
	if not ok:
		_toast("ثبت نتیجه ناموفق بود")
	var w := 0 if score[0] > score[1] else (1 if score[1] > score[0] else -1)
	_send({"k": "res", "winner": w, "rd": d if d != null else 0, "score": [int(score[0]), int(score[1])], "ok": ok})
	# resend once (cheap insurance against a dropped broadcast)
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_inside_tree():
			_send({"k": "res", "winner": w, "rd": d if d != null else 0, "score": [int(score[0]), int(score[1])], "ok": ok}))
	if link and is_instance_valid(link):
		link.ping()
	await get_tree().create_timer(1.1).timeout
	if done == "ended" and is_inside_tree():
		done = "finished"
		_finish(_outcome(score, d, ok))

func _outcome(score: Array, d: Variant, reported: bool) -> Dictionary:
	var w := 0 if score[0] > score[1] else (1 if score[1] > score[0] else -1)
	var my := int(start.my_team)
	var rd: Variant = null
	if d != null:
		if not start.ranked:
			rd = 0
		elif my == 1:
			rd = -int(d)
		elif my == 0:
			rd = int(d)
	return {"match_id": match_id, "score": [int(score[0]), int(score[1])], "winner": w, "rating_delta": rd,
		"my_team": my if my >= 0 else null, "teams": start.teams, "team_ids": start.team_ids, "names": start.names,
		"reported": reported, "ranked": start.ranked}

func _finish(o: Dictionary) -> void:
	var sfx := _sfx_node()
	if sfx:
		sfx.music(true)
	_set_oui_skip()
	var nav := get_node_or_null("/root/Nav")
	if nav:
		nav.go("online_result", {"o": o, "outcome": o, "room_id": room_id, "before": params.get("before"), "link": link})

func _exit(why: String) -> void:
	var sfx := _sfx_node()
	if sfx:
		sfx.crowd(false)
		sfx.music(true)
	_set_oui_skip()
	if link and is_instance_valid(link):
		link.refresh()
	var nav := get_node_or_null("/root/Nav")
	if nav:
		nav.go("lobby", {"room_id": room_id, "skip_match": match_id, "why": why, "link": link})

func _set_oui_skip() -> void:
	var oui: Script = _try_load("res://src/online/oui.gd")
	if oui:
		oui.set("skip_match", match_id)

# ======================================================================== host: snapshots
func _send_snap(force := false) -> void:
	var now := _now_ms()
	var rec: int = max(1, link.state.online.size() - 1)
	var hz := 30 if rec <= 1 else (25 if rec <= 3 else 20)
	var moving: bool = eng.phase == "move" or eng.phase == "goal"
	if not force and now - float(hs.last_send) < (1000.0 / hz if moving else 500.0):
		return
	hs.last_send = now
	var p := PackedInt32Array()
	p.resize(eng.bodies.size() * 3)
	var i := 0
	for b in eng.bodies:
		p[i] = int(round(b.x * 10)); p[i + 1] = int(round(b.y * 10)); p[i + 2] = int(round(fposmod(b.ang, TAU_) * 100))
		i += 3
	var bl: NxBody = eng.ball
	var R := [int(round(bl.r0 * 1000)), int(round(bl.r1 * 1000)), int(round(bl.r2 * 1000)), int(round(bl.r3 * 1000)), int(round(bl.r4 * 1000)),
		int(round(bl.r5 * 1000)), int(round(bl.r6 * 1000)), int(round(bl.r7 * 1000)), int(round(bl.r8 * 1000))]
	hs.q += 1
	var s := {"q": hs.q, "ts": now, "hz": hz, "ph": eng.phase, "tu": int(eng.turn), "sc": [int(eng.score[0]), int(eng.score[1])],
		"ml": round(float(eng.mleft) * 10) / 10.0, "tl": round(float(eng.tleft) * 10) / 10.0, "su": 1 if eng.sudden else 0,
		"c": hs.ctrl if hs.ctrl != "" else null, "n": hs.seq, "p": Array(p), "R": R, "ev": hs.evs}
	hs.evs = []
	_send({"k": "s", "s": s})

func _ctrl_for(t: int) -> String:
	var team := team_of(link.state.players, t)
	if team.is_empty():
		return ""
	var n := team.size()
	var st0 := ((int(hs.turn_count[t]) - 1) % n + n) % n
	for i in n:
		var pl: Dictionary = team[(st0 + i) % n]
		var u := str(pl.get("user_id", ""))
		if u == me or link.state.online.has(u):
			return u
	return ""

# ======================================================================== client: snapshots
func _apply_scalars(s: Dictionary) -> void:
	eng.phase = str(s.ph)
	eng.turn = int(s.tu)
	eng.score = [int(s.sc[0]), int(s.sc[1])]
	eng.mleft = float(s.ml)
	eng.tleft = float(s.tl)
	eng.sudden = int(s.su) != 0
	cs.ctrl = str(s.c) if s.get("c") != null else ""
	cs.seq = int(s.n)
	eng.ai_teams = [false, false]
	if s.get("c") == null:
		eng.ai_teams[int(s.tu)] = true
	if s.ph != "aim" and eng.drag != null:
		eng.drag = null
	if s.ev is Array:
		for e in s.ev:
			if e is Array:
				_on_event(dec_ev(e))

func _place_bodies(a: Dictionary, b: Variant, k: float, dt: float) -> void:
	var n: int = eng.bodies.size()
	var ap: Array = a.p
	if ap.size() < n * 3:
		return
	var prev: PackedFloat64Array = cs.prev
	if prev.size() != n * 2:
		prev = PackedFloat64Array()
		prev.resize(n * 2)
	var bp: Array = b.p if (b is Dictionary and b.p is Array and b.p.size() >= n * 3) else []
	var got: bool = cs.got
	for i in n:
		var bd: NxBody = eng.bodies[i]
		var x := float(ap[i * 3]) / 10.0
		var y := float(ap[i * 3 + 1]) / 10.0
		var ang := float(ap[i * 3 + 2]) / 100.0
		if not bp.is_empty():
			x += (float(bp[i * 3]) / 10.0 - x) * k
			y += (float(bp[i * 3 + 1]) / 10.0 - y) * k
			var da := float(bp[i * 3 + 2]) / 100.0 - ang
			if da > PI: da -= TAU_
			elif da < -PI: da += TAU_
			ang += da * k
		var px := prev[i * 2]
		var py := prev[i * 2 + 1]
		bd.vx = (x - px) / max(dt, 0.001) if got else 0.0
		bd.vy = (y - py) / max(dt, 0.001) if got else 0.0
		if absf(bd.vx) < 4: bd.vx = 0.0
		if absf(bd.vy) < 4: bd.vy = 0.0
		bd.x = x; bd.px = x; bd.y = y; bd.py = y; bd.ang = ang; bd.vox = 0.0; bd.voy = 0.0
		prev[i * 2] = x
		prev[i * 2 + 1] = y
	cs.prev = prev
	var src: Variant = (b.R if (b is Dictionary and k > 0.5) else a.R)
	if src is Array and src.size() == 9:
		var bl: NxBody = eng.ball
		bl.r0 = float(src[0]) / 1000.0; bl.r1 = float(src[1]) / 1000.0; bl.r2 = float(src[2]) / 1000.0
		bl.r3 = float(src[3]) / 1000.0; bl.r4 = float(src[4]) / 1000.0; bl.r5 = float(src[5]) / 1000.0
		bl.r6 = float(src[6]) / 1000.0; bl.r7 = float(src[7]) / 1000.0; bl.r8 = float(src[8]) / 1000.0
	cs.got = true
	eng.acc = 0.0

# ======================================================================== network messages
func _on_msg(m: Variant, from: String) -> void:
	if not (m is Dictionary) or done == "finished" and str(m.get("k", "")) != "res":
		return
	if m.has("mid") and str(m.mid) != match_id:
		return   # stale message from another match in this room
	var k := str(m.get("k", ""))
	if k == "s" and not is_host:
		var s: Variant = m.get("s")
		if not (s is Dictionary) or not (s.get("p") is Array) or not s.has("q") or not s.has("ts"):
			return
		var hosts := [str(room0.get("host", ""))]
		if link.state.room is Dictionary:
			hosts.append(str(link.state.room.get("host", "")))
		if from != "" and not hosts.has(from):
			return   # only the host's snapshots count
		var now := _now_ms()
		cs.last_recv = _now()
		var q := int(s.q)
		var buf: Array = cs.buf
		if q <= int(cs.applied) and cs.got:
			return   # already played back
		for x in buf:
			if int(x.q) == q:
				return   # duplicate
		cs.offs.append([now, now - float(s.ts)])
		while cs.offs.size() and now - float(cs.offs[0][0]) > 4000.0:
			cs.offs.pop_front()
		if buf.is_empty() or q > int(buf[buf.size() - 1].q):
			buf.append(s)
		else:
			buf.append(s)
			buf.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.q) < int(b.q))
		if buf.size() > 60:
			cs.buf = buf.slice(buf.size() - 60)
		# shot acknowledged (seq moved on or the shot started)
		if cs.shot != null and (int(s.n) != int(cs.shot.n) or str(s.ph) != "aim"):
			cs.shot = null
	elif k == "shot" and is_host:
		if from != hs.ctrl or eng.phase != "aim" or int(_num(m.get("n"), -1)) != int(hs.seq):
			return
		var b := _body(int(_num(m.get("b"), -999)))
		if b == null or b.team != int(eng.turn):
			return
		var dx := _num(m.get("dx"), 0)
		var dy := _num(m.get("dy"), 0)
		var l := sqrt(dx * dx + dy * dy)
		if l > 18 and l < 5000:
			eng.fire(b, dx, dy, l, true)
	elif k == "aim":
		var ctrl: String = hs.ctrl if is_host else cs.ctrl
		if from != ctrl or from == me:
			return
		var bid := int(_num(m.get("b"), -1))
		if bid < 0:
			if eng.drag != null and eng.drag.ai and not eng.is_ai_turn():
				eng.drag = null
			return
		if eng.phase != "aim":
			return
		var b := _body(bid)
		if b == null:
			return
		eng.drag = {"b": b, "sx": b.x, "sy": b.y, "cx": b.x - _num(m.get("dx"), 0), "cy": b.y - _num(m.get("dy"), 0), "ai": true}
	elif k == "res" and not is_host:
		var sc: Variant = m.get("score")
		cs.res = {"winner": int(_num(m.get("winner"), -1)), "rd": m.get("rd"), "score": sc if sc is Array and sc.size() == 2 else [eng.score[0], eng.score[1]], "ok": bool(m.get("ok", false))}
		if done == "no":
			# the end event was missed (late join / dropped snapshot): end now
			done = "ended"
			cs.end_at = _now()
	elif k == "abort" and not is_host and done != "finished" and done != "aborted" and (from == "" or from == str(room0.get("host", ""))):
		done = "aborted"
		_toast("میزبان بازی را لغو کرد")
		_exit("aborted")

func _body(id: int) -> NxBody:
	for b in eng.bodies:
		if b.id == id:
			return b
	return null

# ======================================================================== main loop
func _process(dt_in: float) -> void:
	if eng == null or done == "aborted" or link == null or not is_instance_valid(link):
		return
	var dt := minf(0.1, dt_in)
	var now := _now()
	if is_host:
		eng.update(dt)
		var urgent := false
		if eng.events.size() > 0:
			for ev in eng.events:
				if ev.t == "turn":
					hs.turn_count[int(ev.team)] += 1
					hs.seq += 1
				hs.evs.append(enc_ev(ev))
				if ev.t != "hit" and ev.t != "wall" and ev.t != "post":
					urgent = true
			var evs: Array = eng.events.duplicate()
			eng.events.clear()
			# controller must be decided before the snapshot that announces the turn
			hs.ctrl = "" if eng.phase == "over" else _ctrl_for(int(eng.turn))
			for ev in evs:
				_on_event(ev)
		var c := "" if eng.phase == "over" else _ctrl_for(int(eng.turn))
		if c != hs.ctrl:
			hs.ctrl = c
			urgent = true
			if c != me and eng.drag != null and not eng.drag.ai:
				eng.drag = null
				_local = null
		var ai: bool = c == "" and eng.phase != "over"
		if bool(eng.ai_teams[int(eng.turn)]) != ai or bool(eng.ai_teams[1 - int(eng.turn)]):
			eng.ai_teams = [false, false]
			eng.ai_teams[int(eng.turn)] = ai
			if not ai:
				eng.ai_plan = null
				if eng.drag != null and eng.drag.ai:
					eng.drag = null
		if done != "finished":
			_send_snap(urgent)
	else:
		_client_tick(dt, now)
		if done == "aborted":
			return
	# the player in control flicks with their own equipped disc's stats
	var cu: String = hs.ctrl if is_host else cs.ctrl
	if cu != "" and eng.c_stats != null:
		for pl in link.state.players:
			if str(pl.get("user_id", "")) == cu:
				eng.c_stats[int(eng.turn)] = _disc_stats(disc_of(pl))
				break
	if eng.parts.size() > 400:
		eng.parts.resize(400)
	if not _view_is_mv:
		view.queue_redraw()
	_hud_tick(cu)

func _client_tick(dt: float, now: float) -> void:
	var now_ms := now * 1000.0
	var off := 0.0
	if cs.offs.size():
		off = 1e18
		for o in cs.offs:
			off = minf(off, float(o[1]))
	var buf: Array = cs.buf
	var hz := float(buf[buf.size() - 1].get("hz", 12)) if buf.size() else 12.0
	if hz <= 0:
		hz = 12.0
	var rt := now_ms - off - 1700.0 / hz
	for s in buf:
		if int(s.q) > int(cs.applied) and float(s.ts) <= rt:
			cs.applied = int(s.q)
			_apply_scalars(s)
	if buf.size():
		var i := 0
		while i + 1 < buf.size() and float(buf[i + 1].ts) <= rt:
			i += 1
		var a: Dictionary = buf[i]
		var b: Variant = buf[i + 1] if i + 1 < buf.size() else null
		var k := 0.0
		if b != null:
			k = clampf((rt - float(a.ts)) / maxf(1.0, float(b.ts) - float(a.ts)), 0.0, 1.0)
		if float(a.ts) <= rt or not cs.got:
			if int(cs.applied) < int(a.q) and not cs.got:
				cs.applied = int(a.q)
				_apply_scalars(a)
			var pv: Variant = buf[i - 1] if i > 0 else null
			# buffer starved while things move → extrapolate from the last two snapshots for up to 120 ms
			if b == null and pv != null and (a.ph == "move" or a.ph == "goal") and rt > float(a.ts):
				_place_bodies(pv, a, 1.0 + minf(120.0, rt - float(a.ts)) / maxf(1.0, float(a.ts) - float(pv.ts)), dt)
			else:
				_place_bodies(a, b, k, dt)
		if i > 3:
			cs.buf = buf.slice(i - 3)
	eng.tick_fx(dt)
	# resend an unacknowledged shot (host dedupes by seq + phase)
	if cs.shot != null and done == "no":
		var sh: Dictionary = cs.shot
		if now - float(sh.at) > 0.45:
			if int(sh.tries) >= 3 or int(sh.n) != int(cs.seq):
				cs.shot = null
			else:
				sh.tries = int(sh.tries) + 1
				sh.at = now
				_send(sh.msg.duplicate())
	# host lost. Our OWN link being down is not the host's fault: wait (the host keeps simulating and
	# snapshots resume on reconnect) up to SELF_OFFLINE_GIVE_UP. With our link up and the host silent
	# (8 s, or 4 s while absent from presence), ask the server to settle the match every 5 s; it agrees
	# once the host has been silent 30 s there (forfeit if opponents are present, else abandon).
	if done == "no":
		if not link.state.connected:
			if float(cs.off_at) == 0.0:
				cs.off_at = now
			if now - float(cs.off_at) > SELF_OFFLINE_GIVE_UP:
				done = "aborted"
				_toast("ارتباط با میزبان قطع شد")
				_exit("hostLost")
				return
		else:
			if float(cs.off_at) > 0.0:
				# back online: silence while we were offline does not count against the host
				cs.off_at = 0.0
				cs.last_recv = maxf(float(cs.last_recv), now - 2.0)
			var silent := now - float(cs.last_recv)
			var host := str(room0.get("host", ""))
			var host_online: bool = link.state.online.has(host)
			var limit := HOST_SILENCE if cs.got else FIRST_SNAP_WAIT
			if silent > limit or (not host_online and silent > 4.0 and cs.got):
				if silent > HOST_GIVE_UP or (not cs.got and int(start.my_team) < 0):
					done = "aborted"
					_toast("ارتباط با میزبان قطع شد")
					_exit("hostLost")
					return
				if int(start.my_team) >= 0 and not cs.claiming and now - float(cs.claim_at) > 5.0:
					_claim_host_lost()
	if done == "ended":
		if cs.res != null and now - float(cs.end_at) > 0.9:
			done = "finished"
			_finish(_outcome(cs.res.score, cs.res.rd, cs.res.ok))
		elif cs.res == null and now - float(cs.end_at) > 10.0:
			done = "finished"
			_finish_from_db()

func _host_quit_rpc() -> void:
	if link and is_instance_valid(link) and link.has_method("host_quit"):
		link.host_quit(match_id, [int(eng.score[0]), int(eng.score[1])])
	else:
		Supa.call_rpc("abandon_match", {"p_match": match_id})
		if link and is_instance_valid(link):
			link.ping()

func _claim_host_lost() -> void:
	if not link.has_method("claim_host_lost"):
		return
	cs.claiming = true
	cs.claim_at = _now()
	var r: Dictionary = await link.claim_host_lost(match_id, [int(eng.score[0]), int(eng.score[1])])
	cs.claiming = false
	if not is_inside_tree() or done != "no":
		return
	if r.ok and r.data is Dictionary:
		var d: Dictionary = r.data
		if str(d.get("outcome", "")) == "forfeit":
			done = "finished"
			var sc := [int(_num(d.get("score_a"), eng.score[0])), int(_num(d.get("score_b"), eng.score[1]))]
			_toast("میزبان قطع شد؛ نتیجه ثبت شد")
			_finish(_outcome(sc, d.get("rating_delta"), true))
			return
		done = "aborted"
		_toast("ارتباط با میزبان قطع شد")
		_exit("hostLost")
	elif str(r.get("raw", "")).contains("not live"):
		done = "ended"
		cs.end_at = _now() - 9.0   # settled meanwhile (host reported): read the result from the DB
	# "host still online" -> keep waiting, retry in 5 s

## back from the background: never count our own pause as host silence
func _on_resumed(_away: float) -> void:
	cs.last_recv = _now()
	if not is_host:
		cs.offs.clear()       # clock offset re-estimated from fresh snapshots
		cs.buf = []
		cs.got = false        # snap to the next snapshot instead of interpolating across the gap

func _finish_from_db() -> void:
	var r: Dictionary = await Supa.select("matches", "select=score_a,score_b,status&id=eq." + match_id, true)
	var sc := [int(eng.score[0]), int(eng.score[1])]
	var ok := false
	if r.ok and r.data is Dictionary and str(r.data.get("status", "")) == "done":
		sc = [int(_num(r.data.get("score_a"), sc[0])), int(_num(r.data.get("score_b"), sc[1]))]
		ok = true
	if is_inside_tree():
		_finish(_outcome(sc, null, ok))

func _hud_tick(ctrl: String) -> void:
	var m: int = max(0, int(ceil(float(eng.mleft))))
	var clock := ""
	if float(cfg.match_time) > 0:
		clock = "گل طلایی" if eng.sudden else "%d:%02d" % [m / 60, m % 60]
	else:
		clock = "تا %s گل" % NX.fa(int(cfg.limit))
	var tl := 1.0
	if float(cfg.turn_time) > 0 and eng.phase == "aim":
		tl = maxf(0.0, float(eng.tleft) / float(cfg.turn_time))
	var wait: bool = not is_host and (not cs.got or not link.state.connected or (done == "no" and _now() - float(cs.last_recv) > HOST_SILENCE))
	var s0 := int(eng.score[0])
	var s1 := int(eng.score[1])
	var my_turn: bool = ctrl == me and eng.phase == "aim" and int(start.my_team) >= 0
	# oracle reminder + countdown ticks
	if ctrl == me and eng.phase == "aim" and float(cfg.turn_time) > 0:
		if float(eng.tleft) < 5 and float(eng.tleft) > 0 and co.reminded != co.turn_n:
			co.reminded = co.turn_n
			_oracle_call("coach", ["نوبت توئه و ۵ ثانیه مونده! ⏱", "alert"])
		var sec := int(ceil(float(eng.tleft)))
		if sec <= 3 and sec > 0 and sec != _tick_at:
			_tick_at = sec
			var sfx := _sfx_node()
			if sfx:
				sfx.play("tick")
	else:
		_tick_at = -1
	var key := [s0, s1, int(eng.turn), clock, snappedf(tl, 0.01), eng.sudden, ctrl, eng.phase, wait, my_turn]
	if key == _hud.get("key"):
		return
	var prev: Array = _hud.get("key", [])
	_hud["key"] = key
	_score_l.text = "%d : %d" % ([s1, s0] if flipped else [s0, s1])
	_clock_l.text = clock
	_clock_l.add_theme_color_override("font_color", NX.GOLD if eng.sudden else NX.DIM)
	_turn_bar.size.x = _turn_bar_bg.size.x * tl
	var turn_name := "نوبت توئه!" if ctrl == me else "نوبت: %s" % _name_of(ctrl)
	_turn_l.text = turn_name if eng.phase == "aim" else ("گل!" if eng.phase == "goal" else ("پایان بازی" if eng.phase == "over" else "در حال حرکت…"))
	_turn_l.add_theme_color_override("font_color", Color.WHITE if my_turn else NX.TEXT)
	_wait.visible = wait
	if prev.is_empty() or prev[2] != key[2] or prev[9] != my_turn:
		_update_turn_style(my_turn)
	# my turn → haptic + chime
	if my_turn and (not _my_turn_prev or (prev.size() and prev[2] != key[2])):
		var sfx := _sfx_node()
		if sfx:
			sfx.haptic("medium")
			sfx.play("ready")
	_my_turn_prev = my_turn

# ======================================================================== input
func _can_act() -> bool:
	if int(start.my_team) < 0 or done != "no":
		return false
	if is_host:
		return eng.phase == "aim" and hs.ctrl == me and not eng.is_ai_turn()
	return eng.phase == "aim" and cs.ctrl == me and _now() - float(cs.pending_shot) > 1.5

func _send_aim(force := false) -> void:
	var d: Variant = eng.drag
	if d == null or d.ai:
		return
	var now := _now()
	if not force and now - float(hs.last_aim) < 0.12:
		return
	hs.last_aim = now
	_send({"k": "aim", "b": d.b.id, "dx": int(round(d.sx - d.cx)), "dy": int(round(d.sy - d.cy))})

func _on_touch(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.index != 0:
			return
		if e.pressed:
			_grant(e.position)
		elif e.canceled:
			_terminate()
		else:
			_release()
	elif e is InputEventScreenDrag:
		if e.index == 0:
			_move(e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not _emulated():
		if e.pressed:
			_grant(e.position)
		else:
			_release()
	elif e is InputEventMouseMotion and not _emulated() and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_move(e.position)

func _emulated() -> bool:
	return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))

func _grant(pos: Vector2) -> void:
	if not _can_act():
		return
	var p := _world(pos)
	var sfx := _sfx_node()
	if is_host:
		if eng.pick(p.x, p.y):
			if sfx:
				sfx.haptic("light")
			_local = {"b": eng.drag.b, "sx": eng.drag.sx, "sy": eng.drag.sy} if eng.drag != null else null
		return
	var best: NxBody = null
	var bd := 1e9
	for b in eng.bodies:
		if b.team == int(start.my_team) and b.team == int(eng.turn):
			var d := Vector2(p.x - b.x, p.y - b.y).length()
			if d < b.r + 34 and d < bd:
				best = b
				bd = d
	if best == null:
		return
	if sfx:
		sfx.haptic("light")
	_local = {"b": best, "sx": best.x, "sy": best.y}
	eng.drag = {"b": best, "sx": best.x, "sy": best.y, "cx": p.x, "cy": p.y, "ai": false}

func _move(pos: Vector2) -> void:
	if _local == null or eng.drag == null or eng.drag.ai:
		return
	var p := _world(pos)
	eng.move(p.x, p.y)
	_send_aim()

func _release() -> void:
	var l0: Variant = _local
	_local = null
	if l0 == null:
		return
	var d: Variant = eng.drag
	if is_host:
		eng.release()
		_send({"k": "aim", "b": -1})
		return
	eng.drag = null
	_send({"k": "aim", "b": -1})
	if d == null or d.ai:
		return
	var dx: float = d.sx - d.cx
	var dy: float = d.sy - d.cy
	var l := sqrt(dx * dx + dy * dy)
	if l > 18 and _can_act():
		co.power = minf(l, LMAX) / LMAX
		cs.pending_shot = _now()
		var msg := {"k": "shot", "b": l0.b.id, "dx": round(dx * 10) / 10.0, "dy": round(dy * 10) / 10.0, "n": cs.seq}
		cs.shot = {"msg": msg.duplicate(), "n": cs.seq, "at": _now(), "tries": 0}
		_send(msg)

func _terminate() -> void:
	_local = null
	if eng.drag != null and not eng.drag.ai:
		eng.drag = null
	_send({"k": "aim", "b": -1})

func _unhandled_input(e: InputEvent) -> void:
	# Android back / Esc opens the quit dialog (the match has its own)
	if e.is_action_pressed("ui_cancel"):
		_show_quit(not _quit_layer.visible)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _quit_layer:
		_show_quit(true)

func _do_quit() -> void:
	_show_quit(false)
	if is_host:
		done = "aborted"
		_send({"k": "abort"})
		_host_quit_rpc()
	else:
		done = "aborted"
	_exit("quit")

# ======================================================================== utils
func _now() -> float:
	return Time.get_unix_time_from_system()

func _now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0

func _sfx_node() -> Node:
	return get_node_or_null("/root/Sfx")

func _toast(m: String) -> void:
	var nav := get_node_or_null("/root/Nav")
	if nav and nav.has_method("toast"):
		nav.toast(m, "err")
	else:
		print("[online_match] ", m)

func _nav_chrome(on: bool) -> void:
	var nav := get_node_or_null("/root/Nav")
	if nav and nav.has_method("chrome"):
		nav.chrome(on)

func _try_load(path: String) -> Script:
	if ResourceLoader.exists(path):
		var s: Variant = load(path)
		if s is Script and (s as Script).can_instantiate():
			return s
	return null

var _oracle_fns := {}
func _oracle_call(fn: String, args: Array) -> Variant:
	if _oracle == null:
		return null
	if _oracle_fns.is_empty():
		for m in _oracle.get_script_method_list():
			_oracle_fns[str(m.name)] = true
		_oracle_fns["__"] = true
	if _oracle_fns.has(fn):
		return _oracle.callv(fn, args)
	return null


# ======================================================================== fallback renderer
## Used only when MatchView is not available (keeps the screen usable / testable).
class _FallbackView extends Node2D:
	var eng: Variant = null
	var flipped := false
	var _s := 1.0
	var _o := Vector2.ZERO

	func _layout() -> void:
		var vs := get_viewport_rect().size
		var w: float = eng.Fr - eng.Fl
		var h: float = eng.Fb - eng.Ft
		_s = minf(vs.x * 0.94 / w, (vs.y - 500.0) / h)
		_o = Vector2(vs.x / 2.0 - eng.CX * _s, vs.y / 2.0 - eng.CY * _s)

	func to_screen(x: float, y: float) -> Vector2:
		var p := _o + Vector2(x, y) * _s
		return get_viewport_rect().size - p if flipped else p

	func to_world(pos: Vector2) -> Vector2:
		_layout()
		var p := get_viewport_rect().size - pos if flipped else pos
		return (p - _o) / _s

	func _draw() -> void:
		if eng == null:
			return
		_layout()
		var a := to_screen(eng.Fl, eng.Ft)
		var b := to_screen(eng.Fr, eng.Fb)
		draw_rect(Rect2(a, b - a).abs(), Color(0.05, 0.25, 0.15), true)
		draw_rect(Rect2(a, b - a).abs(), Color(1, 1, 1, 0.5), false, 3.0)
		for bd in eng.bodies:
			var c := Color("#39d5ff") if bd.team == 0 else (Color("#ff4a5a") if bd.team == 1 else Color.WHITE)
			draw_circle(to_screen(bd.x, bd.y), bd.r * _s, c)
		var d: Variant = eng.drag
		if d != null:
			draw_line(to_screen(d.sx, d.sy), to_screen(d.sx + (d.sx - d.cx), d.sy + (d.sy - d.cy)), Color(1, 0.82, 0.34), 6.0)
