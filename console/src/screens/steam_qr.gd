extends Control
## Connexion Steam : QR code à scanner avec l'application Steam du téléphone (Steam Guard).

const UI := preload("res://src/ui.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")

var _qr_box: PanelContainer
var _qr: TextureRect
var _status_icon: AnimIcon
var _status: Label
var _retry: Button
var _cancel: Button
var _poll: Timer
var _done := false
var _scan_line: ColorRect


func _ready() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 90)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_top = 80
	h.offset_bottom = -100

	_qr_box = PanelContainer.new()
	var sb := UI.panel_box(Color.WHITE, 36, 30)
	sb.shadow_color = Color(0.48, 0.6, 1.0, 0.45)
	sb.shadow_size = 60
	sb.shadow_offset = Vector2.ZERO
	_qr_box.add_theme_stylebox_override("panel", sb)
	_qr_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_qr_box)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(440, 440)
	holder.clip_contents = true
	_qr_box.add_child(holder)
	_qr = TextureRect.new()
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(_qr)
	_qr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scan_line = ColorRect.new()
	_scan_line.color = Color(0.48, 0.6, 1.0, 0.35)
	_scan_line.size = Vector2(440, 6)
	holder.add_child(_scan_line)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	v.custom_minimum_size.x = 760
	h.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var logo := TextureRect.new()
	logo.texture = App.brand("steam", 44, UI.ACCENT)
	logo.custom_minimum_size = Vector2(44, 44)
	head.add_child(logo)
	head.add_child(UI.label("STEAM", 26, 700, UI.ACCENT))
	v.add_child(head)
	v.add_child(UI.label("Scannez avec votre téléphone", 58, 750))
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 14)
	for s in [["1", "Ouvrez l'application Steam sur votre téléphone"], ["2", "Touchez l'icône Steam Guard (le bouclier)"], ["3", "Choisissez « Scanner un QR code » et visez l'écran"]]:
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
		var tl := UI.label(s[1], 28, 450, Color("d6dbe7"))
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
		steps.add_child(row)
	v.add_child(steps)
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 16)
	_status_icon = AnimIcon.new("spinner", "on", 44, UI.ACCENT)
	st.add_child(_status_icon)
	_status = UI.label("Préparation du code…", 28, 500)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(_status)
	v.add_child(st)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 20)
	_retry = UI.chunky("Nouveau code", "refresh", "normal", 26)
	_retry.visible = false
	_retry.pressed.connect(_start)
	btns.add_child(_retry)
	_cancel = UI.chunky("Annuler", "", "ghost", 26)
	_cancel.pressed.connect(func(): App.back())
	btns.add_child(_cancel)
	v.add_child(btns)
	for i in v.get_child_count():
		UI.fade_in(v.get_child(i), 0.1 + 0.07 * i, 0.5)
	_qr_box.pivot_offset = Vector2(250, 250)
	_qr_box.scale = Vector2(0.85, 0.85)
	_qr_box.create_tween().tween_property(_qr_box, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_poll = Timer.new()
	_poll.wait_time = 2.0
	_poll.timeout.connect(_check)
	add_child(_poll)


func on_enter() -> void:
	_start()


func on_leave() -> void:
	_poll.stop()


func default_focus() -> Control:
	return _retry if _retry.visible else _cancel


func _process(delta: float) -> void:
	if _scan_line and not _done and _qr.texture:
		_scan_line.visible = true
		_scan_line.position.y = 220.0 + 200.0 * sin(Time.get_ticks_msec() / 700.0)
	elif _scan_line:
		_scan_line.visible = false


func _start() -> void:
	_retry.visible = false
	_qr.modulate.a = 0.3
	_status_icon.kind = "spinner"
	_status.text = "Préparation du code…"
	var r = await App.api("POST", "/steam/login/qr")
	if not (r is Dictionary) or r.has("_error"):
		_status_icon.kind = "check"
		_status_icon.color = UI.DANGER
		_status.text = r._error if r is Dictionary else "Service système injoignable"
		_retry.visible = true
		App.quiet_focus(_retry)
		return
	# Le SVG du QR fait ~37 unités : on le rastérise net à ~440 px.
	var svg: String = r.qrSvg
	_qr.texture = App.svg_from_string(svg, 12.0)
	_qr.create_tween().tween_property(_qr, "modulate:a", 1.0, 0.4)
	_status_icon.kind = "spinner"
	_status.text = "En attente du scan…"
	_poll.start()


func _check() -> void:
	var s = await App.api("GET", "/steam/login/status")
	if not (s is Dictionary) or _done:
		return
	match s.state:
		"scanned":
			_status_icon.kind = "check"
			_status_icon.color = UI.ACCENT
			_status_icon.set_state("on")
			_status.text = "Scanné ! Validez sur votre téléphone."
		"done":
			_done = true
			_poll.stop()
			App.sfx.play("success")
			_status_icon.kind = "check"
			_status_icon.color = UI.OK
			_status_icon.set_state("on")
			_status.text = "Bienvenue %s ! Import de la bibliothèque…" % s.account.personaName
			var tw := _qr_box.create_tween()
			tw.tween_property(_qr_box, "scale", Vector2(0.0, 1.0), 0.25)
			tw.tween_callback(func():
				var a = s.account
				_qr.texture = null
				_qr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				_qr_box.get_theme_stylebox("panel").bg_color = Color("1b2838")
				_qr.texture = App.brand("steam", 300, Color.WHITE))
			tw.tween_property(_qr_box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			await App.load_library()
			App.toast("Steam connecté : %s" % s.account.personaName, "check")
			await get_tree().create_timer(1.0).timeout
			App.back()
		"timeout", "error":
			_poll.stop()
			_qr.modulate.a = 0.15
			_status_icon.kind = "check"
			_status_icon.color = UI.WARN
			_status.text = "Le code a expiré." if s.state == "timeout" else str(s.get("error", "Erreur"))
			_retry.visible = true
			App.quiet_focus(_retry)
