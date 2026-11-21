extends Control
## Fin de l'onboarding : éclat de lumière, confettis lumineux, « Commencer à jouer ».

const UI := preload("res://src/ui.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")
const Home := preload("res://src/screens/home.gd")

var _go: Button


class Burst extends Control:
	var t := 0.0
	var parts := []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 70:
			var a := randf() * TAU
			parts.append([a, randf_range(250, 900), randf_range(3, 9), [Color("7c9cff"), Color("b56bff"), Color("3ddc97"), Color.WHITE][i % 4]])
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size / 2.0
		var e := minf(t / 1.6, 1.0)
		var ease := 1.0 - pow(1.0 - e, 3.0)
		draw_circle(c, 80 + ease * 520, Color(0.5, 0.6, 1.0, 0.12 * (1.0 - e)))
		for p in parts:
			var pos: Vector2 = c + Vector2(cos(p[0]), sin(p[0])) * p[1] * ease + Vector2(0, t * t * 40)
			draw_circle(pos, p[2] * (1.0 - e * 0.6), Color(p[3], 1.0 - e * 0.85))


func _ready() -> void:
	set_meta("can_back", false)
	var b := Burst.new()
	add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 26)
	add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := AnimIcon.new("check", "on", 130, UI.OK)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var name: String = App.account.personaName if App.account is Dictionary else ""
	var t := UI.label("Tout est prêt%s !" % ((", " + name) if name != "" else ""), 80, 800)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label("Votre console est configurée. Bon jeu.", 30, 400, UI.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UI.vspacer(10))
	_go = UI.chunky("Commencer à jouer", "play_arrow", "primary", 34)
	_go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_go.pressed.connect(_finish)
	v.add_child(_go)
	for i in v.get_child_count():
		UI.fade_in(v.get_child(i), 0.25 + 0.1 * i, 0.6)


func on_enter() -> void:
	App.sfx.play("success")
	App.bg.set_energy(0.15, 0.6)


func default_focus() -> Control:
	return _go


func hints() -> Array:
	return [["ui_accept", "Commencer"]]


func _finish() -> void:
	App.bg.set_energy(0.0, 1.0)
	App.settings["onboarded"] = true
	App.api("POST", "/settings", {"onboarded": true})
	App.replace_all(Home.new())
