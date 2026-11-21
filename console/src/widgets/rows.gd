extends VBoxContainer
## Liste de réglages façon console : interrupteur animé, choix ◀ valeur ▶, action, info, titre de section.
## Définition d'une ligne (Dictionary) :
##   {kind="toggle", label, desc?, get: Callable, set: Callable}
##   {kind="choice", label, desc?, options: [[valeur, "texte"], …], get, set}
##   {kind="action", label, desc?, value?, icon?, danger?, run: Callable}
##   {kind="info", label, value}
##   {kind="header", label}

const UI := preload("res://src/ui.gd")

var _rows: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_rows(defs: Array) -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	var i := 0
	for d in defs:
		var row := _make(d)
		add_child(row)
		UI.fade_in(row, i * 0.03, 0.3)
		i += 1


func first_focusable() -> Control:
	for c in get_children():
		if c is Button and not c.is_queued_for_deletion():
			return c
	return null


func refresh() -> void:
	for c in get_children():
		if c.has_meta("render"):
			c.get_meta("render").call()


func _make(d: Dictionary) -> Control:
	var kind: String = d.kind
	if kind == "header":
		var l := UI.label(str(d.label).to_upper(), 20, 700, UI.DIM)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 22)
		m.add_theme_constant_override("margin_left", 8)
		m.add_child(l)
		return m
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL if kind != "info" else Control.FOCUS_NONE
	b.custom_minimum_size.y = 78
	var normal := UI.box(Color(1, 1, 1, 0.05) if kind != "info" else Color(0, 0, 0, 0), Color(0, 0, 0, 0.25) if kind != "info" else Color(0, 0, 0, 0), 3 if kind != "info" else 0, 20, Vector2(26, 12))
	normal.shadow_size = 0
	var foc := UI.box(Color(1, 1, 1, 0.15), Color(0, 0, 0, 0.3), 3, 20, Vector2(26, 12))
	foc.shadow_size = 0
	foc.border_color = Color(1, 1, 1, 0.0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc if kind != "info" else normal)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", UI.focus_ring(24, 3))
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 18)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 26
	h.offset_right = -24
	if d.has("icon"):
		h.add_child(UI.icon_rect(d.icon, 34, UI.DANGER if d.get("danger", false) else UI.TEXT))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var title := UI.label(d.label, 26, 550, UI.DANGER if d.get("danger", false) else UI.TEXT)
	title.clip_text = true
	v.add_child(title)
	if d.has("desc"):
		v.add_child(UI.label(d.desc, 19, 400, UI.DIM))
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(right)

	var render := func():
		for c in right.get_children():
			c.queue_free()
		match kind:
			"info":
				var val := UI.label(str(d.value), 23, 500, Color("c9cfdd"))
				val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				val.custom_minimum_size.x = 420
				val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				right.add_child(val)
			"toggle":
				right.add_child(Toggle.new(d.get.call()))
			"choice":
				var cur = d.get.call()
				var txt := ""
				for o in d.options:
					if o[0] == cur:
						txt = o[1]
				if txt == "" and d.options.size() > 0:
					txt = d.options[0][1]
				var arrows := b.has_focus()
				right.add_child(UI.label("◀", 18, 700, UI.ACCENT if arrows else Color(1, 1, 1, 0.25)))
				var val2 := UI.label(txt, 24, 650)
				val2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				val2.custom_minimum_size.x = 230
				right.add_child(val2)
				right.add_child(UI.label("▶", 18, 700, UI.ACCENT if arrows else Color(1, 1, 1, 0.25)))
			"action":
				if d.has("value"):
					right.add_child(UI.label(str(d.value.call() if d.value is Callable else d.value), 23, 500, UI.DIM))
				right.add_child(UI.label("›", 40, 400, UI.DIM))
	b.set_meta("render", render)
	render.call()

	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		if kind == "choice": render.call())
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		if kind == "choice": render.call())
	b.pressed.connect(_on_press.bind(d, render, b))
	b.gui_input.connect(func(ev: InputEvent):
		if kind != "choice":
			return
		if ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right"):
			b.accept_event()
			App.sfx.play("tick")
			_cycle(d, 1 if ev.is_action_pressed("ui_right") else -1, render))
	return b


func _on_press(d: Dictionary, render: Callable, b: Button) -> void:
	match d.kind:
		"toggle":
			await d.set.call(not d.get.call())
			render.call()
		"choice":
			await _cycle(d, 1, render)
		"action":
			await d.run.call()
			if is_instance_valid(b):
				render.call()


func _cycle(d: Dictionary, dir: int, render: Callable) -> void:
	var cur = d.get.call()
	var idx := 0
	for i in d.options.size():
		if d.options[i][0] == cur:
			idx = i
	var nxt = d.options[(idx + dir + d.options.size()) % d.options.size()][0]
	await d.set.call(nxt)
	render.call()


class Toggle extends Control:
	var on := false
	var _p := 0.0
	func _init(v: bool) -> void:
		on = v
		_p = 1.0 if v else 0.0
		custom_minimum_size = Vector2(66, 38)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.16).lerp(Color("7c9cff"), _p)
		sb.set_corner_radius_all(19)
		draw_style_box(sb, Rect2(Vector2(0, 2), Vector2(66, 34)))
		draw_circle(Vector2(19 + 28 * _p, 19), 13, Color.WHITE)
