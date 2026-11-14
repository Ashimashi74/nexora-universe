class_name NxLoadout
extends VBoxContainer
## Formation · Ball · Disc picker (flat v3), used before kickoff (setup sheet) and in a match (HUD button sheet).
## Shows only what the player owns. Every pick is saved to the Store profile (form / ball / team) and reported
## through on_change(kind: "form"|"ball"|"team", value) so a running match can apply it at a safe moment.
##   var lo := NxLoadout.new(func(k, v): ...)   # add to a sheet or a VBox

var on_change: Callable
var _rows := {}       # kind -> Array[[Control, value]]
var _cur := {}        # kind -> value

func _init(cb := Callable()) -> void:
	on_change = cb
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	var p := UD.p()
	_cur = {"form": int(p.get("form", 0)), "ball": int(p.get("ball", 0)), "team": str(p.get("team", "club0"))}
	# formation: text chips
	add_child(_title(I18n.t("kb.formation")))
	var fr := _hrow()
	var forms := UD.forms()
	for i in forms.size():
		var nm := FormationPicker.t("form.n%d" % i, str(forms[i][0]))
		fr[1].add_child(_chip(nm, "form", i))
	add_child(fr[0])
	# ball: owned balls
	add_child(_title(I18n.t("home.ball")))
	var br := _hrow()
	var owned_b: Array = p.get("ownedBalls", [0])
	for i in UD.ball_names().size():
		if i != 0 and not UD._has_num(owned_b, i) and i != int(_cur["ball"]):
			continue
		br[1].add_child(_thumb(UD.ball_tex(i), "ball", i))
	add_child(br[0])
	# disc: owned team discs
	add_child(_title(I18n.t("home.disc")))
	var dr := _hrow()
	for t in UD.teams():
		var id: String = str(t["id"])
		if id != str(_cur["team"]) and not UD.disc_owned(id):
			continue
		dr[1].add_child(_thumb(UD.team_tex(t), "team", id))
	add_child(dr[0])
	_refresh()

func _title(t: String) -> Label:
	var l := Kit.label(t, 32, NX.DIM, true)
	l.horizontal_alignment = I18n.AR
	return l

func _hrow() -> Array:
	var hs := Kit.hscroll(14)
	var sc: ScrollContainer = hs[0]
	sc.custom_minimum_size.y = 128
	return hs

func _chip(text: String, kind: String, val) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 104)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Kit.label(text, 30, NX.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(Kit.margin(l, 28, 0, 28, 0))
	_reg(pc, kind, val)
	return pc

func _thumb(tex: Texture2D, kind: String, val) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(116, 116)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var im := Kit.img(tex, 92)
	pc.add_child(Kit.center(im))
	_reg(pc, kind, val)
	return pc

func _reg(pc: Control, kind: String, val) -> void:
	if not _rows.has(kind):
		_rows[kind] = []
	_rows[kind].append([pc, val])
	Kit.tap(pc, func(): _pick(kind, val), 0.94)

func _pick(kind: String, val) -> void:
	if _cur.get(kind) == val:
		return
	_cur[kind] = val
	UD.set_p({kind: val})
	_refresh()
	if on_change.is_valid():
		on_change.call(kind, val)

func _refresh() -> void:
	for kind in _rows:
		for e in _rows[kind]:
			var on: bool = e[1] == _cur.get(kind)
			var sb := NX.box(Color(NX.ACCENT, 0.16) if on else NX.SURF2, 24, 3 if on else 0, NX.ACCENT if on else Color.TRANSPARENT)
			(e[0] as Control).add_theme_stylebox_override("panel", sb)
