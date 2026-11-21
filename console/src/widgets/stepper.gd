extends HBoxContainer
## Progression de l'onboarding (points reliés, l'étape courante respire).

const UI := preload("res://src/ui.gd")
const STEPS := ["Manette", "Réseau", "Installation", "Comptes", "Affichage"]

var current := 0


func _init(cur := 0) -> void:
	current = cur


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 18)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	position.y = 54
	for i in STEPS.size():
		var dot := Dot.new(i, current)
		add_child(dot)
		var l := UI.label(STEPS[i], 22, 600 if i == current else 500, UI.TEXT if i <= current else Color(UI.DIM, 0.7))
		add_child(l)
		if i < STEPS.size() - 1:
			var line := ColorRect.new()
			line.custom_minimum_size = Vector2(44, 2)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.color = Color(1, 1, 1, 0.35 if i < current else 0.12)
			add_child(line)
	resized.connect(func(): position.x = (get_parent_area_size().x - size.x) / 2.0)


class Dot extends Control:
	var idx := 0
	var cur := 0
	var _t := 0.0

	func _init(i: int, c: int) -> void:
		idx = i
		cur = c
		custom_minimum_size = Vector2(34, 34)

	func _process(d: float) -> void:
		_t += d
		if idx == cur:
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		if idx < cur:
			draw_circle(c, 15, Color("3ddc97", 0.22))
			draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-2, 5), c + Vector2(7, -5)]), Color("3ddc97"), 3.0, true)
		elif idx == cur:
			var p := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(c, 15 + p * 3.0, Color("7c9cff", 0.18 * (1.0 - p)))
			draw_circle(c, 13, Color.WHITE)
			var f := App.font(700)
			var s := str(idx + 1)
			var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			draw_string(f, c + Vector2(-sz.x / 2.0, 6.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("0b0e16"))
		else:
			draw_arc(c, 13, 0, TAU, 32, Color(1, 1, 1, 0.25), 2.0, true)
			var f2 := App.font(600)
			var s2 := str(idx + 1)
			var sz2 := f2.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
			draw_string(f2, c + Vector2(-sz2.x / 2.0, 6), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.5))
