extends Control
## Onboarding 5 : l'écran. Résolution, Hz, VRR, HDR, upscaling, limite d'images, taille de l'interface.

const UI := preload("res://src/ui.gd")
const Stepper := preload("res://src/widgets/stepper.gd")
const Rows := preload("res://src/widgets/rows.gd")

var on_next: Callable
var _rows: Rows
var _next: Button


func _init(next_cb: Callable) -> void:
	on_next = next_cb


func _ready() -> void:
	add_child(Stepper.new(4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 380
	v.offset_right = -380
	v.offset_top = 140
	v.offset_bottom = -110
	var t := UI.label("Votre écran", 60, 750)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("Appliqué par gamescope à chaque démarrage de session.", 26, 400, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_box(UI.PANEL, 30, 18))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(panel)
	_rows = Rows.new()
	panel.add_child(_rows)
	_next = UI.chunky("Continuer", "check", "primary", 30)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_next.pressed.connect(func(): on_next.call())
	v.add_child(_next)
	for i in v.get_child_count():
		UI.fade_in(v.get_child(i), 0.07 * i, 0.5)


func on_enter() -> void:
	var info = await App.api("GET", "/display")
	_rows.set_rows(display_rows(info if info is Dictionary else {}))
	await get_tree().process_frame
	App.quiet_focus(_rows.first_focusable())


func default_focus() -> Control:
	return _rows.first_focusable() if _rows else null


func hints() -> Array:
	return [["lr", "Modifier"], ["ui_accept", "Sélectionner"], ["ui_cancel", "Retour"]]


static func display_rows(info: Dictionary) -> Array:
	var modes: Array = info.get("modes", [{"width": 1920, "height": 1080, "refresh": [60]}])
	var disp := func() -> Dictionary:
		var d: Dictionary = App.settings.get("display", {})
		if d.is_empty():
			d = {"width": 3840, "height": 2160, "refresh": 60, "vrr": true, "hdr": false, "upscaler": "off", "fpsLimit": 0}
		return d
	var save := func(patch: Dictionary):
		var d: Dictionary = disp.call().duplicate()
		d.merge(patch, true)
		App.settings["display"] = d
		var r = await App.api("POST", "/settings", {"display": d})
		if r is Dictionary and r.has("display"):
			App.settings = r
	var res_opts := []
	for m in modes:
		res_opts.append(["%dx%d" % [m.width, m.height], "%d × %d%s" % [m.width, m.height, " (4K)" if int(m.width) == 3840 else ""]])
	return [
		{"kind": "choice", "label": "Résolution", "desc": "Modes simulés en développement" if info.get("simulated", true) else "Sortie %s" % info.get("output", ""),
			"options": res_opts,
			"get": func(): return "%dx%d" % [disp.call().width, disp.call().height],
			"set": func(v):
				var p: PackedStringArray = str(v).split("x")
				await save.call({"width": int(p[0]), "height": int(p[1])})},
		{"kind": "choice", "label": "Fréquence", "desc": "Hertz de l'écran",
			"options": [[30, "30 Hz"], [60, "60 Hz"], [120, "120 Hz"], [144, "144 Hz"]],
			"get": func(): return int(disp.call().refresh),
			"set": func(v): await save.call({"refresh": v})},
		{"kind": "toggle", "label": "VRR (FreeSync / G-Sync)", "desc": "Fréquence variable si l'écran la gère",
			"get": func(): return disp.call().vrr, "set": func(v): await save.call({"vrr": v})},
		{"kind": "toggle", "label": "HDR", "desc": "Écrans et jeux compatibles",
			"get": func(): return disp.call().hdr, "set": func(v): await save.call({"hdr": v})},
		{"kind": "choice", "label": "Mise à l'échelle", "desc": "Upscaling des jeux par gamescope",
			"options": [["off", "Désactivée"], ["fsr", "AMD FSR"], ["nis", "NVIDIA NIS"], ["integer", "Entière (rétro)"]],
			"get": func(): return disp.call().upscaler, "set": func(v): await save.call({"upscaler": v})},
		{"kind": "choice", "label": "Limite d'images par seconde",
			"options": [[0, "Aucune"], [30, "30 i/s"], [40, "40 i/s"], [60, "60 i/s"], [120, "120 i/s"]],
			"get": func(): return int(disp.call().fpsLimit), "set": func(v): await save.call({"fpsLimit": v})},
		{"kind": "choice", "label": "Taille de l'interface", "desc": "Si les bords sont coupés sur votre TV",
			"options": [[0.9, "90 %"], [1.0, "100 %"], [1.1, "110 %"]],
			"get": func(): return float(App.settings.get("uiScale", 1.0)),
			"set": func(v):
				App.settings["uiScale"] = v
				App.root.get_tree().root.content_scale_factor = v
				await App.api("POST", "/settings", {"uiScale": v})},
	]
