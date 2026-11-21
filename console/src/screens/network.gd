extends Control
## Onboarding 2 : connexion. Icônes vivantes (Wi-Fi qui cherche puis capte, globe qui tourne).

const UI := preload("res://src/ui.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")
const Stepper := preload("res://src/widgets/stepper.gd")
const VKeyboard := preload("res://src/widgets/vkeyboard.gd")

var _link_icon: AnimIcon
var _link_title: Label
var _link_sub: Label
var _net_icon: AnimIcon
var _net_title: Label
var _net_sub: Label
var _list: VBoxContainer
var _continue: Button


func _ready() -> void:
	add_child(Stepper.new(1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 360
	col.offset_right = -360
	col.offset_top = 150
	col.offset_bottom = -110

	var t := UI.label("Connexion à Internet", 60, 750)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := UI.label("Pour Steam, les mises à jour et les jaquettes de vos jeux.", 28, 400, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 24)
	col.add_child(tiles)
	var a := _tile("wifi")
	_link_icon = a[0]; _link_title = a[1]; _link_sub = a[2]
	tiles.add_child(a[3])
	var b := _tile("globe")
	_net_icon = b[0]; _net_title = b[1]; _net_sub = b[2]
	tiles.add_child(b[3])

	col.add_child(UI.label("RÉSEAUX WI-FI", 22, 700, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	_continue = UI.chunky("Continuer", "check", "primary", 30)
	_continue.pressed.connect(_finish)
	foot.add_child(_continue)

	for i in col.get_child_count():
		UI.fade_in(col.get_child(i), 0.1 + i * 0.07, 0.6)


func _tile(kind: String) -> Array:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI.panel_box(UI.PANEL, 28, 26))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	p.add_child(h)
	var ic := AnimIcon.new(kind, "search", 84, UI.ACCENT)
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var t := UI.label("…", 30, 650)
	var s := UI.label("", 22, 400, UI.DIM)
	v.add_child(t)
	v.add_child(s)
	return [ic, t, s, p]


func default_focus() -> Control:
	return _continue


func on_enter() -> void:
	_link_title.text = "Recherche…"
	_net_title.text = "Internet"
	_net_sub.text = "Vérification…"
	await _status()
	await _scan()


func _status() -> void:
	var st = await App.api("GET", "/network/status")
	if not (st is Dictionary) or st.has("_error"):
		_link_icon.set_state("off")
		_link_title.text = "Service réseau absent"
		_net_icon.set_state("off")
		_net_sub.text = "Mode hors-ligne"
		return
	App.network = st
	if st.connected:
		_link_icon.kind = "ethernet" if st.type == "ethernet" else "wifi"
		_link_icon.color = UI.OK
		_link_icon.set_state("on")
		_link_title.text = "Ethernet" if st.type == "ethernet" else st.get("name", "Wi-Fi")
		_link_sub.text = "Connecté · %s" % (st.addresses[0] if st.addresses.size() > 0 else "")
	else:
		_link_icon.set_state("search")
		_link_title.text = "Non connecté"
		_link_sub.text = "Choisissez un réseau ci-dessous"
	_net_icon.color = UI.OK if st.internet else UI.WARN
	_net_icon.set_state("on" if st.internet else "off")
	_net_sub.text = "Accès Internet OK" if st.internet else "Pas d'accès Internet"


func _scan() -> void:
	for c in _list.get_children():
		c.queue_free()
	var spin := HBoxContainer.new()
	spin.add_theme_constant_override("separation", 16)
	spin.add_child(AnimIcon.new("spinner", "on", 34, UI.DIM))
	spin.add_child(UI.label("Recherche des réseaux Wi-Fi…", 24, 400, UI.DIM))
	_list.add_child(spin)
	var nets = await App.api("GET", "/network/wifi")
	spin.queue_free()
	if not (nets is Array):
		return
	var i := 0
	for n in nets:
		var b := _row(n)
		_list.add_child(b)
		UI.fade_in(b, i * 0.06, 0.4)
		i += 1


func _row(n: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 84
	var normal := UI.box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0.3), 4, 22, Vector2(28, 14))
	var foc := UI.box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0.3), 4, 22, Vector2(28, 14))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", UI.focus_ring(26, 3))
	b.focus_entered.connect(func(): b.add_theme_stylebox_override("normal", foc))
	b.focus_exited.connect(func(): b.add_theme_stylebox_override("normal", normal))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 28
	h.offset_right = -28
	var strength := clampf(n.signal / 100.0, 0.25, 1.0)
	h.add_child(UI.icon_rect("wifi", 40, Color(1, 1, 1, 0.35 + 0.65 * strength)))
	var name := UI.label(n.ssid, 28, 600)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name)
	h.add_child(UI.hspacer())
	if n.active:
		var c := UI.label("Connecté", 22, 600, UI.OK)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	var sig := UI.label("%d %%" % n.signal, 22, 500, UI.DIM)
	sig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sig)
	if n.secure:
		h.add_child(UI.icon_rect("lock", 30, UI.DIM))
	b.pressed.connect(func(): _connect(n))
	return b


func _connect(n: Dictionary) -> void:
	var pw = ""
	if n.secure:
		var kb := VKeyboard.new("Mot de passe de « %s »" % n.ssid, true)
		App.open_modal(kb)
		pw = await kb.done
		if pw == null or pw == "":
			return
	_link_icon.kind = "wifi"
	_link_icon.color = UI.ACCENT
	_link_icon.set_state("search")
	_link_title.text = "Connexion à %s…" % n.ssid
	var res = await App.api("POST", "/network/wifi/connect", {"ssid": n.ssid, "password": pw})
	if res is Dictionary and res.has("_error"):
		App.sfx.play("error")
		App.toast(res._error, "wifi_off", UI.DANGER)
	else:
		App.sfx.play("success")
		App.toast("Connecté à %s" % n.ssid, "wifi")
	await _status()
	App.quiet_focus(_continue)


func _finish() -> void:
	# Depuis les Réglages : simple retour ; pendant l'onboarding : étape suivante.
	if App.settings.get("onboarded", false):
		App.back()
	else:
		preload("res://src/flow.gd").next("network")
