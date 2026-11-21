extends Control
## Connexion Epic Games à la manette : un QR code ouvre sur le téléphone une page servie par la console ;
## on s'y connecte à Epic puis on colle le code → la console le reçoit directement. Rien à taper sur la TV.

const UI := preload("res://src/ui.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")

var _qr: TextureRect
var _status_icon: AnimIcon
var _status: Label
var _url: Label
var _retry: Button
var _cancel: Button
var _poll: Timer
var _done := false


func _ready() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 90)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_top = 60
	h.offset_bottom = -100

	var box := PanelContainer.new()
	var sb := UI.panel_box(Color.WHITE, 36, 30)
	sb.shadow_color = Color(1, 1, 1, 0.25)
	sb.shadow_size = 50
	sb.shadow_offset = Vector2.ZERO
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(box)
	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(420, 420)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(_qr)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	v.custom_minimum_size.x = 780
	h.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var logo := TextureRect.new()
	logo.texture = App.brand("epicgames", 48, Color.WHITE)
	logo.custom_minimum_size = Vector2(48, 48)
	head.add_child(logo)
	head.add_child(UI.label("EPIC GAMES", 26, 700))
	v.add_child(head)
	v.add_child(UI.label("Connectez-vous depuis votre téléphone", 54, 750))
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 14)
	for s in [["1", "Scannez le QR code (même Wi-Fi que la console)"], ["2", "Touchez « Se connecter à Epic Games »"], ["3", "Copiez le texte affiché et collez-le, puis « Envoyer »"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var num := PanelContainer.new()
		var nsb := UI.panel_box(Color(1, 1, 1, 0.12), 22, 0)
		nsb.shadow_size = 0
		num.add_theme_stylebox_override("panel", nsb)
		num.custom_minimum_size = Vector2(44, 44)
		var nl := UI.label(s[0], 24, 700)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.add_child(nl)
		row.add_child(num)
		var tl := UI.label(s[1], 27, 450, Color("d6dbe7"))
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
		steps.add_child(row)
	v.add_child(steps)
	_url = UI.label("", 20, 400, UI.DIM)
	v.add_child(_url)
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 16)
	_status_icon = AnimIcon.new("spinner", "on", 44, UI.ACCENT)
	st.add_child(_status_icon)
	_status = UI.label("Préparation…", 28, 500)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(_status)
	v.add_child(st)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 20)
	_retry = UI.chunky("Recommencer", "refresh", "normal", 26)
	_retry.visible = false
	_retry.pressed.connect(_start)
	btns.add_child(_retry)
	_cancel = UI.chunky("Annuler", "", "ghost", 26)
	_cancel.pressed.connect(func(): App.back())
	btns.add_child(_cancel)
	v.add_child(btns)
	for i in v.get_child_count():
		UI.fade_in(v.get_child(i), 0.1 + 0.07 * i, 0.5)
	UI.fade_in(box, 0.05, 0.6)
	_poll = Timer.new()
	_poll.wait_time = 1.5
	_poll.timeout.connect(_check)
	add_child(_poll)


func on_enter() -> void:
	App.bg.set_hero(null)
	App.bg.tint(Color("2b2b2b"))
	_start()


func on_leave() -> void:
	_poll.stop()


func default_focus() -> Control:
	return _retry if _retry.visible else _cancel


func _start() -> void:
	_retry.visible = false
	_status_icon.kind = "spinner"
	_status.text = "Préparation…"
	var r = await App.api("POST", "/epic/login")
	if not (r is Dictionary) or r.has("_error"):
		_status_icon.kind = "check"
		_status_icon.color = UI.DANGER
		_status.text = r._error if r is Dictionary else "Service système injoignable"
		_retry.visible = true
		App.quiet_focus(_retry)
		return
	_qr.texture = App.svg_from_string(r.qrSvg, 11.0)
	_url.text = r.pairUrl
	_status.text = "En attente du téléphone…"
	_poll.start()


func _check() -> void:
	var s = await App.api("GET", "/epic/login/status")
	if not (s is Dictionary) or _done:
		return
	if s.state == "done":
		_done = true
		_poll.stop()
		App.sfx.play("success")
		_status_icon.kind = "check"
		_status_icon.color = UI.OK
		_status_icon.set_state("on")
		_status.text = "Bienvenue %s ! Import de la bibliothèque…" % s.get("name", "")
		await App.load_library()
		App.toast("Epic Games connecté", "check")
		await get_tree().create_timer(1.0).timeout
		App.back()
	elif s.state == "error":
		_poll.stop()
		_status.text = str(s.get("error", "Erreur"))
		_retry.visible = true
