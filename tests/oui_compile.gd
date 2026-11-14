extends SceneTree
## Compile every OUI-owned script with autoloads present.
##   godot --headless --script res://tests/oui_compile.gd
const FILES := ["res://src/online/oui.gd", "res://src/online/ui_bits.gd", "res://src/online/hub.gd", "res://src/online/lobby.gd",
	"res://src/online/ranks.gd", "res://src/online/tournaments.gd", "res://src/online/challenges.gd", "res://src/online/online_result.gd",
	"res://src/online/arena.gd", "res://src/online/online_match.gd", "res://src/social/social.gd", "res://src/social/chat.gd",
	"res://src/social/club.gd", "res://src/social/public_profile.gd", "res://src/oracle/kb.gd", "res://src/oracle/coach.gd",
	"res://src/oracle/oracle.gd", "res://src/screens/account.gd", "res://src/net/discs.gd"]
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var bad := 0
	for f in FILES:
		var s = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		var okk: bool = s != null and s is GDScript and (s as GDScript).can_instantiate()
		print(("OK   " if okk else "FAIL ") + f)
		if not okk: bad += 1
	print("compile failures: ", bad)
	quit(1 if bad else 0)
