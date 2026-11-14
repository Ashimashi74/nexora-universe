extends NxScreen
## Play (RN Play.tsx): online entry card with tilt + shine and quick links, 3D swipe carousel of
## offline modes (perspective-ish scale/fade/parallax, spring snap, velocity fling), dots,
## "enter mode" button, league road.

var carousel: _Carousel
var dots: HBoxContainer
var enter_btn: NxButton
var idx := 0

func build() -> void:
	make_scroll(20)
	_fill()
	end_body()

func on_store_changed() -> void:
	rebuild(_fill)

func _fill() -> void:
	var p := UD.p()
	var head := Kit.vbox(0)
	var e := Kit.caps("PORTAL · SELECT", 26, NX.hdr(NX.PINK, 1.3), 12)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(e)
	var t := Kit.title(I18n.t("play.choose_a_game_mode"), 57)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(t)
	body.add_child(ent(head, 0))
	body.add_child(ent(padx(_online_card()), 1))
	body.add_child(Kit.section(I18n.t("play.offline"), "OFFLINE · BOT & LOCAL"))
	carousel = _Carousel.new()
	carousel.modes = Launch.modes()
	carousel.index = idx
	carousel.changed.connect(_on_idx)
	carousel.picked.connect(func(k): Nav.go("setup", {"mode": k}))
	body.add_child(carousel)
	dots = Kit.hbox(8)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	for m in carousel.modes:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(21, 21)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.add_theme_stylebox_override("panel", NX.box(NX.hdr(m["color"], 1.2), 11))
		dots.add_child(d)
	body.add_child(dots)
	carousel.moved.connect(_dots)
	var m0: Dictionary = carousel.modes[idx]
	enter_btn = Kit.button(I18n.t("play.enter_x") % m0["name"], func(): Nav.go("setup", {"mode": carousel.modes[idx]["k"]}), m0["grad"])
	body.add_child(Kit.margin(enter_btn, 62, 26, 62, 0))
	# league road
	body.add_child(Kit.section(I18n.t("play.league_road"), "LEAGUE ROAD", NX.GOLD))
	var hs := Kit.hscroll(0)
	var road: HBoxContainer = hs[1]
	road.alignment = BoxContainer.ALIGNMENT_CENTER
	var tr := int(p.get("trophies", 0))
	var lg := UD.league(tr)
	road.add_child(Kit.gap(0, 30))
	for i in UD.LEAGUES.size():
		var L: Array = UD.LEAGUES[i]
		var reached := tr >= int(L[1])
		var cur := i == int(lg["idx"])
		if i > 0:
			var seg := Panel.new()
			seg.custom_minimum_size = Vector2(68, 10)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.add_theme_stylebox_override("panel", NX.box(NX.hdr(NX.GOLD, 1.3) if reached else Color(1, 1, 1, 0.12), 5))
			road.add_child(seg)
		var card := PanelContainer.new()
		var sb := NX.box(Color(1, 0.82, 0.34, 0.12) if cur else Color(0.03, 0.047, 0.133, 0.8), 47, 3, NX.hdr(NX.GOLD, 1.2) if cur else NX.LINE, 28 if cur else 0, Color(1, 0.82, 0.34, 0.45))
		sb.content_margin_top = 18; sb.content_margin_bottom = 18
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(224, 0)
		var v := Kit.vbox(2)
		var im := Kit.img(UD.ui(UD.MEDAL[i]), 140)
		im.modulate.a = 1.0 if reached else 0.35
		v.add_child(Kit.center(im))
		var n := Kit.label(UD.LEAGUE_FA[L[0]], 29, Color.WHITE if reached else NX.DIM2)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		var tt := Kit.title(NX.fa(L[1]), 24, NX.GOLD if reached else NX.DIM2, "head")
		tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tt)
		card.add_child(v)
		if cur:
			card.ready.connect(func():
				card.pivot_offset = card.size * 0.5
				var pt := card.create_tween().set_loops()
				pt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				pt.tween_property(card, "scale", Vector2(1.05, 1.05), 1.2)
				pt.tween_property(card, "scale", Vector2.ONE, 1.2))
		road.add_child(card)
	road.add_child(Kit.gap(0, 30))
	(hs[0] as ScrollContainer).custom_minimum_size.y = 330
	body.add_child(hs[0])
	# scroll the road to the current league
	(func():
		var sc: ScrollContainer = hs[0]
		await get_tree().process_frame
		if is_instance_valid(sc):
			sc.scroll_horizontal = int(max(0, int(lg["idx"]) * 292 - 300))).call_deferred()
	_dots(float(idx))

func _on_idx(i: int) -> void:
	idx = i
	var m: Dictionary = carousel.modes[i]
	enter_btn.set_text(I18n.t("play.enter_x") % m["name"])
	enter_btn.set_style(m["grad"])

func _dots(x: float) -> void:
	for i in dots.get_child_count():
		var d := dots.get_child(i) as Control
		var k := maxf(0.0, 1.0 - absf(x - i))
		d.custom_minimum_size.x = 21 + k * 47
		d.modulate.a = 0.35 + k * 0.65

func _online_card() -> Control:
	var v := Kit.vbox(20)
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 292)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var g := NxGrad.new([Color("#ff8a5c"), Color("#c23a7e"), Color("#3a1d8a")], 62, 0.6, 0.3)
	g.set_border(4.0, Color(0.63, 0.86, 1.0, 0.55))
	g.set_glow(Color(1.5, 0.45, 0.9, 0.45), 30.0, 30.0)
	card.add_child(g)
	var row := Kit.hbox(20, true)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(Kit.img(UD.art("planet"), 218))
	var col := Kit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := Kit.hbox(18, true)
	var ttl := Kit.label(I18n.t("hub.online"), 62, Color.WHITE, true)
	Kit.glow_text(ttl, NX.CYAN, 16)
	tl.add_child(ttl)
	var live := PanelContainer.new()
	var lsb := NX.box(NX.hdr(NX.RED, 1.2), 24)
	lsb.content_margin_left = 16; lsb.content_margin_right = 16
	live.add_theme_stylebox_override("panel", lsb)
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lh := Kit.hbox(8)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", NX.box(Color.WHITE, 8))
	lh.add_child(dot)
	lh.add_child(Kit.caps("LIVE", 23, Color.WHITE, 2))
	live.add_child(lh)
	tl.add_child(live)
	var blink := dot.create_tween().set_loops()
	blink.tween_property(dot, "modulate:a", 0.2, 0.6)
	blink.tween_property(dot, "modulate:a", 1.0, 0.6)
	col.add_child(tl)
	var d := Kit.label(I18n.t("account.play_real_players_1v1_2v2"), 31, Color("#d6e6ff"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	var op := UD.online_profile()
	if not op.is_empty():
		col.add_child(Kit.label(I18n.t("play.rating_x_gems_x") % [NX.fa(int(op.get("rating", 0))), NX.fa(int(op.get("gems", 0)))], 29, NX.GOLD, true))
	row.add_child(col)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.offset_left = -g.pad; g.offset_top = -g.pad; g.offset_right = g.pad; g.offset_bottom = g.pad
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 36; row.offset_right = -36
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	var sh := card.create_tween().set_loops()
	sh.tween_interval(1.8)
	sh.tween_method(func(x): g.shine = x, 0.0, 1.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	sh.tween_callback(func(): g.shine = -1.0)
	# tilt toward the touch point on press
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			var tw := card.create_tween()
			if ev.pressed:
				var nx: float = ev.position.x / maxf(1.0, card.size.x) - 0.5
				tw.tween_property(card, "rotation", deg_to_rad(-nx * 3.0), 0.15)
				tw.parallel().tween_property(card, "scale", Vector2(0.97, 0.97), 0.15)
			else:
				tw.tween_property(card, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				if card.get_global_rect().has_point(ev.global_position):
					UD.sfx("ui")
					UD.haptic("medium")
					Nav.online("hub"))
	v.add_child(card)
	var links := Kit.hbox(18, true)
	for l in [["arena", I18n.t("arena.arena"), "x_crown"], ["tours", I18n.t("hub.tournament"), "@trophy_tournament"], ["leagues", I18n.t("tournaments.league"), "@trophy_league"], ["challenges", I18n.t("kb.challenge"), "@t_events"], ["social", I18n.t("home.social"), "@t_friends"]]:
		var b := NxNeon.new(36, 8)
		b.custom_minimum_size = Vector2(0, 114)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := Kit.hbox(8, true)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(Kit.img(UD.ui(l[2]) if str(l[2]).begins_with("@") else UD.ui2(l[2]), 68))
		h.add_child(Kit.label(l[1], 29, NX.TEXT, true))
		b.add_child(h)
		var entry: String = l[0]
		Kit.tap(b, func(): Nav.online(entry), 0.94)
		links.add_child(b)
	v.add_child(links)
	return v


## Horizontal 3D carousel of mode cards. RTL-agnostic (index 0 at the centre on start).
class _Carousel extends Control:
	signal changed(i: int)
	signal moved(x: float)
	signal picked(k: String)
	var modes: Array = []
	var index := 0
	var x := 0.0          # continuous position in card units
	var cards: Array[Control] = []
	var arts: Array[Control] = []
	var cw := 0.0
	var gap := 36.0
	var _drag := false
	var _moved := false
	var _start := Vector2.ZERO
	var _x0 := 0.0
	var _vel := 0.0
	var _last_t := 0
	var _last_x := 0.0
	var _tw: Tween

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = false
		cw = minf(1080 * 0.72, 858)
		custom_minimum_size = Vector2(0, cw * 1.32 + 80)
		x = index
		for i in modes.size():
			var c := _card(modes[i])
			add_child(c)
			cards.append(c)
		resized.connect(_place)
		_place()

	func _card(m: Dictionary) -> Control:
		var col: Color = m["color"]
		var w := cw
		var h := cw * 1.32
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(w, h)
		c.pivot_offset = c.size * 0.5
		var g := NxGrad.new([Color(col.r, col.g, col.b, 0.38), Color(0.055, 0.086, 0.25, 0.9), Color(0.02, 0.03, 0.094, 0.98)], 72, 1.57, 0.18)
		g.set_border(4.0, Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 0.6))
		g.set_glow(Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.55), 36.0, 40.0)
		g.position = Vector2(-40, -40)
		g.size = c.size + Vector2(80, 80)
		c.add_child(g)
		var portal := Kit.img(UD.ui2("portal"), Vector2(w * 1.05, w * 0.7))
		portal.position = Vector2(-w * 0.025, 26)
		portal.modulate = Color(1.0, 0.6, 0.9, 0.3)
		c.add_child(portal)
		var art := Control.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size = Vector2(w, w * 0.8)
		art.position = Vector2(0, w * 0.06)
		c.add_child(art)
		var pul := Kit.pulse(w * 0.45, Color(col.r, col.g, col.b, 0.45))
		Kit.put(art, pul, w * 0.5, w * 0.36)
		var im := Kit.img(UD.ui(m["img"]), Vector2(w * 0.58, w * 0.62))
		Kit.put(art, im, w * 0.5, w * 0.36)
		Kit.bob(im, 16, 2.6)
		arts.append(art)
		var v := Kit.vbox(4)
		v.position = Vector2(40, h - 420)
		v.size = Vector2(w - 80, 400)
		v.alignment = BoxContainer.ALIGNMENT_END
		var e := Kit.caps(m["en"], 26, NX.hdr(col, 1.4), 8)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(e)
		var n := Kit.title(m["name"], 62)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Kit.glow_text(n, col, 18)
		v.add_child(n)
		var d := Kit.para(m["desc"], 31, Color("#c6dbff"), HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(d)
		var rw := PanelContainer.new()
		var rsb := NX.box(Color(0, 0, 0, 0.25), 36, 3, Color(col.r, col.g, col.b, 0.45))
		rsb.content_margin_left = 26; rsb.content_margin_right = 26; rsb.content_margin_top = 6; rsb.content_margin_bottom = 6
		rw.add_theme_stylebox_override("panel", rsb)
		rw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var rh := Kit.hbox(10, true)
		rh.add_child(Kit.img(UD.ui2("c_coin"), 52))
		rh.add_child(Kit.label(m["reward"], 29, Color("#ffe9a8")))
		rw.add_child(rh)
		v.add_child(rw)
		v.add_child(Kit.gap(30))
		c.add_child(v)
		return c

	func _place() -> void:
		var cxp := size.x * 0.5
		var step := cw + gap
		for i in cards.size():
			var d := float(i) - x
			var ad := absf(d)
			var c := cards[i]
			var sc := lerpf(1.0, 0.84, minf(1.0, ad))
			# fake rotateY: squash horizontally + slide inward with distance
			var sx := sc * lerpf(1.0, 0.86, minf(1.0, ad))
			c.scale = Vector2(sx, sc)
			c.position = Vector2(cxp + d * step * 0.92 - cw * 0.5, 40)
			c.modulate.a = clampf(1.0 - ad * 0.45 if ad <= 1.0 else 0.55 - (ad - 1.0) * 0.3, 0.0, 1.0)
			c.z_index = 0
			c.rotation = clampf(d, -1.0, 1.0) * 0.035
			arts[i].position.x = clampf(-d, -1.5, 1.5) * 104.0
		# draw order by distance (nearest last) without z_index, which would escape the scroll
		# clip and paint over the tab bar
		var order := cards.duplicate()
		order.sort_custom(func(a, b): return absf(cards.find(a) - x) > absf(cards.find(b) - x))
		for k in order.size():
			move_child(order[k], k)
		moved.emit(x)

	func _process(_d: float) -> void:
		# the carousel art was seen painting through sheets opened over Play; hide it while one is up
		var cover: bool = Nav.has_sheet()
		if visible == cover:
			visible = not cover

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_drag = true
				_moved = false
				_start = ev.position
				_x0 = x
				_vel = 0.0
				_last_t = Time.get_ticks_msec()
				_last_x = ev.position.x
				if _tw: _tw.kill()
			elif _drag:
				_drag = false
				if not _moved:
					# tap: centre card opens, side cards scroll into view
					var cxp := size.x * 0.5
					if absf(ev.position.x - cxp) < cw * 0.5:
						UD.sfx("ui")
						UD.haptic("light")
						var k: String = modes[index]["k"]
						var c := cards[index]
						var tw := c.create_tween()
						tw.tween_property(c, "scale", c.scale * 0.96, 0.08)
						tw.tween_property(c, "scale", c.scale, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
						picked.emit(k)
					else:
						_snap(index + (1 if ev.position.x > cxp else -1))
				else:
					var target := roundf(x - _vel * 0.18)
					_snap(int(target))
		elif ev is InputEventMouseMotion and _drag:
			var dx: float = ev.position.x - _start.x
			if not _moved and absf(dx) > 18 and absf(dx) > absf(ev.position.y - _start.y):
				_moved = true
			if _moved:
				var now := Time.get_ticks_msec()
				var dt := maxf(1.0, now - _last_t) / 1000.0
				_vel = lerpf(_vel, (ev.position.x - _last_x) / (cw + gap) / dt, 0.4)
				_last_t = now
				_last_x = ev.position.x
				x = clampf(_x0 - dx / (cw + gap), -0.35, modes.size() - 0.65)
				_place()
				accept_event()

	func _snap(i: int) -> void:
		i = clampi(i, 0, modes.size() - 1)
		if _tw: _tw.kill()
		_tw = create_tween()
		_tw.tween_method(func(v): x = v; _place(), x, float(i), 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		if i != index:
			index = i
			UD.haptic("light")
			changed.emit(i)
