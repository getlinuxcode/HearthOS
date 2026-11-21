extends RefCounted
## Palette, typographie et composants réutilisables (style « flat » avec relief).

const BG := Color("05070d")
const TEXT := Color("eef1f8")
const DIM := Color("98a1b8")
const ACCENT := Color("7c9cff")
const ACCENT2 := Color("b56bff")
const OK := Color("3ddc97")
const WARN := Color("ffb547")
const DANGER := Color("ff5d6c")
const PANEL := Color(0.08, 0.10, 0.16, 0.82)


static func label(text: String, size := 26, weight := 500, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", App.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func icon_rect(name: String, px := 40, color := TEXT) -> TextureRect:
	var t := TextureRect.new()
	t.texture = App.icon(name, px, color)
	t.custom_minimum_size = Vector2(px, px)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Boîte « flat » avec une tranche inférieure plus sombre : donne du relief sans dégradé.
static func box(face: Color, edge: Color, depth := 6, radius := 40, pad := Vector2(36, 16), push := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = face
	s.border_color = edge
	s.border_width_bottom = depth
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y + push
	s.content_margin_bottom = pad.y - push + depth * 0.5
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 8)
	s.anti_aliasing = true
	return s


static func panel_box(color := PANEL, radius := 32, pad := 32) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 30
	s.shadow_offset = Vector2(0, 14)
	return s


static func focus_ring(radius := 44, width := 4, color := Color.WHITE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_border_width_all(width)
	s.border_color = color
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.set_expand_margin_all(7)
	s.shadow_color = Color(ACCENT, 0.55)
	s.shadow_size = 26
	return s


## Bouton à relief. kind : "normal" | "primary" | "danger" | "ghost".
static func chunky(text: String, icon_name := "", kind := "normal", size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", App.font(650))
	b.add_theme_font_size_override("font_size", size)
	var face: Color
	var edge: Color
	var fg: Color
	var face_focus: Color
	match kind:
		"primary":
			face = Color("f2f4fa"); edge = Color("aab3c9"); fg = Color("0b0e16"); face_focus = Color.WHITE
		"danger":
			face = Color("ff5d6c"); edge = Color("a92e3a"); fg = Color.WHITE; face_focus = Color("ff7884")
		"ghost":
			face = Color(1, 1, 1, 0.0); edge = Color(0, 0, 0, 0); fg = DIM; face_focus = Color(1, 1, 1, 0.12)
		_:
			face = Color(1, 1, 1, 0.10); edge = Color(0, 0, 0, 0.45); fg = TEXT; face_focus = Color(1, 1, 1, 0.2)
	var depth := 0 if kind == "ghost" else 6
	var normal := box(face, edge, depth)
	var focused := box(face_focus, edge, depth)
	if kind == "ghost":
		normal.shadow_size = 0
		focused.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focused)
	b.add_theme_stylebox_override("pressed", box(face.darkened(0.1), edge, 2, 40, Vector2(36, 16), 4))
	b.add_theme_stylebox_override("focus", focus_ring())
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		var col := fg
		if kind == "ghost" and c != "font_color":
			col = TEXT
		b.add_theme_color_override(c, col)
	if icon_name != "":
		b.icon = App.icon(icon_name, int(size * 1.25), fg)
		b.add_theme_constant_override("h_separation", 14)
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", focused)
		if kind == "ghost": b.add_theme_color_override("font_color", TEXT)
		pop(b, 1.07))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		if kind == "ghost": b.add_theme_color_override("font_color", fg)
		pop(b, 1.0))
	b.pressed.connect(func(): App.sfx.play("confirm"))
	center_pivot(b)
	return b


static func center_pivot(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size / 2.0)


## Mise à l'échelle avec rebond (ressort).
static func pop(c: Control, s: float, d := 0.32) -> void:
	if not c.is_inside_tree():
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(s, s), d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Apparition organique : fondu + glissement + léger zoom, décalé de `delay`.
static func appear(c: Control, delay := 0.0, from := Vector2(0, 30), d := 0.6) -> void:
	c.modulate.a = 0.0
	var target := c.position
	c.set_meta("appear_offset", from)
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		c.position += from
		var t2 := c.create_tween().set_parallel(true)
		t2.tween_property(c, "modulate:a", 1.0, d * 0.8).set_trans(Tween.TRANS_SINE)
		t2.tween_property(c, "position", c.position - from, d).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT))


## Apparition pour les nœuds dans un conteneur (la position est gérée par le conteneur).
static func fade_in(c: CanvasItem, delay := 0.0, d := 0.5) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, d).set_trans(Tween.TRANS_SINE)


static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func vspacer(h := 0) -> Control:
	var c := Control.new()
	if h > 0:
		c.custom_minimum_size.y = h
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func fmt_playtime(minutes: float) -> String:
	if minutes <= 0:
		return "Jamais joué"
	if minutes < 60:
		return "%d min" % minutes
	return "%d h de jeu" % roundi(minutes / 60.0)
