extends Control
## Racine : fond vivant, couche d'écrans, modales, barre d'aide, notifications.

const UI := preload("res://src/ui.gd")
const Background := preload("res://src/widgets/background.gd")
const HintsBar := preload("res://src/widgets/hints.gd")
const Boot := preload("res://src/screens/boot.gd")
const PadConnect := preload("res://src/screens/pad_connect.gd")
const Network := preload("res://src/screens/network.gd")
const Home := preload("res://src/screens/home.gd")
const InGame := preload("res://src/screens/ingame.gd")
const Overlay := preload("res://src/screens/overlay.gd")

var _toasts: VBoxContainer


func _ready() -> void:
	App.root = self
	var th := Theme.new()
	th.default_font = App.font(500)
	th.default_font_size = 26
	theme = th

	var bg := Background.new()
	add_child(bg)
	App.bg = bg

	var screens := Control.new()
	screens.name = "Screens"
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screens)
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	App.screen_layer = screens

	var modals := Control.new()
	modals.name = "Modals"
	modals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modals)
	modals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	App.modal_layer = modals

	var hints := HintsBar.new()
	add_child(hints)
	App.hints = hints

	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 12)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.position.y = 36

	get_viewport().gui_focus_changed.connect(App.on_focus_changed)
	App.glyphs_changed.connect(App.refresh_hints)

	var scene: String = App.args.get("scene", "boot")
	if scene == "boot":
		App.push(Boot.new())
	else:
		await _jump(scene)
	if App.args.has("shot"):
		_screenshot(App.args.shot, float(App.args.get("delay", "4")))


## Accès direct à un écran (développement et captures).
func _jump(scene: String) -> void:
	App.bg.reveal(0.01)
	var info = await App.api("GET", "/system/info")
	if info is Dictionary and not info.has("_error"):
		App.info = info
	var s = await App.api("GET", "/settings")
	App.settings = s if s is Dictionary and not s.has("_error") else {}
	App.settings["onboarded"] = true
	await App.load_library()
	var direct := {
		"install": "res://src/screens/install.gd", "accounts": "res://src/screens/accounts.gd",
		"qr": "res://src/screens/steam_qr.gd", "display": "res://src/screens/display.gd",
		"done": "res://src/screens/done.gd", "settings": "res://src/screens/settings.gd",
		"epic": "res://src/screens/epic_login.gd", "updates": "res://src/screens/settings.gd",
		"emulators": "res://src/screens/emulators.gd", "store": "res://src/screens/store.gd",
	}
	if direct.has(scene):
		var scr = load(direct[scene])
		match scene:
			"install": App.push(scr.new(func(): pass))
			"accounts": App.push(scr.new(true, func(): pass))
			"display": App.push(scr.new(func(): pass))
			"updates": App.push(scr.new("updates"))
			_: App.push(scr.new())
		return
	match scene:
		"pad": App.push(PadConnect.new())
		"network": App.push(Network.new())
		"home": App.push(Home.new())
		"launch":
			App.push(Home.new())
			await get_tree().create_timer(2.5).timeout
			App.current()._launch()
		"ingame", "overlay":
			App.push(Home.new())
			await get_tree().create_timer(0.3).timeout
			var g: Dictionary = App.library[0]
			App.running_game = g
			App.push(InGame.new(g))
			if scene == "overlay":
				await get_tree().create_timer(1.0).timeout
				open_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("guide"):
		get_viewport().set_input_as_handled()
		if App.running_game != null:
			if not App.overlay_open:
				open_overlay()
		elif App.current() and not (App.current() is Home) and App.settings.get("onboarded", false):
			App.replace_all(Home.new())
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var top := App.top_layer()
		if top and top.has_method("on_cancel") and top.on_cancel():
			get_viewport().set_input_as_handled()
			return
		if top and top.get_meta("is_modal", false):
			App.sfx.play("back")
			App.close_modal(top)
		elif App.current() and App.current().get_meta("can_back", true):
			App.back()
		get_viewport().set_input_as_handled()


func open_overlay() -> void:
	if App.overlay_open:
		return
	App.overlay_open = true
	var o := Overlay.new()
	o.set_meta("is_modal", true)
	App.open_modal(o)
	App.sfx.play("overlay")


func show_toast(text: String, icon_name: String, color: Color) -> void:
	var p := PanelContainer.new()
	var sb := UI.panel_box(Color(0.1, 0.12, 0.19, 0.95), 40, 18)
	sb.content_margin_left = 26
	sb.content_margin_right = 32
	sb.border_width_bottom = 4
	sb.border_color = Color(0, 0, 0, 0.4)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	h.add_child(UI.icon_rect(icon_name, 34, color))
	h.add_child(UI.label(text, 26, 600))
	_toasts.add_child(p)
	p.pivot_offset = Vector2(200, 30)
	p.scale = Vector2(0.6, 0.6)
	p.modulate.a = 0
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(2.8)
	tw.chain().tween_property(p, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(p.queue_free)
	_toasts.position.x = (size.x - _toasts.size.x) / 2.0


func _screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
	get_tree().quit()
