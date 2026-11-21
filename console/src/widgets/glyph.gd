extends Control
## Glyphe de bouton de manette dessiné (✕ ○ □ △ / A B X Y / touches clavier).

const Pads := preload("res://src/pads.gd")

var action := "ui_accept"
var family := "keyboard"
var px := 40.0
var pulse := false
var _t := 0.0

const PS := {"ui_accept": "cross", "ui_cancel": "circle", "btn_x": "square", "btn_y": "triangle"}
const PS_COL := {"cross": Color("8fb4ff"), "circle": Color("ff7a7a"), "square": Color("f49bd6"), "triangle": Color("45dcb4")}
const XB := {"ui_accept": ["A", Color("4cc04c")], "ui_cancel": ["B", Color("ef4b4b")], "btn_x": ["X", Color("3d8cf5")], "btn_y": ["Y", Color("f2c330")]}
const NIN := {"ui_accept": "B", "ui_cancel": "A", "btn_x": "Y", "btn_y": "X"}
const KEYS := {"ui_accept": "Entrée", "ui_cancel": "Échap", "btn_x": "X", "btn_y": "Y", "start": "M", "select": "V",
	"guide": "H", "lb": "Pg↑", "rb": "Pg↓", "ui_left": "←", "ui_right": "→", "ui_up": "↑", "ui_down": "↓", "lr": "← →"}
const SHOULDER := {
	"ps": {"lb": "L1", "rb": "R1"}, "xbox": {"lb": "LB", "rb": "RB"}, "nintendo": {"lb": "L", "rb": "R"},
}


func _init(a := "ui_accept", fam := "keyboard", size_px := 40.0) -> void:
	action = a
	family = fam
	px = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(_width(), px)


func _process(delta: float) -> void:
	if pulse:
		_t += delta
		queue_redraw()


func _width() -> float:
	if Pads.glyph_style(family) == "keyboard":
		var txt: String = KEYS.get(action, action)
		return maxf(px, App.font(700).get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px * 0.42)).x + px * 0.6)
	if action in ["lb", "rb"]:
		return px * 1.4
	return px


func _draw() -> void:
	var style := Pads.glyph_style(family)
	var r := px / 2.0
	var c := Vector2(size.x / 2.0, size.y / 2.0)
	var glow := 0.5 + 0.5 * sin(_t * 5.0) if pulse else 0.0
	if pulse:
		draw_circle(c, r + 4.0 + glow * 6.0, Color(1, 1, 1, 0.12 * (1.0 - glow)))
	var f := App.font(700)
	if style == "keyboard":
		var txt: String = KEYS.get(action, action)
		var rect := Rect2(Vector2.ZERO, size)
		_draw_round(rect, 8.0, Color(1, 1, 1, 0.16))
		_draw_round(Rect2(0, size.y - 4, size.x, 4), 2.0, Color(0, 0, 0, 0.25))
		_text(f, txt, c, px * 0.42, Color("e8ecf4"))
		return
	if action in ["lb", "rb"]:
		var txt: String = SHOULDER.get(style, SHOULDER.xbox)[action]
		_draw_round(Rect2(Vector2.ZERO, size), r * 0.6, Color(1, 1, 1, 0.16))
		_text(f, txt, c, px * 0.42, Color("e8ecf4"))
		return
	draw_circle(c, r, Color(1, 1, 1, 0.14))
	draw_arc(c, r - 1, 0, TAU, 40, Color(1, 1, 1, 0.22), 1.5, true)
	if action == "start" or action == "select" or action == "guide" or action == "lr":
		var sym = {"start": "≡", "select": "⧉", "guide": "⌂", "lr": "◂▸"}[action]
		_text(f, sym, c, px * 0.5, Color("e8ecf4"))
		return
	if style == "ps":
		var kind: String = PS.get(action, "cross")
		var col: Color = PS_COL[kind]
		var s := r * 0.42
		match kind:
			"cross":
				draw_line(c - Vector2(s, s), c + Vector2(s, s), col, 3.0, true)
				draw_line(c + Vector2(s, -s), c + Vector2(-s, s), col, 3.0, true)
			"circle":
				draw_arc(c, s, 0, TAU, 32, col, 3.0, true)
			"square":
				draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2), col, false, 3.0)
			"triangle":
				var pts := PackedVector2Array([c + Vector2(0, -s * 1.1), c + Vector2(s * 1.1, s * 0.8), c + Vector2(-s * 1.1, s * 0.8), c + Vector2(0, -s * 1.1)])
				draw_polyline(pts, col, 3.0, true)
	elif style == "nintendo":
		_text(f, NIN.get(action, "B"), c, px * 0.5, Color("e8ecf4"))
	else:
		var d: Array = XB.get(action, ["A", Color.WHITE])
		_text(f, d[0], c, px * 0.5, d[1])


func _text(f: Font, txt: String, c: Vector2, fs: float, col: Color) -> void:
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs))
	draw_string(f, Vector2(c.x - sz.x / 2.0, c.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)


func _draw_round(rect: Rect2, radius: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, rect)
