extends Node
## TEST STUB of the GAME worker's Sfx
var log_calls := []
func play(key: String, vol := 1.0) -> void: log_calls.append(key)
func haptic(kind := "light") -> void: pass
func music(on: bool) -> void: pass
func menu_music(on: bool) -> void: print("[stub] menu_music ", on)
func crowd(on: bool) -> void: pass
func apply_prefs() -> void: pass
