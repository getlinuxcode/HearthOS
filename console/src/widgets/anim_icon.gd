extends Control
## Icônes animées dessinées en vectoriel : wifi, bluetooth, globe (internet), ethernet, check, spinner.
## state : "search" | "on" | "off"

var kind := "wifi"
var state := "search"
var color := Color.WHITE
var _t := 0.0
var _born := 0.0


func _init(k := "wifi", s := "search", px := 96.0, col := Color.WHITE) -> void:
	kind = k
	state = s
	color = col
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(s: String) -> void:
	if s != state:
		state = s
		_born = _t


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	match kind:
		"wifi": _wifi()
		"bt": _bt()
		"globe": _globe()
		"ethernet": _ethernet()
		"check": _check()
		"spinner": _spinner()


func _wifi() -> void:
	var h := size.y
	var c := Vector2(size.x / 2.0, h * 0.8)
	var w := h * 0.085
	var dim := Color(color, 0.18)
	var since := _t - _born
	for i in 3:
		var r := h * (0.2 + 0.2 * i)
		var a := 1.0
		if state == "search":
			var ph := fmod(_t * 1.5, 4.0)
			a = clampf(ph - i, 0.0, 1.0) * clampf(4.0 - ph, 0.0, 1.0) * 1.0
			a = 0.18 + 0.82 * a
		elif state == "off":
			a = 0.18
		else:
			# allumage en cascade à la connexion
			a = clampf((since - i * 0.12) * 5.0, 0.18, 1.0)
		draw_arc(c, r, -PI * 0.76, -PI * 0.24, 32, Color(color, a), w, true)
	draw_circle(c, w * 0.9, color if state != "off" else dim)
	if state == "on":
		var ph2 := fmod(_t, 2.8) / 2.8
		draw_arc(c, h * (0.62 + ph2 * 0.3), -PI * 0.76, -PI * 0.24, 32, Color(color, 0.35 * (1.0 - ph2)), w * 0.6, true)
	elif state == "off":
		draw_line(Vector2(size.x * 0.2, h * 0.15), Vector2(size.x * 0.8, h * 0.9), color, w * 0.7, true)


func _bt() -> void:
	var s := size.y / 24.0
	var o := Vector2((size.x - size.y) / 2.0, 0)
	var pts := PackedVector2Array()
	for p in [Vector2(7, 7), Vector2(17, 17), Vector2(12, 22), Vector2(12, 2), Vector2(17, 7), Vector2(7, 17)]:
		pts.append(o + p * s)
	var c := size / 2.0
	if state == "search":
		for k in 3:
			var ph := fmod(_t * 0.7 + k / 3.0, 1.0)
			draw_arc(c, size.y * (0.25 + ph * 0.45), 0, TAU, 48, Color(color, 0.4 * (1.0 - ph)), 2.0, true)
	draw_circle(c, size.y * 0.36, Color(color, 0.1))
	draw_polyline(pts, color, 2.2 * s, true)


func _globe() -> void:
	var c := size / 2.0
	var r := size.y * 0.4
	var w := size.y * 0.045
	var col := color if state != "off" else Color(color, 0.3)
	draw_arc(c, r, 0, TAU, 48, col, w, true)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(col, 0.7), w * 0.7, true)
	for lat in [-0.55, 0.55]:
		var y: float = r * lat
		var hw := sqrt(r * r - y * y)
		draw_line(c + Vector2(-hw, y), c + Vector2(hw, y), Color(col, 0.5), w * 0.6, true)
	var spin := _t * 0.9 if state != "off" else 0.0
	for k in 3:
		var ang := spin + k * PI / 3.0
		var rx := r * cos(ang)
		var pts := PackedVector2Array()
		for i in 25:
			var a := -PI / 2.0 + PI * i / 24.0
			pts.append(c + Vector2(rx * cos(a), r * sin(a)))
		draw_polyline(pts, Color(col, 0.35 + 0.5 * absf(sin(ang))), w * 0.7, true)


func _ethernet() -> void:
	var s := size.y / 24.0
	var o := Vector2((size.x - size.y) / 2.0, 0)
	var box := Rect2(o + Vector2(5, 9) * s, Vector2(14, 10) * s)
	draw_rect(box, color, false, 2.0 * s)
	draw_polyline(PackedVector2Array([o + Vector2(9, 9) * s, o + Vector2(9, 5) * s, o + Vector2(15, 5) * s, o + Vector2(15, 9) * s]), color, 2.0 * s, true)
	for k in 3:
		var x := 9.0 + k * 3.0
		var on := state == "on" and fmod(_t * 3.0 - k * 0.4, 1.5) < 0.6
		draw_line(o + Vector2(x, 13) * s, o + Vector2(x, 16) * s, color if on else Color(color, 0.35), 1.8 * s, true)


func _check() -> void:
	var c := size / 2.0
	var r := size.y * 0.42
	var p := clampf((_t - _born) / 0.45, 0.0, 1.0)
	p = 1.0 - pow(1.0 - p, 3.0)
	draw_circle(c, r, Color(color, 0.16 * p))
	draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * p, 48, color, size.y * 0.06, true)
	var q := clampf((_t - _born - 0.3) / 0.3, 0.0, 1.0)
	if q > 0.0:
		var a := c + Vector2(-r * 0.42, 0)
		var b := c + Vector2(-r * 0.1, r * 0.32)
		var e := c + Vector2(r * 0.48, -r * 0.32)
		var pts := PackedVector2Array([a])
		if q < 0.4:
			pts.append(a.lerp(b, q / 0.4))
		else:
			pts.append(b)
			pts.append(b.lerp(e, (q - 0.4) / 0.6))
		draw_polyline(pts, color, size.y * 0.075, true)


func _spinner() -> void:
	var c := size / 2.0
	var r := size.y * 0.4
	draw_arc(c, r, 0, TAU, 48, Color(color, 0.15), size.y * 0.08, true)
	var a := _t * 5.0
	var len := 1.2 + 0.8 * sin(_t * 2.0)
	draw_arc(c, r, a, a + len, 32, color, size.y * 0.08, true)
