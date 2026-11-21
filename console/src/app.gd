extends Node
## Cœur du shell : état, navigation entre écrans, API du daemon, ressources, entrées globales.

signal pads_changed
signal glyphs_changed
signal library_changed

const API := "http://127.0.0.1:7300/api"
const Sfx := preload("res://src/sfx.gd")
const Pads := preload("res://src/pads.gd")

var root: Control
var bg: Node
var screen_layer: Control
var modal_layer: Control
var hints: Node
var toasts: VBoxContainer

var info := {}
var settings := {}
var library: Array = []
var account = null
var epic_account = null
var update_notified := ""
var demo_library := true
var network := {}
var daemon_online := false
var running_game = null
var overlay_open := false
var active_family := "keyboard"
var args := {}
var sfx: Node

var _fonts := {}
var _font_file: FontFile
var _tex := {}
var _stack: Array[Control] = []
var _quiet_focus := false
var _modals: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Une interface de menus n'a pas besoin de plus : sur un écran 144 Hz en 4K, le rendu
	# non bridé faisait tourner la carte graphique à pleine puissance.
	Engine.max_fps = 60
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_setup_input()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	sfx = Sfx.new()
	add_child(sfx)
	Input.joy_connection_changed.connect(func(_d, _c): pads_changed.emit())


func _setup_input() -> void:
	_action("guide", [JOY_BUTTON_GUIDE], [KEY_HOME, KEY_H])
	_action("start", [JOY_BUTTON_START], [KEY_M])
	_action("select", [JOY_BUTTON_BACK], [KEY_V])
	_action("lb", [JOY_BUTTON_LEFT_SHOULDER], [KEY_PAGEUP])
	_action("rb", [JOY_BUTTON_RIGHT_SHOULDER], [KEY_PAGEDOWN])
	_action("btn_x", [JOY_BUTTON_X], [KEY_X])
	_action("btn_y", [JOY_BUTTON_Y], [KEY_Y])
	_action("ui_cancel", [], [KEY_BACKSPACE])


func _action(name: String, joy: Array, keys: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.5)
	for b in joy:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.device = -1
		InputMap.action_add_event(name, e)
	for k in keys:
		var e := InputEventKey.new()
		e.keycode = k
		InputMap.action_add_event(name, e)


# ------------------------------------------------------------------ Ressources

func font(weight := 500) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	if _font_file == null:
		_font_file = FontFile.new()
		_font_file.load_dynamic_font("res://assets/fonts/Outfit.ttf")
		_font_file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_file.hinting = TextServer.HINTING_LIGHT
		_font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var fv := FontVariation.new()
	fv.base_font = _font_file
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_fonts[weight] = fv
	return fv


func svg_texture(path: String, px: int, color := Color.WHITE) -> Texture2D:
	var key := "%s|%d|%s" % [path, px, color.to_html()]
	if _tex.has(key):
		return _tex[key]
	var s := FileAccess.get_file_as_string(path)
	if s.is_empty():
		return null
	s = s.replace("<svg ", "<svg fill=\"#%s\" " % color.to_html(false))
	var base := 24.0
	var rx := RegEx.create_from_string("width=\"([0-9.]+)\"")
	var m := rx.search(s)
	if m:
		base = float(m.get_string(1))
	else:
		var vb := RegEx.create_from_string("viewBox=\"[-0-9.]+ [-0-9.]+ ([0-9.]+)")
		var mv := vb.search(s)
		if mv:
			base = float(mv.get_string(1))
	var img := Image.new()
	img.load_svg_from_string(s, float(px) / base)
	if color.a < 1.0:
		img.adjust_bcs(1, 1, 1)
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


func svg_from_string(svg: String, scale: float) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(svg, scale)
	return ImageTexture.create_from_image(img)


## Icône de console émulée (PNG monochrome blanc, à teinter via modulate).
func system_icon(id: String) -> Texture2D:
	var key := "sys|" + id
	if _tex.has(key):
		return _tex[key]
	var path := "res://assets/systems/%s.png" % id
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


func icon(name: String, px := 48, color := Color.WHITE) -> Texture2D:
	return svg_texture("res://assets/icons/%s.svg" % name, px, color)


func brand(name: String, px := 64, color := Color.WHITE) -> Texture2D:
	return svg_texture("res://assets/brands/%s.svg" % name, px, color)


## Télécharge (avec cache disque) une image distante : jaquettes, illustrations Steam.
func remote_texture(url: String) -> Texture2D:
	if url == "":
		return null
	if _tex.has(url):
		return _tex[url]
	var cache_path := "user://img_%s" % url.md5_text()
	var bytes := PackedByteArray()
	if FileAccess.file_exists(cache_path):
		bytes = FileAccess.get_file_as_bytes(cache_path)
	else:
		var req := HTTPRequest.new()
		req.timeout = 20
		add_child(req)
		var e := req.request(url)
		if e != OK:
			push_warning("image %s : requête impossible (%d)" % [url, e])
			req.queue_free()
			return null
		var res = await req.request_completed
		req.queue_free()
		if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
			push_warning("image %s : résultat %d, HTTP %d" % [url, res[0], res[1]])
			_tex[url] = null
			return null
		bytes = res[3]
		var f := FileAccess.open(cache_path, FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		_tex[url] = null
		return null
	# On ne garde en mémoire que la taille réellement affichée.
	var max_w := 1920 if url.contains("hero") else 420
	if img.get_width() > max_w:
		img.resize(max_w, int(img.get_height() * float(max_w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex[url] = tex
	return tex


## Couleur dominante (saturée) d'une image : teinte le fond animé.
func dominant_color(tex: Texture2D) -> Color:
	if tex == null:
		return Color("3b3f8f")
	var img := tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(12, 12, Image.INTERPOLATE_BILINEAR)
	var best := Color("3b3f8f")
	var best_score := -1.0
	var avg := Color(0, 0, 0)
	for y in 12:
		for x in 12:
			var c = img.get_pixel(x, y)
			avg += c / 144.0
			var score = c.s * (0.35 + c.v)
			if c.v > 0.15 and score > best_score:
				best_score = score
				best = c
	var out := best.lerp(avg, 0.25)
	return Color.from_hsv(out.h, clampf(out.s * 1.1, 0.35, 0.85), clampf(out.v, 0.45, 0.8))


const STEAM_CDN := "https://cdn.cloudflare.steamstatic.com/steam/apps/"

func steam_img(appid_v, kind: String) -> String:
	var appid := int(appid_v)
	match kind:
		"portrait": return STEAM_CDN + "%s/library_600x900.jpg" % appid
		"hero": return STEAM_CDN + "%s/library_hero.jpg" % appid
		"logo": return STEAM_CDN + "%s/logo.png" % appid
		_: return STEAM_CDN + "%s/header.jpg" % appid


# ------------------------------------------------------------------ API daemon

func api(method: String, path: String, body = null, timeout := 15.0) -> Variant:
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var payload := JSON.stringify(body if body != null else {}) if method == "POST" else ""
	if req.request(API + path, PackedStringArray(["Content-Type: application/json"]), m, payload) != OK:
		req.queue_free()
		return null
	var res = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		daemon_online = false
		return null
	daemon_online = true
	var parsed = JSON.parse_string(res[3].get_string_from_utf8())
	if res[1] >= 400:
		return {"_error": parsed.get("error", "Erreur") if parsed is Dictionary else "Erreur %d" % res[1]}
	return parsed


const DEMO_GAMES := [
	[1091500, "Cyberpunk 2077"], [1245620, "ELDEN RING"], [1086940, "Baldur's Gate 3"], [1145360, "Hades"],
	[367520, "Hollow Knight"], [413150, "Stardew Valley"], [292030, "The Witcher 3: Wild Hunt"],
	[814380, "Sekiro: Shadows Die Twice"], [730, "Counter-Strike 2"], [570, "Dota 2"],
]

func load_library() -> void:
	var lib = await api("GET", "/library")
	if lib is Dictionary and lib.has("games"):
		library = lib.games
		account = lib.get("account")
		epic_account = lib.get("epic")
		demo_library = lib.get("demo", false)
	else:
		library = []
		for g in DEMO_GAMES:
			library.append({"id": "steam:%d" % g[0], "appid": g[0], "name": g[1], "source": "steam",
				"installed": false, "playtimeMinutes": 0, "lastPlayed": 0, "demo": true})
		demo_library = true
	library_changed.emit()


# ------------------------------------------------------------------ Écrans

func push(screen: Control) -> void:
	var prev: Control = _stack.back() if not _stack.is_empty() else null
	_stack.append(screen)
	_enter(screen, true)
	if prev:
		prev.set_meta("last_focus", get_viewport().gui_get_focus_owner())
		_leave(prev, true, false)
		sfx.play("transition")


func replace_all(screen: Control) -> void:
	var old := _stack.duplicate()
	_stack.clear()
	_stack.append(screen)
	_enter(screen, true)
	for s in old:
		_leave(s, true, true)


func back() -> void:
	if _stack.size() <= 1:
		return
	var cur: Control = _stack.pop_back()
	_leave(cur, false, true)
	var prev: Control = _stack.back()
	prev.visible = true
	_enter(prev, false)
	sfx.play("transition_back")


func current() -> Control:
	return _stack.back() if not _stack.is_empty() else null


func _enter(s: Control, forward: bool) -> void:
	if s.get_parent() == null:
		screen_layer.add_child(s)
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.pivot_offset = screen_layer.size / 2.0
	s.modulate.a = 0.0
	s.scale = Vector2.ONE * (1.04 if forward else 0.96)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if s.has_method("on_enter") and forward:
		s.on_enter()
	elif s.has_method("on_resume") and not forward:
		s.on_resume()
	var lf = s.get_meta("last_focus") if s.has_meta("last_focus") else null
	if not forward and lf is Control and is_instance_valid(lf) and lf.is_visible_in_tree():
		quiet_focus(lf)
	elif s.has_method("default_focus"):
		var f = s.default_focus()
		if f:
			quiet_focus(f)
	refresh_hints()


func _leave(s: Control, forward: bool, destroy: bool) -> void:
	s.pivot_offset = screen_layer.size / 2.0
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, 0.3)
	tw.tween_property(s, "scale", Vector2.ONE * (0.96 if forward else 1.04), 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		if destroy:
			if s.has_method("on_leave"): s.on_leave()
			s.queue_free()
		else:
			s.visible = false)


func open_modal(m: Control) -> void:
	_modals.append(m)
	modal_layer.add_child(m)
	sfx.play("open")
	refresh_hints()


func close_modal(m: Control) -> void:
	_modals.erase(m)
	if is_instance_valid(m):
		m.queue_free()
	var top = top_layer()
	if top and top.has_method("default_focus") and not top.has_meta("last_focus"):
		var f = top.default_focus()
		if f: quiet_focus(f)
	refresh_hints()


func top_layer() -> Control:
	if not _modals.is_empty():
		return _modals.back()
	return current()


func quiet_focus(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	_quiet_focus = true
	c.grab_focus()
	_quiet_focus = false


func on_focus_changed(_c: Control) -> void:
	if not _quiet_focus:
		sfx.play("move")


func refresh_hints() -> void:
	if hints == null:
		return
	var top := top_layer()
	var h: Array = top.hints() if top and top.has_method("hints") else [["ui_accept", "Sélectionner"], ["ui_cancel", "Retour"]]
	hints.show_hints(h)


func toast(text: String, icon_name := "check", color := Color("3ddc97")) -> void:
	if root:
		root.show_toast(text, icon_name, color)


# ------------------------------------------------------------------ Entrées globales

func _input(event: InputEvent) -> void:
	# Console : le curseur disparaît dès qu'on joue à la manette ou au clavier.
	if event is InputEventMouseMotion and event.relative.length() > 2.0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif (event is InputEventJoypadButton or event is InputEventKey) and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if event is InputEventJoypadButton and event.pressed:
		_set_family(Pads.identify(event.device).family)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		_set_family(Pads.identify(event.device).family)
	elif event is InputEventKey and event.pressed:
		_set_family("keyboard")


func _set_family(f: String) -> void:
	if f != active_family:
		active_family = f
		glyphs_changed.emit()


## Capture d'écran réelle (fichier dans files/captures, accessible par FTP).
func capture_screen() -> void:
	await get_tree().create_timer(0.7).timeout
	var r = await api("POST", "/media/screenshot")
	if r is Dictionary and r.has("_error"):
		sfx.play("error")
		toast(r._error, "close", Color("ff5d6c"))
	elif r is Dictionary:
		sfx.play("success")
		toast("Capture enregistrée · files/captures/%s" % r.name, "photo_camera", Color("7c9cff"))
