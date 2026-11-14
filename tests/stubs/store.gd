extends Node
## TEST STUB of the GAME worker's Store (only used in /tmp/uitest copies)
signal changed
var p: Dictionary = {}
func _init() -> void:
	p = UD.default_profile()
	p["coins"] = 2400
	p["xp"] = 340
	p["trophies"] = 420
	p["played"] = 7; p["wins"] = 5; p["losses"] = 1; p["draws"] = 1; p["goalsFor"] = 19; p["goalsAgainst"] = 8; p["bestStreak"] = 3
func set_p(patch: Dictionary) -> void:
	for k in patch:
		p[k] = patch[k]
	changed.emit()
func reset() -> void:
	p = UD.default_profile()
	changed.emit()
