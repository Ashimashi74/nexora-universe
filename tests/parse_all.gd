extends SceneTree
## v3: loads (= parses + compiles) every GDScript under res://src, res://addons and res://tests and reports failures.
## Run: godot --headless -s res://tests/parse_all.gd   (exit code 1 when any script fails to load)

var bad: Array = []
var n := 0

func _walk(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with("."): _walk(dir.path_join(f))
		elif f.ends_with(".gd"):
			var p := dir.path_join(f)
			if p == "res://tests/parse_all.gd": f = d.get_next(); continue
			n += 1
			var s = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
			if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate() and not (s as GDScript).is_abstract():
				bad.append(p)
		f = d.get_next()

func _initialize() -> void:
	for root in ["res://src", "res://addons", "res://tests"]:
		_walk(root)
	print("PARSE_ALL scripts=%d failed=%d %s" % [n, bad.size(), str(bad)])
	quit(1 if bad.size() > 0 else 0)
