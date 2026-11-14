class_name NetImg
extends RefCounted
## Network image cache (avatar / chat photo URLs → ImageTexture), lazy + de-duplicated + LRU,
## plus small reusable online widgets: Avatar, PingBadge, VoiceBar, ChatPanel (room chat over RoomLink).
## Owner: OUI worker.

const MAX_ITEMS := 220
const MAX_PARALLEL := 4

static var _cache: Dictionary = {}       # url -> Texture2D
static var _order: Array[String] = []    # LRU (oldest first)
static var _waiting: Dictionary = {}     # url -> Array[Callable]
static var _queue: Array[String] = []
static var _active := 0
static var _failed: Dictionary = {}      # url -> unix time of failure (retry after 30 s)


static func has(url: String) -> bool:
	return _cache.has(url)


static func get_tex(url: String) -> Texture2D:
	if _cache.has(url):
		_touch(url)
		return _cache[url]
	return null


static func put(url: String, t: Texture2D) -> void:
	if url == "" or t == null:
		return
	_cache[url] = t
	_touch(url)
	_trim()


## cb.call(tex: Texture2D or null). Calls immediately when cached.
static func fetch(url: String, cb: Callable) -> void:
	if url == "":
		cb.call(null)
		return
	if _cache.has(url):
		_touch(url)
		cb.call(_cache[url])
		return
	if _failed.has(url) and Time.get_unix_time_from_system() - float(_failed[url]) < 30.0:
		cb.call(null)
		return
	if _waiting.has(url):
		(_waiting[url] as Array).append(cb)
		return
	_waiting[url] = [cb]
	_queue.append(url)
	_pump()


static func _touch(url: String) -> void:
	var k := _order.find(url)
	if k >= 0:
		_order.remove_at(k)
	_order.append(url)


static func _trim() -> void:
	while _order.size() > MAX_ITEMS:
		var old: String = _order.pop_front()
		_cache.erase(old)


static func _pump() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	while _active < MAX_PARALLEL and not _queue.is_empty():
		var url: String = _queue.pop_front()
		_active += 1
		_download(tree, url)


static func _download(tree: SceneTree, url: String) -> void:
	var hr := HTTPRequest.new()
	hr.timeout = 25
	hr.use_threads = true
	tree.root.add_child.call_deferred(hr)
	await hr.ready
	var e := hr.request(url)
	var t: Texture2D = null
	if e == OK:
		var res: Array = await hr.request_completed
		if res[0] == HTTPRequest.RESULT_SUCCESS and int(res[1]) < 300:
			t = decode(res[3])
	hr.queue_free()
	_active -= 1
	if t:
		put(url, t)
	else:
		_failed[url] = Time.get_unix_time_from_system()
	var cbs: Array = _waiting.get(url, [])
	_waiting.erase(url)
	for cb in cbs:
		if (cb as Callable).is_valid():
			(cb as Callable).call(t)
	_pump()


static func decode(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 12:
		return null
	var im := Image.new()
	var e := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		e = im.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		e = im.load_jpg_from_buffer(bytes)
	elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		e = im.load_webp_from_buffer(bytes)
	if e != OK:
		return null
	# keep memory sane for big chat photos
	var m := maxi(im.get_width(), im.get_height())
	if m > 1024:
		var f := 1024.0 / m
		im.resize(maxi(1, int(im.get_width() * f)), maxi(1, int(im.get_height() * f)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(im)


# ============================================================================ Avatar
## round avatar: uploaded photo (cover) or team-skin disc (contain), coloured ring, dimmed when offline.
static func avatar(av: Variant, url: Variant, size: float = 40, ring: Color = OUI.CYAN, dim := false) -> Avatar:
	var a := Avatar.new()
	a.custom_minimum_size = Vector2(OUI.px(size), OUI.px(size))
	a.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	a.set_data(av, url, ring, dim)
	return a


class Avatar extends Control:
	var key := ""
	var url := ""
	var ring := Color("#4fe3ff")
	var dim := false
	var tex: Texture2D = null
	var is_photo := false
	var dot: Variant = null   # Color for online dot (null = none)
	var _pts := PackedVector2Array()
	var _uvs := PackedVector2Array()
	var _sz := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_data(av: Variant, u: Variant, r: Color = Color("#4fe3ff"), dm := false) -> void:
		key = "" if av == null else str(av)
		url = "" if u == null else str(u)
		ring = r
		dim = dm
		modulate.a = 0.5 if dim else 1.0
		if url != "":
			var cached := NetImg.get_tex(url)
			if cached:
				_set_tex(cached, true)
			else:
				_set_tex(OUI.disc_tex(key), false)
				var want := url
				NetImg.fetch(url, func(t: Texture2D) -> void:
					if is_instance_valid(self) and url == want and t:
						_set_tex(t, true))
		else:
			_set_tex(OUI.disc_tex(key), false)
		queue_redraw()

	func set_ring(r: Color) -> void:
		ring = r
		queue_redraw()

	func _set_tex(t: Texture2D, photo: bool) -> void:
		tex = t
		is_photo = photo
		_sz = Vector2.ZERO
		queue_redraw()

	func _build(rad: float, c: Vector2) -> void:
		_pts.clear()
		_uvs.clear()
		var n := 36
		var tw := 1.0
		var th := 1.0
		if tex:
			tw = float(tex.get_width())
			th = float(tex.get_height())
		# cover: crop the short side to a square
		var ux := 1.0
		var uy := 1.0
		if is_photo:
			if tw > th:
				ux = th / tw
			else:
				uy = tw / th
		for k in n:
			var ang := TAU * k / n
			var v := Vector2(cos(ang), sin(ang))
			_pts.append(c + v * rad)
			_uvs.append(Vector2(0.5 + v.x * 0.5 * ux, 0.5 + v.y * 0.5 * uy))
		_sz = size

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("#050816"))
		var inner := r - maxf(2.0, r * 0.08) - 1.0
		if tex:
			if is_photo:
				if _sz != size:
					_build(inner, c)
				draw_colored_polygon(_pts, Color.WHITE, _uvs, tex)
			else:
				var s2 := inner * 2.0
				draw_texture_rect(tex, Rect2(c - Vector2(s2, s2) * 0.5, Vector2(s2, s2)), false)
		draw_arc(c, r - maxf(1.0, r * 0.04), 0, TAU, 48, ring, maxf(2.0, r * 0.08), true)
		if dot is Color:
			var dr := maxf(5.0, r * 0.22)
			var dp := Vector2(c.x - r * 0.72, c.y + r * 0.72)
			draw_circle(dp, dr + 2, Color("#0b1236"))
			draw_circle(dp, dr, dot)


# ============================================================================ PingBadge
## green < 80 ms, yellow < 150 ms, red otherwise (reads link.state.rtt)
class PingBadge extends PanelContainer:
	var link: Variant = null
	var _l: Label
	var _dot: ColorRect
	func _init(l: Variant = null) -> void:
		link = l
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = OUI.px(24)
		var h := OUI.hbox(5)
		h.layout_direction = Control.LAYOUT_DIRECTION_LTR
		add_child(h)
		_dot = ColorRect.new()
		_dot.custom_minimum_size = Vector2(OUI.px(8), OUI.px(8))
		_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_dot)
		_l = OUI.lbl("— ms", 10, OUI.DIM, "head", I18n.AL)
		h.add_child(_l)
		if link != null and link.has_signal("changed"):
			link.changed.connect(_upd)
		_upd()
	func _upd(_x: Variant = null) -> void:
		if link == null or not is_instance_valid(_l):
			return
		var st: Dictionary = OUI.d(link.state)
		var r: Variant = st.get("rtt")
		var col: Color = OUI.DIM
		if r != null:
			var v := float(r)
			col = OUI.GREEN if v < 80 else (OUI.GOLD if v < 150 else OUI.RED)
		_l.text = "— ms" if r == null else "%d ms" % int(r)
		_l.add_theme_color_override("font_color", col)
		_dot.color = col
		var stb := OUI.sb(Color(6 / 255.0, 10 / 255.0, 30 / 255.0, 0.85), 12, Color(col, 0.53), 1)
		stb.content_margin_left = OUI.px(8)
		stb.content_margin_right = OUI.px(8)
		add_theme_stylebox_override("panel", stb)


# ============================================================================ VoiceBar
## Voice controls (RN VoiceBar) over the Voice autoload. room_id = room to join.
class VoiceBar extends HBoxContainer:
	var room_id := ""
	var enabled := true
	var compact := false
	func _init(rid: String = "", en := true, cmp := false) -> void:
		room_id = rid
		enabled = en
		compact = cmp
	func _ready() -> void:
		add_theme_constant_override("separation", OUI.px(8))
		custom_minimum_size.y = OUI.px(44)
		Voice.state_changed.connect(_on_state)
		_build()
	func _on_state(_s: Variant = null) -> void:
		_build()
	func _vstate() -> Dictionary:
		var v: Variant = Voice.state
		return v if v is Dictionary else {}
	func _build() -> void:
		OUI.clear(self)
		if not enabled:
			if not compact:
				add_child(OUI.flbl(I18n.t("ui_bits.voice_chat_is_off_for"), OUI.TS_CAP, OUI.DIM2))
			return
		if not Voice.supported():
			var off := OUI.pill("🔇", Callable(), OUI.DIM2, 44, 44)
			off.disabled = true
			add_child(off)
			if not compact:
				var why: String = Voice.support_reason()
				add_child(OUI.flbl(why if why != "" else I18n.t("ui_bits.voice_chat_only_works_in"), OUI.TS_CAP, OUI.DIM, "body", true, 2))
			return
		var v := _vstate()
		var status := str(v.get("status", "off"))
		if status == "on":
			add_child(OUI.pill("✕", func() -> void: Voice.leave(), OUI.RED, 44, 44))
			var spk := bool(v.get("speaker", true))
			add_child(OUI.pill("🔊" if spk else "🔇", func() -> void: Voice.set_speaker(not spk), OUI.CYAN if spk else OUI.DIM2, 44, 44))
			var pub := bool(v.get("can_publish", true))
			var mic := bool(v.get("mic", false))
			if pub:
				add_child(OUI.pill("🎙" if mic else "🚫", func() -> void: Voice.set_mic(not mic), OUI.GREEN if mic else OUI.DIM2, 44, 44))
			if not compact:
				add_child(OUI.flbl((I18n.t("ui_bits.mic_on") if mic else I18n.t("ui_bits.mic_off")) if pub else I18n.t("ui_bits.listener_only"), OUI.TS_CAP, OUI.DIM))
		else:
			var connecting := status == "connecting"
			var jb := OUI.pill("…" if connecting else ("🎙" if compact else I18n.t("ui_bits.join_voice_chat")), func() -> void: Voice.join(room_id), OUI.CYAN, 44, 44)
			jb.disabled = connecting
			add_child(jb)
			if not compact and status == "error" and str(v.get("error", "")) != "":
				add_child(OUI.flbl(str(v.get("error")), OUI.TS_CAP, OUI.ORANGE, "body", true, 2))


# ============================================================================ ChatPanel
## Room chat over RoomLink broadcast 'chat' (RN ChatPanel). Newest at the bottom, max 80 kept by the link.
class ChatPanel extends VBoxContainer:
	var link: Variant = null
	var compact := false
	var _list: VBoxContainer
	var _sc: ScrollContainer
	var _in: LineEdit
	var _shown := 0
	var _me := ""
	var _mic: Button
	var _voice_row: Control
	func _init(l: Variant = null, cmp := false) -> void:
		link = l
		compact = cmp
	func _ready() -> void:
		layout_direction = I18n.LD
		add_theme_constant_override("separation", 0)
		_sc = OUI.scroll()
		_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_sc)
		_list = OUI.vbox(2)
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sc.add_child(OUI.margin(_list, 8, 8, 8, 8))
		# voice status strip (separate from text messages)
		_voice_row = OUI.vbox(0)
		_voice_row.visible = false
		add_child(_voice_row)
		# input row: mic + small text field + send (simple, compact)
		var row := OUI.hbox(8)
		row.layout_direction = Control.LAYOUT_DIRECTION_LTR
		_mic = OUI.pill("🎙", _toggle_voice, OUI.CYAN, 44, 44)
		row.add_child(_mic)
		_in = OUI.line_edit(I18n.t("ui_bits.message"), 200, false, false, 44)
		_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_in.text_submitted.connect(func(_t: String) -> void: _send())
		row.add_child(_in)
		var send := OUI.pill("➤", _send, OUI.CYAN, 44, 44)
		row.add_child(send)
		add_child(OUI.margin(row, 8, 8, 8, 8))
		if link != null:
			_me = str(link.me)
			link.chat_open = true
			link.mark_read()
			if link.has_signal("changed"):
				link.changed.connect(_sync)
			Voice.state_changed.connect(_on_voice)
			_on_voice()
		_sync()
	func _exit_tree() -> void:
		if link != null:
			link.chat_open = false
		Voice.state_changed.disconnect(_on_voice)
	# ---- separate voice controls (join/leave the room's voice chat from the chat panel)
	func _room_id() -> String:
		if link == null:
			return ""
		var st := OUI.d(link.state)
		return OUI.s(OUI.d(st.get("room")).get("id"))
	func _on_voice(_s: Variant = null) -> void:
		if _mic == null or not is_instance_valid(_mic):
			return
		var v: Variant = Voice.state
		var st: Dictionary = v if v is Dictionary else {}
		var status := str(st.get("status", "off"))
		var on := status == "on"
		var connecting := status == "connecting"
		if not Voice.supported():
			_mic.text = "🚫"
			_mic.disabled = true
			_mic.add_theme_color_override("font_color", OUI.DIM2)
			_voice_row.visible = false
			return
		_mic.text = "🎙" if not on else "🔊"
		_mic.disabled = connecting
		_mic.add_theme_color_override("font_color", OUI.GREEN if on else (OUI.CYAN if not connecting else OUI.DIM))
		_voice_row.visible = on
		if on:
			OUI.clear(_voice_row)
			var mic := bool(st.get("mic", false))
			var pub := bool(st.get("can_publish", true))
			var h := OUI.hbox(8)
			h.layout_direction = Control.LAYOUT_DIRECTION_LTR
			h.add_child(OUI.lbl(I18n.t("ui_bits.voice_chat_on"), OUI.TS_CAP, OUI.GREEN, "bold"))
			if pub:
				h.add_child(OUI.pill("🎙" if mic else "🚫", func() -> void: Voice.set_mic(not mic), OUI.GREEN if mic else OUI.DIM2, 44, 44))
			h.add_child(OUI.pill(I18n.t("ui_bits.leave_voice"), func() -> void: Voice.leave(), OUI.RED, 44, 44))
			_voice_row.add_child(OUI.margin(h, 8, 2, 8, 0))
	func _toggle_voice() -> void:
		if not Voice.supported():
			return
		var v: Variant = Voice.state
		var st: Dictionary = v if v is Dictionary else {}
		if str(st.get("status", "off")) == "on":
			Voice.leave()
		else:
			var rid := _room_id()
			if rid != "":
				Voice.join(rid)
	func _send() -> void:
		var t := _in.text.strip_edges()
		if t == "" or link == null:
			return
		link.send_chat(t)
		_in.text = ""
		OUI.buzz("light")
	func _sync(_x: Variant = null) -> void:
		if link == null or not is_instance_valid(_list):
			return
		var chat: Array = OUI.a(OUI.d(link.state).get("chat"))
		if chat.size() < _shown:
			OUI.clear(_list)
			_shown = 0
		if chat.is_empty() and _list.get_child_count() == 0:
			_list.add_child(OUI.lbl(I18n.t("ui_bits.no_messages_yet_say_hi"), OUI.TS_SMALL, OUI.DIM2, "body", HORIZONTAL_ALIGNMENT_CENTER))
			_list.get_child(0).set_meta("placeholder", true)
			return
		if _list.get_child_count() > 0 and _list.get_child(0).has_meta("placeholder"):
			OUI.clear(_list)
		# chat is capped at 80 by the link, so a rebuild when it rotates is cheap
		if chat.size() == 80 and _shown == 80:
			OUI.clear(_list)
			_shown = 0
		for k in range(_shown, chat.size()):
			_list.add_child(_bubble(OUI.d(chat[k])))
		_shown = chat.size()
		link.mark_read()
		_scroll_end.call_deferred()
	func _scroll_end() -> void:
		if is_instance_valid(_sc):
			await get_tree().process_frame
			if is_instance_valid(_sc):
				_sc.scroll_vertical = int(_sc.get_v_scroll_bar().max_value)
	func _bubble(c: Dictionary) -> Control:
		var mine := str(c.get("uid", "")) == _me
		var outer := HBoxContainer.new()
		outer.layout_direction = Control.LAYOUT_DIRECTION_LTR
		outer.alignment = BoxContainer.ALIGNMENT_BEGIN if mine else BoxContainer.ALIGNMENT_END
		var pc := PanelContainer.new()
		var st := OUI.sb(Color(79 / 255.0, 227 / 255.0, 1, 0.16) if mine else Color(20 / 255.0, 30 / 255.0, 70 / 255.0, 0.9), 14, Color(79 / 255.0, 227 / 255.0, 1, 0.35) if mine else OUI.LINE, 1)
		st.content_margin_left = OUI.px(12)
		st.content_margin_right = OUI.px(12)
		st.content_margin_top = OUI.px(4 if compact else 6)
		st.content_margin_bottom = OUI.px(4 if compact else 6)
		if mine:
			st.corner_radius_bottom_left = OUI.px(4)
		else:
			st.corner_radius_bottom_right = OUI.px(4)
		pc.add_theme_stylebox_override("panel", st)
		var v := OUI.vbox(0)
		if not mine:
			v.add_child(OUI.lbl(str(c.get("name", "")), OUI.TS_TINY, OUI.CYAN, "bold"))
		var t := OUI.lbl(str(c.get("text", "")), OUI.TS_SMALL if compact else 13, OUI.TEXT, "body", I18n.AR, true, 0)
		t.custom_minimum_size.x = OUI.px(40)
		v.add_child(t)
		pc.add_child(v)
		pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if mine else Control.SIZE_SHRINK_END
		var w := OUI.px(300)
		t.custom_minimum_size.x = mini(w, maxi(OUI.px(40), int(t.get_theme_font("font").get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.get_theme_font_size("font_size")).x) + 4))
		outer.add_child(pc)
		return outer
