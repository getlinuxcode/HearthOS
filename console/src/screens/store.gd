extends Control
## Boutique Steam dans l'interface : sélections (promos, meilleures ventes…), recherche, fiche, achat.
## Le paiement se termine chez Steam (QR code vers le téléphone ou client Steam) : Valve n'ouvre pas
## d'API d'achat aux applications tierces.

const UI := preload("res://src/ui.gd")
const Dialog := preload("res://src/widgets/dialog.gd")
const VKeyboard := preload("res://src/widgets/vkeyboard.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")

const ROUND := """
shader_type canvas_item;
uniform vec2 sz = vec2(400.0, 187.0);
uniform float radius = 16.0;
void fragment() {
	vec2 p = UV * sz;
	vec2 q = abs(p - sz * 0.5) - (sz * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(-1.0, 1.0, d)));
}
"""

var term := ""
var results = null
var _v: VBoxContainer
var _search: Button
var _first: Control
var _shader: Shader


func _init(search_term := "", search_results = null) -> void:
	term = search_term
	results = search_results


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = ROUND
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	scroll.offset_bottom = -100
	_v = VBoxContainer.new()
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_v.add_theme_constant_override("separation", 18)
	scroll.add_child(_v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 100)
	m.add_theme_constant_override("margin_right", 100)
	m.add_child(head)
	_v.add_child(m)
	var logo := TextureRect.new()
	logo.texture = App.brand("steam", 54, Color.WHITE)
	logo.custom_minimum_size = Vector2(54, 54)
	head.add_child(logo)
	head.add_child(UI.label("Résultats : « %s »" % term if results != null else "Boutique", 52, 800))
	head.add_child(UI.hspacer())
	_search = UI.chunky("Rechercher", "storefront", "normal", 24)
	_search.pressed.connect(_do_search)
	head.add_child(_search)


func on_enter() -> void:
	App.bg.set_hero(null)
	App.bg.tint(Color("1b4a8a"))
	var spin := HBoxContainer.new()
	spin.alignment = BoxContainer.ALIGNMENT_CENTER
	spin.add_child(AnimIcon.new("spinner", "on", 60, UI.ACCENT))
	_v.add_child(spin)
	var sections: Array = []
	if results != null:
		sections = [{"title": "%d jeu(x)" % results.size(), "items": results}]
	else:
		var r = await App.api("GET", "/store/featured")
		sections = r if r is Array else []
	spin.queue_free()
	if sections.is_empty():
		_v.add_child(_pad(UI.label("Boutique indisponible : vérifiez la connexion Internet.", 28, 400, UI.DIM)))
	var si := 0
	for s in sections:
		if s.items.is_empty():
			continue
		_v.add_child(_pad(UI.label(s.title, 32, 700)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		var sc := ScrollContainer.new()
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		sc.follow_focus = false
		sc.custom_minimum_size.y = 300
		var inner := MarginContainer.new()
		inner.add_theme_constant_override("margin_left", 100)
		inner.add_theme_constant_override("margin_right", 100)
		inner.add_theme_constant_override("margin_top", 16)
		inner.add_theme_constant_override("margin_bottom", 16)
		inner.add_child(row)
		sc.add_child(inner)
		_v.add_child(sc)
		var i := 0
		for it in s.items:
			var t := _tile(it)
			row.add_child(t)
			UI.fade_in(t, 0.04 * i + si * 0.1, 0.4)
			if _first == null:
				_first = t
			i += 1
		si += 1
	if _first:
		App.quiet_focus(_first)


func _pad(c: Control) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 100)
	m.add_child(c)
	return m


func default_focus() -> Control:
	return _first if _first else _search


func hints() -> Array:
	return [["ui_accept", "Voir"], ["btn_y", "Rechercher"], ["ui_cancel", "Retour"]]


func _unhandled_input(event: InputEvent) -> void:
	if App.top_layer() == self and event.is_action_pressed("btn_y"):
		get_viewport().set_input_as_handled()
		_do_search()


func _price(cents, currency) -> String:
	if cents == null:
		return ""
	if int(cents) == 0:
		return "Gratuit"
	var sym := "€" if str(currency) == "EUR" else str(currency)
	return ("%.2f %s" % [int(cents) / 100.0, sym]).replace(".", ",")


func _tile(it: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(420, 260)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.19, 0.92)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 10)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", UI.focus_ring(22, 4))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(420, 196)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("sz", Vector2(420, 196))
	img.material = mat
	v.add_child(img)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_child(info)
	v.add_child(m)
	var name := UI.label(it.name, 21, 600)
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(name)
	if it.get("discount", 0) and int(it.discount) > 0:
		var tag := PanelContainer.new()
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color("4c6b22")
		tsb.set_corner_radius_all(6)
		tsb.content_margin_left = 8
		tsb.content_margin_right = 8
		tag.add_theme_stylebox_override("panel", tsb)
		tag.add_child(UI.label("-%d%%" % int(it.discount), 19, 800, Color("beee11")))
		info.add_child(tag)
	info.add_child(UI.label(_price(it.get("priceFinal"), it.get("currency", "EUR")), 21, 700))
	UI.center_pivot(b)
	b.focus_entered.connect(func():
		UI.pop(b, 1.06)
		var sc := b.get_parent().get_parent().get_parent() as ScrollContainer
		if sc:
			sc.create_tween().tween_property(sc, "scroll_horizontal", maxi(0, int(b.position.x) - 40), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		var hero = await App.remote_texture(App.steam_img(it.appid, "hero"))
		if b.has_focus():
			App.bg.set_hero(hero)
			if img.texture: App.bg.tint(App.dominant_color(img.texture), 0.8))
	b.focus_exited.connect(func(): UI.pop(b, 1.0))
	b.pressed.connect(func(): App.push(StoreItem.new(int(it.appid))))
	_load(img, it.image)
	return b


func _load(img: TextureRect, url: String) -> void:
	var tex = await App.remote_texture(url)
	if is_instance_valid(img) and tex:
		img.texture = tex
		img.modulate.a = 0
		img.create_tween().tween_property(img, "modulate:a", 1.0, 0.3)


func _do_search() -> void:
	var kb := VKeyboard.new("Rechercher un jeu dans la boutique")
	kb.value = term
	App.open_modal(kb)
	var t = await kb.done
	if t == null or str(t).strip_edges() == "":
		return
	var r = await App.api("GET", "/store/search?q=" + str(t).strip_edges().uri_encode())
	if not (r is Array):
		App.toast("Recherche impossible", "close", UI.DANGER)
		return
	var nxt = load("res://src/screens/store.gd").new(str(t).strip_edges(), r)
	App.push(nxt)


# ------------------------------------------------------------------ Fiche d'un jeu

class StoreItem extends Control:
	const UI2 := preload("res://src/ui.gd")
	const Dialog2 := preload("res://src/widgets/dialog.gd")
	var appid := 0
	var _buy: Button
	var _d: Dictionary = {}

	func _init(id: int) -> void:
		appid = id

	func default_focus() -> Control:
		return _buy

	func on_enter() -> void:
		var hero = await App.remote_texture(App.steam_img(appid, "hero"))
		App.bg.set_hero(hero)
		var r = await App.api("GET", "/store/app/%d" % appid)
		if not (r is Dictionary) or r.has("_error"):
			var l := UI2.label("Fiche indisponible.", 30, 500, UI2.DIM)
			l.position = Vector2(110, 200)
			add_child(l)
			return
		_d = r
		var root := HBoxContainer.new()
		root.add_theme_constant_override("separation", 60)
		add_child(root)
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.offset_left = 110
		root.offset_right = -110
		root.offset_top = 120
		root.offset_bottom = -120
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 20)
		left.custom_minimum_size.x = 660
		root.add_child(left)
		var header := TextureRect.new()
		header.custom_minimum_size = Vector2(660, 308)
		header.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		header.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		left.add_child(header)
		header.texture = await App.remote_texture(r.headerImage)
		var shots := HBoxContainer.new()
		shots.add_theme_constant_override("separation", 12)
		left.add_child(shots)
		for i in mini(3, r.screenshots.size()):
			var t := TextureRect.new()
			t.custom_minimum_size = Vector2(212, 120)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			shots.add_child(t)
			_shot(t, r.screenshots[i])
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 20)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(right)
		var title := UI2.label(r.name, 58, 800)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(title)
		var meta := UI2.label(", ".join(PackedStringArray(r.developers)) + ((" · " + r.releaseDate) if r.get("releaseDate") else ""), 24, 500, UI2.DIM)
		right.add_child(meta)
		var desc := UI2.label(r.description, 27, 400, Color("d6dbe7"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(desc)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 10)
		chips.add_theme_constant_override("v_separation", 10)
		for g in r.genres:
			var c := PanelContainer.new()
			var sb := UI2.panel_box(Color(1, 1, 1, 0.1), 20, 8)
			sb.shadow_size = 0
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			c.add_theme_stylebox_override("panel", sb)
			c.add_child(UI2.label(g, 21, 600))
			chips.add_child(c)
		right.add_child(chips)
		right.add_child(UI2.vspacer())
		var buy := HBoxContainer.new()
		buy.add_theme_constant_override("separation", 30)
		buy.add_child(UI2.label(r.get("price", "") if r.get("price") else "Prix indisponible", 44, 800))
		_buy = UI2.chunky("Obtenir" if r.isFree else "Acheter", "storefront", "primary", 32)
		_buy.pressed.connect(_buy_dialog)
		buy.add_child(_buy)
		right.add_child(buy)
		for i in right.get_child_count():
			UI2.fade_in(right.get_child(i), 0.05 * i, 0.4)
		UI2.fade_in(left, 0.0, 0.4)
		App.quiet_focus(_buy)

	func _shot(t: TextureRect, url: String) -> void:
		var tex = await App.remote_texture(url)
		if is_instance_valid(t):
			t.texture = tex

	func _buy_dialog() -> void:
		var url := "https://store.steampowered.com/app/%d" % appid
		var qr = await App.api("GET", "/qr?text=" + url.uri_encode())
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 34)
		var box := PanelContainer.new()
		var sb := UI2.panel_box(Color.WHITE, 22, 16)
		sb.shadow_size = 0
		box.add_theme_stylebox_override("panel", sb)
		var qt := TextureRect.new()
		qt.custom_minimum_size = Vector2(280, 280)
		qt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		qt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		qt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if qr is Dictionary and qr.has("svg"):
			qt.texture = App.svg_from_string(qr.svg, 8.0)
		box.add_child(qt)
		h.add_child(box)
		var t := Dialog2.text("Le paiement se fait chez Steam, en toute sécurité :\n\n• Scannez le QR code et payez sur votre téléphone. Le jeu apparaîtra ensuite dans votre bibliothèque.\n\n• Ou ouvrez la page d'achat dans le client Steam, sur la TV.", 520)
		h.add_child(t)
		Dialog2.open(("Obtenir " if _d.get("isFree", false) else "Acheter ") + _d.get("name", ""), h, [
			["Ouvrir dans Steam", func(): App.api("POST", "/store/app/%d/open" % appid), "primary", "storefront"],
			["Fermer", Callable(), "normal", "close"],
		], 1000)
