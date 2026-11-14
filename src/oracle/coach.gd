class_name OracleCoach
extends RefCounted
## ORACLE runtime (port of RN src/oracle/coach.ts + the OracleProvider half of Oracle.tsx):
##  • coach_miss(power, misses)        match-coach tip after a shot that missed the ball
##  • say / react / coach              speak in the floating bubble when it is mounted, else a tiny toast
##  • make_bubble()                    floating draggable mascot for main.gd (tabs only) with speech bubble,
##                                     action chips, idle→sleep after 45 s and the first-run onboarding tour
##  • set_scene("match"|"ui"), set_quiet(key, on)
## Owner: OUI worker.

const SOFT := [
	"نزدیک بود! از دیواره کمانه بزن؛ زاویه‌ی بهتری به توپ می‌رسه. 🎯",
	"دیسکی رو انتخاب کن که مسیر مستقیم‌تری تا توپ داره. 👀",
	"پیش‌نمایش مسیر رو دنبال کن؛ نقطه‌ها نشون می‌دن دیسک کجا می‌ره.",
	"گاهی یک ضربه‌ی کوتاه برای بستن مسیر حریف بهترین حرکته. 🛡",
]

const TIPS := [
	"از دیواره‌ها برای ضربه‌ی کمانه‌ای استفاده کن؛ دروازه‌بان‌ها انتظارش رو ندارن.",
	"همیشه قدرت کامل لازم نیست؛ ضربه‌ی متوسط توپ رو کنترل‌شده‌تر می‌بره.",
	"یک دیسک رو جلوی دروازه نگه دار تا ضدحمله‌ها رو خنثی کنه.",
	"قبل از شوت، پیش‌نمایش مسیر رو نگاه کن؛ دیسک‌های دقیق‌تر مسیر بلندتری نشون می‌دن.",
	"با ضربه‌ی اول نمی‌شه گل زد؛ اول توپ رو به موقعیت خوب برسون.",
	"اگر زمان نوبت کمه، یک ضربه‌ی امن دفاعی بهتر از از دست دادن نوبته.",
]

const GAPS := {"goal": 3.0, "reward": 2.5, "levelup": 1.0, "purchase": 2.0, "nogems": 15.0, "error": 20.0, "search": 5.0, "challengeDone": 4.0, "message": 8.0, "follow": 5.0, "tourReady": 10.0}

const TOUR := [
	{"tab": "", "idx": -1, "text": "سلام! من اوراکل‌ام 🤖 بذار در چند ثانیه ایستگاه NEXORA رو نشونت بدم.", "mood": "hello"},
	{"tab": "home", "idx": 0, "text": "خانه: جایزه‌ی روزانه، چالش‌های امروز و ورود سریع به بخش آنلاین این‌جاست.", "mood": "present"},
	{"tab": "play", "idx": 1, "text": "بازی: مقابل ربات یا دو نفره روی یک گوشی، و آنلاین: مسابقه‌ی سریع، آرنا، اتاق‌ها، تورنمنت و لیگ.", "mood": "excited"},
	{"tab": "social", "idx": 2, "text": "اجتماعی: پیام بده، گروه و کانال بساز، دوست دنبال کن و به یک باشگاه بپیوند.", "mood": "curious"},
	{"tab": "shop", "idx": 3, "text": "فروشگاه: دیسک‌ها با الماس، توپ و زمین با سکه. قدرت و دقت هر دیسک در بازی واقعاً اثر داره!", "mood": "happy"},
	{"tab": "profile", "idx": 4, "text": "پروفایل: عکس، سطح، لیگ و آمار. حساب مهمانت رو هم از تنظیمات به ایمیل وصل کن.", "mood": "idea"},
	{"tab": "home", "idx": -1, "text": "هر وقت سؤال داشتی روی من بزن؛ من این گوشه منتظرم. بزن بریم! 🚀", "mood": "joy"},
]

static var _last: Dictionary = {}
static var _quiet: Dictionary = {}
static var scene := "ui"
static var bubble: Variant = null      # mounted OracleBubble (Control) or null
static var _coach_layer: CanvasLayer = null
static var _watch_ch: Variant = null
static var _watch_uid := ""
static var _completed: Dictionary = {}
static var _primed := false


static func coach_miss(power: float, misses: int) -> String:
	if power > 0.92:
		return I18n.t("coach.too_much_power_pull_less")
	if power < 0.18:
		return I18n.t("coach.that_shot_was_too_soft")
	if misses % 2 == 1:
		return SOFT[randi() % SOFT.size()]
	return ""


static func tip() -> String:
	return TIPS[randi() % TIPS.size()]


## result screens: out = "victory" | "defeat" | "draw"
static func result_line(out: String) -> Dictionary:
	if out == "victory":
		return {"mood": "joy" if randf() < 0.5 else "laugh", "text": [I18n.t("coach.great_job_captain"), I18n.t("coach.what_a_win_the_galaxy"), I18n.t("coach.keep_it_up_champ")][randi() % 3]}
	if out == "defeat":
		return {"mood": "calm", "text": I18n.t("coach.no_worries_the_next_one") % tip()}
	return {"mood": "content", "text": I18n.t("coach.a_draw_we_were_just")}


static func enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not tree.root.has_node("Store"):
		return true
	var p: Variant = Store.p
	return not (p is Dictionary and p.get("oracle", true) == false)


static func set_scene(s: String) -> void:
	scene = s
	if bubble != null and is_instance_valid(bubble):
		bubble.visible = s == "ui" and enabled()


static func set_quiet(key: String, on: bool) -> void:
	if on:
		_quiet[key] = true
	else:
		_quiet.erase(key)


static func _bubble_live() -> bool:
	return bubble != null and is_instance_valid(bubble) and bubble.is_visible_in_tree() and scene == "ui"


static func say(text: String, mood: String = "content", actions: Array = []) -> void:
	if not enabled():
		return
	if _bubble_live():
		bubble.say(text, mood, actions)
	else:
		coach(text, mood)


static func _announce(text: String, mood: String, actions: Array = []) -> void:
	if _bubble_live():
		bubble.say(text, mood, actions)
	else:
		coach(text, mood)


static func react(ev: String, detail: String = "") -> void:
	if not enabled():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(ev, -999.0)) < float(GAPS.get(ev, 3.0)):
		return
	_last[ev] = now
	if ev == "message" and _quiet.has("chat"):
		return
	match ev:
		"goal": coach([I18n.t("coach.gooooal"), I18n.t("coach.what_a_shot"), I18n.t("coach.the_net_is_shaking")][randi() % 3], "excited" if randf() < 0.5 else "laugh")
		"reward": _announce((I18n.t("coach.reward_received_x") % detail) if detail != "" else I18n.t("coach.your_reward_is_here"), "joy")
		"levelup": _announce((I18n.t("coach.level_x_you_re_getting") % detail) if detail != "" else I18n.t("coach.new_level"), "spin")
		"purchase": _announce(I18n.t("coach.congrats_you_ll_shine_with"), "happy")
		"nogems": _announce(I18n.t("coach.not_enough_gems_daily_challenges"), "confused", ["challenges", "tours"])
		"error": _announce(I18n.t("coach.oops_x_don_t_worry") % (detail if detail != "" else I18n.t("coach.something_went_wrong")), "alert")
		"search": coach(I18n.t("coach.finding_you_an_opponent"), "spin")
		"challengeDone": _announce(I18n.t("coach.challenge_x_completed_claim_your") % detail, "excited", ["claim"])
		"message": _announce((I18n.t("coach.new_message_from_x") % detail) if detail != "" else I18n.t("coach.you_have_a_new_message"), "curious", ["messages"])
		"follow": _announce((I18n.t("coach.x_followed_you") % detail) if detail != "" else I18n.t("coach.you_have_a_new_follower"), "curious")
		"tourReady": _announce(I18n.t("coach.your_tournament_match_is_ready"), "alert", ["tours"])


## tiny non-blocking coach toast (top in matches, bottom elsewhere)
static func coach(text: String, mood: String = "idea") -> void:
	if not enabled() or text == "":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _coach_layer == null or not is_instance_valid(_coach_layer):
		_coach_layer = CanvasLayer.new()
		_coach_layer.layer = 95
		tree.root.add_child.call_deferred(_coach_layer)
	for ch in _coach_layer.get_children():
		ch.queue_free()
	var vp := tree.root.get_visible_rect().size
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.layout_direction = I18n.LD
	var st := OUI.sb(Color(8 / 255.0, 14 / 255.0, 40 / 255.0, 0.92), 20, Color(92 / 255.0, 225 / 255.0, 1, 0.45), 1)
	st.content_margin_left = OUI.px(10)
	st.content_margin_right = OUI.px(10)
	st.content_margin_top = OUI.px(6)
	st.content_margin_bottom = OUI.px(6)
	pc.add_theme_stylebox_override("panel", st)
	var h := OUI.hbox(6)
	h.add_child(OUI.img(OUI.oracle_tex(mood), 38))
	h.add_child(OUI.flbl(text, 12, OUI.TEXT, "body", true, 3))
	pc.add_child(h)
	var w := vp.x - OUI.px(48)
	pc.custom_minimum_size.x = w
	pc.position = Vector2(OUI.px(24), OUI.px(108) + OUI.top_inset() if scene == "match" else vp.y - OUI.px(150))
	_ignore_input(pc)   # full-width strip near the bottom: must never swallow taps meant for the screen below
	_coach_layer.add_child(pc)
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.4)
	tw.tween_property(pc, "modulate:a", 0.0, 0.2)
	tw.tween_callback(pc.queue_free)


static func _ignore_input(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_input(c)


# ---------------------------------------------------------------- live social / challenge events
static func start_watch() -> void:
	var u := OUI.uid()
	if u == _watch_uid:
		return
	if _watch_ch != null:
		Supa.remove_channel(_watch_ch)
		_watch_ch = null
	_watch_uid = u
	_completed = {}
	_primed = false
	if u == "":
		return
	_check_challenges()
	var ch: Variant = Supa.channel("oracle:" + u, {})
	ch.on_postgres("UPDATE", "public", "user_challenges", "user_id=eq." + u, func(_r: Variant) -> void: _check_challenges())
	ch.on_postgres("INSERT", "public", "follows", "followee=eq." + u, func(rec: Variant) -> void:
		var nr := _new_rec(rec)
		var p: Variant = OUI.one(await OUI.get_rows("profiles?select=username&id=eq." + OUI.s(nr.get("follower"))))
		react("follow", OUI.s(OUI.d(p).get("username"))))
	ch.on_postgres("INSERT", "public", "messages", "", func(rec: Variant) -> void:
		var m := _new_rec(rec)
		if m.is_empty() or OUI.s(m.get("sender")) == OUI.uid():
			return
		var p: Variant = OUI.one(await OUI.get_rows("profiles?select=username&id=eq." + OUI.s(m.get("sender"))))
		react("message", OUI.s(OUI.d(p).get("username"))))
	ch.subscribe(func(_s: Variant) -> void: pass)
	_watch_ch = ch


static func _new_rec(rec: Variant) -> Dictionary:
	return OUI.rec_new(rec)


static func _check_challenges() -> void:
	var res: Dictionary = await ChallengesScreen.load_challenges()
	if not res.get("ok", false):
		return
	var now := {}
	for c in res.get("list", []):
		if int(c.get("progress", 0)) >= int(c.get("target", 1)) and not bool(c.get("claimed", false)):
			now[str(c.get("def_id"))] = true
	if _primed:
		for c in res.get("list", []):
			var k := str(c.get("def_id"))
			if now.has(k) and not _completed.has(k):
				react("challengeDone", str(c.get("title_fa", "")))
	_completed = now
	_primed = true


# ================================================================ floating bubble (mount from main.gd)
## var b := OracleCoach.make_bubble(); chrome_layer.add_child(b)  — show only while the tab bar is visible.
static func make_bubble() -> Control:
	var b := OracleBubble.new()
	bubble = b
	return b


class Sprite2Fade extends Control:
	## two stacked textures that cross-fade on mood change, with an occasional blink
	var a: TextureRect
	var b: TextureRect
	var front := 0
	var mood := "idle"
	var _blink_t := 4.0
	var blink := true
	func _init(sz: float = 72, m := "idle", bl := true) -> void:
		custom_minimum_size = Vector2(OUI.px(sz), OUI.px(sz))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mood = m
		blink = bl
		a = _mk(m)
		b = _mk(m)
		b.modulate.a = 0.0
		add_child(a)
		add_child(b)
	func _mk(m: String) -> TextureRect:
		var t := TextureRect.new()
		t.texture = _tx(m)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	## the new NEXORA robot mascot replaces the old mood sheet when present; moods then "pop"
	func _tx(m: String) -> Texture2D:
		var t := UD.art("mascot")
		return t if t else OUI.oracle_tex(m)
	func set_mood(m: String) -> void:
		if m == mood:
			return
		mood = m
		if UD.art("mascot"):
			pivot_offset = size * 0.5
			var pw := create_tween()
			pw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.12)
			pw.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			return
		var to: TextureRect = b if front == 0 else a
		var from: TextureRect = a if front == 0 else b
		to.texture = OUI.oracle_tex(m)
		front = 1 - front
		var tw := create_tween().set_parallel()
		tw.tween_property(to, "modulate:a", 1.0, 0.26)
		tw.tween_property(from, "modulate:a", 0.0, 0.26)
	func _process(dt: float) -> void:
		if not blink or UD.art("mascot"):
			return
		_blink_t -= dt
		if _blink_t <= 0:
			_blink_t = 3.5 + randf() * 3.5
			if mood == "idle" or mood == "neutral":
				var cur: TextureRect = a if front == 0 else b
				cur.texture = OUI.oracle_tex("content")
				get_tree().create_timer(0.17).timeout.connect(func() -> void:
					if is_instance_valid(cur):
						cur.texture = OUI.oracle_tex(mood))


class OracleBubble extends Control:
	const SPR := 72.0
	var sprite: Sprite2Fade
	var holder: Control
	var speech: PanelContainer = null
	var pad: ColorRect
	var sleeping := false
	var idle_t := 45.0
	var hide_t := 0.0
	var dragging := false
	var drag_from := Vector2.ZERO
	var press_pos := Vector2.ZERO
	var moved := false
	var side_right := false
	var t := 0.0
	var tour_step := -1
	var tour_node: Control = null
	var _greeted := false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout_direction = I18n.LD
		holder = Control.new()
		holder.custom_minimum_size = Vector2(OUI.px(SPR), OUI.px(SPR + 10))
		holder.size = holder.custom_minimum_size
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(holder)
		pad = ColorRect.new()
		pad.color = Color(OUI.CYAN, 0.5)
		pad.size = Vector2(OUI.px(SPR - 16), OUI.px(10))
		pad.position = Vector2(OUI.px(8), OUI.px(SPR))
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pad)
		sprite = Sprite2Fade.new(SPR, "idle", true)
		holder.add_child(sprite)
		holder.gui_input.connect(_on_input)
		resized.connect(_clamp)
		_place_default.call_deferred()
		OUI.boot()
		OUI.ebus().profile_changed.connect(func(_p: Dictionary) -> void: OracleCoach.start_watch())
		OracleCoach.start_watch()
		visible = OracleCoach.enabled() and OracleCoach.scene == "ui"
		get_tree().create_timer(2.6).timeout.connect(_greet)

	func _place_default() -> void:
		holder.position = Vector2(OUI.px(12), _max_y())

	func _min_y() -> float:
		return OUI.px(120) + OUI.top_inset()

	func _max_y() -> float:
		return size.y - OUI.px(80 + 20) - OUI.px(SPR)

	func _clamp() -> void:
		if holder:
			holder.position.y = clampf(holder.position.y, _min_y(), maxf(_min_y(), _max_y()))

	func _greet() -> void:
		if _greeted or not is_instance_valid(self) or not OracleCoach.enabled():
			return
		_greeted = true
		var p: Dictionary = Store.p if Store.p is Dictionary else {}
		if not bool(p.get("oracleTour", false)):
			_tour(0)
			return
		var h := Time.get_datetime_dict_from_system()["hour"] as int
		var g := I18n.t("coach.good_morning") if (h >= 5 and h < 12) else (I18n.t("coach.good_afternoon") if h < 17 else (I18n.t("coach.good_evening") if h < 21 else I18n.t("coach.good_night")))
		var name := OUI.s(OUI.profile.get("username", ""))
		if name == "":
			name = str(p.get("name", ""))
		say(I18n.t("coach.x_x_ready_for_a") % [g, name], "hello" if (h >= 5 and h < 12) else "wave", ["quick", "challenges"])

	func _process(dt: float) -> void:
		t += dt
		sprite.position.y = sin(t * TAU / 4.4) * OUI.px(4)
		pad.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * TAU / 3.2))
		visible = OracleCoach.enabled() and OracleCoach.scene == "ui"
		if not sleeping and speech == null and tour_step < 0:
			idle_t -= dt
			if idle_t <= 0:
				sleeping = true
				sprite.set_mood("sleep")
		if speech != null:
			hide_t -= dt
			if hide_t <= 0:
				_close_speech()

	func _input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch or ev is InputEventMouseButton:
			idle_t = 45.0

	func _on_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				dragging = true
				moved = false
				press_pos = ev.global_position
				drag_from = holder.position
			else:
				dragging = false
				if moved:
					var right := holder.position.x + OUI.px(SPR) / 2.0 > size.x / 2.0
					side_right = right
					var tw := create_tween()
					tw.tween_property(holder, "position:x", size.x - OUI.px(SPR) - OUI.px(12) if right else float(OUI.px(12)), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					if speech:
						_place_speech()
				else:
					_tap()
			accept_event()
		elif ev is InputEventMouseMotion and dragging:
			var dv: Vector2 = ev.global_position - press_pos
			if dv.length() > OUI.px(8):
				moved = true
			if moved:
				holder.position = Vector2(drag_from.x + dv.x, clampf(drag_from.y + dv.y, _min_y(), maxf(_min_y(), _max_y())))
				if speech:
					_place_speech()
			accept_event()

	func _tap() -> void:
		OUI.sfx("ui")
		if sleeping:
			sleeping = false
			sprite.set_mood("wave")
			say(I18n.t("coach.i_m_awake_how_can"), "wave", OracleKB.SUGGESTIONS.slice(0, 3))
		else:
			_close_speech()
			Nav.go("oracle", {})

	func say(text: String, mood: String = "content", actions: Array = []) -> void:
		sleeping = false
		idle_t = 45.0
		sprite.set_mood(mood)
		_close_speech()
		speech = PanelContainer.new()
		speech.layout_direction = I18n.LD
		var st := OUI.sb(Color(10 / 255.0, 18 / 255.0, 52 / 255.0, 0.97), 18, Color(92 / 255.0, 225 / 255.0, 1, 0.55), 1, 12)
		st.shadow_color = Color(OUI.CYAN, 0.35)
		st.shadow_size = OUI.px(8)
		speech.add_theme_stylebox_override("panel", st)
		# wide bubble: up to 70% of the screen; never derived from a 0-size (not yet laid out) parent
		var vw := size.x if size.x > 100 else get_viewport_rect().size.x
		var w := minf(vw * 0.7, vw - OUI.px(SPR + 24))
		var v := OUI.vbox(6)
		var top := OUI.hbox(4)
		top.layout_direction = Control.LAYOUT_DIRECTION_LTR
		top.add_child(OUI.pill("✕", func() -> void: _close_speech(), OUI.DIM, 28, 28))
		top.add_child(OUI.expand())
		v.add_child(top)
		var tl := OUI.lbl(text, 15, OUI.TEXT, "body", I18n.AR, true, 0)
		var inner := w - OUI.px(24)
		tl.custom_minimum_size.x = clampf(UD.text_w(tl) + 6.0, minf(OUI.px(140), inner), inner)
		tl.visible_ratio = 0.0
		v.add_child(tl)
		var tw := tl.create_tween()
		tw.tween_property(tl, "visible_ratio", 1.0, clampf(text.length() * 0.009, 0.2, 2.5))
		if not actions.is_empty():
			var fl := HFlowContainer.new()
			fl.add_theme_constant_override("h_separation", OUI.px(6))
			fl.add_theme_constant_override("v_separation", OUI.px(6))
			for aid in actions:
				var a_id := str(aid)
				fl.add_child(OUI.pill(str(OracleKB.ACTION_LABEL.get(a_id, a_id)), func() -> void:
					_close_speech()
					var r: Dictionary = await OracleScreen.run_action(a_id)
					if not r.is_empty() and is_instance_valid(self):
						say(str(r.get("text", "")), str(r.get("mood", "content")), r.get("actions", [])), OUI.CYAN, 0, 34))
			v.add_child(fl)
		speech.add_child(v)
		# the bubble is decoration over the menu (up to 70% wide, near the bottom): only its buttons take input,
		# everything else lets taps through to the grid/list below (user: lower shop/team items did not respond)
		_passthru(speech)
		add_child(speech)
		hide_t = minf(14.0, 4.5 + text.length() * 0.055)
		_place_speech.call_deferred()
		OUI.fade_in(speech, 0.18)

	func _passthru(n: Node) -> void:
		if n is Control and not (n is BaseButton):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in n.get_children():
			_passthru(c)

	func _place_speech() -> void:
		if speech == null or not is_instance_valid(speech):
			return
		var sz := speech.get_combined_minimum_size()
		var x := holder.position.x + OUI.px(SPR - 14) if not side_right else holder.position.x - sz.x + OUI.px(14)
		x = clampf(x, OUI.px(8), size.x - sz.x - OUI.px(8))
		speech.position = Vector2(x, maxf(OUI.px(60), holder.position.y - sz.y + OUI.px(6)))

	func _close_speech() -> void:
		if speech and is_instance_valid(speech):
			speech.queue_free()
		speech = null
		if not sleeping:
			sprite.set_mood("idle")

	# ------------------------------------------------------------ onboarding tour
	func _tour(step: int) -> void:
		tour_step = step
		if tour_node and is_instance_valid(tour_node):
			tour_node.queue_free()
		if step < 0 or step >= OracleCoach.TOUR.size():
			return
		var s: Dictionary = OracleCoach.TOUR[step]
		if str(s["tab"]) != "":
			Nav.go(str(s["tab"]), {})
		OUI.sfx("ui")
		var root := Control.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_STOP
		var veil := ColorRect.new()
		veil.color = Color(1 / 255.0, 3 / 255.0, 12 / 255.0, 0.72)
		veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(veil)
		var idx := int(s["idx"])
		var tab_h := OUI.px(72)
		if idx >= 0:
			var bar_w := minf(size.x - OUI.px(20), OUI.px(520))
			var cw := bar_w / 5.0
			var cx := (size.x + bar_w) / 2.0 - cw * (idx + 0.5)
			var cy := size.y - OUI.px(10) - tab_h / 2.0
			var ring := Ring.new()
			ring.size = Vector2(OUI.px(80), OUI.px(80))
			ring.position = Vector2(cx, cy) - ring.size / 2.0
			root.add_child(ring)
		var card := PanelContainer.new()
		card.layout_direction = I18n.LD
		card.add_theme_stylebox_override("panel", OUI.sb(Color(12 / 255.0, 20 / 255.0, 58 / 255.0, 0.98), 24, Color(92 / 255.0, 225 / 255.0, 1, 0.5), 1, 14))
		var v := OUI.vbox(10)
		var h := OUI.hbox(8)
		h.add_child(Sprite2Fade.new(92, str(s["mood"]), false))
		var tl := OUI.flbl(str(s["text"]), 13, OUI.TEXT, "body", true, 0)
		tl.visible_ratio = 0.0
		tl.create_tween().tween_property(tl, "visible_ratio", 1.0, 1.0)
		h.add_child(tl)
		v.add_child(h)
		var bh := OUI.hbox(8)
		var last := step >= OracleCoach.TOUR.size() - 1
		var nb := OUI.btn(I18n.t("coach.start") if last else I18n.t("coach.next"), func() -> void:
			if last:
				_end_tour()
			else:
				_tour(step + 1), "primary", true)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(nb)
		if not last:
			var sk := OUI.btn(I18n.t("coach.skip"), _end_tour, "dark", true)
			sk.custom_minimum_size.x = OUI.px(110)
			bh.add_child(sk)
		v.add_child(bh)
		var dots := OUI.hbox(6, BoxContainer.ALIGNMENT_CENTER)
		for k in OracleCoach.TOUR.size():
			var dd := ColorRect.new()
			dd.color = OUI.CYAN if k == step else Color(1, 1, 1, 0.25)
			dd.custom_minimum_size = Vector2(OUI.px(16 if k == step else 6), OUI.px(6))
			dots.add_child(dd)
		v.add_child(dots)
		card.add_child(v)
		card.custom_minimum_size.x = size.x - OUI.px(32)
		root.add_child(card)
		add_child(root)
		tour_node = root
		await get_tree().process_frame
		if is_instance_valid(card):
			card.position = Vector2(OUI.px(16), size.y - tab_h - OUI.px(50) - card.size.y)
		OUI.fade_in(root, 0.25)

	func _end_tour() -> void:
		_tour(-1)
		tour_step = -1
		Store.set_p({"oracleTour": true})
		say(I18n.t("coach.tap_me_whenever_you_have_2"), "wave", ["quick"])


class Ring extends Control:
	var t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
	func _draw() -> void:
		var k := 0.5 + 0.5 * sin(t * TAU / 1.4)
		var r := size.x * 0.5 * (1.0 + k * 0.12)
		draw_circle(size * 0.5, r, Color(79 / 255.0, 227 / 255.0, 1, 0.12))
		draw_arc(size * 0.5, r, 0, TAU, 48, Color(OUI.CYAN, 0.6 + k * 0.4), 4.0, true)
