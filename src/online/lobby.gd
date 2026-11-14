extends Control
## Room lobby (port of RN Lobby.tsx + the room-state navigation of OnlineRoot.tsx):
## seats per team, spectators, ready / start, host settings + kick, chat, voice, share code,
## auto 3-2-1 start for quick/arena rooms, host returning to a stuck "playing" room ends that match.
## Uses OUI.link (RoomLink). RPC: take_seat, set_ready, start_match, kick, spectate, update_room,
## abandon_match, leave_room. Starts the match with Nav.go("online_match", {room_id, match_id, link, before, spectator}).

var params: Dictionary = {}
var link: Variant = null
var busy := ""
var sig := ""
var count := 0
var count_timer: Timer
var counting := false
var page: Dictionary
var body: VBoxContainer
var bar_slot: VBoxContainer
var overlay: Control = null
var confirm: Control = null
var title_l: Label


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	# params from online_match / online_result: {room_id, link, skip_match, why}
	var pl: Variant = params.get("link")
	if pl != null and is_instance_valid(pl) and not bool(pl.get("dead")):
		if OUI.link != pl:
			if OUI.link != null and is_instance_valid(OUI.link) and OUI.link != pl:
				OUI.drop_link()
			OUI.link = pl
			OUI.ebus().link_changed.emit()
	link = OUI.link
	if link != null and not is_instance_valid(link):
		OUI.link = null
		link = null
	if link == null:
		Nav.go.call_deferred("hub", {})
		return
	var skip := OUI.s(params.get("skip_match", ""))
	if skip != "":
		OUI.skip_match = skip
		OUI.first_load = false
	if params.has("skip_match"):
		link.refresh()
	if link.has_signal("changed"):
		link.changed.connect(_on_change)
	Voice.state_changed.connect(_on_change)
	count_timer = Timer.new()
	count_timer.wait_time = 1.0
	count_timer.timeout.connect(_tick)
	add_child(count_timer)
	_build_shell()
	_on_change()


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	# popups (leave confirm, chat / settings sheets) are closed first by Nav; then ask before leaving
	if confirm and is_instance_valid(confirm):
		_close_confirm()
		return true
	_ask_leave()
	return true


func _st() -> Dictionary:
	return OUI.d(link.state) if link != null else {}


func _room() -> Dictionary:
	return OUI.d(_st().get("room"))


func _me() -> String:
	return OUI.s(link.me) if link != null else ""


# ---------------------------------------------------------------- shell
func _build_shell() -> void:
	OUI.clear(self)
	var right := OUI.hbox(OUI.S_S)
	right.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var shb := OUI.tap(OUI.img(OUI.ui2("c_mega"), 24), _share)
	shb.custom_minimum_size = Vector2(OUI.px(44), OUI.px(44))
	right.add_child(shb)
	var pb := NetImg.PingBadge.new(link)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(pb)
	page = OUI.page(self, "…", "LOBBY", _ask_leave, right)
	title_l = page["header"].get_meta("title")
	body = page["body"]
	var bar := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(2 / 255.0, 4 / 255.0, 14 / 255.0, 0.95)
	st.content_margin_left = OUI.px(OUI.S_L)
	st.content_margin_right = OUI.px(OUI.S_L)
	st.content_margin_top = OUI.px(OUI.S_M)
	st.content_margin_bottom = OUI.px(OUI.S_M)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = OUI.px(16)
	bar.add_theme_stylebox_override("panel", st)
	bar_slot = OUI.vbox(OUI.S_S)
	bar.add_child(bar_slot)
	(page["root"] as VBoxContainer).add_child(bar)
	body.add_child(OUI.spinner(36))


# ---------------------------------------------------------------- state → UI + navigation (OnlineRoot)
func _on_change(_x: Variant = null) -> void:
	if link == null or not is_inside_tree():
		return
	var st := _st()
	if not bool(st.get("loaded", false)):
		return
	var room := _room()
	if bool(st.get("gone", false)):
		OUI.toast(I18n.t("lobby.you_left_the_room") if not room.is_empty() else I18n.t("lobby.the_room_was_closed"), "err")
		OUI.drop_link()
		Nav.go("hub", {})
		OUI.prune_history()
		return
	if room.is_empty():
		return
	if OUI.first_load:
		OUI.first_load = false
		# a host coming back to a room stuck in "playing" (e.g. app was killed) ends that match
		if OUI.s(room.get("status")) == "playing" and OUI.s(room.get("current_match")) != "" and OUI.s(room.get("host")) == _me():
			OUI.skip_match = OUI.s(room.get("current_match"))
			_abandon(OUI.skip_match)
			return
	var cm := OUI.s(room.get("current_match"))
	if OUI.s(room.get("status")) == "playing" and cm != "" and cm != OUI.skip_match:
		_go_match(cm)
		return
	_render()


func _abandon(mid: String) -> void:
	var r: Dictionary = await Supa.call_rpc("abandon_match", {"p_match": mid})
	if OUI.ok(r) and link != null:
		link.ping()


func _go_match(mid: String) -> void:
	OUI.before_profile = OUI.profile.duplicate()
	OUI.skip_match = mid
	var me := _me()
	var spectator := true
	for p in OUI.a(_st().get("players")):
		if OUI.s(p.get("user_id")) == me and OUI.s(p.get("role")) == "player":
			spectator = false
	Nav.go("online_match", {"room_id": OUI.s(_room().get("id")), "match_id": mid, "link": link, "before": OUI.before_profile, "spectator": spectator})


func _watch_live() -> void:
	var m := OUI.s(_room().get("current_match"))
	if m != "":
		_go_match(m)


func _seats() -> Array:
	var room := _room()
	var n := OUI.team_size(OUI.s(room.get("mode"), "1v1"))
	var t: Array = [[], []]
	for k in n:
		t[0].append(null)
		t[1].append(null)
	for p in OUI.a(_st().get("players")):
		if OUI.s(p.get("role")) == "player" and p.get("team") != null and p.get("slot") != null:
			var tm := OUI.i(p.get("team"))
			var sl := OUI.i(p.get("slot"))
			if (tm == 0 or tm == 1) and sl < n:
				t[tm][sl] = p
	return t


func _render() -> void:
	var st := _st()
	var room := _room()
	var v: Dictionary = Voice.state if Voice.state is Dictionary else {}
	var s2 := JSON.stringify([room, st.get("players"), (st.get("online", {}) as Dictionary).keys() if st.get("online") is Dictionary else [], st.get("unread"), OUI.a(st.get("chat")).size(), v.get("speaking", []), busy])
	if s2 == sig:
		return
	sig = s2
	var me := _me()
	var players := OUI.a(st.get("players"))
	var online: Dictionary = OUI.d(st.get("online"))
	var seats := _seats()
	var n := OUI.team_size(OUI.s(room.get("mode"), "1v1"))
	var specs := players.filter(func(p: Variant) -> bool: return OUI.s(p.get("role")) == "spectator")
	var meP: Dictionary = {}
	for p in players:
		if OUI.s(p.get("user_id")) == me:
			meP = p
	var is_host := OUI.s(room.get("host")) == me
	var am_player := OUI.s(meP.get("role")) == "player"
	var full := true
	for t in seats:
		for x in t:
			if x == null:
				full = false
	var not_ready := players.filter(func(p: Variant) -> bool: return OUI.s(p.get("role")) == "player" and not bool(p.get("ready", false)) and OUI.s(p.get("user_id")) != OUI.s(room.get("host")))
	# v3: the host can always start once every seated player is ready — empty seats are played by the bot
	# (online_match: "a team with nobody connected is played by the bot"; server start_match has no full-room check)
	var can_start := is_host and am_player and not_ready.is_empty() and OUI.s(room.get("status")) == "waiting"
	var speaking: Array = OUI.a(v.get("speaking"))
	var playing := OUI.s(room.get("status")) == "playing"
	var kind := OUI.s(room.get("kind"), "casual")
	var settings := OUI.d(room.get("settings"))

	title_l.text = OUI.s(room.get("name"))
	OUI.clear(body)
	# ---- info strip
	var info := OUI.panel(OUI.CYAN)
	var iv := OUI.vbox(OUI.S_S)
	var ih := OUI.hbox(OUI.S_S)
	var cv := OUI.vbox(0)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(OUI.lbl(I18n.t("lobby.room_code"), OUI.TS_CAP, OUI.DIM))
	var code_l := OUI.lbl(OUI.s(room.get("code")), 24, OUI.CYAN, "title")
	cv.add_child(code_l)
	ih.add_child(cv)
	ih.add_child(OUI.pill(I18n.t("lobby.copy"), _copy, OUI.CYAN, 64, 44))
	ih.add_child(OUI.pill(I18n.t("lobby.share"), _share, OUI.CYAN, 64, 44))
	iv.add_child(ih)
	var bf := HFlowContainer.new()
	bf.add_theme_constant_override("h_separation", OUI.px(4))
	bf.add_theme_constant_override("v_separation", OUI.px(4))
	bf.add_child(OUI.badge(OUI.rule_label(settings), OUI.VIOLET))
	var ranked := bool(room.get("ranked", false))
	bf.add_child(OUI.badge(I18n.t("hub.ranked") if ranked else I18n.t("lobby.friendly"), OUI.GOLD if ranked else OUI.GREEN))
	if OUI.s(room.get("tournament_match_id")) != "":
		bf.add_child(OUI.badge(I18n.t("hub.tournament"), OUI.ORANGE))
	if playing:
		bf.add_child(OUI.badge(I18n.t("lobby.in_game"), OUI.RED, true))
	iv.add_child(bf)
	info.add_child(iv)
	body.add_child(info)
	# ---- teams
	var teams := OUI.hbox(OUI.S_S)
	for t in 2:
		var col := OUI.CYAN if t == 0 else OUI.RED
		var tv := OUI.vbox(OUI.S_S)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var th := PanelContainer.new()
		th.add_theme_stylebox_override("panel", OUI.sb(Color(col, 0.18), 12, Color(col, 0.4), 1))
		th.custom_minimum_size.y = OUI.px(36)
		th.add_child(OUI.lbl(I18n.t("lobby.blue_team") if t == 0 else I18n.t("lobby.red_team"), OUI.TS_BODY, col, "bold", HORIZONTAL_ALIGNMENT_CENTER))
		tv.add_child(th)
		for k in n:
			var p: Variant = seats[t][k]
			if p != null:
				var uid2 := OUI.s(p.get("user_id"))
				tv.add_child(_seat(p, me, OUI.s(room.get("host")), online.has(uid2), speaking.has(uid2), col, is_host and uid2 != me and not playing))
			else:
				var team := t
				var slot := k
				var ep := PanelContainer.new()
				var est := OUI.sb(Color(6 / 255.0, 10 / 255.0, 30 / 255.0, 0.4), 16, OUI.DIM2, 1)
				ep.add_theme_stylebox_override("panel", est)
				ep.custom_minimum_size.y = OUI.px(68)
				if busy == "seat%d%d" % [t, k]:
					var cc := CenterContainer.new()
					cc.add_child(OUI.spinner())
					ep.add_child(cc)
				else:
					var eh := OUI.hbox(OUI.S_XS, BoxContainer.ALIGNMENT_CENTER)
					eh.add_child(OUI.lbl("+", 18, OUI.DIM, "title"))
					eh.add_child(OUI.lbl(I18n.t("lobby.sit"), OUI.TS_CAP, OUI.DIM))
					ep.add_child(eh)
				var tb := OUI.tap(ep, func() -> void: _sit(team, slot))
				tb.disabled = playing or busy != ""
				tv.add_child(tb)
		teams.add_child(tv)
	body.add_child(teams)
	# ---- spectators
	var sp := OUI.panel(null)
	sp.visible = specs.size() > 0   # v3: no empty spectators card
	var sv := OUI.vbox(OUI.S_S)
	var sh := OUI.hbox(OUI.S_S)
	sh.add_child(OUI.flbl(I18n.t("lobby.spectators_x") % OUI.fa(specs.size()), OUI.TS_SMALL, OUI.TEXT, "bold"))
	if am_player and not playing:
		sh.add_child(OUI.pill(I18n.t("lobby.spectate_only"), _watch, OUI.SKY, 44, 36))
	sv.add_child(sh)
	if specs.size() > 0:
		var hs := OUI.hscroll()
		hs.custom_minimum_size.y = OUI.px(64)
		var hh := OUI.hbox(OUI.S_S)
		for p in specs:
			var pv := OUI.vbox(2)
			pv.custom_minimum_size.x = OUI.px(64)
			var pr := OUI.d(p.get("profiles"))
			var uid3 := OUI.s(p.get("user_id"))
			pv.add_child(NetImg.avatar(_disc_of(pr), pr.get("avatar_url"), 40, OUI.GREEN if speaking.has(uid3) else OUI.DIM2, not online.has(uid3)))
			pv.add_child(OUI.lbl(OUI.s(pr.get("username"), "…"), OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
			hh.add_child(pv)
		hs.add_child(hh)
		sv.add_child(hs)
	else:
		sv.add_child(OUI.lbl(I18n.t("lobby.no_one_is_watching"), OUI.TS_CAP, OUI.DIM2))
	sp.add_child(sv)
	body.add_child(sp)
	# ---- voice
	var vp := OUI.panel(null)
	var vv := OUI.vbox(OUI.S_S)
	vv.add_child(OUI.lbl(I18n.t("hub.voice_chat"), OUI.TS_SMALL, OUI.TEXT, "bold"))
	vv.add_child(NetImg.VoiceBar.new(OUI.s(room.get("id")), bool(room.get("voice", true)), false))
	vp.add_child(vv)
	body.add_child(vp)
	# ---- chat preview
	var chat := OUI.a(st.get("chat"))
	var cp := OUI.panel(null)
	var chh := OUI.hbox(OUI.S_S)
	chh.add_child(OUI.img(OUI.ui2("c_bell"), 32))
	var ctv := OUI.vbox(2)
	ctv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctv.add_child(OUI.lbl(I18n.t("lobby.room_chat"), OUI.TS_SMALL, OUI.TEXT, "bold"))
	var last := OUI.d(chat.back()) if chat.size() > 0 else {}
	ctv.add_child(OUI.lbl(("%s: %s" % [OUI.s(last.get("name")), OUI.s(last.get("text"))]) if chat.size() > 0 else I18n.t("lobby.tap_to_type_a_message"), OUI.TS_CAP, OUI.DIM))
	chh.add_child(ctv)
	var unread := OUI.i(st.get("unread"))
	if unread > 0:
		chh.add_child(OUI.unread_dot(unread))
	cp.add_child(chh)
	body.add_child(OUI.tap(cp, _open_chat))
	if is_host and not playing and OUI.s(room.get("tournament_match_id")) == "":
		body.add_child(OUI.btn(I18n.t("lobby.room_settings"), _open_settings, "dark", true))
	# ---- action bar: main action (start / ready / status) + a clear Leave button, always visible
	OUI.clear(bar_slot)
	var act_row := OUI.hbox(OUI.S_S)
	var leave_b := OUI.btn(I18n.t("m3.leave"), _ask_leave, "dark")
	leave_b.custom_minimum_size.x = OUI.px(120)
	leave_b.add_theme_color_override("font_color", OUI.RED)
	if playing:
		bar_slot.add_child(OUI.btn(I18n.t("lobby.join_live_match"), _watch_live, "red"))
	elif kind == "quick" or kind == "arena":
		var np := players.filter(func(p: Variant) -> bool: return OUI.s(p.get("role")) == "player").size()
		bar_slot.add_child(OUI.lbl(I18n.t("lobby.ready_to_start") if full else I18n.t("lobby.searching_for_opponents_x_x") % [OUI.fa(np), OUI.fa(n * 2)], OUI.TS_BODY, OUI.CYAN, "bold", HORIZONTAL_ALIGNMENT_CENTER))
	elif is_host:
		var reason := (I18n.t("lobby.waiting_for_x_player_s") % OUI.fa(not_ready.size())) if not_ready.size() > 0 else (I18n.t("m3.bots_fill") if not full else "")
		if reason != "":
			bar_slot.add_child(OUI.lbl(reason, OUI.TS_CAP, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		var sb := OUI.btn(I18n.t("lobby.starting") if busy == "start" else I18n.t("lobby.start_match"), _start, "gold" if can_start else "dark")
		sb.disabled = not can_start or busy != ""
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act_row.add_child(sb)
	elif am_player:
		var rd := bool(meP.get("ready", false))
		var rb := OUI.btn(I18n.t("lobby.i_m_ready") if rd else I18n.t("lobby.ready_up"), _ready_toggle, "green" if rd else "primary")
		rb.disabled = busy != ""
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act_row.add_child(rb)
	else:
		bar_slot.add_child(OUI.lbl(I18n.t("lobby.tap_an_empty_slot_to"), OUI.TS_SMALL, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	if act_row.get_child_count() == 0:
		act_row.add_child(OUI.expand())
	act_row.add_child(leave_b)
	bar_slot.add_child(act_row)
	# ---- quick / arena: as soon as every seat is filled (players are auto-ready) the host starts after 3-2-1
	var auto := (kind == "quick" or kind == "arena") and OUI.s(room.get("status")) == "waiting" and full and not_ready.is_empty()
	if auto and not counting:
		_count_start()
	elif not auto and counting:
		_count_stop()


static func _disc_of(pr: Dictionary) -> Variant:
	var e := OUI.s(pr.get("equipped_disc"))
	return e if e != "" else pr.get("avatar")


func _seat(p: Dictionary, me: String, host: String, online: bool, talking: bool, color: Color, can_kick: bool) -> Control:
	var uid2 := OUI.s(p.get("user_id"))
	var pr := OUI.d(p.get("profiles"))
	var is_h := uid2 == host
	var pc := PanelContainer.new()
	var border := OUI.GREEN if talking else (color if uid2 == me else OUI.LINE)
	var st := OUI.sb(Color(10 / 255.0, 16 / 255.0, 44 / 255.0, 0.88), 16, border, 1)
	st.content_margin_left = OUI.px(8)
	st.content_margin_right = OUI.px(8)
	st.content_margin_top = OUI.px(6)
	st.content_margin_bottom = OUI.px(6)
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size.y = OUI.px(68)
	var h := OUI.hbox(OUI.S_S)
	var av := NetImg.avatar(_disc_of(pr), pr.get("avatar_url"), 40, OUI.GREEN if talking else color, not online)
	av.dot = OUI.GREEN if online else OUI.DIM2
	h.add_child(av)
	var v := OUI.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(OUI.lbl(("👑 " if is_h else "") + OUI.s(pr.get("username"), "…"), OUI.TS_SMALL, OUI.TEXT, "bold"))
	var rd := bool(p.get("ready", false))
	v.add_child(OUI.lbl(I18n.t("lobby.host") if is_h else (I18n.t("lobby.ready") if rd else I18n.t("lobby.not_ready")), OUI.TS_TINY, OUI.GOLD if is_h else (OUI.GREEN if rd else OUI.DIM2)))
	var ds := OUI.disc_stats(OUI.s(p.get("disc_id")) if OUI.s(p.get("disc_id")) != "" else pr.get("equipped_disc"))
	v.add_child(OUI.stat_bars(ds["power"], ds["accuracy"], true))
	h.add_child(v)
	if can_kick:
		var kb := OUI.pill("✕", func() -> void: _kick(uid2), OUI.RED, 40, 44)
		kb.disabled = busy == "kick" + uid2
		h.add_child(kb)
	pc.add_child(h)
	return pc


# ---------------------------------------------------------------- actions
func _run(key: String, fn: Callable, ok_msg: String = "") -> void:
	if busy != "":
		return
	busy = key
	sig = ""
	_render()
	var r: Dictionary = await fn.call()
	if not is_inside_tree():
		return
	if OUI.ok(r):
		link.ping()
		await link.refresh()
		if ok_msg != "":
			OUI.toast(ok_msg, "ok")
	else:
		OUI.toast_err(OUI.err(r))
		OUI.buzz("heavy")
	busy = ""
	sig = ""
	_render()


func _rid() -> String:
	return OUI.s(_room().get("id"))


func _sit(team: int, slot: int) -> void:
	_run("seat%d%d" % [team, slot], func() -> Dictionary: return await Supa.call_rpc("take_seat", {"p_room": _rid(), "p_team": team, "p_slot": slot}))


func _ready_toggle() -> void:
	var me := _me()
	var cur := false
	for p in OUI.a(_st().get("players")):
		if OUI.s(p.get("user_id")) == me:
			cur = bool(p.get("ready", false))
	_run("ready", func() -> Dictionary:
		var r: Dictionary = await Supa.call_rpc("set_ready", {"p_room": _rid(), "p_ready": not cur})
		if OUI.ok(r):
			OUI.sfx("ready")
			OUI.buzz("medium")
		return r)


func _start() -> void:
	_run("start", func() -> Dictionary:
		var r: Dictionary = await Supa.call_rpc("start_match", {"p_room": _rid()})
		if OUI.ok(r):
			OUI.buzz("heavy")
		return r)


func _kick(u: String) -> void:
	_run("kick" + u, func() -> Dictionary: return await Supa.call_rpc("kick", {"p_room": _rid(), "p_user": u}), I18n.t("lobby.player_kicked"))


func _watch() -> void:
	_run("spec", func() -> Dictionary: return await Supa.call_rpc("spectate", {"p_room": _rid()}))


func _copy() -> void:
	DisplayServer.clipboard_set(OUI.s(_room().get("code")))
	OUI.toast(I18n.t("lobby.room_code_copied"), "ok")
	OUI.buzz("light")


## no native share sheet in Godot core: copy the invite text instead
func _share() -> void:
	DisplayServer.clipboard_set(I18n.t("lobby.let_s_play_nexora_nroom") % OUI.s(_room().get("code")))
	OUI.toast(I18n.t("lobby.invite_text_copied_send_it"))


# ---------------------------------------------------------------- auto start 3-2-1
func _count_start() -> void:
	counting = true
	count = 3
	_show_count()
	count_timer.start()


func _count_stop() -> void:
	counting = false
	count = 0
	count_timer.stop()
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


func _tick() -> void:
	count -= 1
	if count > 0:
		_show_count()
		return
	count_timer.stop()
	counting = false
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	if OUI.s(_room().get("host")) == _me():
		_start()


func _show_count() -> void:
	OUI.sfx("tick")
	OUI.buzz("light")
	if overlay == null or not is_instance_valid(overlay):
		overlay = ColorRect.new()
		(overlay as ColorRect).color = Color(2 / 255.0, 4 / 255.0, 14 / 255.0, 0.7)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var v := OUI.vbox(0)
		var n := OUI.lbl("", 96, Color.WHITE, "title", HORIZONTAL_ALIGNMENT_CENTER)
		n.add_theme_color_override("font_shadow_color", OUI.CYAN)
		n.add_theme_constant_override("shadow_outline_size", OUI.px(8))
		n.name = "N"
		v.add_child(n)
		v.add_child(OUI.lbl(I18n.t("lobby.the_match_is_starting"), OUI.TS_H, OUI.CYAN, "bold", HORIZONTAL_ALIGNMENT_CENTER))
		cc.add_child(v)
		overlay.add_child(cc)
		add_child(overlay)
		OUI.fade_in(overlay, 0.15)
	var nl := overlay.find_child("N", true, false) as Label
	if nl:
		nl.text = OUI.fa(count)
		nl.pivot_offset = nl.size * 0.5
		nl.scale = Vector2(1.5, 1.5)
		nl.create_tween().tween_property(nl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- leave confirm
func _ask_leave() -> void:
	if confirm and is_instance_valid(confirm):
		return
	var v := OUI.vbox(OUI.S_S)
	v.add_child(OUI.lbl(I18n.t("lobby.leave_the_room"), 20, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(OUI.lbl(I18n.t("lobby.your_slot_will_be_freed"), OUI.TS_SMALL, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, true, 3))
	v.add_child(OUI.spacer(OUI.S_S))
	v.add_child(OUI.btn(I18n.t("nav.stay"), _close_confirm, "primary"))
	v.add_child(OUI.btn(I18n.t("nav.quit"), func() -> void:
		_close_confirm()
		Voice.leave()
		OUI.leave_room(true), "red", true))
	confirm = OUI.modal(self, v, OUI.RED, _close_confirm)


func _close_confirm() -> void:
	if confirm and is_instance_valid(confirm):
		confirm.queue_free()
	confirm = null


# ---------------------------------------------------------------- sheets
func _open_chat() -> void:
	var cpn := NetImg.ChatPanel.new(link, false)
	OUI.open_sheet(I18n.t("lobby.chat"), "ROOM CHAT", cpn, OUI.CYAN, 0.72)


func _open_settings() -> void:
	var room := _room()
	var settings := OUI.d(room.get("settings"))
	var st := {"rule": OUI.settings_to_rule(settings), "turn": OUI.i(settings.get("turn"), 15) if settings.get("turn") != null else 15, "field": OUI.i(settings.get("field")), "mode": OUI.s(room.get("mode"), "1v1")}
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_XS)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL))
	var nf := OUI.field(I18n.t("hub.room_name"), "", 40)
	(nf.get_meta("input") as LineEdit).text = OUI.s(room.get("name"))
	v.add_child(nf)
	v.add_child(OUI.cap_label(I18n.t("hub.mode")))
	var mi: Array = []
	for m in OUI.MODES:
		mi.append([m, OUI.MODE_FA[m]])
	v.add_child(OUI.segment(mi, st["mode"], func(x: Variant) -> void: st["mode"] = str(x), OUI.SKY))
	v.add_child(OUI.cap_label(I18n.t("lobby.match_rule")))
	v.add_child(OUI.segment(OUI.RULES, st["rule"], func(x: Variant) -> void: st["rule"] = x, OUI.VIOLET))
	v.add_child(OUI.cap_label(I18n.t("hub.turn_time")))
	v.add_child(OUI.segment(OUI.TURNS, st["turn"], func(x: Variant) -> void: st["turn"] = x, OUI.GREEN))
	v.add_child(OUI.cap_label(I18n.t("hub.field")))
	v.add_child(preload("res://src/online/hub.gd").field_picker(st["field"], func(i: int) -> void: st["field"] = i))
	v.add_child(OUI.spacer(OUI.S_L))
	var save := OUI.btn(I18n.t("lobby.save"), Callable(), "primary")
	save.pressed.connect(func() -> void:
		save.disabled = true
		save.text = I18n.t("lobby.saving")
		var ns := settings.duplicate()
		ns.merge(OUI.rule_to_settings(str(st["rule"])), true)
		ns["turn"] = st["turn"]
		ns["field"] = st["field"]
		var r: Dictionary = await Supa.call_rpc("update_room", {"p_room": _rid(), "p_settings": ns, "p_name": OUI.field_value(nf).strip_edges().substr(0, 40), "p_mode": st["mode"]})
		if OUI.ok(r):
			link.ping()
			await link.refresh()
			OUI.toast(I18n.t("lobby.settings_saved"), "ok")
			Nav.close_sheet()
		else:
			OUI.toast_err(OUI.err(r))
			if is_instance_valid(save):
				save.disabled = false
				save.text = I18n.t("lobby.save"))
	v.add_child(save)
	OUI.open_sheet(I18n.t("lobby.room_settings"), "ROOM SETTINGS", sc, OUI.CYAN, 0.8)
