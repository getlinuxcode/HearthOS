extends HBoxContainer
## Barre d'aide en bas à droite : glyphes adaptés à la manette utilisée.

const Glyph := preload("res://src/widgets/glyph.gd")
const UI := preload("res://src/ui.gd")

var _last: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 34)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -64
	offset_bottom = -40


func show_hints(h: Array) -> void:
	var same := h == _last
	_last = h
	for c in get_children():
		c.queue_free()
	for i in h.size():
		var pair: Array = h[i]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		box.add_child(Glyph.new(pair[0], App.active_family, 38))
		var l := UI.label(pair[1], 24, 500, Color("c9cfdd"))
		box.add_child(l)
		add_child(box)
		if not same:
			UI.fade_in(box, i * 0.05, 0.35)
