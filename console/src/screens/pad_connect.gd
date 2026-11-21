extends Control
## Onboarding 1 : grande manette, halo qui pulse sur le bouton central.
## « Appuyez sur le bouton PS » → explosion lumineuse, vibration, la bonne manette s'affiche.

const UI := preload("res://src/ui.gd")
const Pads := preload("res://src/pads.gd")
const PadStage := preload("res://src/widgets/pad_stage.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")
const Glyph := preload("res://src/widgets/glyph.gd")
const Network := preload("res://src/screens/network.gd")
const Stepper := preload("res://src/widgets/stepper.gd")

const CYCLE := ["dualsense", "xbox", "ds4", "switch", "xbox360"]

var _stage: PadStage
var _eyebrow: Label
var _title: Label
var _sub: Label
var _status_icon: AnimIcon
var _status: Label
var _status_row: HBoxContainer
var _continue: Button
var _kb: Button
var _state := ""
var _cycle_i := 0
var _cycle_t := 0.0
var _pad := {}


func _ready() -> void:
	set_meta("can_back", false)
	var stepper := Stepper.new(0)
	add_child(stepper)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 60
	row.offset_right = -140
	row.offset_top = 120
	row.offset_bottom = -110

	_stage = PadStage.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_stretch_ratio = 1.25
	row.add_child(_stage)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	row.add_child(col)

	_eyebrow = UI.label("BIENVENUE", 24, 700, UI.ACCENT)
	col.add_child(_eyebrow)
	_title = UI.label("", 68, 750)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_sub = UI.label("", 30, 400, UI.DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size.x = 640
	col.add_child(_sub)

	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 18)
	col.add_child(UI.vspacer(8))
	col.add_child(_status_row)
	_status_icon = AnimIcon.new("bt", "search", 56, UI.ACCENT)
	_status_row.add_child(_status_icon)
	_status = UI.label("", 28, 500)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_row.add_child(_status)

	col.add_child(UI.vspacer(20))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 22)
	col.add_child(btns)
	_continue = UI.chunky("Continuer", "check", "primary", 30)
	_continue.visible = false
	_continue.pressed.connect(_next)
	btns.add_child(_continue)
	_kb = UI.chunky("Continuer au clavier", "", "ghost", 26)
	_kb.pressed.connect(_next)
	btns.add_child(_kb)

	for i in col.get_child_count():
		var c := col.get_child(i)
		if c is CanvasItem:
			UI.fade_in(c, 0.15 + i * 0.08, 0.7)

	App.pads_changed.connect(_refresh)


func on_enter() -> void:
	App.bg.default_tint()
	App.bg.set_hero(null)
	_refresh()
	if App.args.has("fakepad"):
		await get_tree().create_timer(1.2).timeout
		_ready_with({"device": 0, "family": App.args.fakepad, "name": "DualShock 4" if App.args.fakepad == "ds4" else "Manette", "vendor": "054c", "product": "09cc"})


func default_focus() -> Control:
	return _continue if _continue.visible else _kb


func hints() -> Array:
	if _state == "ready":
		return [["ui_accept", "Continuer"]]
	return [["guide", "Allumer la manette"], ["ui_accept", "Continuer au clavier"]]


func _process(delta: float) -> void:
	if _state == "search":
		_cycle_t += delta
		if _cycle_t > 2.6:
			_cycle_t = 0.0
			_cycle_i = (_cycle_i + 1) % CYCLE.size()
			_stage.show_family(CYCLE[_cycle_i])


func _refresh() -> void:
	if _state == "ready":
		return
	var pads := Pads.connected()
	if pads.is_empty():
		_set_search()
	else:
		_set_press(pads[0])


func _set_search() -> void:
	if _state == "search":
		return
	_state = "search"
	_stage.halo = true
	_stage.show_family(CYCLE[_cycle_i])
	_title.text = "Allumez votre manette"
	_sub.text = "Appuyez sur le bouton central de votre manette (PS, Xbox, HOME…) ou branchez-la en USB."
	_status_icon.kind = "bt"
	_status_icon.set_state("search")
	_status.text = "Recherche de manettes…"
	App.refresh_hints()


func _set_press(p: Dictionary) -> void:
	_state = "press"
	_pad = p
	_stage.halo = true
	_stage.show_family(p.family)
	_title.text = "%s détectée" % p.name
	_sub.text = "Appuyez sur le bouton %s pour la démarrer." % Pads.home_button_name(p.family)
	_status_icon.kind = "bt"
	_status_icon.set_state("on")
	_status.text = "En attente d'un appui…"
	App.refresh_hints()


func _input(event: InputEvent) -> void:
	if _state == "ready" or not is_visible_in_tree():
		return
	if event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		_ready_with(Pads.identify(event.device))


func _ready_with(p: Dictionary) -> void:
	_state = "ready"
	_pad = p
	_stage.show_family(p.family, p.family != _stage.family)
	_stage.halo = false
	_stage.burst()
	App.sfx.play("pad")
	Input.start_joy_vibration(p.device, 0.5, 0.8, 0.35)
	_eyebrow.text = "MANETTE CONNECTÉE"
	_title.text = "%s prête !" % p.name
	_sub.text = "Tout se pilote à la manette, jusqu'à l'installation. Le clavier et la souris restent utilisables."
	_status_icon.kind = "check"
	_status_icon.color = UI.OK
	_status_icon.set_state("on")
	_status.text = "Identifiée · USB %s:%s" % [p.vendor, p.product] if p.vendor != "" else "Identifiée"
	_continue.visible = true
	_kb.visible = false
	UI.pop(_continue, 1.0)
	App.quiet_focus(_continue)
	for n in [_title, _sub, _status_row]:
		n.modulate.a = 0.0
		UI.fade_in(n, 0.1, 0.5)
	App.refresh_hints()


func _next() -> void:
	App.push(Network.new())
