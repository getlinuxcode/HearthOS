extends Control
## Menu en jeu (bouton PS / Xbox / HOME) : le jeu se floute, les cartes montent en cascade.
## Reprendre, Accueil, Capture, Performances, FSR, Son, Manette, Quitter (maintenir).

const UI := preload("res://src/ui.gd")
const Pads := preload("res://src/pads.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")
const PadArt := preload("res://src/widgets/pad_art.gd")
const Home := preload("res://src/screens/home.gd")

const BLUR := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 6.0 * amount;
	vec3 acc = vec3(0.0);
	float n = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			acc += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb;
			n += 1.0;
		}
	}
	vec3 col = acc / n;
	col = mix(col, col * vec3(0.35, 0.38, 0.5), amount);
	COLOR = vec4(col, 1.0);
}
"""

const VOL_STEPS := [100, 75, 50, 25, 0]

var _blur: ColorRect
var _row: HBoxContainer
var _cards: Array[Button] = []
var _header: Control
var _closing := false
var _hold_t := -1.0
var _quit_card: Button
var _vol_i := 0
var _detail: Label


func _init() -> void:
	set_meta("is_modal", true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur = ColorRect.new()
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLUR
	m.shader = sh
	_blur.material = m
	add_child(_blur)
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_method(func(x: float): m.set_shader_parameter("amount", x), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_SINE)

	_build_header()

	_detail = UI.label("", 28, 500, Color("c9cfdd"))
	add_child(_detail)
	_detail.position = Vector2(110, 640)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 22)
	add_child(_row)
	_row.position = Vector2(110, 700)
	var g = App.running_game
	var pads := Pads.connected()
	var pad_name: String = pads[0].name if not pads.is_empty() else "Aucune manette"
	var defs := [
		["resume", "play_arrow", "Reprendre", "Retour au jeu"],
		["home", "home", "Accueil", "Sans quitter"],
		["shot", "photo_camera", "Capture", "Image de l'écran"],
		["vol", "volume_up", "Son", "100 %"],
		["pad", "sports_esports", "Manette", pad_name],
		["quit", "close", "Quitter", "Maintenir"],
	]
	for i in defs.size():
		var c := _card(defs[i])
		_row.add_child(c)
		_cards.append(c)
		c.modulate.a = 0
		c.position.y += 60
	await get_tree().process_frame
	for i in _cards.size():
		var c := _cards[i]
		var y := c.position.y
		c.position.y = y + 80
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "position:y", y, 0.55).set_delay(0.03 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.3).set_delay(0.03 * i)
	App.quiet_focus(_cards[0])
	_on_focus(0)
	_load_volume()


func _build_header() -> void:
	var g: Dictionary = App.running_game if App.running_game else {}
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 26)
	add_child(_header)
	_header.position = Vector2(110, 90)
	var cover := TextureRect.new()
	cover.texture = g.get("_cover")
	cover.custom_minimum_size = Vector2(120, 180)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header.add_child(cover)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	_header.add_child(v)
	v.add_child(UI.label("EN JEU", 22, 700, UI.ACCENT))
	v.add_child(UI.label(g.get("name", ""), 54, 800))
	var mins := 0
	var cur = App.current()
	if cur and cur.get("started_at") != null:
		mins = int((Time.get_ticks_msec() - cur.started_at) / 60000)
	v.add_child(UI.label("Session : %d min" % mins, 26, 500, UI.DIM))
	UI.fade_in(_header, 0.05, 0.4)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 22)
	add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -360
	right.offset_right = -90
	right.offset_top = 96
	right.alignment = BoxContainer.ALIGNMENT_END
	var net: Dictionary = App.network
	right.add_child(AnimIcon.new("ethernet" if net.get("type", "") == "ethernet" else "wifi", "on", 44))
	var t := Time.get_time_dict_from_system()
	right.add_child(UI.label("%02d:%02d" % [t.hour, t.minute], 40, 650))
	UI.fade_in(right, 0.1, 0.4)


func _card(d: Array) -> Button:
	var id: String = d[0]
	var b := Button.new()
	b.custom_minimum_size = Vector2(196, 216)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("id", id)
	var danger := id == "quit"
	var normal := UI.box(Color(0.14, 0.16, 0.24, 0.92), Color(0, 0, 0, 0.5), 6, 28, Vector2(18, 18))
	var foc := UI.box(Color("f2f4fa") if not danger else Color("ff5d6c"), Color("aab3c9") if not danger else Color("a92e3a"), 6, 28, Vector2(18, 18))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_top = 24
	v.offset_right = -18
	v.offset_bottom = -18
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(60, 60)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	ic.texture = App.icon(d[1], 60, Color.WHITE if not danger else UI.DANGER)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(ic)
	v.add_child(UI.vspacer())
	var title := UI.label(d[2], 28, 700)
	v.add_child(title)
	var sub := UI.label(d[3], 20, 500, UI.DIM)
	sub.clip_text = true
	sub.custom_minimum_size.x = 150
	v.add_child(sub)
	b.set_meta("sub", sub)
	var fill := ColorRect.new()
	fill.color = Color(1, 1, 1, 0.35)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = Vector2(0, 8)
	b.add_child(fill)
	b.set_meta("fill", fill)
	UI.center_pivot(b)
	var dark := Color("0b0e16") if not danger else Color.WHITE
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		ic.texture = App.icon(d[1], 60, dark)
		title.add_theme_color_override("font_color", dark)
		sub.add_theme_color_override("font_color", Color(dark, 0.7))
		UI.pop(b, 1.08)
		var tw := b.create_tween()
		tw.tween_property(v, "offset_top", 16.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_on_focus(_cards.find(b)))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		ic.texture = App.icon(d[1], 60, Color.WHITE if not danger else UI.DANGER)
		title.add_theme_color_override("font_color", UI.TEXT)
		sub.add_theme_color_override("font_color", UI.DIM)
		UI.pop(b, 1.0)
		v.offset_top = 24
		_cancel_hold())
	b.pressed.connect(func(): _activate(id, b))
	if danger:
		_quit_card = b
	return b


func _on_focus(i: int) -> void:
	if i < 0:
		return
	var texts := {
		"resume": "Fermer le menu et reprendre la partie.",
		"home": "Revenir à l'accueil sans fermer le jeu.",
		"shot": "Enregistrer une capture d'écran du jeu.",
		"vol": "Volume général.",
		"pad": "Manette utilisée par le joueur 1.",
		"quit": "Maintenez le bouton de validation pour quitter le jeu.",
	}
	var id: String = _cards[i].get_meta("id")
	_detail.text = texts.get(id, "")
	_detail.modulate.a = 0
	_detail.create_tween().tween_property(_detail, "modulate:a", 1.0, 0.25)


func _activate(id: String, b: Button) -> void:
	var sub: Label = b.get_meta("sub")
	match id:
		"resume":
			close()
		"home":
			close()
			App.replace_all(Home.new())
		"shot":
			# On ferme le menu d'abord : la capture montre le jeu, pas le menu.
			close()
			App.capture_screen()
		"vol":
			# Volume système réel (PipeWire)
			_vol_i = (_vol_i + 1) % VOL_STEPS.size()
			var r = await App.api("POST", "/media/volume", {"volume": VOL_STEPS[_vol_i] / 100.0})
			if r is Dictionary and r.has("_error"):
				App.toast(r._error, "close", UI.DANGER)
			else:
				sub.text = "%d %%" % VOL_STEPS[_vol_i]
		"pad":
			var pads := Pads.connected()
			if not pads.is_empty():
				Input.start_joy_vibration(pads[0].device, 0.4, 0.6, 0.3)
		"quit":
			pass # géré par le maintien (voir _input)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("guide"):
		get_viewport().set_input_as_handled()
		close()
		return
	if _quit_card and _quit_card.has_focus() and event.is_action("ui_accept"):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo() and _hold_t < 0.0:
			_hold_t = 0.0
		elif not event.is_pressed():
			_cancel_hold()


func _process(delta: float) -> void:
	if _hold_t >= 0.0 and _quit_card:
		_hold_t += delta
		var fill: ColorRect = _quit_card.get_meta("fill")
		var p := clampf(_hold_t / 1.4, 0.0, 1.0)
		fill.position = Vector2(14, _quit_card.size.y - 18)
		fill.size = Vector2((_quit_card.size.x - 28) * p, 6)
		if p >= 1.0:
			_hold_t = -1.0
			_quit_game()


func _cancel_hold() -> void:
	_hold_t = -1.0
	if _quit_card:
		var fill: ColorRect = _quit_card.get_meta("fill")
		fill.size.x = 0


func _quit_game() -> void:
	App.sfx.play("transition_back")
	var name: String = App.running_game.name if App.running_game else ""
	App.running_game = null
	App.api("POST", "/games/stop")
	close()
	App.replace_all(Home.new())
	App.toast("%s fermé" % name, "close", UI.DIM)


func on_cancel() -> bool:
	close()
	return true


func close() -> void:
	if _closing:
		return
	_closing = true
	App.sfx.play("back")
	var m: ShaderMaterial = _blur.material
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(x: float): m.set_shader_parameter("amount", x), 1.0, 0.0, 0.3)
	for i in _cards.size():
		tw.tween_property(_cards[i], "modulate:a", 0.0, 0.2).set_delay(0.015 * i)
		tw.tween_property(_cards[i], "position:y", _cards[i].position.y + 60, 0.3).set_delay(0.015 * i)
	tw.tween_property(_header, "modulate:a", 0.0, 0.2)
	tw.tween_property(_detail, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func():
		App.overlay_open = false
		App.close_modal(self))


func hints() -> Array:
	return [["ui_accept", "Sélectionner"], ["guide", "Reprendre"], ["ui_cancel", "Fermer"]]


## Affiche le volume système réel sur la carte « Son ».
func _load_volume() -> void:
	var r = await App.api("GET", "/media/volume")
	if not (r is Dictionary) or r.has("_error"):
		return
	var pct := roundi(float(r.volume) * 100.0) if not r.get("muted", false) else 0
	var best := 0
	for i in VOL_STEPS.size():
		if absi(VOL_STEPS[i] - pct) < absi(VOL_STEPS[best] - pct):
			best = i
	_vol_i = best
	for c in _cards:
		if c.get_meta("id") == "vol":
			c.get_meta("sub").text = "%d %%" % pct
