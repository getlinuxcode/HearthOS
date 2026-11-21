extends Control
## « Jeu en cours ». Sur la distribution, gamescope affiche le jeu par-dessus et cet écran est caché ;
## en développement, il représente le jeu (illustration assombrie) pour tester l'overlay.

const UI := preload("res://src/ui.gd")
const Glyph := preload("res://src/widgets/glyph.gd")

var game: Dictionary
var started_at := 0


func _init(g: Dictionary) -> void:
	game = g
	started_at = Time.get_ticks_msec()
	set_meta("can_back", false)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.55, 0.55, 0.6)
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if game.source == "steam":
		art.texture = await App.remote_texture(App.steam_img(game.appid, "hero"))
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UI.panel_box(Color(0, 0, 0, 0.55), 30, 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	tag.add_child(h)
	h.add_child(UI.label(("Démo : jeu simulé ·" if game.get("demo", false) else "%s est lancé ·" % game.name), 24, 500, UI.DIM))
	h.add_child(Glyph.new("guide", App.active_family, 36))
	h.add_child(UI.label("pour ouvrir le menu", 24, 500, UI.DIM))
	add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tag.position.y -= 90
	tag.position.x -= 260
	UI.fade_in(tag, 1.5, 0.8)


func hints() -> Array:
	return []


## Pendant le jeu, l'interface s'efface : plus de fond animé, rendu seulement si nécessaire.
func on_enter() -> void:
	App.bg.visible = false
	OS.low_processor_usage_mode = true
	if not game.get("demo", false):
		_watch()


func _exit_tree() -> void:
	App.bg.visible = true
	OS.low_processor_usage_mode = false


## Surveille le jeu : quand il se ferme (depuis le jeu lui-même), retour automatique à l'accueil.
func _watch() -> void:
	while is_inside_tree():
		await get_tree().create_timer(2.0).timeout
		if not is_inside_tree() or App.running_game == null:
			return
		var s = await App.api("GET", "/games/running")
		if s is Dictionary and not s.get("running", true) and App.running_game != null:
			var name: String = game.name
			App.running_game = null
			App.replace_all(load("res://src/screens/home.gd").new())
			App.toast("Partie terminée : %s" % name, "sports_esports", UI.DIM)
			return
