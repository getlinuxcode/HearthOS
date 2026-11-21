extends Control
## Onboarding 3 : installation à la manette.
## Disque → mode (à côté de Windows / espace libre / disque entier) → taille → maintenir pour confirmer → progression.

const UI := preload("res://src/ui.gd")
const Stepper := preload("res://src/widgets/stepper.gd")
const AnimIcon := preload("res://src/widgets/anim_icon.gd")

const GB := 1073741824.0
const MIN_GB := 64
const STEP_GB := 16
const HOLD_S := 2.2

var on_done: Callable
var _body: VBoxContainer
var _stage := "disk"
var _disks: Array = []
var _disk: Dictionary = {}
var _mode := "alongside"
var _size_gb := 256
var _focus_first: Control
var _slider: SizeBar
var _hold: HoldButton
var _ring: Ring
var _step_label: Label
var _poll: Timer
var _simulated := true


func _init(done: Callable) -> void:
	on_done = done


func _ready() -> void:
	add_child(Stepper.new(2))
	_simulated = App.info.get("mock", true)
	if _simulated:
		var tag := PanelContainer.new()
		var sb := UI.panel_box(Color(1.0, 0.71, 0.28, 0.16), 30, 10)
		sb.shadow_size = 0
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		tag.add_theme_stylebox_override("panel", sb)
		tag.add_child(UI.label("Mode simulation : aucun disque ne sera modifié", 21, 600, UI.WARN))
		add_child(tag)
		tag.position.y = 112
		tag.resized.connect(func(): tag.position.x = (get_viewport_rect().size.x - tag.size.x) / 2.0)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	add_child(_body)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = 330
	_body.offset_right = -330
	_body.offset_top = 175
	_body.offset_bottom = -110
	_poll = Timer.new()
	_poll.wait_time = 0.6
	_poll.timeout.connect(_poll_progress)
	add_child(_poll)


func on_enter() -> void:
	_clear()
	_body.add_child(_title("Analyse des disques…"))
	var d = await App.api("GET", "/disks")
	_disks = d if d is Array else []
	_go("disk")


func default_focus() -> Control:
	return _focus_first


func hints() -> Array:
	match _stage:
		"size": return [["lr", "Ajuster"], ["ui_accept", "Continuer"], ["ui_cancel", "Retour"]]
		"confirm": return [["ui_accept", "Maintenir pour installer"], ["ui_cancel", "Retour"]]
		"progress": return []
	return [["ui_accept", "Sélectionner"], ["ui_cancel", "Retour"]]


func on_cancel() -> bool:
	match _stage:
		"mode": _go("disk")
		"size": _go("mode")
		"manual": _go("mode")
		"confirm": _go({"erase": "mode", "manual": "manual"}.get(_mode, "size"))
		"progress": return true
		_: return false
	App.sfx.play("transition_back")
	return true


func _go(s: String) -> void:
	_stage = s
	_clear()
	match s:
		"disk": _disk_stage()
		"mode": _mode_stage()
		"size": _size_stage()
		"manual": _manual_stage()
		"confirm": _confirm_stage()
		"progress": _progress_stage()
	var i := 0
	for c in _body.get_children():
		UI.fade_in(c, i * 0.06, 0.45)
		i += 1
	if _focus_first:
		App.quiet_focus(_focus_first)
	App.refresh_hints()


func _clear() -> void:
	_focus_first = null
	for c in _body.get_children():
		c.queue_free()


func _title(t: String, sub := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var l := UI.label(t, 56, 750)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if sub != "":
		var s := UI.label(sub, 26, 400, UI.DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	return v


func _card(min_h := 120) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = min_h
	var normal := UI.box(Color(0.1, 0.12, 0.19, 0.85), Color(0, 0, 0, 0.45), 5, 26, Vector2(30, 20))
	var foc := UI.box(Color(0.17, 0.2, 0.3, 0.95), Color(0, 0, 0, 0.45), 5, 26, Vector2(30, 20))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", foc)
	b.add_theme_stylebox_override("pressed", foc)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", UI.focus_ring(30, 4))
	UI.center_pivot(b)
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", foc)
		UI.pop(b, 1.03))
	b.focus_exited.connect(func():
		b.add_theme_stylebox_override("normal", normal)
		UI.pop(b, 1.0))
	return b


func _fmt(bytes: float) -> String:
	return "%.1f To" % (bytes / GB / 1024.0) if bytes >= 1024.0 * GB else "%d Go" % roundi(bytes / GB)


# ------------------------------------------------------------------ 1. Disque

func _disk_stage() -> void:
	_body.add_child(_title("Où installer ?", "Tout se fait à la manette. Rien n'est écrit avant votre confirmation."))
	for d in _disks:
		var b := _card(140)
		b.disabled = d.get("isBootMedia", false)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 24)
		b.add_child(h)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 30
		h.offset_right = -30
		var ico := PanelContainer.new()
		var isb := UI.panel_box(Color(1, 1, 1, 0.08), 18, 0)
		isb.shadow_size = 0
		ico.add_theme_stylebox_override("panel", isb)
		ico.custom_minimum_size = Vector2(84, 84)
		ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var it := UI.label(str(d.transport).to_upper(), 20, 800, UI.DIM)
		it.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		it.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ico.add_child(it)
		h.add_child(ico)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 6)
		h.add_child(v)
		v.add_child(UI.label(d.model, 30, 650))
		v.add_child(UI.label("%s · %s" % [_fmt(d.size), d.path], 22, 400, UI.DIM))
		var bar := PartBar.new(d)
		bar.custom_minimum_size = Vector2(0, 14)
		v.add_child(bar)
		var tags := VBoxContainer.new()
		tags.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(tags)
		for os_name in d.get("detectedOS", []):
			tags.add_child(_badge("%s détecté" % os_name, Color("3d8cf5")))
		if d.get("isBootMedia", false):
			tags.add_child(_badge("Support de démarrage", UI.DIM))
		elif d.get("freeSpace", 0) > MIN_GB * GB:
			tags.add_child(_badge("%s libres" % _fmt(d.freeSpace), UI.OK))
		b.pressed.connect(func():
			_disk = d
			_mode = "alongside" if d.has("shrinkable") else ("free" if d.freeSpace >= MIN_GB * GB else "erase")
			_go("mode"))
		_body.add_child(b)
		if _focus_first == null and not b.disabled:
			_focus_first = b
	var skip := UI.chunky("Passer : rester en mode live", "", "ghost", 24)
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.pressed.connect(func(): on_done.call())
	_body.add_child(skip)
	if _focus_first == null:
		_focus_first = skip


func _badge(t: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UI.panel_box(Color(col, 0.18), 10, 6)
	sb.shadow_size = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UI.label(t, 19, 700, col.lightened(0.35)))
	return p


class PartBar extends Control:
	var d: Dictionary
	func _init(disk: Dictionary) -> void:
		d = disk
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var cols := {"windows": Color("3d8cf5"), "efi": Color("8a8f9c"), "linux": Color("f2a33a"), "data": Color("5b6170")}
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.07)
		sb.set_corner_radius_all(7)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var x := 0.0
		var total: float = d.size
		for p in d.get("partitions", []):
			var w: float = maxf(size.x * p.size / total, 3.0)
			draw_rect(Rect2(x, 0, w - 2, size.y), cols.get(p.get("os", "data"), cols.data))
			x += w


# ------------------------------------------------------------------ 2. Mode

func _mode_stage() -> void:
	var d := _disk
	_body.add_child(_title(d.model, "Comment utiliser ce disque ?"))
	var can_along: bool = d.has("shrinkable") and d.shrinkable.maxBytes >= MIN_GB * GB
	var can_free: bool = d.get("freeSpace", 0) >= MIN_GB * GB
	var opts := [
		["alongside", "À côté de Windows", "Windows reste intact. Au démarrage : jouer ici, ou travailler sous Windows.", can_along, "logout"],
		["free", "Dans l'espace libre", "Utilise %s non partitionnés sans toucher au reste." % _fmt(d.get("freeSpace", 0)), can_free, "folder"],
		["erase", "Effacer tout le disque", "Supprime TOUT le contenu (Windows compris) pour ne garder que la console.", d.size >= MIN_GB * GB, "close"],
		["manual", "Partitionnement manuel", "Choisissez vous-même la partition système (formatée) et la partition EFI parmi les partitions existantes.", d.partitions.size() > 0, "tune"],
	]
	for o in opts:
		var b := _card(130)
		b.disabled = not o[3]
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 26)
		b.add_child(h)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 34
		h.offset_right = -30
		var danger: bool = o[0] == "erase"
		h.add_child(UI.icon_rect(o[4], 48, UI.DANGER if danger else UI.ACCENT))
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UI.label(o[1], 32, 700, UI.DANGER if danger else UI.TEXT))
		var why := "Indisponible sur ce disque"
		if o[0] == "alongside" and _has_bitlocker(d):
			why = "Windows est chiffré par BitLocker : suspendez-le dans Windows, puis recommencez"
		var desc := UI.label(o[2] if o[3] else why, 22, 400, UI.DIM if o[3] else UI.WARN)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(desc)
		var mode: String = o[0]
		b.pressed.connect(func():
			_mode = mode
			if mode == "erase":
				_size_gb = int(d.size / GB)
				_go("confirm")
			elif mode == "manual":
				_go("manual")
			else:
				_size_gb = clampi(int(_max_gb() * 0.5 / STEP_GB) * STEP_GB, MIN_GB, _max_gb())
				_go("size"))
		_body.add_child(b)
		if _focus_first == null and o[3]:
			_focus_first = b


func _max_gb() -> int:
	var bytes: float = 0.0
	if _mode == "alongside":
		bytes = _disk.shrinkable.maxBytes
	elif _mode == "free":
		bytes = _disk.freeSpace
	else:
		bytes = _disk.size
	return int(bytes / GB)


# ------------------------------------------------------------------ 3. Taille

class SizeBar extends Button:
	var total := 1000.0
	var value := 256.0
	var shown := 256.0
	var other_label := "Windows"
	var _t := 0.0
	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		for st in ["normal", "hover", "pressed", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _process(d: float) -> void:
		_t += d
		shown = lerpf(shown, value, minf(1.0, d * 12.0))
		queue_redraw()
	func _draw() -> void:
		var f := App.font(700)
		var f2 := App.font(500)
		var r := Rect2(Vector2(0, 20), Vector2(size.x, 120))
		var pct := clampf(shown / total, 0.08, 0.92)
		var split := r.size.x * (1.0 - pct)
		var a := StyleBoxFlat.new()
		a.bg_color = Color("3d8cf5", 0.45)
		a.set_corner_radius_all(22)
		a.corner_radius_top_right = 6
		a.corner_radius_bottom_right = 6
		draw_style_box(a, Rect2(r.position, Vector2(split - 4, r.size.y)))
		var b := StyleBoxFlat.new()
		b.bg_color = Color("7c9cff").lerp(Color("b56bff"), 0.5 + 0.5 * sin(_t))
		b.set_corner_radius_all(22)
		b.corner_radius_top_left = 6
		b.corner_radius_bottom_left = 6
		draw_style_box(b, Rect2(r.position + Vector2(split + 4, 0), Vector2(r.size.x - split - 4, r.size.y)))
		draw_string(f2, r.position + Vector2(28, 50), other_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8))
		draw_string(f, r.position + Vector2(28, 92), "%d Go" % roundi(total - shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
		draw_string(f2, r.position + Vector2(split + 30, 50), "Console", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85))
		draw_string(f, r.position + Vector2(split + 30, 92), "%d Go" % roundi(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
		# poignée
		var hx := r.position.x + split
		var focused := has_focus()
		var glow := 0.5 + 0.5 * sin(_t * 4.0)
		if focused:
			draw_circle(Vector2(hx, r.get_center().y), 34 + glow * 5, Color(1, 1, 1, 0.12))
		draw_circle(Vector2(hx, r.get_center().y), 26, Color.WHITE)
		draw_string(f, Vector2(hx - 17, r.get_center().y + 9), "◀▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("0b0e16"))


func _size_stage() -> void:
	_body.add_child(_title("Quelle place pour vos jeux ?", "Les jeux modernes pèsent souvent 50 à 150 Go. Gauche / droite pour ajuster."))
	_body.add_child(UI.vspacer(20))
	_slider = SizeBar.new()
	_slider.custom_minimum_size = Vector2(0, 170)
	var part: Dictionary = {}
	for p in _disk.partitions:
		if _disk.has("shrinkable") and p.path == _disk.shrinkable.partition:
			part = p
	_slider.total = float(part.size if _mode == "alongside" and not part.is_empty() else _disk.size) / GB
	_slider.value = _size_gb
	_slider.shown = _size_gb * 0.6
	_slider.other_label = "Windows" if _mode == "alongside" else "Existant"
	_slider.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right"):
			_slider.accept_event()
			var nv := clampi(_size_gb + (STEP_GB if ev.is_action_pressed("ui_right") else -STEP_GB), MIN_GB, _max_gb())
			if nv == _size_gb:
				App.sfx.play("error")
			else:
				_size_gb = nv
				_slider.value = nv
				App.sfx.play("tick"))
	_body.add_child(_slider)
	if _mode == "alongside" and part.has("used"):
		var n := UI.label("Windows utilise %s ; une marge de sécurité lui est toujours laissée." % _fmt(part.used), 22, 400, UI.DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(n)
	_body.add_child(UI.vspacer(20))
	var next := UI.chunky("Continuer", "check", "primary", 30)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(func(): _go("confirm"))
	_body.add_child(next)
	_slider.focus_neighbor_bottom = next.get_path()
	_focus_first = _slider


# ------------------------------------------------------------------ 4. Confirmation

class HoldButton extends Button:
	var progress := 0.0
	var danger := false
	var _t := 0.0
	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(560, 96)
		for st in ["normal", "hover", "pressed", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var base := StyleBoxFlat.new()
		base.bg_color = Color(1, 1, 1, 0.1)
		base.set_corner_radius_all(48)
		base.border_width_bottom = 6
		base.border_color = Color(0, 0, 0, 0.45)
		draw_style_box(base, r)
		if progress > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = (Color("ff5d6c") if danger else Color("7c9cff")).lerp(Color("b56bff") if not danger else Color("ff8a5c"), progress)
			fill.set_corner_radius_all(48)
			draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(maxf(96.0, size.x * progress), size.y)))
		if has_focus():
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.set_border_width_all(4)
			ring.border_color = Color(1, 1, 1, 0.75 + 0.25 * sin(_t * 4.0))
			ring.set_corner_radius_all(54)
			draw_style_box(ring, r.grow(7))
		var f := App.font(700)
		var txt := "Maintenez pour installer" if progress < 1.0 else "C'est parti !"
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
		draw_string(f, Vector2((size.x - sz.x) / 2.0, size.y / 2.0 + 11), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


var _holding := false

func _confirm_stage() -> void:
	_body.add_child(_title("Prêt à installer"))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_box(UI.PANEL, 28, 30))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var lines := [["Disque", "%s (%s)" % [_disk.model, _disk.path], UI.TEXT]]
	match _mode:
		"erase": lines.append(["Attention", "TOUTES les données de ce disque seront effacées", UI.DANGER])
		"alongside":
			lines.append(["Windows", "réduit de %d Go, ses fichiers sont conservés" % _size_gb, UI.TEXT])
			lines.append(["Démarrage", "menu pour choisir le système", UI.TEXT])
		"free": lines.append(["Espace", "%d Go d'espace libre utilisés" % _size_gb, UI.TEXT])
		"manual":
			lines.append(["Système", "%s (sera formatée en btrfs)" % _manual.root, UI.WARN])
			if _manual.get("efi", "") != "":
				lines.append(["EFI", "%s (%s)" % [_manual.efi, "formatée" if _manual.get("formatEfi", false) else "réutilisée"], UI.TEXT])
	lines.append(["Hearth", "Arch Linux · btrfs avec instantanés · comptes et réglages de cette session conservés", UI.TEXT])
	lines.append(["Démarrage", "menu GRUB : Hearth par défaut, Windows et autres systèmes détectés", UI.TEXT])
	for l in lines:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 20)
		var k := UI.label(l[0], 24, 500, UI.DIM)
		k.custom_minimum_size.x = 200
		h.add_child(k)
		h.add_child(UI.label(l[1], 26, 600, l[2]))
		v.add_child(h)
	if _mode == "alongside":
		v.add_child(UI.label("Avant de continuer : désactivez BitLocker et le « démarrage rapide » de Windows.", 21, 400, UI.WARN))
	_body.add_child(p)
	_body.add_child(UI.vspacer(16))
	_hold = HoldButton.new()
	_hold.danger = _mode == "erase"
	_hold.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_hold)
	_focus_first = _hold


func _input(event: InputEvent) -> void:
	if _stage != "confirm" or _hold == null or not _hold.has_focus():
		return
	if event.is_action("ui_accept"):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_holding = true
		elif not event.is_pressed():
			_holding = false


func _process(delta: float) -> void:
	if _stage == "confirm" and _hold and is_instance_valid(_hold):
		if _holding:
			_hold.progress = minf(1.0, _hold.progress + delta / HOLD_S)
			if _hold.progress >= 1.0:
				_holding = false
				_launch_install()
		elif _hold.progress < 1.0:
			_hold.progress = maxf(0.0, _hold.progress - delta * 2.5)


func _launch_install() -> void:
	App.sfx.play("confirm")
	var plan := {"disk": _disk.path, "mode": _mode, "sizeGB": _size_gb}
	if _mode == "manual":
		plan["manual"] = _manual
	var r = await App.api("POST", "/install/start", plan)
	if r is Dictionary and r.has("_error"):
		App.sfx.play("error")
		App.toast(r._error, "close", UI.DANGER)
		_hold.progress = 0.0
		return
	_go("progress")


# ------------------------------------------------------------------ 5. Progression

class Ring extends Control:
	var pct := 0.0
	var shown := 0.0
	var _t := 0.0
	func _process(d: float) -> void:
		_t += d
		shown = lerpf(shown, pct, minf(1.0, d * 4.0))
		queue_redraw()
	func _draw() -> void:
		var c := size / 2.0
		var r := size.y * 0.42
		draw_arc(c, r, 0, TAU, 96, Color(1, 1, 1, 0.08), 14, true)
		if shown > 0.001:
			var steps := 64
			var prev := c + Vector2(0, -r)
			for i in range(1, steps + 1):
				var a := -PI / 2.0 + TAU * shown * i / steps
				var p := c + Vector2(cos(a), sin(a)) * r
				draw_line(prev, p, Color("7c9cff").lerp(Color("b56bff"), float(i) / steps), 14, true)
				prev = p
			draw_circle(prev, 11 + 3 * sin(_t * 5.0), Color(1, 1, 1, 0.9))
		var f := App.font(750)
		var txt := "%d %%" % roundi(shown * 100.0)
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 60)
		draw_string(f, c + Vector2(-sz.x / 2.0, 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color.WHITE)


func _progress_stage() -> void:
	_body.add_child(_title("Installation en cours"))
	_ring = Ring.new()
	_ring.custom_minimum_size = Vector2(340, 340)
	_ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_ring)
	_step_label = UI.label("Préparation…", 28, 500, UI.DIM)
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_step_label)
	App.bg.set_energy(0.25, 2.0)
	_poll.start()


func _poll_progress() -> void:
	var p = await App.api("GET", "/install/progress")
	if not (p is Dictionary) or not is_instance_valid(_ring):
		return
	_ring.pct = p.percent / 100.0
	if _step_label.text != p.step:
		_step_label.text = p.step
		UI.fade_in(_step_label, 0.0, 0.3)
	if p.state == "done":
		_poll.stop()
		App.bg.set_energy(0.0, 1.5)
		App.sfx.play("success")
		_step_label.text = "Simulation terminée" if p.simulated else "Hearth est installé ! Retirez la clé USB puis redémarrez : le menu de démarrage s'affichera."
		var ok := UI.chunky("Continuer" if p.simulated else "Redémarrer maintenant", "check" if p.simulated else "refresh", "primary", 30)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if p.simulated:
			ok.pressed.connect(func(): on_done.call())
		else:
			ok.pressed.connect(func():
				App.bg.blackout(1.0, 0.6)
				App.api("POST", "/power/reboot"))
		_body.add_child(ok)
		UI.fade_in(ok, 0.2, 0.4)
		App.quiet_focus(ok)
	elif p.state == "error":
		_poll.stop()
		App.bg.set_energy(0.0, 1.0)
		App.sfx.play("error")
		_step_label.text = "Installation interrompue : %s" % p.get("error", "erreur inconnue")
		_step_label.add_theme_color_override("font_color", UI.DANGER)
		_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var back := UI.chunky("Revenir au choix du disque", "arrow_back", "normal", 28)
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		back.pressed.connect(func(): _go("disk"))
		_body.add_child(back)
		App.quiet_focus(back)


# ------------------------------------------------------------------ Partitionnement manuel

var _manual := {}
var _roles := {}

func _has_bitlocker(d: Dictionary) -> bool:
	for p in d.get("partitions", []):
		if p.get("bitlocker", false):
			return true
	return false


func _manual_stage() -> void:
	_body.add_child(_title("Partitionnement manuel", "Attribuez un rôle aux partitions de %s. Gauche / droite pour changer." % _disk.model))
	var Rows = load("res://src/widgets/rows.gd")
	var rows = Rows.new()
	var defs := []
	_roles = {}
	for p in _disk.partitions:
		var path: String = p.path
		var is_esp: bool = p.get("os", "") == "efi"
		_roles[path] = "efi" if is_esp and not _roles.values().has("efi") else "ignore"
		var desc := "%s · %s%s" % [_fmt(p.size), str(p.get("fstype", "inconnu")), (" · " + str(p.label)) if p.get("label", "") != "" else ""]
		var opts := [["ignore", "Ne pas toucher"], ["root", "Système Hearth (formatée)"], ["efi", "EFI (réutilisée)"], ["efi_fmt", "EFI (formatée)"]]
		if p.get("bitlocker", false) or p.get("os", "") == "windows":
			opts = [["ignore", "Ne pas toucher (Windows)"]]
		defs.append({"kind": "choice", "label": path, "desc": desc, "options": opts,
			"get": func(): return _roles[path],
			"set": func(v): _roles[path] = v})
	if defs.is_empty():
		defs.append({"kind": "info", "label": "Aucune partition", "value": "Utilisez « Effacer tout le disque » ou créez des partitions"})
	rows.set_rows(defs)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_box(UI.PANEL, 28, 16))
	panel.add_child(rows)
	_body.add_child(panel)
	var next := UI.chunky("Continuer", "check", "primary", 30)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_manual_next)
	_body.add_child(next)
	_focus_first = rows.first_focusable() if rows.first_focusable() else next


func _manual_next() -> void:
	var roots := []
	var efis := []
	for path in _roles:
		match _roles[path]:
			"root": roots.append(path)
			"efi", "efi_fmt": efis.append(path)
	var err := ""
	if roots.size() != 1:
		err = "Choisissez une (et une seule) partition « Système Hearth »"
	elif efis.size() > 1:
		err = "Une seule partition EFI à la fois"
	if err != "":
		App.sfx.play("error")
		App.toast(err, "close", UI.DANGER)
		return
	var efi: String = efis[0] if efis.size() == 1 else ""
	_manual = {"root": roots[0], "efi": efi, "formatEfi": efi != "" and _roles[efi] == "efi_fmt"}
	_go("confirm")
