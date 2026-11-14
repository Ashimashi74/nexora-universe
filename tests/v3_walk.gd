extends Node
## v3 screen walk: opens every v3 screen through Nav, reports script errors / missing screens and (when rendering)
## saves screenshots to $NX_SHOTS.  NX_V3WALK=1 [NX_SHOTS=/dir] godot [--headless] --path . res://src/main.tscn
## NX_V3ONLY=name1,name2 limits the walk.

var shots := ""
var render := false
var fails: Array = []

func _ready() -> void:
	render = DisplayServer.get_name() != "headless"
	shots = OS.get_environment("NX_SHOTS")
	if shots != "": DirAccess.make_dir_recursive_absolute(shots)
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String) -> void:
	if not render or shots == "": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/v3_%s.png" % [shots, name])
	print("[v3walk] shot ", name)

func _visit(name: String, params := {}, wait := 1.4) -> void:
	var only := OS.get_environment("NX_V3ONLY")
	if only != "" and not (name in only.split(",")): return
	Nav.go(name, params)
	await _wait(wait)
	var ok: bool = Nav.current == name
	print("[v3walk] ", name, " -> ", Nav.current, " ", "OK" if ok else "FAIL")
	if not ok: fails.append(name)
	await _shot(name + ("_" + str(params.get("tag", "")) if params.has("tag") else ""))

func _run() -> void:
	await _wait(2.0)
	var intro = Nav.screen
	if intro and intro.has_method("enter"): intro.enter()
	await _wait(1.2)
	for tab in ["home", "play", "social", "shop", "profile"]:
		await _visit(tab)
	await _visit("prematch", {"tag": "team"})
	var s = Nav.screen
	if s and s.has_method("_go_form"):
		s._go_form()
		await _wait(0.8)
		await _shot("prematch_form")
	await _visit("prematch", {"picker": true, "tag": "picker"})
	await _visit("rooms")
	await _visit("tournaments")
	await _visit("tournament_v2", {"id": "00000000-0000-0000-0000-000000000000", "tag": "detail"})
	await _visit("admin")
	await _visit("notifications")
	await _visit("oracle")
	await _visit("public_profile", {"id": "00000000-0000-0000-0000-000000000000", "tag": "x"})
	print("[v3walk] DONE fails=", fails)
	get_tree().quit(1 if fails.size() > 0 else 0)
