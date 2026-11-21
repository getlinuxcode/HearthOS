extends Control
## Comptes de jeux (onboarding 4 et Réglages) : cartes Steam / Epic / GOG avec les logos officiels.

const UI := preload("res://src/ui.gd")
const Stepper := preload("res://src/widgets/stepper.gd")
const SteamQR := preload("res://src/screens/steam_qr.gd")
const Dialog := preload("res://src/widgets/dialog.gd")

var onboarding := true
var on_next: Callable
var _grid: HBoxContainer
var _next: Button


func _init(is_onboarding := true, next_cb := Callable()) -> void:
	onboarding = is_onboarding
	on_next = next_cb


func _ready() -> void:
	if onboarding:
		add_child(Stepper.new(3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 30)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 220
	v.offset_right = -220
	v.offset_top = 120
	v.offset_bottom = -120
	var t := UI.label("Vos comptes de jeux", 60, 750)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("Votre bibliothèque arrive ici automatiquement. Aucune autre application à ouvrir.", 28, 400, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UI.vspacer(20))
	_grid = HBoxContainer.new()
	_grid.add_theme_constant_override("separation", 34)
	_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_grid)
	v.add_child(UI.vspacer(20))
	_next = UI.chunky("Continuer" if onboarding else "Terminé", "check", "primary", 30)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_next.pressed.connect(func():
		if on_next.is_valid(): on_next.call()
		else: App.back())
	v.add_child(_next)
	for i in v.get_child_count():
		UI.fade_in(v.get_child(i), 0.08 * i, 0.5)
	_render()


func on_resume() -> void:
	_render()


func default_focus() -> Control:
	return _grid.get_child(0) if _grid.get_child_count() > 0 else _next


func _render() -> void:
	var keep := 0
	for i in _grid.get_child_count():
		if _grid.get_child(i).has_focus():
			keep = i
	for c in _grid.get_children():
		c.queue_free()
	var acc = App.account
	var steam_sub := "Connecté : %s" % acc.personaName if acc is Dictionary else "Connexion par QR code"
	_grid.add_child(_card("steam", "Steam", steam_sub, Color("1b2838"), acc is Dictionary, _steam))
	var ep = App.epic_account
	var epic_sub := "Connecté : %s" % ep.name if ep is Dictionary else "Connexion depuis le téléphone"
	_grid.add_child(_card("epicgames", "Epic Games", epic_sub, Color("2a2a2a"), ep is Dictionary, _epic))
	_grid.add_child(_card("gogdotcom", "GOG", "Bientôt", Color("5c2d91"), false, func(): App.toast("GOG arrive bientôt", "schedule", UI.ACCENT)))
	await get_tree().process_frame
	if _grid.get_child_count() > keep:
		App.quiet_focus(_grid.get_child(keep))


func _card(brand: String, name: String, sub: String, color: Color, connected: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(380, 360)
	b.focus_mode = Control.FOCUS_ALL
	var normal := UI.box(Color(color, 0.85), color.darkened(0.5), 7, 34, Vector2(20, 20))
	var foc := UI.box(color.lightened(0.15), color.darkened(0.45), 7, 34, Vector2(20, 20))
	if connected:
		normal.border_color = Color("2a9d6f")
		foc.border_color = Color("2a9d6f")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", UI.focus_ring(40, 4))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var logo := TextureRect.new()
	logo.texture = App.brand(brand, 120, Color.WHITE)
	logo.custom_minimum_size = Vector2(120, 120)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(logo)
	var n := UI.label(name, 34, 750)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var s := UI.label(sub, 22, 500, UI.OK if connected else Color(1, 1, 1, 0.7))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	UI.center_pivot(b)
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		UI.pop(b, 1.06)
		var tw := logo.create_tween()
		tw.tween_property(logo, "rotation", 0.08, 0.12)
		tw.tween_property(logo, "rotation", -0.05, 0.12)
		tw.tween_property(logo, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_BACK))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		UI.pop(b, 1.0))
	logo.resized.connect(func(): logo.pivot_offset = logo.size / 2.0)
	b.pressed.connect(cb)
	return b


func _steam() -> void:
	if App.account is Dictionary:
		Dialog.open("Compte Steam", Dialog.text("Connecté en tant que %s." % App.account.personaName), [
			["Fermer", Callable(), "primary", "check"],
			["Se déconnecter", _logout, "danger", "logout"],
		])
	else:
		App.push(SteamQR.new())


func _logout() -> void:
	await App.api("POST", "/steam/logout")
	await App.load_library()
	_render()


func _epic() -> void:
	if App.epic_account is Dictionary:
		Dialog.open("Compte Epic Games", Dialog.text("Connecté en tant que %s." % App.epic_account.name), [
			["Fermer", Callable(), "primary", "check"],
			["Se déconnecter", _epic_logout, "danger", "logout"],
		])
	else:
		App.push(load("res://src/screens/epic_login.gd").new())


func _epic_logout() -> void:
	await App.api("POST", "/epic/logout")
	await App.load_library()
	_render()
