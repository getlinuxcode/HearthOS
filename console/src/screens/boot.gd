extends Control
## Allumage : le logo se trace, la flamme s'allume, le nom apparaît lettre à lettre,
## puis le fond vivant se dévoile et on enchaîne sur l'onboarding ou l'accueil.

const UI := preload("res://src/ui.gd")
const PadConnect := preload("res://src/screens/pad_connect.gd")
const Home := preload("res://src/screens/home.gd")


class Mark extends Control:
	var trace := 0.0
	var flame := 0.0
	var glow := 0.0
	var _t := 0.0

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := size.y * 0.42
		var pts := PackedVector2Array()
		for i in 7:
			var a := -PI / 2.0 + TAU * i / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		# tracé progressif de l'hexagone
		var total := trace * 6.0
		var line := PackedVector2Array([pts[0]])
		for i in 6:
			if total <= i:
				break
			line.append(pts[i].lerp(pts[i + 1], clampf(total - i, 0.0, 1.0)))
		var col_a := Color("7c9cff")
		var col_b := Color("b56bff")
		if glow > 0.0:
			for k in 4:
				draw_polyline(line, Color(col_a, 0.08 * glow), 14.0 + k * 10.0, true)
		if line.size() > 1:
			draw_polyline(line, col_a.lerp(col_b, 0.5 + 0.5 * sin(_t)), size.y * 0.045, true)
		# flamme
		if flame > 0.0:
			var f := PackedVector2Array()
			var cols := PackedColorArray()
			var h := r * 0.95 * flame
			var w := r * 0.5 * flame
			var base := c + Vector2(0, r * 0.42)
			var wob := sin(_t * 3.0) * 0.06
			for i in 33:
				var a := TAU * i / 32.0
				# goutte : rayon plus fin vers le haut
				var y := -cos(a)
				var x := sin(a) * (0.55 + 0.45 * (1.0 - y) * 0.5) * (1.0 + wob * y)
				var pt := base + Vector2(x * w, -(y + 1.0) * 0.5 * h + h * 0.08 * (1.0 - y))
				f.append(pt)
				cols.append(col_b.lerp(col_a, clampf((y + 1.0) / 2.0, 0.0, 1.0)))
			draw_polygon(f, cols)


var _mark: Mark
var _name_box: HBoxContainer
var _tag: Label
var _status: Label


func _ready() -> void:
	set_meta("can_back", false)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 26)
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_mark = Mark.new()
	_mark.custom_minimum_size = Vector2(190, 190)
	_mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_mark)

	_name_box = HBoxContainer.new()
	_name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_name_box.add_theme_constant_override("separation", 22)
	center.add_child(_name_box)
	for ch in "HEARTH":
		var l := UI.label(ch, 76, 300)
		l.modulate.a = 0.0
		_name_box.add_child(l)

	_tag = UI.label("Votre salon. Vos jeux.", 28, 400, UI.DIM)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.modulate.a = 0.0
	center.add_child(_tag)

	_status = UI.label("", 22, 400, UI.DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.position.y -= 110


func hints() -> Array:
	return []


func on_enter() -> void:
	_run()


func _run() -> void:
	App.sfx.play("boot")
	_fetch()
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_mark, "trace", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_mark, "flame", 1.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_mark, "glow", 1.0, 0.8)
	tw.parallel().tween_callback(func(): App.bg.reveal(2.4))
	var i := 0
	for l in _name_box.get_children():
		tw.parallel().tween_property(l, "modulate:a", 1.0, 0.5).set_delay(0.08 * i)
		i += 1
	tw.tween_property(_tag, "modulate:a", 1.0, 0.6)
	tw.tween_interval(0.9)
	await tw.finished
	while not _loaded:
		await get_tree().process_frame
	var nxt: Control = Home.new() if App.settings.get("onboarded", false) and App.info.get("mode", "") != "live" else PadConnect.new()
	App.replace_all(nxt)


var _loaded := false

func _fetch() -> void:
	var info = await App.api("GET", "/system/info")
	if info is Dictionary and not info.has("_error"):
		App.info = info
		var s = await App.api("GET", "/settings")
		if s is Dictionary:
			App.settings = s
	else:
		_status.text = "Service système indisponible : mode autonome"
		App.settings = {"onboarded": false}
	await App.load_library()
	_loaded = true
