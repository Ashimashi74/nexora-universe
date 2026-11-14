extends Control
## Online result: score, XP / coins / rating actually granted by the backend (profile diff), level-up,
## oracle line (port of RN OnlineResult.tsx).
## params: {o: OnlineOutcome, before: profile dict}
##   OnlineOutcome = {match_id, score:[a,b], winner:-1|0|1, rating_delta:int|null, my_team:0|1|null,
##                    teams:[teamIdOrDict, teamIdOrDict], names:[a,b], reported:bool, ranked:bool}
##   (camelCase keys matchId/ratingDelta/myTeam from a 1:1 TS port are accepted too)
## Tables: profiles (refresh own row).

var o: Dictionary = {}
var before: Dictionary = {}
var after: Dictionary = {}
var out := "draw"
var mine: Variant = null
var body: VBoxContainer
var rewards_slot: VBoxContainer
var ring: TextureRect


func setup(p: Dictionary) -> void:
	o = OUI.d(p.get("o", p.get("outcome", {})))
	before = OUI.d(p.get("before", OUI.before_profile))
	var mid := OUI.s(o.get("match_id", o.get("matchId", "")))
	if mid != "":
		OUI.skip_match = mid
	var pl: Variant = p.get("link")
	if pl != null and is_instance_valid(pl) and not bool(pl.get("dead")) and OUI.link != pl:
		OUI.link = pl


func _g(snake: String, camel: String, def: Variant = null) -> Variant:
	if o.has(snake):
		return o[snake]
	if o.has(camel):
		return o[camel]
	return def


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = I18n.LD
	mine = _g("my_team", "myTeam", null)
	var winner := OUI.i(o.get("winner"), -1)
	if mine == null:
		out = "draw"
	elif winner == -1:
		out = "draw"
	elif winner == OUI.i(mine):
		out = "victory"
	else:
		out = "defeat"
	var col := OUI.GOLD if out == "victory" else (OUI.RED if out == "defeat" else OUI.CYAN)
	var sc := OUI.scroll()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	body = OUI.vbox(OUI.S_S)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(OUI.margin(body, OUI.S_L, OUI.S_S + OUI.top_inset() / OUI.K, OUI.S_L, OUI.S_XL))
	# banner with rotating ring
	var bw := minf(get_viewport_rect().size.x * 0.9, OUI.px(380))
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(bw, bw * 0.62)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring = TextureRect.new()
	ring.texture = OUI.ui2("ring")
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.size = Vector2(bw * 0.9, bw * 0.9)
	ring.position = Vector2(bw * 0.05, bw * 0.31 - bw * 0.45)
	ring.pivot_offset = ring.size * 0.5
	ring.modulate = Color(col, 0.5)
	stage.add_child(ring)
	var ban := TextureRect.new()
	ban.texture = OUI.ui(out)
	ban.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ban.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ban.size = Vector2(bw, bw * 0.6)
	ban.position = Vector2(0, bw * 0.01)
	ban.pivot_offset = ban.size * 0.5
	ban.scale = Vector2(0.4, 0.4)
	ban.modulate.a = 0.0
	stage.add_child(ban)
	body.add_child(stage)
	var tw := ban.create_tween().set_parallel()
	tw.tween_property(ban, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ban, "modulate:a", 1.0, 0.35)
	# score panel
	var sp := OUI.panel(col, OUI.S_M, true)
	var sh := OUI.hbox(OUI.S_S)
	sh.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var teams: Array = OUI.a(o.get("teams"))
	var names: Array = OUI.a(o.get("names"))
	var score: Array = OUI.a(o.get("score"))
	sh.add_child(_side(teams[0] if teams.size() > 0 else null, OUI.s(names[0] if names.size() > 0 else ""), OUI.CYAN))
	var mid := OUI.vbox(0)
	var sl := OUI.lbl("%s : %s" % [OUI.i(score[0] if score.size() > 0 else 0), OUI.i(score[1] if score.size() > 1 else 0)], 38, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER)
	sl.add_theme_color_override("font_shadow_color", Color(col, 0.8))
	sl.add_theme_constant_override("shadow_outline_size", OUI.px(6))
	mid.add_child(sl)
	mid.add_child(OUI.lbl("RANKED" if bool(o.get("ranked", false)) else "FRIENDLY", 9, OUI.DIM, "head", HORIZONTAL_ALIGNMENT_CENTER))
	sh.add_child(mid)
	sh.add_child(_side(teams[1] if teams.size() > 1 else null, OUI.s(names[1] if names.size() > 1 else ""), OUI.RED))
	sp.add_child(sh)
	body.add_child(sp)
	rewards_slot = OUI.vbox(OUI.S_S)
	body.add_child(rewards_slot)
	var reported := bool(o.get("reported", false))
	if mine == null:
		rewards_slot.add_child(OUI.lbl(I18n.t("online_result.you_were_a_spectator_in"), OUI.TS_SMALL, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	elif not reported:
		var wp := OUI.panel(OUI.ORANGE)
		wp.add_child(OUI.lbl(I18n.t("online_result.the_result_wasn_t_saved"), OUI.TS_SMALL, OUI.ORANGE, "body", HORIZONTAL_ALIGNMENT_CENTER, true, 2))
		rewards_slot.add_child(wp)
	else:
		var wv := OUI.vbox(OUI.S_S)
		wv.custom_minimum_size.y = OUI.px(120)
		wv.alignment = BoxContainer.ALIGNMENT_CENTER
		var spn := OUI.spinner()
		spn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wv.add_child(spn)
		wv.add_child(OUI.lbl(I18n.t("online_result.collecting_rewards"), OUI.TS_CAP, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		rewards_slot.add_child(wv)
		_load_after(0)
	if mine != null:
		if out == "victory":
			OUI.sfx("win")
			OUI.buzz("success")
		elif out == "defeat":
			OUI.sfx("lose")
		var line := OracleCoach.result_line(out)
		var oh := OUI.hbox(OUI.S_S)
		var spr := OUI.img(OUI.oracle_tex(str(line["mood"])), 84, 92)
		oh.add_child(spr)
		var bub := PanelContainer.new()
		var bst := OUI.sb(Color(14 / 255.0, 24 / 255.0, 64 / 255.0, 0.92), 16, Color(92 / 255.0, 225 / 255.0, 1, 0.4), 1, OUI.S_M)
		bst.corner_radius_bottom_right = OUI.px(4)
		bub.add_theme_stylebox_override("panel", bst)
		bub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bub.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		bub.add_child(OUI.lbl(str(line["text"]), OUI.TS_SMALL, OUI.TEXT, "body", I18n.AR, true, 0))
		oh.add_child(bub)
		body.add_child(OUI.margin(oh, 0, OUI.S_M, 0, 0))
		var ftw := spr.create_tween().set_loops()
		ftw.tween_property(spr, "position:y", -OUI.px(4), 1.1).set_trans(Tween.TRANS_SINE).as_relative()
		ftw.tween_property(spr, "position:y", OUI.px(4), 1.1).set_trans(Tween.TRANS_SINE).as_relative()
	body.add_child(OUI.spacer(OUI.S_M))
	body.add_child(OUI.btn(I18n.t("online_result.back_to_lobby"), _to_lobby, "gold" if out == "victory" else "primary"))
	body.add_child(OUI.btn(I18n.t("online_result.leave_room"), func() -> void: OUI.leave_room(true), "dark", true))


func _process(dt: float) -> void:
	if is_instance_valid(ring):
		ring.rotation += dt * TAU / 20.0


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	_to_lobby()
	return true


func _to_lobby() -> void:
	if OUI.link != null:
		OUI.link.refresh()
		Nav.go("lobby", {"room_id": OUI.s(OUI.link.id), "link": OUI.link, "skip_match": OUI.skip_match})
	else:
		Nav.go("hub", {})


func _side(team: Variant, name: String, c: Color) -> Control:
	var v := OUI.vbox(OUI.S_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var key: Variant = team
	if team is Dictionary:
		key = team.get("id", "%s%d" % [OUI.s(team.get("cat"), "club"), OUI.i(team.get("idx"))])
	elif team is Object and team != null and "id" in team:
		key = team.get("id")
	var av := NetImg.avatar(key, null, 54, c)
	v.add_child(av)
	v.add_child(OUI.lbl(name, OUI.TS_SMALL, OUI.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER))
	return v


## the backend has granted rewards by now; poll the profile a couple of times in case realtime is late
func _load_after(n: int) -> void:
	var p: Dictionary = await OUI.refresh_profile()
	if not is_inside_tree():
		return
	if not p.is_empty() and (before.is_empty() or OUI.i(p.get("xp")) != OUI.i(before.get("xp")) or n >= 2):
		after = p
		_show_rewards()
	elif n < 2:
		await get_tree().create_timer(1.2).timeout
		if is_inside_tree():
			_load_after(n + 1)
	else:
		after = p
		_show_rewards()


func _show_rewards() -> void:
	OUI.clear(rewards_slot)
	if after.is_empty():
		return
	var has_b := not before.is_empty()
	var d_xp := OUI.i(after.get("xp")) - OUI.i(before.get("xp")) if has_b else 0
	var d_coins := OUI.i(after.get("coins")) - OUI.i(before.get("coins")) if has_b else 0
	var rd: Variant = _g("rating_delta", "ratingDelta", 0)
	var d_rating := OUI.i(after.get("rating")) - OUI.i(before.get("rating")) if has_b else OUI.i(rd)
	var d_arena := OUI.i(after.get("arena_points")) - OUI.i(before.get("arena_points")) if has_b else 0
	var lv_up := OUI.i(after.get("level")) if has_b and OUI.i(after.get("level")) > OUI.i(before.get("level")) else 0
	var rh := OUI.hbox(0)
	rh.add_child(_rw(OUI.ui2("x_star"), d_xp, OUI.CYAN, 0.15, "XP"))
	rh.add_child(_rw(OUI.ui2("c_coin"), d_coins, OUI.GOLD, 0.3, ""))
	rh.add_child(_rw(OUI.ui2("x_trophy"), d_rating, OUI.GREEN if d_rating >= 0 else OUI.RED, 0.45, I18n.t("online_result.rating")))
	if d_arena != 0:
		rh.add_child(_rw(OUI.ui2("x_crown"), d_arena, OUI.VIOLET, 0.6, I18n.t("arena.arena")))
	rewards_slot.add_child(rh)
	var lp := OUI.level_progress(OUI.i(after.get("xp")))
	var lpn := OUI.panel(null)
	var lv := OUI.vbox(OUI.S_S)
	var lh := OUI.hbox(OUI.S_S)
	lh.add_child(OUI.flbl(I18n.t("hub.level_x") % OUI.fa(lp["level"]), OUI.TS_BODY, OUI.TEXT, "bold"))
	lh.add_child(OUI.lbl("%s / %s XP" % [OUI.fa(lp["cur"]), OUI.fa(lp["need"])], OUI.TS_CAP, OUI.DIM))
	lv.add_child(lh)
	lv.add_child(OUI.bar(lp["frac"], OUI.CYAN, OUI.VIOLET, 8))
	lpn.add_child(lv)
	rewards_slot.add_child(lpn)
	if lv_up > 0:
		var up := OUI.panel(OUI.VIOLET, OUI.S_M, true)
		var uh := OUI.hbox(OUI.S_M)
		uh.add_child(OUI.img(OUI.ui2("x_crown"), 48))
		var uv := OUI.vbox(0)
		uv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uv.add_child(OUI.lbl(I18n.t("online_result.level_x") % OUI.fa(lv_up), 18, Color("#d6b8ff"), "title"))
		uv.add_child(OUI.lbl(I18n.t("online_result.you_reached_a_new_level"), OUI.TS_CAP, OUI.DIM))
		uh.add_child(uv)
		up.add_child(uh)
		rewards_slot.add_child(up)
		OracleCoach.react("levelup", OUI.fa(lv_up))
	OUI.fade_in(rewards_slot)


func _rw(t: Texture2D, v: int, c: Color, delay: float, label: String) -> Control:
	var wrap := OUI.margin(null, OUI.S_XS, OUI.S_XS, OUI.S_XS, OUI.S_XS)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p := OUI.panel(c, OUI.S_S)
	var vb := OUI.vbox(2)
	var im := OUI.img(t, 36)
	im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(im)
	var nl := OUI.lbl(I18n.t("online_result.0"), 15, c, "title", HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(nl)
	if label != "":
		vb.add_child(OUI.lbl(label, OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	p.add_child(vb)
	wrap.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_method(func(x: float) -> void:
		if is_instance_valid(nl):
			var n := int(round(x))
			nl.text = ("+" if n >= 0 else "") + OUI.fa(n), 0.0, float(v), 0.6)
	return wrap
