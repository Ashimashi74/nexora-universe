extends NxScreen
## Team (RN Team.tsx): segmented [دیسک | توپ | زمین | ترکیب].
## Discs: hero with spinning rings + rarity + stat bars + buy/equip, 10 category chips, 4-col grid.
## Balls: spinning/bobbing ball hero, trail colours, buy/equip, grid. Fields: arena preview + grid.
## Formation: mini pitch with spring-in slots + 6 formation tiles.

var sub := 0          # 0 disc, 1 ball, 2 field, 3 form
var seg: NxSegment
var cat := ""
var focus := ""
var fball := -1
var ffield := -1
var busy := false
var _anim_hero := true

func build() -> void:
	var p := UD.p()
	focus = str(p.get("team", "club0"))
	cat = str(UD.team_by_id(focus)["cat"])
	fball = int(p.get("ball", 0))
	ffield = int(p.get("field", 0))
	if params.has("sub"):
		sub = int(params["sub"])
	make_scroll(20)
	_fill()
	end_body()
	# segment pinned under the HUD
	seg = Kit.tabs([I18n.t("home.disc"), I18n.t("home.ball"), I18n.t("hub.field"), I18n.t("kb.formation")], _on_sub, sub)
	var bar := Kit.margin(seg, NX.PAD, 0, NX.PAD, 0)
	bar.position = Vector2(0, Nav.insets()["top"] - 6)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = Nav.insets()["top"] - 6
	bar.offset_bottom = bar.offset_top + 114
	add_child(bar)
	var sd := UD.discs()
	if sd and sd.has_signal("changed"):
		sd.connect("changed", func(): if is_inside_tree(): on_store_changed())

func on_store_changed() -> void:
	_anim_hero = false
	rebuild(_fill)

func _on_sub(i: int) -> void:
	sub = i
	_anim_hero = true
	rebuild(_fill)
	scroll.scroll_vertical = 0

func _fill() -> void:
	body.add_child(Kit.gap(130))
	match sub:
		0: _discs()
		1: _balls()
		2: _fields()
		3: _formation()

# ------------------------------------------------------------------ discs
func _discs() -> void:
	var ft := UD.team_by_id(focus)
	var rr := UD.rarity_info(UD.rarity(ft))
	var rc: Color = rr["c"]
	var owned := UD.disc_owned(ft["id"])
	var price := UD.disc_price(ft["id"])
	var ds := UD.disc_stats(ft["id"])
	body.add_child(_disc_hero(ft, rc))
	var tg := Kit.tag(rr["n"], Color(rc.r, rc.g, rc.b, 0.12), NX.hdr(rc, 1.3), 23)
	var tsb := tg.get_theme_stylebox("panel") as StyleBoxFlat
	tsb.set_border_width_all(3)
	tsb.border_color = Color(rc.r, rc.g, rc.b, 0.55)
	body.add_child(Kit.center(tg))
	var nm := Kit.title(str(ft["name"]).to_upper(), 52)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(nm)
	var pn := Kit.glass(rc, false)
	var v := Kit.vbox(16)
	v.add_child(Kit.stat_bars(int(ds["power"]), int(ds["accuracy"])))
	v.add_child(Kit.para(I18n.t("team.power_max_shot_speed_accuracy"), 26, NX.DIM))
	var p := UD.p()
	var op := UD.online_profile()
	var b: NxButton
	if str(p.get("team", "")) == ft["id"]:
		b = Kit.button_small(I18n.t("team.selected"), Callable(), "dark")
		b.set_disabled(true)
	elif owned:
		b = Kit.button_small(I18n.t("team.select_this_disc"), _disc_act, "primary")
	else:
		var sub_l := I18n.t("team.balance_x_gems") % NX.fa(int(op.get("gems", 0))) if not op.is_empty() else ""
		b = Kit.button_ex("…" if busy else I18n.t("team.buy_x_gems") % NX.fa(price), _disc_act, "violet", true, null, sub_l)
		b.set_disabled(busy)
	v.add_child(b)
	pn.add_child(v)
	body.add_child(padx(pn))
	# category chips
	var hs := Kit.hscroll(16)
	var row: HBoxContainer = hs[1]
	row.add_child(Kit.gap(0, 20))
	for k in UD.CAT_ORDER:
		if UD.teams_of(k).is_empty():
			continue
		var acc := NX.GOLD if k in ["leg", "vip"] else (NX.VIOLET if k in ["emb", "chrome"] else NX.CYAN)
		var ch := Kit.chip(UD.CAT_FA.get(k, k), acc, cat == k)
		var kk: String = k
		Kit.tap(ch, func():
			cat = kk
			_anim_hero = false
			rebuild(_fill), 0.92)
		row.add_child(ch)
	row.add_child(Kit.gap(0, 20))
	(hs[0] as ScrollContainer).custom_minimum_size.y = 110
	body.add_child(hs[0])
	# grid
	var grid := _grid(4)
	var cell := (1080.0 - NX.PAD * 2 - 3 * 20) / 4.0
	var eq := str(p.get("team", ""))
	for t in UD.teams_of(cat):
		grid.add_child(_disc_cell(t, cell, t["id"] == focus, UD.disc_owned(t["id"]), t["id"] == eq))
	body.add_child(padx(grid))

func _disc_hero(t: Dictionary, color: Color) -> Control:
	var st := Kit.stage(1080, 600)
	var pad := Kit.img(UD.ui("holopad"), Vector2(624, 224))
	Kit.put(st, pad, 540, 600 - 112)
	var pul := Kit.pulse(390, Color(color.r, color.g, color.b, 0.45))
	Kit.put(st, pul, 540, 300)
	var ring := Kit.img(UD.ui2("ring"), 572)
	ring.modulate.a = 0.75
	Kit.put(st, ring, 540, 300)
	Kit.spin(ring, 12.0)
	var dash := _DashRing.new()
	dash.color = Color(color.r, color.g, color.b, 0.55)
	dash.custom_minimum_size = Vector2(478, 478)
	Kit.put(st, dash, 540, 300)
	Kit.spin(dash, 6.0, -1.0)
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(384, 384)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", NX.box(Color("#050816"), 192, 10, NX.hdr(color, 1.3), 46, Color(color.r, color.g, color.b, 0.75)))
	var im := Kit.img(UD.team_tex(t), 344)
	im.position = Vector2(20, 20)
	disc.add_child(im)
	var gl := NxGrad.new([Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)], 192, 1.0, 0.0)
	gl.position = Vector2(10, 10)
	gl.size = Vector2(364, 364)
	disc.add_child(gl)
	Kit.put(st, disc, 540, 300)
	if _anim_hero:
		disc.scale = Vector2(0.75, 0.75)
		var tw := disc.create_tween()
		tw.tween_property(disc, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return st

func _disc_cell(t: Dictionary, cell: float, sel: bool, own: bool, eq: bool) -> Control:
	var rc: Color = UD.rarity_info(UD.rarity(t))["c"]
	var c := PanelContainer.new()
	var sb := NX.box(Color(rc.r, rc.g, rc.b, 0.13) if sel else Color(0.03, 0.047, 0.133, 0.78), 42, 3, NX.hdr(rc, 1.2) if sel else Color(0.43, 0.67, 1.0, 0.16))
	sb.content_margin_top = 10; sb.content_margin_bottom = 8
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size = Vector2(cell, cell + 52)
	var v := Kit.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var im := Kit.img(UD.team_tex(t), cell - 42)
	im.modulate.a = 1.0 if own else 0.5
	v.add_child(Kit.center(im))
	if eq:
		var l := Kit.label(I18n.t("team.active"), 23, NX.hdr(NX.GREEN, 1.2))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	elif own:
		v.add_child(Kit.gap(30))
	else:
		var h := Kit.hbox(4)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(Kit.img(UD.ui2("x_gem"), 31))
		h.add_child(Kit.title(str(UD.disc_price(t["id"])), 21, Color("#9fd8ff"), "head"))
		v.add_child(h)
	c.add_child(v)
	if not own:
		var lk := Kit.label("🔒", 23)
		lk.position = Vector2(cell - 44, 6)
		c.add_child(lk)
		lk.top_level = false
	var id: String = t["id"]
	Kit.tap(c, func():
		focus = id
		_anim_hero = true
		rebuild(_fill)
		scroll.create_tween().tween_property(scroll, "scroll_vertical", 0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT), 0.92)
	return c

func _disc_act() -> void:
	if busy:
		return
	var ft := UD.team_by_id(focus)
	if UD.disc_owned(ft["id"]):
		UD.set_p({"team": ft["id"]})
		UD.haptic("success")
		toast(I18n.t("team.x_selected") % ft["name"], "ok")
		var dz := UD.discs()
		if UD.signed_in() and dz and dz.has_method("equip"):
			var r = await dz.equip(ft["id"])
			if r is Dictionary and not r.get("ok", true):
				toast(str(r.get("error", "")), "err")
		return
	busy = true
	rebuild(_fill)
	await UD.buy_and_equip_disc(ft["id"], ft["name"])
	busy = false
	if is_inside_tree():
		rebuild(_fill)

# ------------------------------------------------------------------ balls
func _balls() -> void:
	var p := UD.p()
	var owned_l: Array = p.get("ownedBalls", [])
	var owned := UD._has_num(owned_l, fball)
	var price := UD.ball_price(fball)
	var eq := int(p.get("ball", 0)) == fball
	var st := Kit.stage(1080, 572)
	var pad := Kit.img(UD.ui("holopad"), Vector2(598, 218))
	Kit.put(st, pad, 540, 572 - 125)
	var shadow := Panel.new()
	shadow.custom_minimum_size = Vector2(286, 47)
	shadow.add_theme_stylebox_override("panel", NX.box(Color(0, 0, 0, 0.55), 143))
	Kit.put(st, shadow, 540, 572 - 128)
	var pul := Kit.pulse(338, Color(0.24, 1.0, 0.85, 0.35))
	Kit.put(st, pul, 540, 270)
	var ball := Kit.img(UD.ball_tex(fball), 344)
	Kit.put(st, ball, 540, 270)
	Kit.spin(ball, 5.0)
	Kit.bob(ball, 36, 1.4)
	var sh := shadow.create_tween().set_loops()
	sh.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sh.tween_property(shadow, "scale", Vector2(0.75, 1), 1.4)
	sh.parallel().tween_property(shadow, "modulate:a", 0.6, 1.4)
	sh.tween_property(shadow, "scale", Vector2(1, 1), 1.4)
	sh.parallel().tween_property(shadow, "modulate:a", 1.0, 1.4)
	body.add_child(st)
	var nm := Kit.title(UD.ball_name(fball).to_upper(), 52)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(nm)
	var tr := Kit.hbox(16)
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in UD.trail(fball):
		var r := Panel.new()
		r.custom_minimum_size = Vector2(73, 16)
		var col := Color(str(c))
		r.add_theme_stylebox_override("panel", NX.box(NX.hdr(col, 1.6), 8, 0, Color.TRANSPARENT, 12, Color(col, 0.8)))
		tr.add_child(r)
	body.add_child(tr)
	var cap := Kit.label(I18n.t("team.ball_trail_colour"), 26, NX.DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(cap)
	body.add_child(Kit.margin(_buy_btn(eq, owned, price, _ball_act), 130, 10, 130, 16))
	var grid := _grid(4)
	var cell := (1080.0 - NX.PAD * 2 - 3 * 20) / 4.0
	for i in 36:
		var own := UD._has_num(owned_l, i)
		var sel := i == fball
		var e := int(p.get("ball", 0)) == i
		var c := _cell(UD.ball_tex(i), cell, cell - 58, sel, NX.GREEN, own, I18n.t("team.active") if e else (UD.ball_name(i) if own else "%d ◉" % UD.ball_price(i)), NX.GREEN if e else (NX.DIM if own else NX.GOLD), false)
		var ii := i
		Kit.tap(c, func():
			fball = ii
			_anim_hero = true
			rebuild(_fill), 0.92)
		grid.add_child(c)
	body.add_child(padx(grid))

func _ball_act() -> void:
	var p := UD.p()
	var owned := UD._has_num(p.get("ownedBalls", []), fball)
	if owned:
		UD.set_p({"ball": fball})
		UD.haptic("success")
		toast(I18n.t("team.ball_selected"), "ok")
		return
	var price := UD.ball_price(fball)
	if int(p.get("coins", 0)) < price:
		toast(I18n.t("shop.not_enough_coins"), "err")
		return
	var ob: Array = (p.get("ownedBalls", []) as Array).duplicate()
	ob.append(fball)
	UD.set_p({"coins": int(p["coins"]) - price, "ownedBalls": ob, "ball": fball})
	UD.sfx("ui")
	UD.haptic("success")
	toast(I18n.t("team.new_ball_unlocked"), "ok")

# ------------------------------------------------------------------ fields
func _fields() -> void:
	var p := UD.p()
	var owned_l: Array = p.get("ownedFields", [])
	var owned := UD._has_num(owned_l, ffield)
	var price := UD.field_price(ffield)
	var eq := int(p.get("field", 0)) == ffield
	var arena := PanelContainer.new()
	var asb := NX.box(Color("#050816"), 47, 5, NX.hdr(NX.CYAN, 1.3), 50, Color(0.22, 0.84, 1.0, 0.55))
	asb.content_margin_left = 8; asb.content_margin_right = 8; asb.content_margin_top = 8; asb.content_margin_bottom = 8
	arena.add_theme_stylebox_override("panel", asb)
	arena.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var th := Kit.img(UD.field_thumb(ffield), Vector2(416, 556), "cover")
	arena.add_child(th)
	var gl := NxGrad.new([Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.0), Color(0, 0, 0, 0.3)], 40, 1.57, 0.0)
	arena.add_child(gl)
	body.add_child(Kit.center(arena))
	if _anim_hero:
		arena.ready.connect(func():
			arena.pivot_offset = arena.size * 0.5
			arena.scale = Vector2(0.9, 0.9)
			arena.create_tween().tween_property(arena, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	var nm := Kit.title(str(UD.field(ffield)["name"]).to_upper(), 52)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(nm)
	body.add_child(Kit.margin(_buy_btn(eq, owned, price, _field_act), 130, 10, 130, 16))
	var grid := _grid(3)
	var cell := (1080.0 - NX.PAD * 2 - 2 * 20) / 3.0
	for i in UD.fields().size():
		var own := UD._has_num(owned_l, i)
		var e := int(p.get("field", 0)) == i
		var c := _cell(UD.field_thumb(i), cell, cell - 42, i == ffield, NX.CYAN, own, I18n.t("team.active") if e else (str(UD.field(i)["name"]) if own else "%d ◉" % UD.field_price(i)), NX.GREEN if e else (NX.DIM if own else NX.GOLD), true)
		var ii := i
		Kit.tap(c, func():
			ffield = ii
			_anim_hero = true
			rebuild(_fill), 0.94)
		grid.add_child(c)
	body.add_child(padx(grid))

func _field_act() -> void:
	var p := UD.p()
	if UD._has_num(p.get("ownedFields", []), ffield):
		UD.set_p({"field": ffield})
		UD.haptic("success")
		toast(I18n.t("team.field_selected"), "ok")
		return
	var price := UD.field_price(ffield)
	if int(p.get("coins", 0)) < price:
		toast(I18n.t("shop.not_enough_coins"), "err")
		return
	var of: Array = (p.get("ownedFields", []) as Array).duplicate()
	of.append(ffield)
	UD.set_p({"coins": int(p["coins"]) - price, "ownedFields": of, "field": ffield})
	UD.sfx("ui")
	UD.haptic("success")
	toast(I18n.t("team.new_field_unlocked"), "ok")

# ------------------------------------------------------------------ formation
func _formation() -> void:
	var p := UD.p()
	var me := UD.team_by_id(str(p.get("team", "club0")))
	var fo := int(p.get("form", 0))
	var fw := minf(1080.0 - 166, 780)
	var fh := fw * 1.35
	var pitch := Control.new()
	pitch.custom_minimum_size = Vector2(fw, fh)
	pitch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pitch.clip_contents = true
	var bg := Kit.img(UD.field_thumb(int(p.get("field", 0))), Vector2(fw, fh), "cover")
	pitch.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.008, 0.024, 0.078, 0.35)
	shade.size = Vector2(fw, fh)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pitch.add_child(shade)
	var lines := _PitchLines.new()
	lines.size = Vector2(fw, fh)
	pitch.add_child(lines)
	var pts := UD.slots(fo)
	var i := 0
	for pt in pts:
		var x := 47.0 + float(pt[0]) * (fw - 94)
		var y := fh - float(pt[1]) * fh * 1.9
		var s := Panel.new()
		s.custom_minimum_size = Vector2(104, 104)
		s.add_theme_stylebox_override("panel", NX.box(Color("#050816"), 52, 5, NX.hdr(NX.CYAN, 1.4), 16, Color(0.22, 0.84, 1.0, 0.8)))
		var im := Kit.img(UD.team_tex(me), 88)
		im.position = Vector2(8, 8)
		s.add_child(im)
		Kit.put(pitch, s, x, y)
		s.scale = Vector2.ZERO
		var tw := s.create_tween()
		tw.tween_interval(i * 0.05)
		tw.tween_property(s, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		i += 1
	var frame := PanelContainer.new()
	var fsb := NX.box(Color(0, 0, 0, 0), 52, 5, Color(0.31, 0.89, 1.0, 0.55))
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(pitch)
	body.add_child(Kit.center(frame))
	var fm: Array = UD.forms()[fo]
	var t := Kit.title("%s · %s" % [fm[0], fm[1]], 47)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(t)
	var grid := _grid(3)
	var j := 0
	for f in UD.forms():
		var on := j == fo
		var c := PanelContainer.new()
		var sb := NX.box(Color(0.31, 0.89, 1.0, 0.15) if on else Color(0.03, 0.047, 0.133, 0.8), 42, 3, NX.hdr(NX.CYAN, 1.2) if on else NX.LINE)
		sb.content_margin_top = 24; sb.content_margin_bottom = 24
		c.add_theme_stylebox_override("panel", sb)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := Kit.vbox(2)
		var a := Kit.title(f[0], 36, Color.WHITE if on else NX.DIM, "head")
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		var b := Kit.label(f[1], 26, NX.DIM2)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(b)
		c.add_child(v)
		var jj := j
		Kit.tap(c, func(): UD.set_p({"form": jj}), 0.94)
		grid.add_child(c)
		j += 1
	body.add_child(padx(grid))

# ------------------------------------------------------------------ helpers
func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.layout_direction = I18n.LD
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 20)
	return g

func _cell(tex: Texture2D, cell: float, art: float, sel: bool, acc: Color, own: bool, caption: String, cap_col: Color, tall: bool) -> Control:
	var c := PanelContainer.new()
	var sb := NX.box(Color(acc.r, acc.g, acc.b, 0.12) if sel else Color(0.03, 0.047, 0.133, 0.78), 42, 3, NX.hdr(acc, 1.2) if sel else Color(0.43, 0.67, 1.0, 0.16))
	sb.content_margin_top = 16; sb.content_margin_bottom = 12; sb.content_margin_left = 8; sb.content_margin_right = 8
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size.x = cell
	var v := Kit.vbox(8)
	var im := Kit.img(tex, Vector2(art, art * 1.33) if tall else Vector2(art, art), "cover" if tall else "contain")
	im.modulate.a = 1.0 if own else 0.5
	v.add_child(Kit.center(im))
	var l := Kit.label(caption, 25, cap_col)
	if not NX.is_fa(caption):
		l.add_theme_font_override("font", NX.font("bold"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = cell - 24
	v.add_child(l)
	c.add_child(v)
	return c

func _buy_btn(eq: bool, owned: bool, price: int, cb: Callable) -> NxButton:
	if eq:
		var b := Kit.button_small(I18n.t("team.selected"), Callable(), "dark")
		b.set_disabled(true)
		return b
	if owned:
		return Kit.button_small(I18n.t("team.select"), cb, "green")
	return Kit.button_small(I18n.t("team.buy_x") % price, cb, "gold", UD.ui2("c_coin"))


class _DashRing extends Control:
	var color := Color.WHITE
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5 - 3
		var n := 36
		for i in n:
			var a0 := TAU * i / n
			draw_arc(c, r, a0, a0 + TAU / n * 0.55, 4, NX.hdr(color, 1.3), 5.0, true)


class _PitchLines extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := Color(1, 1, 1, 0.35)
		draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), c, 3.0, true)
		draw_arc(size * 0.5, 78, 0, TAU, 48, c, 3.0, true)
