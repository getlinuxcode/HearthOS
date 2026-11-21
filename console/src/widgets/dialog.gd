extends Control
## Fenêtre modale générique : titre, contenu libre, boutons à relief. Ⓑ ferme.
## Boutons : [["Texte", Callable, "kind", "icône"], …] — "kind" : normal | primary | danger.

signal closed

const UI := preload("res://src/ui.gd")

var title := ""
var body: Control
var buttons: Array = []
var width := 760
var vertical := true
var _first: Control
var _panel: PanelContainer


func _init(t: String, content: Control = null, btns: Array = [], w := 760) -> void:
	title = t
	body = content
	buttons = btns
	width = w
	set_meta("is_modal", true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.0)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.create_tween().tween_property(dim, "color:a", 0.66, 0.3)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.panel_box(Color(0.09, 0.11, 0.18, 0.98), 40, 40))
	_panel.custom_minimum_size.x = width
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	_panel.add_child(v)
	v.add_child(UI.label(title, 40, 750))
	if body:
		v.add_child(body)
	if not buttons.is_empty():
		var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
		box.add_theme_constant_override("separation", 14)
		v.add_child(UI.vspacer(4))
		v.add_child(box)
		for bdef in buttons:
			var b := UI.chunky(bdef[0], bdef[3] if bdef.size() > 3 else "", bdef[2] if bdef.size() > 2 else "normal", 27)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT if vertical else HORIZONTAL_ALIGNMENT_CENTER
			var cb: Callable = bdef[1]
			b.pressed.connect(func():
				close()
				if cb.is_valid(): cb.call())
			box.add_child(b)
			if _first == null:
				_first = b
	await get_tree().process_frame
	_panel.position = (get_viewport_rect().size - _panel.size) / 2.0 + Vector2(0, 40)
	_panel.modulate.a = 0
	var tw := _panel.create_tween().set_parallel(true)
	tw.tween_property(_panel, "position:y", _panel.position.y - 40, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	var f := default_focus()
	if f:
		App.quiet_focus(f)


func default_focus() -> Control:
	if _first:
		return _first
	if body and body.has_method("first_focusable"):
		return body.first_focusable()
	return null


func close() -> void:
	App.close_modal(self)
	closed.emit()


static func open(t: String, content: Control = null, btns: Array = [], w := 760) -> Control:
	var d = load("res://src/widgets/dialog.gd").new(t, content, btns, w)
	App.open_modal(d)
	return d


static func text(s: String, w := 680) -> Label:
	var l := UI.label(s, 26, 400, Color("c9cfdd"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l
