class_name NxScreen
extends Control
## Base for UI-owned screens: params, a vertical scroller padded by Nav.insets(),
## rebuild() that keeps the scroll position, and Store.changed → on_store_changed().

var params := {}
var scroll: ScrollContainer
var body: VBoxContainer
var built := false   # false during the first build (entrance animations only then)
var _store_dirty := false

func setup(p: Dictionary) -> void:
	params = p

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()
	built = true
	var st := UD.node("Store")
	if st and st.has_signal("changed"):
		st.connect("changed", _on_store)

func _on_store() -> void:
	if _store_dirty:
		return
	_store_dirty = true
	# coalesce bursts of Store updates into one refresh per frame
	(func():
		_store_dirty = false
		if is_inside_tree():
			on_store_changed()).call_deferred()

## override
func build() -> void:
	pass

## override (default: rebuild the scroll body)
func on_store_changed() -> void:
	pass

## standard full-screen scroller between HUD and tab bar
func make_scroll(sep := 22) -> VBoxContainer:
	var sl := Kit.scroll_list(sep)
	scroll = sl[0]
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	body = sl[1]
	_pad_body()
	return body

func _pad_body() -> void:
	var ins := Nav.insets()
	var top := Kit.gap(ins["top"])
	top.name = "TopPad"
	body.add_child(top)

func end_body() -> void:
	var b := Kit.gap(Nav.insets()["bottom"] + 20)
	b.name = "BottomPad"
	body.add_child(b)

## clear and rebuild the body with `fill` while keeping the scroll offset
func rebuild(fill: Callable) -> void:
	var y := scroll.scroll_vertical if scroll else 0
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_pad_body()
	fill.call()
	end_body()
	if scroll:
		(func(): scroll.scroll_vertical = y).call_deferred()

## padded row helper: horizontal page margin around a control
func padx(c: Control, px := NX.PAD) -> MarginContainer:
	return Kit.margin(c, px, 0, px, 0)

## entrance animation only on first build
func ent(c: Control, i := 0) -> Control:
	if not built:
		Kit.enter(c, i)
	return c

func toast(t: String, k := "info") -> void:
	Nav.toast(t, k)
