extends Control
## Offline result screen — port of src/screens/Result.tsx (+ App.tsx onAgain / nextCup / goHome).
## Params (from match.gd): {r:{score, teams, ai, ai_lvl}, reward:{coins,xp,trophies,gems}|null,
##   cup:{stage,won,champion}|null, level_up:int, names:[a,b], launch:Launch}

signal again_started(launch: Dictionary)

const D := preload("res://src/core/data.gd")
const U := 2.6
const COACH_PATH := "res://src/oracle/coach.gd"

var r: Dictionary = {}
var reward = null
var cup = null
var level_up := 0
var names: Array = ["", ""]
var launch: Dictionary = {}
var out := "draw"
var col := NX.CYAN
var scroll: ScrollContainer
var _busy := false

func setup(params: Dictionary) -> void:
	r = params.get("r", {"score": [0, 0], "teams": [], "ai": true, "ai_lvl": 1})
	reward = params.get("reward", null)
	cup = params.get("cup", null)
	level_up = int(params.get("level_up", 0))
	launch = params.get("launch", {})
	var nm = params.get("names", launch.get("names", null))
	if nm is Array and nm.size() >= 2: names = [String(nm[0]), String(nm[1])]
	var sc: Array = r.get("score", [0, 0])
	var a := int(sc[0])
	var b := int(sc[1])
	out = "victory" if a > b else ("defeat" if a < b else "draw")
	col = NX.GOLD if out == "victory" else (NX.RED if out == "defeat" else NX.CYAN)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# RN Space theme per outcome: win / lose / system
	Nav.backdrop({"victory": "win", "defeat": "lose"}.get(out, "system"), 0.0)
	var sl := Kit.scroll_list(0)
	scroll = sl[0]
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var v: VBoxContainer = sl[1]
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	var m := Kit.margin(null, 16 * U, NX.safe_top + 10 * U, 16 * U, NX.safe_bottom + 24 * U)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(m)
	var col_v := Kit.vbox(0)
	m.add_child(col_v)
	var W := 1080.0
	var vp := get_viewport()
	if vp: W = vp.get_visible_rect().size.x
	var bw := minf(W * 0.9, 380 * U)
	col_v.add_child(_hero(bw))
	col_v.add_child(_score_panel())
	if reward is Dictionary:
		col_v.add_child(Kit.gap(12 * U))
		col_v.add_child(_rewards())
	if level_up > 0:
		col_v.add_child(Kit.gap(12 * U))
		col_v.add_child(_level_panel())
	col_v.add_child(Kit.gap(14 * U))
	col_v.add_child(_oracle_row())
	if cup is Dictionary:
		var ct: String
		if cup.get("champion", false): ct = "قهرمان جام نکسورا! ۴۰۰+ سکه"
		elif cup.get("won", false): ct = "مرحله‌ی %s از سه رد شد" % ["یک", "دو", "سه"][clampi(int(cup.get("stage", 0)), 0, 2)]
		else: ct = "از جام حذف شدی"
		var cl := Kit.label(ct, int(16 * U), NX.hdr(NX.GOLD if cup.get("won", false) else NX.RED, 1.2), true)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_v.add_child(Kit.gap(14 * U))
		col_v.add_child(cl)
	col_v.add_child(Kit.gap(14 * U))
	var again_t := "بازی دوباره"
	if cup is Dictionary: again_t = "مرحله‌ی بعد" if (cup.get("won", false) and not cup.get("champion", false)) else "جام دوباره"
	var b1 := Kit.button(again_t, again, "gold" if out == "victory" else "primary")
	col_v.add_child(Kit.enter(b1, 6))
	col_v.add_child(Kit.gap(10 * U))
	var b2 := Kit.button_small("بازگشت به خانه", home, "dark")
	col_v.add_child(Kit.enter(b2, 7))

func on_back() -> bool:
	home()
	return true

# ------------------------------------------------------------------ parts
func _hero(bw: float) -> Control:
	var st := Kit.stage(bw, bw * 0.66)
	st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ring := Kit.img(D.ui2("ring"), bw * 0.95)
	ring.modulate.a = 0.5
	Kit.put(st, ring, bw * 0.5, bw * 0.33)
	Kit.spin(ring, 20.0)
	var pl := Kit.pulse(bw * 0.5, Color(col.r, col.g, col.b, 0.27))
	Kit.put(st, pl, bw * 0.5, bw * 0.33)
	var ban := Kit.img(D.ui(out), Vector2(bw, bw * 0.62))
	Kit.put(st, ban, bw * 0.5, bw * 0.33)
	ban.scale = Vector2(0.4, 0.4)
	ban.modulate.a = 0.0
	ban.ready.connect(func():
		var tw := ban.create_tween().set_parallel(true)
		tw.tween_property(ban, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ban, "modulate:a", 1.0, 0.35))
	return st

func _side(tex: Texture2D, name: String, c: Color) -> Control:
	var v := Kit.vbox(int(4 * U))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var logo := Panel.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.custom_minimum_size = Vector2(58 * U, 58 * U)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.add_theme_stylebox_override("panel", NX.box(Color("#050816"), int(29 * U), 5, NX.hdr(c, 1.3), 18, Color(c.r, c.g, c.b, 0.6)))
	var t := Kit.round_img(tex, 52 * U)
	t.position = Vector2(3 * U, 3 * U)
	logo.add_child(t)
	v.add_child(logo)
	var l := Kit.label(name, int(12 * U), NX.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 40
	v.add_child(l)
	return v

func _team_tex(i: int) -> Texture2D:
	var ts: Array = r.get("teams", [])
	if i < ts.size():
		var t = ts[i]
		if t is Dictionary: return D.team_tex(String(t.get("id", "club0")))
		return D.team_tex(String(t))
	return D.team_tex("club0")

func _score_panel() -> Control:
	var p := Kit.glass(col, true, 14 * U)
	var h := Kit.hbox(int(6 * U))
	p.add_child(h)
	h.add_child(_side(_team_tex(0), names[0], NX.CYAN))
	var mid := Kit.vbox(-6)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	var sc: Array = r.get("score", [0, 0])
	var s := Kit.title("%d : %d" % [int(sc[0]), int(sc[1])], int(40 * U), Color.WHITE)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Kit.glow_text(s, col, 16)
	mid.add_child(s)
	var f := Kit.caps("FINAL", int(9 * U), NX.DIM, 10)
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(f)
	h.add_child(mid)
	h.add_child(_side(_team_tex(1), names[1], NX.RED))
	return Kit.enter(p, 1)

func _rewards() -> Control:
	var h := Kit.hbox(int(8 * U), true)
	var rw: Dictionary = reward
	h.add_child(_rw(D.ui2("c_coin"), int(rw.get("coins", 0)), NX.GOLD, 0.2, false, ""))
	h.add_child(_rw(D.ui2("x_star"), int(rw.get("xp", 0)), NX.CYAN, 0.35, false, "XP"))
	var tr := int(rw.get("trophies", 0))
	h.add_child(_rw(D.ui2("x_trophy"), tr, NX.GREEN if tr >= 0 else NX.RED, 0.5, true, ""))
	if int(rw.get("gems", 0)) != 0:
		h.add_child(_rw(D.ui2("x_gem"), int(rw.gems), Color("#9fd8ff"), 0.65, false, ""))
	return h

func _rw(tex: Texture2D, val: int, c: Color, delay: float, sign: bool, label: String) -> Control:
	var p := Kit.glass(c, false)
	p.set_pad(4 * U, 10 * U)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Kit.vbox(int(2 * U))
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var i := Kit.img(tex, 40 * U)
	i.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(i)
	var l := Kit.title(_rw_text(0, sign, label), int(15 * U), NX.hdr(c, 1.15))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	p.modulate.a = 0.0
	p.ready.connect(func():
		await get_tree().process_frame
		if not is_instance_valid(p): return
		p.pivot_offset = p.size * 0.5
		p.scale = Vector2(0.5, 0.5)
		var tw := p.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(p, "modulate:a", 1.0, 0.2)
		tw.parallel().tween_property(p, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var tc := p.create_tween()
		tc.tween_interval(delay)
		tc.tween_method(func(k: float): l.text = _rw_text(int(roundf(val * k)), sign, label), 0.0, 1.0, 0.6))
	return p

static func _rw_text(n: int, _sign: bool, label: String) -> String:
	# RN: `${sign && n >= 0 ? '+' : n >= 0 ? '+' : ''}${n}${label ? ' ' + label : ''}`
	return ("+" if n >= 0 else "") + str(n) + ((" " + label) if label != "" else "")

func _level_panel() -> Control:
	var p := Kit.glass(NX.VIOLET, true, 12 * U)
	var h := Kit.hbox(int(10 * U), true)
	p.add_child(h)
	h.add_child(Kit.img(D.ui2("x_crown"), 50 * U))
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(Kit.label("سطح %s!" % NX.fa(level_up), int(18 * U), Color("#d6b8ff"), true))
	v.add_child(Kit.label("به سطح جدید رسیدی · ۱۰۰+ سکه هدیه", int(11 * U), NX.DIM))
	h.add_child(v)
	return Kit.enter(p, 3)

func _line() -> Dictionary:
	if ResourceLoader.exists(COACH_PATH):
		var s = load(COACH_PATH)
		if s is GDScript and (s as GDScript).can_instantiate() and (s as GDScript).has_method("result_line"):
			var d = s.result_line(out)
			if d is Dictionary and d.has("text"): return d
	if out == "victory": return {"mood": "joy", "text": "عالی بود کاپیتان! 🏆"}
	if out == "defeat": return {"mood": "calm", "text": "اشکالی نداره، دست بعدی مال ماست. 💙"}
	return {"mood": "content", "text": "مساوی! فقط یک ضربه تا برد فاصله داشتیم. 🤝"}

func _oracle_row() -> Control:
	var ln := _line()
	var h := Kit.hbox(int(8 * U), true)
	var st := Kit.stage(96 * U, 104 * U)
	var o := Kit.img(D.oracle_tex(String(ln.get("mood", "idle"))), Vector2(96 * U, 104 * U))
	st.add_child(o)
	Kit.bob(o, 4 * U, 1.6)
	h.add_child(st)
	var bub := PanelContainer.new()
	bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := NX.box(Color(14 / 255.0, 30 / 255.0, 80 / 255.0, 0.9), int(16 * U), 3, Color(92 / 255.0, 225 / 255.0, 1, 0.4))
	sb.corner_radius_bottom_right = int(4 * U)
	sb.content_margin_left = 10 * U; sb.content_margin_right = 10 * U
	sb.content_margin_top = 10 * U; sb.content_margin_bottom = 10 * U
	bub.add_theme_stylebox_override("panel", sb)
	bub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bub.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var t := Kit.para(String(ln.get("text", "")), int(12 * U), Color("#e6f4ff"))
	bub.add_child(t)
	var wrap := Kit.vbox(0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(bub)
	wrap.add_child(Kit.gap(24 * U))
	h.add_child(wrap)
	h.alignment = BoxContainer.ALIGNMENT_END
	return Kit.enter(h, 4)

# ------------------------------------------------------------------ actions
static func next_launch(l: Dictionary, p: Dictionary, cup_state) -> Dictionary:
	var c: Dictionary = l.get("cfg", {})
	var ts: Array = l.get("teams", [])
	var opp = ts[1] if ts.size() > 1 else D.pick_opp()
	if cup_state is Dictionary:
		if cup_state.get("won", false) and not cup_state.get("champion", false):
			var pool := D.opp_pool()
			return D.build_launch("cup", p, {"lvl": 1, "rule": "g3", "tt": int(p.get("turnTime", 15)), "opp": pool[randi() % pool.size()], "stage": int(l.get("stage", 0)) + 1})
		return D.build_launch("cup", p, {"lvl": 0, "rule": "g3", "tt": int(p.get("turnTime", 15)), "opp": opp, "stage": 0})
	var rule := "t3" if int(c.get("match_time", 0)) == 180 else ("g5" if int(c.get("limit", 3)) == 5 else "g3")
	return D.build_launch(String(l.get("mode", "quick")), p, {"lvl": int(c.get("ai_lvl", 1)), "rule": rule, "tt": int(c.get("turn_time", 15)), "opp": opp, "stage": 0})

func again() -> void:
	if _busy: return
	_busy = true
	var nl := next_launch(launch, UD.p(), cup)
	# keep the online / test extras of the previous launch (bots, steps)
	for k in ["bots", "steps"]:
		if launch.has(k): nl[k] = launch[k]
	again_started.emit(nl)
	Nav.go("match", nl)

func home() -> void:
	if _busy: return
	_busy = true
	Nav.go("home")
