class_name NxBody
extends RefCounted
## One physics body (disc team 0/1, ball team 2) — same fields as Body in src/game/engine.ts.

var id: int = 0
var team: int = 0
var x: float = 0.0
var y: float = 0.0
var px: float = 0.0
var py: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var r: float = 0.0
var im: float = 0.0
var spin: float = 0.0
var ang: float = 0.0
## 3x3 rotation matrix of the rolling ball, row-major (same layout as the TS Float64Array R[0..8]).
## Stored as 9 scalars so the 240 Hz integrator never allocates; `R` is a convenience view (allocates on read).
var r0: float = 1.0
var r1: float = 0.0
var r2: float = 0.0
var r3: float = 0.0
var r4: float = 1.0
var r5: float = 0.0
var r6: float = 0.0
var r7: float = 0.0
var r8: float = 1.0
var R: PackedFloat64Array:
	get: return PackedFloat64Array([r0, r1, r2, r3, r4, r5, r6, r7, r8])
	set(v):
		if v.size() >= 9:
			r0 = v[0]; r1 = v[1]; r2 = v[2]; r3 = v[3]; r4 = v[4]; r5 = v[5]; r6 = v[6]; r7 = v[7]; r8 = v[8]
var sq: float = 0.0
var tvx: float = 0.0
var tvy: float = 0.0
var ramp: float = 0.0
var boost: float = 0.0
var vox: float = 0.0
var voy: float = 0.0
var gout = null            # NxEngine.Goal or null
var tr: Array = []         # Array[Vector2] disc motion trail
## ball launch ramp timer (feel tweak: eases the ball up to its struck velocity over ~75 ms; 0 in classic mode)
var lt: float = 0.0

func _init(_x := 0.0, _y := 0.0, _team := 0, _r := 0.0, m := 1.0, _id := 0) -> void:
	id = _id; team = _team; x = _x; y = _y; px = _x; py = _y; r = _r; im = 1.0 / m

func reset_rot() -> void:
	r0 = 1.0; r1 = 0.0; r2 = 0.0; r3 = 0.0; r4 = 1.0; r5 = 0.0; r6 = 0.0; r7 = 0.0; r8 = 1.0
