extends Control
## Réglages : menu à gauche (icônes), panneau de lignes à droite. Ⓑ dans le panneau → retour au menu.

const UI := preload("res://src/ui.gd")
const Rows := preload("res://src/widgets/rows.gd")
const Pads := preload("res://src/pads.gd")
const PadArt := preload("res://src/widgets/pad_art.gd")
const Dialog := preload("res://src/widgets/dialog.gd")
const Display := preload("res://src/screens/display.gd")

const CATS := [
	["network", "Réseau", "wifi"], ["display", "Affichage", "tune"], ["pads", "Manettes", "sports_esports"],
	["accounts", "Comptes", "person"], ["files", "Fichiers et FTP", "folder"], ["sound", "Son", "volume_up"],
	["time", "Date et heure", "schedule"], ["updates", "Mises à jour", "refresh"], ["system", "Système", "settings"], ["power", "Alimentation", "power_settings_new"],
]
const TIMEZONES := ["Europe/Paris", "Europe/Brussels", "Europe/Zurich", "America/Montreal", "Europe/London", "America/New_York", "Asia/Tokyo", "UTC"]

var initial := "network"
var _menu: VBoxContainer
var _cat_buttons := {}
var _title: Label
var _rows: Rows
var _extra: VBoxContainer
var _cat := ""
var _scroll: ScrollContainer


func _init(start := "network") -> void:
	initial = start


func _ready() -> void:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 50)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 90
	root.offset_right = -90
	root.offset_top = 60
	root.offset_bottom = -100

	_menu = VBoxContainer.new()
	_menu.custom_minimum_size.x = 430
	_menu.add_theme_constant_override("separation", 8)
	root.add_child(_menu)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(UI.icon_rect("settings", 48, UI.ACCENT))
	head.add_child(UI.label("Réglages", 52, 800))
	_menu.add_child(head)
	_menu.add_child(UI.vspacer(14))
	var i := 0
	for c in CATS:
		var b := _cat_button(c[0], c[1], c[2])
		_menu.add_child(b)
		_cat_buttons[c[0]] = b
		UI.fade_in(b, 0.03 * i, 0.35)
		i += 1

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.panel_box(UI.PANEL, 34, 30))
	root.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	panel.add_child(_scroll)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", 18)
	_scroll.add_child(pv)
	_title = UI.label("", 40, 750)
	pv.add_child(_title)
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 16)
	pv.add_child(_extra)
	_rows = Rows.new()
	pv.add_child(_rows)
	App.pads_changed.connect(func(): if _cat == "pads": _select("pads"))


func on_enter() -> void:
	App.bg.set_hero(null)
	App.bg.default_tint()
	await _select(initial)
	App.quiet_focus(_cat_buttons[initial])


func on_resume() -> void:
	_select(_cat)


func default_focus() -> Control:
	return _cat_buttons.get(_cat if _cat != "" else initial)


func hints() -> Array:
	var f := get_viewport().gui_get_focus_owner()
	if f and _rows.is_ancestor_of(f):
		return [["ui_accept", "Sélectionner"], ["lr", "Modifier"], ["ui_cancel", "Menu"]]
	return [["ui_accept", "Ouvrir"], ["ui_cancel", "Retour"]]


func on_cancel() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	if f and (_rows.is_ancestor_of(f) or _extra.is_ancestor_of(f)):
		App.sfx.play("back")
		App.quiet_focus(_cat_buttons[_cat])
		App.refresh_hints()
		return true
	return false


func _cat_button(id: String, label: String, icon_name: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = App.icon(icon_name, 34, UI.DIM)
	b.add_theme_constant_override("h_separation", 18)
	b.add_theme_font_override("font", App.font(600))
	b.add_theme_font_size_override("font_size", 27)
	b.add_theme_color_override("font_color", UI.DIM)
	b.add_theme_color_override("font_focus_color", Color("0b0e16"))
	b.add_theme_color_override("font_hover_color", Color("0b0e16"))
	var normal := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 22, Vector2(22, 14))
	normal.shadow_size = 0
	var active := UI.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 22, Vector2(22, 14))
	active.shadow_size = 0
	var foc := UI.box(Color(1, 1, 1, 0.95), Color("aab3c9"), 4, 22, Vector2(22, 14))
	foc.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_meta("styles", [normal, active])
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		b.icon = App.icon(icon_name, 34, Color("0b0e16"))
		if _cat != id: _select(id)
		App.refresh_hints())
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", active if _cat == id else normal)
		b.icon = App.icon(icon_name, 34, UI.TEXT if _cat == id else UI.DIM)
		b.add_theme_color_override("font_color", UI.TEXT if _cat == id else UI.DIM))
	b.pressed.connect(func():
		var f := _rows.first_focusable()
		if f == null:
			for c in _extra.find_children("*", "Button", true, false):
				f = c
				break
		if f: App.quiet_focus(f)
		App.refresh_hints())
	return b


func _select(id: String) -> void:
	var prev := _cat
	_cat = id
	for k in _cat_buttons:
		var b: Button = _cat_buttons[k]
		if not b.has_focus():
			var st: Array = b.get_meta("styles")
			b.add_theme_stylebox_override("normal", st[1] if k == id else st[0])
			b.add_theme_color_override("font_color", UI.TEXT if k == id else UI.DIM)
	for c in CATS:
		if c[0] == id:
			_title.text = c[1]
	for c in _extra.get_children():
		c.queue_free()
	_rows.set_rows([])
	if prev != id:
		UI.fade_in(_title, 0.0, 0.25)
	match id:
		"network": await _network()
		"display": await _display()
		"pads": _pads()
		"accounts": _accounts()
		"files": await _files()
		"sound": _sound()
		"time": _time()
		"updates": await _updates()
		"system": _system()
		"power": _power()


func _save(patch: Dictionary) -> void:
	App.settings.merge(patch, true)
	var r = await App.api("POST", "/settings", patch)
	if r is Dictionary and not r.has("_error"):
		App.settings = r


# ------------------------------------------------------------------ Panneaux

func _network() -> void:
	var st = await App.api("GET", "/network/status")
	var s: Dictionary = st if st is Dictionary and not st.has("_error") else {}
	_rows.set_rows([
		{"kind": "info", "label": "Connexion", "value": ("Ethernet" if s.get("type") == "ethernet" else "Wi-Fi · %s" % s.get("name", "")) if s.get("connected", false) else "Déconnecté"},
		{"kind": "info", "label": "Internet", "value": "OK" if s.get("internet", false) else "Indisponible"},
		{"kind": "info", "label": "Adresse IP", "value": ", ".join(PackedStringArray(s.get("addresses", []))) if s.get("addresses", []).size() > 0 else "—"},
		{"kind": "action", "label": "Réseaux Wi-Fi", "desc": "Rechercher et se connecter", "icon": "wifi",
			"run": func(): App.push(load("res://src/screens/network.gd").new())},
	])


func _display() -> void:
	var info = await App.api("GET", "/display")
	_rows.set_rows(Display.display_rows(info if info is Dictionary else {}))


func _pads() -> void:
	var pads := Pads.connected()
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 20)
	_extra.add_child(cards)
	if pads.is_empty():
		cards.add_child(UI.label("Aucune manette connectée.", 26, 400, UI.DIM))
	for p in pads:
		var c := PanelContainer.new()
		var sb := UI.panel_box(Color(1, 1, 1, 0.06), 26, 22)
		sb.shadow_size = 0
		c.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		c.add_child(v)
		var art := TextureRect.new()
		art.texture = App.svg_from_string(PadArt.svg(p.family), 0.42)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(art)
		v.add_child(UI.label(p.name, 26, 650))
		v.add_child(UI.label("Joueur %d%s" % [p.device + 1, (" · USB %s:%s" % [p.vendor, p.product]) if p.vendor != "" else ""], 20, 400, UI.DIM))
		cards.add_child(c)
	_rows.set_rows([
		{"kind": "action", "label": "Tester la manette", "desc": "Boutons, sticks et gâchettes en direct", "icon": "sports_esports",
			"run": func(): App.push(PadTest.new())},
		{"kind": "action", "label": "Tester les vibrations", "icon": "speed",
			"run": func():
				for p in Pads.connected(): Input.start_joy_vibration(p.device, 0.6, 0.9, 0.6)},
		{"kind": "action", "label": "Appairer une manette Bluetooth", "icon": "bluetooth", "run": _pair_help},
		{"kind": "choice", "label": "Clavier virtuel", "options": [["azerty", "AZERTY"], ["qwerty", "QWERTY"]],
			"get": func(): return App.settings.get("keyboardLayout", "azerty"),
			"set": func(v): await _save({"keyboardLayout": v})},
	])


func _pair_help() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	for it in [["dualsense", "DualSense / DualShock 4", "Maintenez Create/Share + PS 3 secondes : la barre lumineuse clignote."],
			["xbox", "Manette Xbox", "Allumez-la puis maintenez le bouton d'appairage sur la tranche."],
			["switch", "Manette Pro Switch", "Maintenez le bouton de synchronisation en haut."]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 20)
		var art := TextureRect.new()
		art.texture = App.svg_from_string(PadArt.svg(it[0]), 0.28)
		h.add_child(art)
		var t := VBoxContainer.new()
		t.add_child(UI.label(it[1], 26, 650))
		var d := UI.label(it[2], 21, 400, UI.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 520
		t.add_child(d)
		h.add_child(t)
		v.add_child(h)
	Dialog.open("Appairer en Bluetooth", v, [["Compris", Callable(), "primary", "check"]], 820)


func _accounts() -> void:
	_rows.set_rows([
		{"kind": "action", "label": "Steam", "desc": ("Connecté : %s" % App.account.personaName) if App.account is Dictionary else "Non connecté", "icon": "person",
			"run": func(): App.push(load("res://src/screens/accounts.gd").new(false))},
		{"kind": "info", "label": "Epic Games", "value": "Bientôt (code d'appareil)"},
		{"kind": "info", "label": "GOG", "value": "Bientôt"},
		{"kind": "info", "label": "Achats", "value": "Finalisés chez Steam : aucune donnée de paiement ne passe par la console"},
	])


func _files() -> void:
	var f = await App.api("GET", "/ftp")
	if not (f is Dictionary) or f.has("_error"):
		_rows.set_rows([{"kind": "info", "label": "FTP", "value": "Service système injoignable"}])
		return
	var ftp: Dictionary = f
	var defs := [
		{"kind": "toggle", "label": "Serveur FTP", "desc": "Envoyer ROM, BIOS et fichiers depuis un PC du réseau local",
			"get": func(): return ftp.enabled,
			"set": func(v):
				var r = await App.api("POST", "/ftp", {"enabled": v})
				if r is Dictionary and r.get("error", "") != "":
					App.toast("FTP : %s" % r.error, "close", UI.DANGER)
				elif r is Dictionary:
					App.toast("Serveur FTP %s" % ("activé" if v else "désactivé"), "folder")
				_select("files")},
	]
	if ftp.enabled:
		var addrs := PackedStringArray()
		for a in ftp.addresses:
			addrs.append("ftp://%s:%d" % [a, ftp.port])
		defs.append({"kind": "info", "label": "Adresse", "value": "  ·  ".join(addrs) if addrs.size() > 0 else "aucune adresse réseau"})
		defs.append({"kind": "info", "label": "Utilisateur", "value": ftp.user})
		defs.append({"kind": "info", "label": "Mot de passe", "value": ftp.password})
		defs.append({"kind": "action", "label": "Nouveau mot de passe", "icon": "refresh",
			"run": func():
				await App.api("POST", "/ftp/password")
				_select("files")})
	defs.append({"kind": "header", "label": "Dossiers partagés"})
	defs.append({"kind": "info", "label": "roms/", "value": "Un sous-dossier par console (snes, gba, psx…) ou en vrac"})
	defs.append({"kind": "info", "label": "bios/", "value": "BIOS demandés par certains émulateurs"})
	defs.append({"kind": "info", "label": "files/", "value": "Tout le reste"})
	defs.append({"kind": "info", "label": "Sécurité", "value": "FTP n'est pas chiffré : à activer uniquement chez vous"})
	_rows.set_rows(defs)


func _sound() -> void:
	_rows.set_rows([
		{"kind": "toggle", "label": "Sons de l'interface",
			"get": func(): return App.sfx.enabled,
			"set": func(v):
				App.sfx.enabled = v
				if v: App.sfx.play("confirm")
				await _save({"sounds": v})},
		{"kind": "choice", "label": "Volume général", "options": [[1.0, "100 %"], [0.75, "75 %"], [0.5, "50 %"], [0.25, "25 %"]],
			"get": func(): return snappedf(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.25),
			"set": func(v):
				AudioServer.set_bus_volume_db(0, linear_to_db(v))
				App.sfx.play("tick")},
		{"kind": "info", "label": "Sortie audio", "value": "Automatique (PipeWire)"},
	])


func _time() -> void:
	var opts := []
	for t in TIMEZONES:
		opts.append([t, t.replace("_", " ")])
	_rows.set_rows([
		{"kind": "choice", "label": "Fuseau horaire", "options": opts,
			"get": func(): return App.settings.get("timezone", "Europe/Paris"),
			"set": func(v): await _save({"timezone": v})},
		{"kind": "toggle", "label": "Format 24 heures", "get": func(): return App.settings.get("clock24h", true),
			"set": func(v): await _save({"clock24h": v})},
		{"kind": "info", "label": "Synchronisation", "value": "Automatique (NTP)"},
	])


func _system() -> void:
	var i: Dictionary = App.info
	var mode: String = {"dev": "Développement", "live": "Live USB", "installed": "Installé"}.get(i.get("mode", "dev"), "?")
	_rows.set_rows([
		{"kind": "info", "label": "Version", "value": i.get("version", "?")},
		{"kind": "info", "label": "Mode", "value": mode},
		{"kind": "info", "label": "Processeur", "value": i.get("cpu", "?")},
		{"kind": "info", "label": "Carte graphique", "value": ", ".join(PackedStringArray(i.get("gpu", []))) if i.get("gpu", []).size() > 0 else "?"},
		{"kind": "info", "label": "Mémoire", "value": "%d Go" % i.get("memoryGB", 0)},
		{"kind": "info", "label": "Noyau", "value": i.get("kernel", "?")},
		{"kind": "info", "label": "Proton par défaut", "value": "Proton-CachyOS"},
		{"kind": "action", "label": "Relancer la configuration initiale", "icon": "refresh",
			"run": func():
				App.settings["onboarded"] = false
				App.replace_all(load("res://src/screens/pad_connect.gd").new())},
	])


func _power() -> void:
	_rows.set_rows([
		{"kind": "action", "label": "Options d'alimentation", "icon": "power_settings_new",
			"run": func(): App.open_modal(load("res://src/screens/power_menu.gd").new())},
	])


# ------------------------------------------------------------------ Test manette

class PadTest extends Control:
	const PadArt2 := preload("res://src/widgets/pad_art.gd")
	const UI2 := preload("res://src/ui.gd")
	var _tex: Texture2D
	var _fam := ""
	var _scale := 1.5
	var _name: Label

	func _ready() -> void:
		set_meta("can_back", false)
		var t := UI2.label("Test de la manette", 52, 800)
		t.position = Vector2(110, 70)
		add_child(t)
		_name = UI2.label("", 28, 500, UI2.DIM)
		_name.position = Vector2(110, 140)
		add_child(_name)
		var h := UI2.label("Appuyez sur les boutons. Maintenez Start + Select (ou Échap) pour quitter.", 24, 400, UI2.DIM)
		h.position = Vector2(110, 960)
		add_child(h)

	func hints() -> Array:
		return [["ui_cancel", "Quitter (Échap)"]]

	func _input(ev: InputEvent) -> void:
		# toutes les entrées manette sont pour le test ; le clavier permet de sortir
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			if Input.is_joy_button_pressed(ev.device, JOY_BUTTON_START) and Input.is_joy_button_pressed(ev.device, JOY_BUTTON_BACK):
				App.back()
		elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			App.back()

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var pads := preload("res://src/pads.gd").connected()
		if pads.is_empty():
			_name.text = "Aucune manette connectée"
			return
		var p: Dictionary = pads[0]
		if p.family != _fam:
			_fam = p.family
			_tex = App.svg_from_string(PadArt2.svg(_fam), _scale)
			_name.text = p.name
		var dev: int = p.device
		var origin := size / 2.0 - _tex.get_size() / 2.0 + Vector2(0, 30)
		draw_texture(_tex, origin)
		var pos: Dictionary = PadArt2.layout(_fam)
		var fr: float = pos.face_r
		var at := func(v: Vector2) -> Vector2: return origin + v * _scale
		var hl := Color("7c9cff")
		var face := [[JOY_BUTTON_A, Vector2(0, fr)], [JOY_BUTTON_B, Vector2(fr, 0)], [JOY_BUTTON_X, Vector2(-fr, 0)], [JOY_BUTTON_Y, Vector2(0, -fr)]]
		for f in face:
			if Input.is_joy_button_pressed(dev, f[0]):
				draw_circle(at.call(pos.face + f[1]), 15 * _scale, Color(hl, 0.85))
		var dp: Vector2 = pos.dpad
		for d in [[JOY_BUTTON_DPAD_UP, Vector2(0, -26)], [JOY_BUTTON_DPAD_DOWN, Vector2(0, 26)], [JOY_BUTTON_DPAD_LEFT, Vector2(-26, 0)], [JOY_BUTTON_DPAD_RIGHT, Vector2(26, 0)]]:
			if Input.is_joy_button_pressed(dev, d[0]):
				draw_circle(at.call(dp + d[1]), 11 * _scale, Color(hl, 0.85))
		for s in [["ls", JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_BUTTON_LEFT_STICK], ["rs", JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_BUTTON_RIGHT_STICK]]:
			var c: Vector2 = pos[s[0]]
			var off := Vector2(Input.get_joy_axis(dev, s[1]), Input.get_joy_axis(dev, s[2])) * 10.0
			draw_circle(at.call(c + off), 21 * _scale, Color(hl if Input.is_joy_button_pressed(dev, s[3]) else Color.WHITE, 0.55))
		for sh in [[JOY_BUTTON_LEFT_SHOULDER, pos.lb], [JOY_BUTTON_RIGHT_SHOULDER, pos.rb]]:
			if Input.is_joy_button_pressed(dev, sh[0]):
				draw_rect(Rect2(at.call(sh[1] - Vector2(42, 18)), Vector2(84, 30) * _scale), Color(hl, 0.85))
		for tr in [[JOY_AXIS_TRIGGER_LEFT, pos.lb - Vector2(0, 26)], [JOY_AXIS_TRIGGER_RIGHT, pos.rb - Vector2(0, 26)]]:
			var v := Input.get_joy_axis(dev, tr[0])
			if v > 0.05:
				draw_rect(Rect2(at.call(tr[1] - Vector2(42, 4)), Vector2(84 * v, 8) * _scale), Color(hl, 0.9))
		for b in [[JOY_BUTTON_BACK, pos.select], [JOY_BUTTON_START, pos.start], [JOY_BUTTON_GUIDE, pos.home]]:
			if Input.is_joy_button_pressed(dev, b[0]):
				draw_circle(at.call(b[1]), 10 * _scale, Color(hl, 0.9))


# ------------------------------------------------------------------ Mises à jour

var _upd_timer: Timer

func _updates() -> void:
	var s = await App.api("GET", "/updates")
	if not (s is Dictionary) or s.has("_error"):
		_rows.set_rows([{"kind": "info", "label": "Mises à jour", "value": "Service système injoignable"}])
		return
	var st: Dictionary = s
	var state_txt: String = {
		"idle": "Pas encore vérifié", "checking": "Recherche…", "uptodate": "À jour",
		"available": "Version %s disponible" % st.get("available", ""), "downloading": "Téléchargement… %d %%" % st.progress,
		"installing": "Installation…", "ready": "Version %s installée : redémarrez l'interface" % st.get("installed", ""),
		"error": "Erreur : %s" % st.get("error", ""),
	}.get(st.state, st.state)
	var defs := [
		{"kind": "info", "label": "Version actuelle", "value": st.current},
		{"kind": "info", "label": "État", "value": state_txt},
	]
	match st.state:
		"available":
			if st.get("notes", "") != "":
				defs.append({"kind": "info", "label": "Nouveautés", "value": st.notes})
			var mb := " (%.1f Mo)" % (float(st.get("size", 0)) / 1048576.0) if st.get("size", 0) else ""
			defs.append({"kind": "action", "label": "Installer la version %s%s" % [st.available, mb], "icon": "download",
				"run": func():
					var r = await App.api("POST", "/updates/install")
					if r is Dictionary and r.has("_error"): App.toast(r._error, "close", UI.DANGER)
					_select("updates")})
		"ready":
			defs.append({"kind": "action", "label": "Redémarrer l'interface maintenant", "icon": "refresh",
				"run": func():
					App.sfx.play("transition")
					App.bg.blackout(1.0, 0.6)
					await get_tree().create_timer(0.7).timeout
					get_tree().quit()})
		"downloading", "installing":
			pass
		_:
			defs.append({"kind": "action", "label": "Rechercher une mise à jour", "icon": "refresh",
				"run": func():
					await App.api("POST", "/updates/check")
					_select("updates")})
	if st.get("rollback", null) != null and st.state != "downloading":
		defs.append({"kind": "action", "label": "Revenir à la version %s" % st.rollback, "icon": "arrow_back",
			"run": func():
				await App.api("POST", "/updates/rollback")
				App.toast("Retour en arrière prêt : redémarrez l'interface", "refresh", UI.ACCENT)
				_select("updates")})
	defs.append({"kind": "header", "label": "Système Arch Linux"})
	if st.systemUpdatable:
		defs.append({"kind": "action", "label": "Mettre à jour le système", "desc": "Noyau, pilotes, Steam, Proton… (instantané btrfs avant)", "icon": "download",
			"run": func():
				var r = await App.api("POST", "/updates/system")
				App.toast(r._error if r is Dictionary and r.has("_error") else "Mise à jour du système lancée", "download", UI.ACCENT)
				_select("updates")})
		if st.get("system", "") != "":
			defs.append({"kind": "info", "label": "Dernière mise à jour système", "value": {"running": "en cours…", "done": "terminée", "error": "échec"}.get(st.system, "")})
	else:
		defs.append({"kind": "info", "label": "Paquets du système", "value": "Disponible une fois Hearth installé sur le disque"})
	defs.append({"kind": "header", "label": "Avancé"})
	defs.append({"kind": "action", "label": "Canal de mise à jour", "desc": st.channel, "icon": "language",
		"run": func():
			var kb := preload("res://src/widgets/vkeyboard.gd").new("Adresse du manifeste (manifest.json)")
			kb.value = st.channel
			App.open_modal(kb)
			var url = await kb.done
			if url != null and str(url) != "":
				var r = await App.api("POST", "/updates/channel", {"url": str(url)})
				if r is Dictionary and r.has("_error"): App.toast(r._error, "close", UI.DANGER)
			_select("updates")})
	_rows.set_rows(defs)
	# Rafraîchissement automatique pendant téléchargement / installation
	if _upd_timer == null:
		_upd_timer = Timer.new()
		_upd_timer.wait_time = 1.0
		_upd_timer.timeout.connect(func():
			if _cat == "updates" and not _rows.is_ancestor_of(get_viewport().gui_get_focus_owner()):
				_select("updates")
			elif _cat == "updates":
				var s2 = await App.api("GET", "/updates")
				if s2 is Dictionary and s2.get("state", "") in ["downloading", "installing", "checking"] or (s2 is Dictionary and s2.get("state", "") != st.state):
					_select("updates"))
		add_child(_upd_timer)
	if st.state in ["downloading", "installing", "checking"]:
		_upd_timer.start()
	else:
		_upd_timer.stop()
