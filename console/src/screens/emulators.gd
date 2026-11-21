extends Control
## Émulateurs : consoles (installer le moteur libretro, BIOS), dossiers de jeux surveillés, accès FTP.
## Le moteur tourne sans son interface : c'est cette console qui gère bibliothèque et lancement.

const UI := preload("res://src/ui.gd")
const Rows := preload("res://src/widgets/rows.gd")
const Dialog := preload("res://src/widgets/dialog.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")

const MAKER_COLORS := {"Nintendo": Color("e4000f"), "Sega": Color("1758a8"), "Sony": Color("2e3fa8"), "NEC": Color("e8730c"), "Arcade": Color("8a2be2")}

var _systems: Array = []
var _grid: GridContainer
var _folders: Rows
var _ftp: Label
var _installing := {}
var _first: Control


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 76
	scroll.offset_right = -76
	scroll.offset_top = 50
	scroll.offset_bottom = -100
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top"]:
		pad.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(pad)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 22)
	pad.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	var logo := TextureRect.new()
	logo.texture = App.brand("retroarch", 56, UI.ACCENT)
	logo.custom_minimum_size = Vector2(56, 56)
	head.add_child(logo)
	head.add_child(UI.label("Émulateurs", 56, 800))
	v.add_child(head)
	v.add_child(UI.label("Choisissez une console pour installer son moteur. Vos jeux apparaissent dans l'accueil, onglet Rétro.", 25, 400, UI.DIM))

	v.add_child(_section("CONSOLES"))
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 20)
	v.add_child(_grid)

	v.add_child(_section("DOSSIERS DE JEUX"))
	_folders = Rows.new()
	v.add_child(_folders)

	v.add_child(_section("DEPUIS UN PC"))
	var ftp := PanelContainer.new()
	ftp.add_theme_stylebox_override("panel", UI.panel_box(UI.PANEL, 26, 26))
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 22)
	ftp.add_child(fh)
	fh.add_child(UI.icon_rect("folder", 48, UI.ACCENT))
	var fv := VBoxContainer.new()
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(fv)
	fv.add_child(UI.label("Transfert FTP", 28, 700))
	_ftp = UI.label("", 22, 400, UI.DIM)
	_ftp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fv.add_child(_ftp)
	var fb := UI.chunky("Gérer", "settings", "normal", 24)
	fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fb.pressed.connect(func(): App.push(load("res://src/screens/settings.gd").new("files")))
	fh.add_child(fb)
	v.add_child(ftp)
	for i in v.get_child_count():
		UI.fade_in(v.get_child(i), 0.04 * i, 0.4)


func _section(t: String) -> Label:
	var l := UI.label(t, 21, 700, UI.DIM)
	l.add_theme_constant_override("line_spacing", 0)
	return l


func on_enter() -> void:
	App.bg.set_hero(null)
	App.bg.tint(Color("5a3fd6"))
	await _reload()
	if _first:
		App.quiet_focus(_first)


func on_resume() -> void:
	_reload()


func default_focus() -> Control:
	return _first


func _reload() -> void:
	var sys = await App.api("GET", "/emu/systems")
	var folders = await App.api("GET", "/emu/folders")
	var ftp = await App.api("GET", "/ftp")
	_systems = sys if sys is Array else []
	_render_systems()
	_render_folders(folders if folders is Array else [])
	if ftp is Dictionary and not ftp.has("_error"):
		_ftp.text = ("Actif · ftp://%s:%d · utilisateur %s · déposez vos jeux dans roms/, vos BIOS dans bios/." % [ftp.addresses[0] if ftp.addresses.size() > 0 else "?", ftp.port, ftp.user]) if ftp.enabled else "Désactivé. Activez-le pour envoyer jeux, BIOS et fichiers depuis votre ordinateur."


func _render_systems() -> void:
	var keep := ""
	var f := get_viewport().gui_get_focus_owner()
	if f and f.has_meta("sys"):
		keep = f.get_meta("sys")
	for c in _grid.get_children():
		c.queue_free()
	_first = null
	for s in _systems:
		var b := _sys_card(s)
		_grid.add_child(b)
		if _first == null:
			_first = b
		if s.id == keep:
			App.quiet_focus.call_deferred(b)


func _sys_card(s: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(404, 196)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("sys", s.id)
	var col: Color = MAKER_COLORS.get(s.maker, UI.ACCENT)
	var normal := UI.box(Color(0.1, 0.12, 0.19, 0.9), Color(0, 0, 0, 0.5), 5, 26, Vector2(22, 18))
	if s.coreInstalled:
		normal.border_color = Color(UI.OK, 0.7)
	var foc := UI.box(Color(0.18, 0.21, 0.31, 0.97), col, 5, 26, Vector2(22, 18))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", UI.focus_ring(32, 4))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_top = 18
	v.offset_right = -160
	v.offset_bottom = -18
	# Icône officielle de la console (thème RetroArch), en filigrane à droite.
	var ico := TextureRect.new()
	ico.texture = App.system_icon(s.id)
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico.modulate = Color(col.lightened(0.55), 0.55)
	b.add_child(ico)
	ico.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ico.offset_left = -158
	ico.offset_right = -10
	ico.offset_top = 22
	ico.offset_bottom = 150
	ico.pivot_offset = Vector2(70, 56)
	b.set_meta("ico", ico)
	var top := HBoxContainer.new()
	top.add_child(UI.label(s.short, 40, 900, col.lightened(0.45)))
	top.add_child(UI.hspacer())
	v.add_child(top)
	var name := UI.label(s.name, 22, 600)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size.x = 220
	v.add_child(name)
	v.add_child(UI.vspacer())
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 10)
	if _installing.has(s.id):
		st.add_child(AnimIcon.new("spinner", "on", 26, UI.ACCENT))
		st.add_child(UI.label("Installation…", 20, 700, UI.ACCENT))
	elif s.coreInstalled:
		st.add_child(UI.icon_rect("check", 26, UI.OK))
		st.add_child(UI.label("Prêt · %d jeu%s" % [s.romCount, "x" if s.romCount > 1 else ""], 20, 700, UI.OK))
	else:
		st.add_child(UI.icon_rect("download", 26, UI.DIM))
		st.add_child(UI.label("Installer le moteur", 20, 600, UI.DIM))
	if s.get("bios", null) is Array:
		for bi in s.bios:
			if not bi.present:
				st.add_child(UI.label("· BIOS manquant", 18, 700, UI.WARN))
				break
	v.add_child(st)
	UI.center_pivot(b)
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		UI.pop(b, 1.05)
		var tw := ico.create_tween().set_parallel(true)
		tw.tween_property(ico, "modulate", Color.WHITE, 0.25)
		tw.tween_property(ico, "scale", Vector2(1.12, 1.12), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		App.bg.tint(col.darkened(0.2), 0.8))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		var tw2 := ico.create_tween().set_parallel(true)
		tw2.tween_property(ico, "modulate", Color(col.lightened(0.55), 0.55), 0.25)
		tw2.tween_property(ico, "scale", Vector2.ONE, 0.3)
		UI.pop(b, 1.0))
	b.pressed.connect(func(): _system_dialog(s))
	return b


func _system_dialog(s: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var big := TextureRect.new()
	big.texture = App.system_icon(s.id)
	big.custom_minimum_size = Vector2(200, 160)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.modulate = MAKER_COLORS.get(s.maker, UI.ACCENT).lightened(0.5)
	v.add_child(big)
	v.add_child(Dialog.text("Moteur : %s (libretro) · %s" % [s.core, "installé" if s.coreInstalled else "non installé"]))
	var exts := " ".join(PackedStringArray(s.extensions)) if s.extensions.size() > 0 else ".zip"
	v.add_child(Dialog.text("Formats : %s, et .cue / .chd / .iso / .zip dans un dossier attribué à cette console." % exts))
	if s.get("bios", null) is Array:
		for bi in s.bios:
			var l := UI.label("BIOS %s : %s" % [bi.file, "présent" if bi.present else "manquant (à déposer dans bios/)"], 23, 600, UI.OK if bi.present else UI.WARN)
			v.add_child(l)
	var btns := [["Fermer", Callable(), "normal", "close"]]
	if not s.coreInstalled:
		btns.push_front(["Installer le moteur", func(): _install(s), "primary", "download"])
	Dialog.open(s.name, v, btns, 820)


func _install(s: Dictionary) -> void:
	_installing[s.id] = true
	_render_systems()
	var r = await App.api("POST", "/emu/systems/%s/install" % s.id)
	_installing.erase(s.id)
	if r is Array:
		_systems = r
		App.toast("%s prêt" % s.name, "check")
	else:
		App.toast(r._error if r is Dictionary else "Installation impossible", "close", UI.DANGER)
	_render_systems()


func _render_folders(folders: Array) -> void:
	var defs := []
	for f in folders:
		var sys_name := "Détection automatique"
		for s in _systems:
			if s.id == f.system:
				sys_name = s.name
		defs.append({"kind": "action", "label": f.path, "icon": "folder",
			"desc": "%s · %d jeu%s%s" % [sys_name, f.romCount, "x" if f.romCount > 1 else "", " · surveillé en direct" if f.watching else ""],
			"run": func(): _folder_dialog(f)})
	defs.append({"kind": "action", "label": "Ajouter un dossier", "desc": "Disque, clé USB, dossier réseau…", "icon": "download", "run": _add_folder})
	_folders.set_rows(defs)


func _folder_dialog(f: Dictionary) -> void:
	Dialog.open("Dossier de jeux", Dialog.text(f.path), [
		["Changer la console", func(): _change_system(f), "normal", "sports_esports"],
		["Rescanner", _rescan, "normal", "refresh"],
		["Retirer (les fichiers restent)", func(): _remove(f), "danger", "close"],
	], 820)


func _rescan() -> void:
	await App.api("POST", "/emu/rescan")
	await App.load_library()
	App.toast("Dossiers rescannés", "refresh", UI.ACCENT)
	_reload()


func _remove(f: Dictionary) -> void:
	await App.api("POST", "/emu/folders/%s/remove" % f.id)
	await App.load_library()
	_reload()


func _change_system(f: Dictionary) -> void:
	var sys = await _pick_system(f.system)
	if sys == null:
		return
	await App.api("POST", "/emu/folders/%s" % f.id, {"system": sys})
	await App.load_library()
	_reload()


func _add_folder() -> void:
	var path = await _browse("")
	if path == null:
		return
	var sys = await _pick_system("auto")
	if sys == null:
		return
	var r = await App.api("POST", "/emu/folders", {"path": path, "system": sys})
	if r is Dictionary and r.has("_error"):
		App.toast(r._error, "close", UI.DANGER)
	else:
		await App.load_library()
		App.toast("Dossier ajouté et surveillé", "folder")
	_reload()


## Choix de la console d'un dossier (grille de puces).
func _pick_system(current: String) -> Variant:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var picked := [null]
	var dh := [null]
	var entries := [{"id": "auto", "short": "AUTO", "name": "Détection automatique"}]
	entries.append_array(_systems)
	var focus_me: Button
	for s in entries:
		var b := UI.chunky(s.short, "", "primary" if s.id == current else "normal", 22)
		b.tooltip_text = s.name
		b.custom_minimum_size = Vector2(200, 64)
		var sid: String = s.id
		b.pressed.connect(func():
			picked[0] = sid
			dh[0].close())
		grid.add_child(b)
		if s.id == current or focus_me == null:
			focus_me = b
	dh[0] = Dialog.open("Ce dossier contient…", grid, [], 960)
	await get_tree().process_frame
	await get_tree().process_frame
	App.quiet_focus(focus_me)
	await dh[0].closed
	return picked[0]


## Navigateur de dossiers à la manette.
func _browse(start: String) -> Variant:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var path_l := UI.label("", 22, 500, UI.DIM)
	path_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	path_l.custom_minimum_size.x = 860
	box.add_child(path_l)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	var rows := Rows.new()
	scroll.add_child(rows)
	var result := [null]
	var d: Control = Dialog.open("Choisir un dossier", box, [], 960)
	var ld := [null]
	ld[0] = func(p: String):
		var r = await App.api("GET", "/fs/browse" + ("?path=" + p.uri_encode() if p != "" else ""))
		if not (r is Dictionary) or r.has("_error"):
			return
		path_l.text = r.path
		var sep := "\\" if r.path.contains("\\") else "/"
		var defs := [{"kind": "action", "label": "Choisir ce dossier", "icon": "check",
			"run": func():
				result[0] = r.path
				d.close()}]
		if r.parent != null:
			defs.append({"kind": "action", "label": "Dossier parent", "icon": "arrow_back", "run": func(): ld[0].call(r.parent)})
		for name in r.dirs:
			var full: String = r.path.trim_suffix(sep) + sep + name
			defs.append({"kind": "action", "label": name, "icon": "folder", "run": func(): ld[0].call(full)})
		rows.set_rows(defs)
		await get_tree().process_frame
		App.quiet_focus(rows.first_focusable())
	await get_tree().process_frame
	ld[0].call(start)
	await d.closed
	return result[0]
