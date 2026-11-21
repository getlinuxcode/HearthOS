extends Control
## Clavier virtuel à la manette. Ⓐ taper · Ⓧ effacer · Ⓨ espace · L1 majuscules · Start valider.

signal done(text)

const UI := preload("res://src/ui.gd")
const ROWS_AZERTY := ["1234567890", "azertyuiop", "qsdfghjklm", "wxcvbn,.-@"]
const ROWS_QWERTY := ["1234567890", "qwertyuiop", "asdfghjkl@", "zxcvbnm,.-"]

var title := ""
var secret := false
var value := ""
var _shift := false
var _field: Label
var _keys: Array[Button] = []
var _panel: PanelContainer
var _finished := false


func _init(t := "", is_secret := false) -> void:
	title = t
	secret = is_secret
	set_meta("is_modal", true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.panel_box(Color(0.09, 0.11, 0.18, 0.97), 36, 30))
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(1240, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_panel.add_child(v)
	v.add_child(UI.label(title, 24, 500, UI.DIM))
	var fieldbox := PanelContainer.new()
	var fsb := UI.panel_box(Color(0, 0, 0, 0.35), 18, 18)
	fsb.border_width_bottom = 3
	fsb.border_color = UI.ACCENT
	fsb.shadow_size = 0
	fieldbox.add_theme_stylebox_override("panel", fsb)
	_field = UI.label("", 38, 500)
	_field.custom_minimum_size.y = 50
	fieldbox.add_child(_field)
	v.add_child(fieldbox)

	var layout: Array = ROWS_AZERTY if App.settings.get("keyboardLayout", "azerty") == "azerty" else ROWS_QWERTY
	for row in layout:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		for ch in row:
			h.add_child(_key(ch, ch, 104))
	var last := HBoxContainer.new()
	last.alignment = BoxContainer.ALIGNMENT_CENTER
	last.add_theme_constant_override("separation", 10)
	v.add_child(last)
	last.add_child(_key("#shift", "", 160, "keyboard_capslock"))
	last.add_child(_key(" ", "Espace", 470, "space_bar"))
	last.add_child(_key("#del", "", 160, "backspace"))
	if secret:
		last.add_child(_key("#show", "", 120, "visibility"))
	var ok := _key("#ok", "Valider", 220, "check")
	ok.add_theme_stylebox_override("normal", UI.box(Color("f2f4fa"), Color("aab3c9"), 5, 16, Vector2(12, 12)))
	for c in ["font_color", "font_focus_color", "font_hover_color"]:
		ok.add_theme_color_override(c, Color("0b0e16"))
	ok.icon = App.icon("check", 30, Color("0b0e16"))
	last.add_child(ok)
	_render()

	_panel.position.y += 80
	_panel.modulate.a = 0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "position:y", _panel.position.y - 120, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	App.quiet_focus(_keys[10])


func _key(id: String, text: String, w: int, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 72)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("key", id)
	b.add_theme_font_override("font", App.font(500))
	b.add_theme_font_size_override("font_size", 30)
	var normal := UI.box(Color(1, 1, 1, 0.09), Color(0, 0, 0, 0.4), 4, 14, Vector2(8, 10))
	normal.shadow_size = 0
	var foc := UI.box(Color(1, 1, 1, 0.95), Color("aab3c9"), 4, 14, Vector2(8, 10))
	foc.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", UI.box(Color(1, 1, 1, 0.7), Color("aab3c9"), 1, 14, Vector2(8, 10), 3))
	b.add_theme_color_override("font_focus_color", Color("0b0e16"))
	b.add_theme_color_override("font_hover_color", Color("0b0e16"))
	if icon_name != "":
		b.icon = App.icon(icon_name, 30, Color.WHITE)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if text == "" else HORIZONTAL_ALIGNMENT_LEFT
	UI.center_pivot(b)
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		if icon_name != "": b.icon = App.icon(icon_name, 30, Color("0b0e16"))
		UI.pop(b, 1.1, 0.2))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		if icon_name != "" and id != "#ok": b.icon = App.icon(icon_name, 30, Color.WHITE)
		UI.pop(b, 1.0, 0.2))
	b.pressed.connect(func(): _type(id))
	_keys.append(b)
	return b


func _type(id: String) -> void:
	match id:
		"#shift":
			_shift = not _shift
			for k in _keys:
				var kid: String = k.get_meta("key")
				if kid.length() == 1:
					k.text = kid.to_upper() if _shift else kid
			App.sfx.play("tick")
			return
		"#del":
			value = value.left(-1)
			App.sfx.play("back")
		"#show":
			secret = not secret
		"#ok":
			_finish(value)
			return
		_:
			value += id.to_upper() if _shift else id
			App.sfx.play("tick")
	_render()


func _render() -> void:
	var shown := "•".repeat(value.length()) if secret else value
	_field.text = shown + "|"


func _finish(v) -> void:
	if _finished:
		return
	_finished = true
	App.close_modal(self)
	done.emit(v)


func on_cancel() -> bool:
	if value != "":
		_type("#del")
	else:
		App.sfx.play("back")
		_finish(null)
	return true


func hints() -> Array:
	return [["ui_accept", "Taper"], ["btn_x", "Effacer"], ["btn_y", "Espace"], ["lb", "Majuscules"], ["start", "Valider"], ["ui_cancel", "Annuler"]]


func _input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_finish(value)
		elif event.keycode == KEY_ESCAPE:
			_finish(null)
		elif event.keycode == KEY_BACKSPACE:
			_type("#del")
		elif event.unicode > 31:
			value += char(event.unicode)
			_render()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("btn_x"):
		_type("#del")
	elif event.is_action_pressed("btn_y"):
		_type(" ")
	elif event.is_action_pressed("lb"):
		_type("#shift")
	elif event.is_action_pressed("start"):
		_finish(value)
	else:
		return
	get_viewport().set_input_as_handled()
