extends Control
## Transition de lancement : la jaquette s'envole vers le centre, le fond tourbillonne,
## un anneau de lumière tourne, puis flash → le jeu.

const UI := preload("res://src/ui.gd")
const InGame := preload("res://src/screens/ingame.gd")

var game: Dictionary
var from: Rect2
var _cover: TextureRect
var _veil: ColorRect
var _flash: ColorRect
var _label: Label
var _ring: Ring


class Ring extends Control:
	var t := 0.0
	var alpha := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size / 2.0
		var r := size.y * 0.5
		for k in 3:
			var a := t * (2.2 + k * 0.7) + k * 2.0
			draw_arc(c, r + k * 16.0, a, a + 1.4 - k * 0.3, 48, Color(0.7, 0.78, 1.0, alpha * (0.8 - k * 0.22)), 5.0 - k, true)


func _init(g: Dictionary, rect: Rect2) -> void:
	game = g
	from = rect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_veil = ColorRect.new()
	_veil.color = Color(0.01, 0.015, 0.04, 0.0)
	add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := get_viewport_rect().size / 2.0
	var target := Vector2(330, 495)
	_ring = Ring.new()
	_ring.size = target + Vector2(90, 90)
	_ring.position = center - _ring.size / 2.0 - Vector2(0, 40)
	add_child(_ring)

	_cover = TextureRect.new()
	_cover.texture = game.get("_cover")
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_SCALE
	_cover.position = from.position
	_cover.size = from.size
	add_child(_cover)

	_label = UI.label("Lancement de %s" % game.name, 34, 600)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(1400, 50)
	_label.position = Vector2(center.x - 700, center.y + target.y / 2.0 + 30)
	_label.modulate.a = 0
	add_child(_label)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	App.sfx.play("launch")
	App.bg.set_energy(1.0, 1.6)
	App.hints.show_hints([])
	var dest := Rect2(center - target / 2.0 - Vector2(0, 40), target)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_veil, "color:a", 0.72, 0.5)
	tw.tween_property(_cover, "position", dest.position, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cover, "size", dest.size, 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ring, "alpha", 1.0, 0.6).set_delay(0.4)
	tw.tween_property(_label, "modulate:a", 1.0, 0.5).set_delay(0.5)
	tw.chain().tween_interval(1.0)
	# envol final
	tw.chain().tween_property(_cover, "scale", Vector2(3.2, 3.2), 0.65).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cover, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tw.parallel().tween_property(_ring, "alpha", 0.0, 0.3)
	tw.parallel().tween_property(_label, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(_flash, "color:a", 0.85, 0.45).set_delay(0.25)
	tw.chain().tween_callback(_enter_game)
	tw.chain().tween_property(_flash, "color", Color(0, 0, 0, 1), 0.35)
	tw.chain().tween_property(_flash, "color:a", 0.0, 0.6)
	tw.chain().tween_callback(queue_free)
	_cover.pivot_offset = target / 2.0
	_start_game()


func _start_game() -> void:
	if game.get("demo", false):
		return
	var res = await App.api("POST", "/games/%s/launch" % game.id.uri_encode())
	if res is Dictionary and res.has("_error"):
		App.toast(res._error, "close", UI.DANGER)


func _enter_game() -> void:
	App.bg.set_energy(0.0, 0.4)
	App.running_game = game
	App.push(InGame.new(game))
