extends MarginContainer
## Chest opening (RN ChestOpen, shown by Nav.open_chest in a modal): chest shakes, flash +
## rays spin up, prize pops with a spring, rewards line, "عالیه!".

const RC := [Color("#8ea3d6"), Color("#4fe3ff"), Color("#b46bff"), Color("#ffd257")]
var prize := {}
var premium := false
var stage: Control
var chest: TextureRect
var rays: TextureRect
var prize_box: Control
var info: VBoxContainer
var opening_l: Label

func setup(params: Dictionary) -> void:
	prize = params.get("prize", {"coins": 0, "gems": 0})
	premium = bool(params.get("premium", false))

func modal_accent() -> Color:
	return NX.GOLD if premium else NX.CYAN

func _ready() -> void:
	var v := Kit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		add_theme_constant_override(k, 58)
	add_child(v)
	var t := Kit.title(I18n.t("chest.royal_chest") if premium else I18n.t("chest.free_chest"), 52)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	stage = Kit.stage(800, 572)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rays = Kit.img(UD.ui2("ring"), 572)
	rays.modulate.a = 0.3
	Kit.put(stage, rays, 400, 286)
	Kit.spin(rays, 9.0)
	var pul := Kit.pulse(364, Color(1, 0.82, 0.34, 0.5) if premium else Color(0.31, 0.89, 1.0, 0.5))
	Kit.put(stage, pul, 400, 286)
	chest = Kit.img(UD.ui2("x_chest" if premium else "c_chest"), 442)
	Kit.put(stage, chest, 400, 286)
	prize_box = Control.new()
	prize_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prize_box.custom_minimum_size = Vector2(400, 400)
	Kit.put(stage, prize_box, 400, 286)
	prize_box.modulate.a = 0.0
	var it = prize.get("item", null)
	if it is Dictionary:
		var fld: bool = it.get("kind", "") == "field"
		var im := Kit.img(UD.item_tex(it), Vector2(286, 390) if fld else Vector2(390, 390), "cover" if fld else "contain")
		Kit.put(prize_box, im, 200, 200)
	else:
		Kit.put(prize_box, Kit.img(UD.ui2("x_coins"), 390), 200, 200)
	v.add_child(Kit.center(stage))
	opening_l = Kit.label(I18n.t("chest.opening"), 36, NX.DIM)
	opening_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(opening_l)
	info = Kit.vbox(8)
	info.modulate.a = 0.0
	if it is Dictionary:
		var n := Kit.title(str(it["name"]), 47, RC[clampi(int(it.get("rar", 1)), 0, 3)])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(n)
	var parts := []
	if it is Dictionary: parts.append(I18n.t("chest.new_item_unlocked"))
	if int(prize.get("coins", 0)) > 0: parts.append(I18n.t("nav.x_coins") % NX.fa(prize["coins"]))
	if int(prize.get("gems", 0)) > 0: parts.append(I18n.t("chest.x_gems") % NX.fa(prize["gems"]))
	var l := Kit.para(" · ".join(parts), 36, NX.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	info.add_child(l)
	info.add_child(Kit.gap(20))
	info.add_child(Kit.button(I18n.t("chest.awesome"), func(): Nav.close_modal(), "gold"))
	info.visible = false
	v.add_child(info)
	# shake → open
	chest.pivot_offset = chest.size * 0.5
	var sh := create_tween()
	for i in 6:
		sh.tween_property(chest, "rotation", deg_to_rad(8), 0.07)
		sh.parallel().tween_property(chest, "scale", Vector2(1.05, 1.05), 0.07)
		sh.tween_property(chest, "rotation", deg_to_rad(-8), 0.07)
		sh.parallel().tween_property(chest, "scale", Vector2(1.0, 1.0), 0.07)
	sh.tween_property(chest, "rotation", 0.0, 0.06)
	get_tree().create_timer(1.0).timeout.connect(_open)

func _open() -> void:
	if not is_inside_tree():
		return
	UD.sfx("ui")
	UD.haptic("heavy")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(chest, "scale", Vector2(1.4, 1.4), 0.2)
	tw.tween_property(chest, "modulate:a", 0.0, 0.2)
	tw.tween_property(rays, "modulate", Color(1.6, 1.5, 1.2, 0.85), 0.3)
	prize_box.scale = Vector2(0.3, 0.3)
	prize_box.position.y += 104
	tw.tween_property(prize_box, "modulate:a", 1.0, 0.3)
	tw.tween_property(prize_box, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(prize_box, "position:y", prize_box.position.y - 104, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	opening_l.visible = false
	info.visible = true
	tw.tween_property(info, "modulate:a", 1.0, 0.4)
