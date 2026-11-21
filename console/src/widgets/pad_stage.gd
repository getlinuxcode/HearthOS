extends Control
## Grande manette flottante avec halo pulsé sur le bouton central (« appuyez pour démarrer »)
## et explosion lumineuse quand la manette est reconnue.

const PadArt := preload("res://src/widgets/pad_art.gd")

var family := "dualsense"
var halo := true
var halo_color := Color("8fb4ff")
var _tex: Texture2D
var _t := 0.0
var _burst := -10.0
var _swap := 1.0   # 0 → 1 : animation d'apparition
var _art_scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(_render)
	_render()


func _render() -> void:
	if size.x < 10:
		return
	_art_scale = minf(size.x / 600.0, size.y / 440.0)
	_tex = App.svg_from_string(PadArt.svg(family), _art_scale)
	queue_redraw()


func show_family(f: String, animate := true) -> void:
	if f == family and _tex != null:
		return
	family = f
	if animate:
		var tw := create_tween()
		tw.tween_method(_set_swap, 1.0, 0.0, 0.18)
		tw.tween_callback(_render)
		tw.tween_method(_set_swap, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_render()


func _set_swap(x: float) -> void:
	_swap = x


func burst() -> void:
	_burst = _t


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var tsz := _tex.get_size()
	var bob := sin(_t * 1.1) * 8.0
	var tilt := sin(_t * 0.7) * 0.025
	var s := 0.85 + 0.15 * _swap
	var center := size / 2.0 + Vector2(0, bob)
	# ombre au sol
	var sh_w := tsz.x * 0.36 * (1.0 - bob / 120.0)
	for i in 6:
		var k := 1.0 - i / 6.0
		draw_set_transform(size / 2.0 + Vector2(0, tsz.y * 0.5 + 26), 0.0, Vector2(1.0, 0.16))
		draw_circle(Vector2.ZERO, sh_w * (0.5 + 0.5 * k), Color(0, 0, 0, 0.07 * _swap))
	draw_set_transform(center, tilt, Vector2(s, s))
	draw_texture(_tex, -tsz / 2.0, Color(1, 1, 1, _swap))
	# halo du bouton central
	var hp := (PadArt.home_pos(family) - PadArt.VIEW / 2.0) * _art_scale
	if halo and _swap > 0.5:
		for k in 3:
			var ph := fmod(_t * 0.8 + k / 3.0, 1.0)
			var r := (20.0 + ph * 90.0) * _art_scale
			draw_arc(hp, r, 0, TAU, 48, Color(halo_color, 0.55 * (1.0 - ph)), 3.0, true)
		var glow := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(hp, 16.0 * _art_scale + glow * 4.0, Color(halo_color, 0.25 + 0.35 * glow))
	var since := _t - _burst
	if since < 1.2:
		var e := since / 1.2
		draw_circle(hp, e * 900.0, Color(1, 1, 1, 0.18 * (1.0 - e)))
		draw_arc(hp, e * 600.0, 0, TAU, 96, Color(halo_color, 0.8 * (1.0 - e)), 6.0 * (1.0 - e) + 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
