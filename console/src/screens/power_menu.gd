extends Control
## Menu d'alimentation (modale) : veille, redémarrer, Windows, éteindre.

const UI := preload("res://src/ui.gd")

var _first: Button


func _init() -> void:
	set_meta("is_modal", true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.0)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.create_tween().tween_property(dim, "color:a", 0.65, 0.3)

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_box(Color(0.09, 0.11, 0.18, 0.97), 40, 40))
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(UI.icon_rect("power_settings_new", 44, UI.ACCENT))
	head.add_child(UI.label("Alimentation", 40, 750))
	v.add_child(head)
	v.add_child(UI.vspacer(8))
	var items := [["Mettre en veille", "schedule", "suspend", "normal"], ["Redémarrer", "refresh", "reboot", "normal"]]
	if App.info.get("windowsDetected", false):
		items.append(["Redémarrer sous Windows", "logout", "reboot-windows", "normal"])
	items.append(["Éteindre", "power_settings_new", "poweroff", "danger"])
	for it in items:
		var b := UI.chunky(it[0], it[1], it[3], 28)
		b.custom_minimum_size.x = 520
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _do(it[2], it[0]))
		v.add_child(b)
		if _first == null:
			_first = b
	await get_tree().process_frame
	p.position = (get_viewport_rect().size - p.size) / 2.0 + Vector2(0, 40)
	p.modulate.a = 0
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "position:y", p.position.y - 40, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	App.quiet_focus(_first)


func default_focus() -> Control:
	return _first


func _do(action: String, label: String) -> void:
	App.close_modal(self)
	var r = await App.api("POST", "/power/%s" % action)
	if r is Dictionary and r.get("simulated", false):
		App.toast("%s (simulation en développement)" % label, "power_settings_new", UI.ACCENT)
	elif r == null:
		App.toast("Service système injoignable", "close", UI.DANGER)
