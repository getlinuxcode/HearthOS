extends Control
## Accueil : carrousel de jaquettes, sélecteur lumineux qui suit le focus,
## fond teinté par la couleur du jeu, illustration en fondu, actions rapides.

const UI := preload("res://src/ui.gd")
const Pads := preload("res://src/pads.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")
const PadArt := preload("res://src/widgets/pad_art.gd")
const Glyph := preload("res://src/widgets/glyph.gd")
const Launch := preload("res://src/screens/launch.gd")
const PowerMenu := preload("res://src/screens/power_menu.gd")

const TILE := Vector2(196, 294)
const TILE_FOCUS := Vector2(262, 393)
const GAP := 26.0
const BASE_X := 110.0
const SHELF_Y := 190.0

const ROUND := """
shader_type canvas_item;
uniform vec2 sz = vec2(200.0, 300.0);
uniform float radius = 18.0;
void fragment() {
	vec2 p = UV * sz;
	vec2 q = abs(p - sz * 0.5) - (sz * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float a = 1.0 - smoothstep(-1.0, 1.0, d);
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * a);
}
"""

const FILTERS := [["all", "Tous les jeux"], ["installed", "Installés"], ["steam", "Steam"], ["rom", "Rétro"]]

var _filter := 0
var _games: Array = []
var _tiles: Array[Button] = []
var _focus_i := 0
var _shelf: Control
var _selector: Selector
var _title: Label
var _meta: HBoxContainer
var _play: Button
var _info: Button
var _quick: Array[Button] = []
var _quick_label: Label
var _tabs: HBoxContainer
var _clock: Label
var _wifi: AnimIcon
var _pad_icon: TextureRect
var _hero_timer: Timer
var _round_shader: Shader
var _empty: Label


class Selector extends Control:
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var p := 0.5 + 0.5 * sin(_t * 2.4)
		var r := Rect2(Vector2(-7, -7), size + Vector2(14, 14))
		for k in 4:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(2)
			sb.border_color = Color(0.55, 0.65, 1.0, (0.12 - k * 0.025) * (0.6 + 0.4 * p))
			sb.set_corner_radius_all(26 + k * 4)
			draw_style_box(sb, r.grow(4 + k * 5))
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(4)
		ring.border_color = Color(1, 1, 1, 0.92)
		ring.set_corner_radius_all(26)
		ring.anti_aliasing = true
		draw_style_box(ring, r)


func _ready() -> void:
	_round_shader = Shader.new()
	_round_shader.code = ROUND
	_build_topbar()

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 34)
	add_child(_tabs)
	_tabs.position = Vector2(BASE_X, 118)

	_shelf = Control.new()
	_shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shelf)
	_shelf.position = Vector2(0, SHELF_Y)
	_selector = Selector.new()
	_shelf.add_child(_selector)

	_empty = UI.label("", 30, 400, UI.DIM)
	_empty.position = Vector2(BASE_X, SHELF_Y + 120)
	add_child(_empty)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 14)
	add_child(info)
	info.position = Vector2(BASE_X, SHELF_Y + TILE_FOCUS.y + 46)
	info.custom_minimum_size.x = 1200
	_title = UI.label("", 66, 800)
	_title.clip_text = true
	_title.custom_minimum_size.x = 1300
	info.add_child(_title)
	_meta = HBoxContainer.new()
	_meta.add_theme_constant_override("separation", 22)
	info.add_child(_meta)
	info.add_child(UI.vspacer(10))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 20)
	info.add_child(btns)
	_play = UI.chunky("Jouer", "play_arrow", "primary", 32)
	_play.custom_minimum_size.x = 250
	_play.pressed.connect(_launch)
	btns.add_child(_play)
	_info = UI.chunky("", "tune", "normal", 30)
	_info.custom_minimum_size.x = 92
	_info.pressed.connect(_open_details)
	btns.add_child(_info)

	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 26)
	add_child(quick)
	quick.position = Vector2(BASE_X, 950)
	for q in [["storefront", "Boutique"], ["sports_esports", "Émulateurs"], ["settings", "Réglages"], ["power_settings_new", "Alimentation"]]:
		var b := _round_button(q[0], q[1])
		quick.add_child(b)
		_quick.append(b)
	_quick_label = UI.label("", 24, 600)
	add_child(_quick_label)
	_quick_label.modulate.a = 0

	_hero_timer = Timer.new()
	_hero_timer.one_shot = true
	_hero_timer.wait_time = 0.22
	_hero_timer.timeout.connect(_update_hero)
	add_child(_hero_timer)

	App.library_changed.connect(_rebuild)
	App.pads_changed.connect(_update_pad_icon)
	App.glyphs_changed.connect(_render_tabs)


func _build_topbar() -> void:
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	add_child(left)
	left.position = Vector2(BASE_X, 40)
	var av := Avatar.new()
	left.add_child(av)
	var acc = App.account
	left.add_child(UI.label(acc.personaName if acc is Dictionary else "Invité", 28, 600))
	if acc is Dictionary and acc.get("avatarUrl", "") != "":
		var tex = await App.remote_texture(acc.avatarUrl)
		av.tex = tex

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 26)
	right.alignment = BoxContainer.ALIGNMENT_END
	add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -500
	right.offset_right = -70
	right.offset_top = 36
	right.offset_bottom = 96
	_pad_icon = TextureRect.new()
	_pad_icon.custom_minimum_size = Vector2(70, 46)
	_pad_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pad_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_pad_icon)
	var net: Dictionary = App.network
	_wifi = AnimIcon.new("ethernet" if net.get("type", "") == "ethernet" else "wifi", "on" if net.get("connected", true) else "off", 44)
	right.add_child(_wifi)
	_clock = UI.label("", 32, 600)
	right.add_child(_clock)
	_update_pad_icon()


class Avatar extends Control:
	var tex: Texture2D:
		set(v):
			tex = v
			queue_redraw()
	func _init() -> void:
		custom_minimum_size = Vector2(52, 52)
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 26, Color("7c9cff"))
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(3, 3), size - Vector2(6, 6)), false)
		else:
			draw_circle(c, 23, Color(0.1, 0.12, 0.2))
			var f := App.font(700)
			draw_string(f, c + Vector2(-8, 9), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		draw_arc(c, 26, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0, true)


func _update_pad_icon() -> void:
	var pads := Pads.connected()
	if pads.is_empty():
		_pad_icon.texture = null
	else:
		_pad_icon.texture = App.svg_from_string(PadArt.svg(pads[0].family), 0.12)


func _process(_d: float) -> void:
	if _clock:
		var t := Time.get_time_dict_from_system()
		_clock.text = "%02d:%02d" % [t.hour, t.minute]


func _round_button(icon_name: String, label: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 92)
	b.focus_mode = Control.FOCUS_ALL
	b.icon = App.icon(icon_name, 44, Color.WHITE)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var normal := UI.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0.45), 5, 46, Vector2(0, 0))
	var foc := UI.box(Color(1, 1, 1, 0.95), Color("aab3c9"), 5, 46, Vector2(0, 0))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", UI.focus_ring(50, 3))
	UI.center_pivot(b)
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		b.icon = App.icon(icon_name, 44, Color("0b0e16"))
		UI.pop(b, 1.12)
		_quick_label.text = label
		_quick_label.position = b.global_position + Vector2(b.size.x / 2.0 - _quick_label.size.x / 2.0, 112)
		var tw := _quick_label.create_tween()
		tw.tween_property(_quick_label, "modulate:a", 1.0, 0.25)
		App.bg.hero_strength(0.25))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		b.icon = App.icon(icon_name, 44, Color.WHITE)
		UI.pop(b, 1.0)
		_quick_label.modulate.a = 0)
	b.pressed.connect(func(): _quick_action(icon_name))
	return b


func _quick_action(id: String) -> void:
	App.sfx.play("confirm")
	match id:
		"power_settings_new":
			var m := PowerMenu.new()
			App.open_modal(m)
		"storefront":
			App.push(load("res://src/screens/store.gd").new())
		"sports_esports":
			App.push(load("res://src/screens/emulators.gd").new())
		"settings":
			App.push(load("res://src/screens/settings.gd").new())


func default_focus() -> Control:
	return _tiles[_focus_i] if not _tiles.is_empty() else _quick[0]


func on_enter() -> void:
	_render_tabs()
	_rebuild()


func on_resume() -> void:
	_update_hero()


func hints() -> Array:
	return [["ui_accept", "Jouer"], ["lr", "Parcourir"], ["lb", "Catégorie"], ["rb", ""], ["guide", "Menu"]]


func _render_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_tabs.add_child(Glyph.new("lb", App.active_family, 36))
	for i in FILTERS.size():
		var l := UI.label(FILTERS[i][1], 28, 700 if i == _filter else 500, UI.TEXT if i == _filter else UI.DIM)
		_tabs.add_child(l)
	_tabs.add_child(Glyph.new("rb", App.active_family, 36))


func _filtered() -> Array:
	var f: String = FILTERS[_filter][0]
	var out := []
	for g in App.library:
		if f == "all" or (f == "installed" and g.get("installed", false)) or (f == "steam" and g.source == "steam") or (f == "rom" and g.source == "rom"):
			out.append(g)
	return out


func _rebuild() -> void:
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	_games = _filtered()
	_focus_i = clampi(_focus_i, 0, maxi(0, _games.size() - 1))
	_empty.text = "" if not _games.is_empty() else ("Aucune ROM : déposez vos jeux par FTP dans roms/." if FILTERS[_filter][0] == "rom" else "Aucun jeu dans cette catégorie.")
	_selector.visible = not _games.is_empty()
	for i in _games.size():
		var t := _make_tile(_games[i], i)
		_shelf.add_child(t)
		_tiles.append(t)
	_shelf.move_child(_selector, _shelf.get_child_count() - 1)
	_layout(true)
	for i in _tiles.size():
		var t := _tiles[i]
		t.modulate.a = 0
		var tw := t.create_tween()
		tw.tween_interval(0.04 * mini(i, 10))
		tw.tween_property(t, "modulate:a", 1.0 if i >= _focus_i else 0.0, 0.4)
	# Voisins de focus : carrousel ↕ bouton Jouer ↕ actions rapides
	for i in _tiles.size():
		var t := _tiles[i]
		t.focus_neighbor_bottom = _play.get_path()
		t.focus_neighbor_left = _tiles[maxi(i - 1, 0)].get_path()
		t.focus_neighbor_right = _tiles[mini(i + 1, _tiles.size() - 1)].get_path()
		t.focus_neighbor_top = t.get_path()
	for q in _quick:
		q.focus_neighbor_top = _play.get_path()
	_play.focus_neighbor_bottom = _quick[0].get_path()
	_info.focus_neighbor_bottom = _quick[1].get_path()
	_play.visible = not _games.is_empty()
	_info.visible = not _games.is_empty()
	if not _games.is_empty():
		App.quiet_focus(_tiles[_focus_i])
		_show_info(_games[_focus_i], false)
		_update_hero()
	else:
		App.quiet_focus(_quick[0])
		_title.text = ""


func _make_tile(g: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.size = TILE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.22)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 12)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb if st != "focus" else StyleBoxEmpty.new())
	var name := UI.label(g.name, 24, 700)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(name)
	name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name.offset_left = 14
	name.offset_right = -14
	var cover := TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_SCALE if g.source == "steam" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _round_shader
	cover.material = mat
	b.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.resized.connect(func(): mat.set_shader_parameter("sz", cover.size))
	if not g.get("installed", false):
		var dl := TextureRect.new()
		dl.texture = App.icon("download", 30, Color.WHITE)
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dl)
		dl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		dl.offset_left = -46
		dl.offset_top = -46
		dl.offset_right = -14
		dl.offset_bottom = -14
	b.focus_entered.connect(func(): _on_tile_focus(i))
	b.pressed.connect(_launch)
	_load_cover(g, cover, name)
	return b


func _load_cover(g: Dictionary, cover: TextureRect, name: Label) -> void:
	var url: String = App.steam_img(g.appid, "portrait") if g.source == "steam" else g.get("coverUrl", "")
	var tex = await App.remote_texture(url)
	if tex == null and g.source == "steam":
		tex = await App.remote_texture(App.steam_img(g.appid, "header"))
		if tex:
			cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not is_instance_valid(cover):
		return
	if tex:
		cover.texture = tex
		name.visible = false
		cover.modulate.a = 0
		cover.create_tween().tween_property(cover, "modulate:a", 1.0, 0.35)
	g["_cover"] = tex


func _on_tile_focus(i: int) -> void:
	var prev := _focus_i
	_focus_i = i
	_layout(false)
	_show_info(_games[i], prev != i)
	_hero_timer.start()
	App.bg.hero_strength(0.62)


## Place les jaquettes : celle qui a le focus est plus grande, ancrée à gauche.
func _layout(instant: bool) -> void:
	for i in _tiles.size():
		var t := _tiles[i]
		var x: float
		var sz := TILE
		if i < _focus_i:
			x = BASE_X - (_focus_i - i) * (TILE.x + GAP)
		elif i == _focus_i:
			x = BASE_X
			sz = TILE_FOCUS
		else:
			x = BASE_X + TILE_FOCUS.x + GAP + (i - _focus_i - 1) * (TILE.x + GAP)
		var pos := Vector2(x, TILE_FOCUS.y - sz.y)
		var alpha := 1.0 if i >= _focus_i else (0.35 if i == _focus_i - 1 else 0.0)
		var tint := 1.0 if i == _focus_i else 0.72
		if instant:
			t.position = pos
			t.size = sz
		else:
			var tw := t.create_tween().set_parallel(true)
			tw.tween_property(t, "position", pos, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(t, "size", sz, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(t, "modulate", Color(tint, tint, tint, alpha), 0.3)
		if instant:
			t.modulate = Color(tint, tint, tint, t.modulate.a)
	if not _tiles.is_empty():
		var target := Rect2(Vector2(BASE_X, 0), TILE_FOCUS)
		if instant:
			_selector.position = target.position
			_selector.size = target.size
		else:
			var tw2 := _selector.create_tween().set_parallel(true)
			tw2.tween_property(_selector, "position", target.position, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw2.tween_property(_selector, "size", target.size, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_selector.visible = _tiles[_focus_i].has_focus() or true


func _show_info(g: Dictionary, animate: bool) -> void:
	_title.text = g.name
	for c in _meta.get_children():
		c.queue_free()
	if g.source == "steam":
		_meta.add_child(_chip_icon(App.brand("steam", 30, Color.WHITE), "Steam"))
	else:
		_meta.add_child(_chip_icon(App.brand("retroarch", 30, Color.WHITE), "Rétro · %s" % str(g.get("system", "")).to_upper()))
	_meta.add_child(_chip_icon(App.icon("timer", 30, UI.DIM), UI.fmt_playtime(g.get("playtimeMinutes", 0))))
	_meta.add_child(_chip_icon(App.icon("check" if g.get("installed", false) else "download", 30, UI.OK if g.get("installed", false) else UI.DIM),
		"Installé" if g.get("installed", false) else "À installer"))
	if g.get("demo", false):
		_meta.add_child(_chip_icon(App.icon("person", 30, UI.WARN), "Démo · connectez Steam"))
	_play.text = "Jouer" if g.get("installed", false) or g.get("demo", false) else "Installer"
	_play.icon = App.icon("play_arrow" if _play.text == "Jouer" else "download", 40, Color("0b0e16"))
	if animate:
		_title.modulate.a = 0
		var base := _title.position
		_title.position.x += 24
		var tw := _title.create_tween().set_parallel(true)
		tw.tween_property(_title, "modulate:a", 1.0, 0.3)
		tw.tween_property(_title, "position:x", base.x, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		UI.fade_in(_meta, 0.08, 0.3)


func _chip_icon(tex: Texture2D, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(30, 30)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(t)
	var l := UI.label(text, 26, 500, Color("c9cfdd"))
	h.add_child(l)
	return h


func _update_hero() -> void:
	if _games.is_empty():
		App.bg.set_hero(null)
		App.bg.default_tint()
		return
	var g: Dictionary = _games[_focus_i]
	var cover = g.get("_cover")
	if cover:
		App.bg.tint(App.dominant_color(cover))
	if g.source == "steam":
		var tex = await App.remote_texture(App.steam_img(g.appid, "hero"))
		if _games.size() > _focus_i and _games[_focus_i] == g:
			App.bg.set_hero(tex)
	else:
		App.bg.set_hero(null)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or App.top_layer() != self:
		return
	if event.is_action_pressed("lb") or event.is_action_pressed("rb"):
		_filter = (_filter + (1 if event.is_action_pressed("rb") else -1) + FILTERS.size()) % FILTERS.size()
		_focus_i = 0
		App.sfx.play("tick")
		_render_tabs()
		_rebuild()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("start"):
		App.open_modal(PowerMenu.new())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not _tiles.is_empty() and not _tiles[_focus_i].has_focus():
			App.quiet_focus(_tiles[_focus_i])
			App.sfx.play("back")


func _launch() -> void:
	if _games.is_empty():
		return
	var g: Dictionary = _games[_focus_i]
	var t := _tiles[_focus_i]
	var l := Launch.new(g, Rect2(t.global_position, t.size))
	App.root.add_child(l)


func _open_details() -> void:
	if _games.is_empty():
		return
	var g: Dictionary = _games[_focus_i]
	if g.source == "steam":
		var Store = load("res://src/screens/store.gd")
		App.push(Store.StoreItem.new(int(g.appid)))
	else:
		App.toast("%s · %s" % [g.name, str(g.get("path", ""))], "folder", UI.ACCENT)
