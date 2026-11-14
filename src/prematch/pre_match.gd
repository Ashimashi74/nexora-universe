extends Control
## Pre-match flow (RN v6 src/prematch/PreMatch.tsx): TEAM SELECT → FORMATION SELECT → match.
##   Nav.go("prematch", {"launch": Launch})   offline: team (◀ ▶ through every disc + «جدول تیم ها») → formation (9) → match
##   Nav.go("prematch", {"picker": true})     app-wide TEAM PICKER (Profile / Shop / Home): pick + «تأیید و بازگشت»
## The chosen team and formation are saved as the new defaults (Store.p.team / Store.p.form; the online disc is equipped too).
## online_prematch.gd extends this script and drives the same two views from the host's broadcast state.

const D := preload("res://src/core/data.gd")

var params: Dictionary = {}
var step := "team"          # team | form
var picker := false
var launch: Dictionary = {}
var team_id := "club0"
var form := 8
var deadline_ms := 0.0      # countdown end (online), 0 = none
var total_s := 0.0          # phase length for the timer bar (online formation)
var read_only := false
var start_label := "ادامه: ترکیب"
var confirm_label := "شروع بازی"
## online: [{label, team, form, ready, captain:{name, level, avatar}, members:[names]}, {..}]
var sides: Array = []
var my_side := 0
var view_tab := 0

var _list: Array = []
var _root: Control
var _disc_img: TextureRect
var _name_l: Label
var _idx_l: Label
var _stats_box: VBoxContainer
var _start_btn: NxButton
var _timer_bar: ColorRect
var _timer_bg: ColorRect
var _form_picker: FormationPicker
var _side_box: Control
var _tick: Timer

func setup(p: Dictionary) -> void:
	params = p
	picker = bool(p.get("picker", false))
	launch = p.get("launch", {}) if p.get("launch") is Dictionary else {}
	var sp := UD.p()
	team_id = str(sp.get("team", "club0"))
	form = D.form_idx(int(sp.get("form", D.FORM_DEFAULT)))
	if picker: start_label = "تأیید و بازگشت"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	layout_direction = I18n.LD
	if Nav.has_method("chrome"): Nav.chrome(false)
	_list = owned_list()
	_tick = Timer.new()
	_tick.wait_time = 0.25
	_tick.autostart = true
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	_build()

func leave() -> void:
	pass

## every disc in the catalog (v3: all discs are free to own / equip), current one first in its category order
func owned_list() -> Array:
	var out: Array = []
	for t in D.TEAMS:
		if UD.disc_owned(str(t.id)): out.append(t)
	return out if out.size() > 0 else [D.TEAMS[0]]

func on_back() -> bool:
	if step == "form" and not picker and sides.is_empty():
		step = "team"; _build(); return true
	return false

# ------------------------------------------------------------------ build
func _build() -> void:
	if _root and is_instance_valid(_root): _root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color("#03061a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var st := TextureRect.new()
	st.texture = UD.menu("bg_stadium")
	st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	st.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	st.set_anchors_preset(Control.PRESET_FULL_RECT)
	st.modulate = Color(1, 1, 1, 0.5)
	_root.add_child(st)
	var shade := ColorRect.new()
	shade.color = Color(0.012, 0.024, 0.1, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	if step == "team": _build_team()
	else: _build_form()

func _bottom_bar(v: Control) -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", NX.box(Color(0.012, 0.024, 0.1, 0.9), 0))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -(230 + NX.safe_bottom)
	_root.add_child(bar)
	bar.add_child(Kit.margin(v, 48, 20, 48, 24 + NX.safe_bottom))

func _build_team() -> void:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_bottom = -(240 + NX.safe_bottom)
	_root.add_child(sc)
	var v := Kit.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	sc.add_child(Kit.margin(v, 36, NX.safe_top + 30, 36, 30))
	# corner buttons + name banner
	var top := HBoxContainer.new()
	top.layout_direction = Control.LAYOUT_DIRECTION_LTR
	top.add_theme_constant_override("separation", 16)
	top.add_child(_corner(UD.menu("ic_trophy"), "جدول تیم ها", _open_table))
	var banner := PanelContainer.new()
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.add_theme_stylebox_override("panel", NX.box(Color(0.12, 0.24, 0.55, 0.85), 36, 3, NX.CYAN, 18, Color(NX.CYAN, 0.5)))
	var bt := Kit.title(_title_text(), 44)
	bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bt.clip_text = true
	banner.add_child(Kit.margin(bt, 24, 18, 24, 18))
	var bwrap := VBoxContainer.new()
	bwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bwrap.add_child(Kit.gap(18))
	bwrap.add_child(banner)
	top.add_child(bwrap)
	var coach_cb := func(): if not picker and sides.is_empty(): _go_form()
	top.add_child(_corner(UD.menu("ic_friends"), "انتخاب مربی", coach_cb if not picker else _open_loadout))
	v.add_child(top)
	# disc + arrows
	var row := HBoxContainer.new()
	row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.add_child(_arrow("◀", func(): _step_team(-1)))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(520, 520)
	var pl := Kit.pulse(300, Color(0.31, 0.89, 1.0, 0.25))
	pl.position = Vector2(260 - 240, 260 - 240)
	holder.add_child(pl)
	_disc_img = Kit.img(null, 460)
	_disc_img.position = Vector2(30, 30)
	_disc_img.size = Vector2(460, 460)
	holder.add_child(_disc_img)
	row.add_child(holder)
	row.add_child(_arrow("▶", func(): _step_team(1)))
	v.add_child(row)
	_name_l = Kit.title("", 50)
	_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name_l)
	_idx_l = Kit.label("", 28, NX.DIM)
	_idx_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_idx_l)
	# stats: قدرت / زمان / هدف
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", NX.box(Color(0.06, 0.08, 0.18, 0.88), 40, 3, Color(NX.CYAN, 0.6)))
	sp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp.custom_minimum_size.x = 780
	_stats_box = Kit.vbox(14)
	sp.add_child(Kit.margin(_stats_box, 34, 26, 34, 26))
	v.add_child(sp)
	# selected + shop (+ loadout in picker mode)
	var bcol := Kit.vbox(18)
	bcol.custom_minimum_size.x = 720
	bcol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sel := Kit.button_small("در انتظار کاپیتان…" if read_only else "انتخاب شده ✓", func():
		if read_only: return
		UD.sfx("ready")
		if picker: _confirm_team(), "dark")
	bcol.add_child(sel)
	if not read_only:
		bcol.add_child(Kit.button_small("فروشگاه", func(): Nav.go("shop"), "violet"))
	if picker:
		bcol.add_child(Kit.button_small("توپ، زمین و ترکیب", _open_loadout, "dark"))
	v.add_child(bcol)
	# team tabs + captain (online)
	_side_box = Kit.vbox(14)
	v.add_child(_side_box)
	# bottom: start / countdown
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 24)
	if picker:
		var cl := Kit.button_small("بستن", func(): Nav.back(), "dark")
		cl.custom_minimum_size.x = 300
		bh.add_child(cl)
	_start_btn = Kit.button(start_label, _confirm_team, "primary")
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_start_btn)
	_bottom_bar(bh)
	_refresh_team()

func _title_text() -> String:
	var sp := get_node_or_null("/root/Supa")
	var prof: Variant = sp.get("profile") if sp else null
	if prof is Dictionary and str(prof.get("username", "")) != "": return str(prof.username)
	return str(UD.p().get("name", "Pilot"))

func _corner(tex: Texture2D, txt: String, cb: Callable) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(230, 230)
	pc.add_theme_stylebox_override("panel", NX.box(Color(0.055, 0.094, 0.25, 0.85), 50, 3, Color(NX.CYAN, 0.4)))
	var v := Kit.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var im := Kit.img(tex, 100)
	im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(im)
	var l := Kit.label(txt, 26, NX.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	pc.add_child(v)
	Kit.tap(pc, cb, 0.94)
	return pc

func _arrow(txt: String, cb: Callable) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(160, 240)
	pc.add_theme_stylebox_override("panel", NX.box(Color(0.31, 0.89, 1.0, 0.12), 56, 3, Color(NX.CYAN, 0.55)))
	var l := Kit.title(txt, 80, NX.CYAN)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	Kit.tap(pc, cb, 0.9)
	return pc

func _shown_team() -> Dictionary:
	if not sides.is_empty() and view_tab != my_side:
		return D.team_by_id(str(sides[view_tab].team))
	return D.team_by_id(team_id)

func _cur_idx() -> int:
	for i in _list.size():
		if str(_list[i].id) == team_id: return i
	return 0

func _refresh_team() -> void:
	if _disc_img == null or not is_instance_valid(_disc_img): return
	var t := _shown_team()
	_disc_img.texture = UD.team_tex(t)
	_name_l.text = str(t.get("name", ""))
	var other := not sides.is_empty() and view_tab != my_side
	_idx_l.text = "%s / %s" % [NX.fa(1 if other else _cur_idx() + 1), NX.fa(1 if other else _list.size())]
	for c in _stats_box.get_children(): c.queue_free()
	var s := UD.disc_stats(str(t.id))
	var pw := int(s.get("power", 5))
	var ac := int(s.get("accuracy", 5))
	var tm := clampi(int(round((pw + ac) / 2.0)), 1, 10)
	for row in [["قدرت", pw], ["زمان", tm], ["هدف", ac]]:
		var h := Kit.hbox(20)
		var k := Kit.label(row[0], 32, NX.TEXT, true)
		k.custom_minimum_size.x = 140
		h.add_child(k)
		var bar := Kit.progress(float(row[1]) / 10.0, NX.INDIGO, NX.CYAN, 60.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(bar)
		var vl := Kit.title(NX.fa(row[1]), 34)
		vl.custom_minimum_size.x = 60
		h.add_child(vl)
		_stats_box.add_child(h)
	_refresh_sides()

func _refresh_sides() -> void:
	if _side_box == null or not is_instance_valid(_side_box): return
	for c in _side_box.get_children(): c.queue_free()
	if sides.is_empty(): return
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 30)
	for i in 2:
		var col: Color = NX.CYAN if i == 0 else Color("#ff4a7a")
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(360, 130)
		pc.add_theme_stylebox_override("panel", NX.box(Color(col, 0.2) if view_tab == i else Color(0.03, 0.05, 0.13, 0.8), 40, 4, col))
		var v := Kit.vbox(2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := Kit.title("تیم یک" if i == 0 else "تیم دو", 40)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		if bool(sides[i].get("ready", false)):
			var r := Kit.label("✓ آماده", 26, NX.GREEN)
			r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(r)
		pc.add_child(v)
		var ii := i
		Kit.tap(pc, func(): view_tab = ii; _refresh_team(), 0.95)
		tabs.add_child(pc)
	_side_box.add_child(tabs)
	var sd: Dictionary = sides[view_tab]
	var cap: Dictionary = sd.get("captain", {})
	var c := Kit.vbox(8)
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	var tag := Kit.tag("کاپیتان", Color(0.47, 0.55, 0.75, 0.5), NX.TEXT, 28)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(tag)
	var av := Kit.avatar(cap.get("avatar", sd.get("team", "club0")), 170, NX.CYAN if view_tab == 0 else Color("#ff4a7a"))
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(av)
	var lv := Kit.tag("سطح %s" % NX.fa(int(cap.get("level", 1))), Color.WHITE, Color("#04122a"), 26)
	lv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(lv)
	var nm := Kit.tag(str(cap.get("name", "ربات")), Color(0.24, 1.0, 0.66, 0.3), NX.TEXT, 32)
	nm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(nm)
	var mem: Array = sd.get("members", [])
	if mem.size() > 0:
		var ml := Kit.label(" · ".join(PackedStringArray(mem)), 26, NX.DIM)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(ml)
	_side_box.add_child(c)

func _step_team(d: int) -> void:
	if read_only or (not sides.is_empty() and view_tab != my_side): return
	var i := (_cur_idx() + d + _list.size()) % _list.size()
	set_team(str(_list[i].id))
	UD.sfx("ui")
	if _disc_img:
		_disc_img.pivot_offset = _disc_img.size / 2
		var tw := _disc_img.create_tween()
		tw.tween_property(_disc_img, "scale", Vector2(0.82, 0.82), 0.09)
		tw.tween_property(_disc_img, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## change my team (saved as the default; online: also sent to the host by online_prematch)
func set_team(id: String) -> void:
	team_id = id
	UD.set_p({"team": id})
	var dz := UD.discs()
	var sp := get_node_or_null("/root/Supa")
	if dz and sp and sp.signed_in() and dz.has_method("equip"):
		dz.equip(id)
	_on_team_changed(id)
	_refresh_team()

func _on_team_changed(_id: String) -> void:
	pass

func _confirm_team() -> void:
	if picker:
		set_team(team_id)
		Nav.toast("تیم انتخاب شد ✓", "ok")
		Nav.back()
		return
	_go_form()

func _go_form() -> void:
	step = "form"
	_build()

func _open_loadout() -> void:
	var lo = load("res://src/ui/loadout.gd")
	if lo:
		Nav.sheet(lo.new(), {"title": "توپ، زمین و ترکیب", "en": "LOADOUT"})

# ------------------------------------------------------------------ team table (all discs, sorted by stats)
func _open_table() -> void:
	var rows: Array = []
	for t in D.TEAMS:
		var s := UD.disc_stats(str(t.id))
		rows.append({"t": t, "s": int(s.get("power", 5)) + int(s.get("accuracy", 5)), "own": UD.disc_owned(str(t.id))})
	rows.sort_custom(func(a, b): return (a.own and not b.own) or (a.own == b.own and a.s > b.s))
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.016, 0.063, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(bg)
	var v := Kit.vbox(12)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = NX.safe_top + 30; v.offset_left = 30; v.offset_right = -30; v.offset_bottom = -NX.safe_bottom - 20
	ov.add_child(v)
	var hd := Kit.hbox(16)
	var tl := Kit.title("جدول تیم ها (%s)" % NX.fa(rows.size()), 50)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(tl)
	hd.add_child(Kit.close_button(func(): ov.queue_free()))
	v.add_child(hd)
	var sl := Kit.scroll_list(12)
	(sl[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sl[0])
	var i := 0
	for r in rows:
		i += 1
		var t: Dictionary = r.t
		var s := UD.disc_stats(str(t.id))
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", NX.box(Color(0.04, 0.055, 0.157, 0.85), 30, 3, NX.CYAN if str(t.id) == team_id else NX.LINE))
		var h := Kit.hbox(16)
		var nl := Kit.label(NX.fa(i), 28, NX.DIM)
		nl.custom_minimum_size.x = 70
		h.add_child(nl)
		h.add_child(Kit.img(UD.team_tex(t), 100))
		var nm := Kit.label(str(t.name), 32, NX.TEXT, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		h.add_child(nm)
		h.add_child(Kit.label("قدرت %s · هدف %s" % [NX.fa(int(s.power)), NX.fa(int(s.accuracy))], 26, NX.DIM))
		if not r.own: h.add_child(Kit.label("🔒", 28))
		pc.add_child(Kit.margin(h, 20, 10, 20, 10))
		if r.own and not read_only and (sides.is_empty() or view_tab == my_side):
			var id := str(t.id)
			Kit.tap(pc, func():
				set_team(id)
				ov.queue_free(), 0.98)
		else:
			pc.modulate.a = 0.5 if not r.own else 1.0
		(sl[1] as Control).add_child(pc)
	_root.add_child(ov)

# ------------------------------------------------------------------ formation step
func _build_form() -> void:
	var v := Kit.vbox(16)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = NX.safe_top + 40; v.offset_left = 30; v.offset_right = -30; v.offset_bottom = -(260 + NX.safe_bottom)
	_root.add_child(v)
	_form_picker = FormationPicker.new()
	_form_picker.value = form
	_form_picker.title_text = "انتخاب ترکیب"
	_form_picker.disc_tex = UD.team_tex(D.team_by_id(team_id))
	_form_picker.save = sides.is_empty()
	_form_picker.read_only = read_only
	_form_picker.on_select = func(fi: int): set_form(fi)
	_form_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_form_picker)
	var col := Kit.vbox(14)
	_timer_bg = ColorRect.new()
	_timer_bg.color = Color(0, 0, 0, 1)
	_timer_bg.custom_minimum_size = Vector2(600, 50)
	_timer_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_timer_bar = ColorRect.new()
	_timer_bar.color = Color("#ff9a20")
	_timer_bar.size = Vector2(600, 50)
	_timer_bg.add_child(_timer_bar)
	_timer_bg.visible = deadline_ms > 0 and total_s > 0
	col.add_child(_timer_bg)
	_start_btn = Kit.button(confirm_label, _confirm_form, "primary")
	col.add_child(_start_btn)
	_bottom_bar(col)

func set_form(fi: int) -> void:
	form = fi
	if sides.is_empty(): UD.set_p({"form": fi})
	_on_form_changed(fi)

func _on_form_changed(_fi: int) -> void:
	pass

func _confirm_form() -> void:
	start_match()

## offline: apply the chosen team + formation to the launch and start the match
func start_match() -> void:
	var p := UD.p()
	var me := D.team_by_id(team_id)
	var l := launch.duplicate(true)
	if l.is_empty() or not (l.get("cfg") is Dictionary):
		l = Launch.build("quick", p, {"lvl": int(p.get("aiLvl", 1))})
	var cfg: Dictionary = l.cfg
	var local := str(l.get("mode", "")) == "local"
	var forms: Array = cfg.get("forms", [form, form])
	cfg["forms"] = [form, form if local else int(forms[1])]
	var stats: Array = cfg.get("stats", [UD.disc_stats(team_id), UD.disc_stats(team_id)])
	cfg["stats"] = [UD.disc_stats(team_id), UD.disc_stats(team_id) if local else stats[1]]
	var vip: Array = cfg.get("vip", [false, false])
	cfg["vip"] = [str(me.cat) in ["vip", "leg"], vip[1]]
	var tids: Array = cfg.get("teams", [team_id, team_id])
	cfg["teams"] = [team_id, team_id if local else str(tids[1])]
	var teams: Array = l.get("teams", [me, me])
	l["teams"] = [me, me if local else teams[1]]
	l["cfg"] = cfg
	Nav.go("match", l)

# ------------------------------------------------------------------ countdown
func _on_tick() -> void:
	if deadline_ms <= 0 or _start_btn == null or not is_instance_valid(_start_btn): return
	var left := maxf(0.0, (deadline_ms - Time.get_unix_time_from_system() * 1000.0) / 1000.0)
	var lbl := start_label if step == "team" else confirm_label
	_start_btn.set_text("%s   %s" % [lbl, NX.fa(int(ceil(left)))])
	if _timer_bar and is_instance_valid(_timer_bar) and total_s > 0:
		_timer_bar.size.x = 600.0 * clampf(left / total_s, 0.02, 1.0)
