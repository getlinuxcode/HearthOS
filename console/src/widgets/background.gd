extends Control
## Fond vivant : nuages de couleur en mouvement lent (fbm + domain warping),
## illustration du jeu en fondu avec effet Ken Burns, particules lumineuses, grain.

const SKY := """
shader_type canvas_item;
uniform vec3 col_deep : source_color = vec3(0.02, 0.03, 0.07);
uniform vec3 col_a : source_color = vec3(0.20, 0.22, 0.62);
uniform vec3 col_b : source_color = vec3(0.47, 0.20, 0.70);
uniform vec3 col_c : source_color = vec3(0.05, 0.45, 0.55);
uniform float speed = 0.035;
uniform float energy = 0.0;
uniform float intensity = 1.0;
uniform float aspect = 1.7778;
uniform float time_offset = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 grad(vec2 p) { float a = hash(p) * 6.2831853; return vec2(cos(a), sin(a)); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad(i), f);
	float b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 0.5 + 0.7 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = r * p * 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV; uv.x *= aspect;
	float t = (TIME + time_offset) * (speed + energy * 0.6);
	vec2 c = vec2(aspect * 0.5, 0.5);
	// tourbillon pendant le lancement d'un jeu
	vec2 d = uv - c; float ang = energy * 2.5 * exp(-dot(d, d) * 2.0);
	uv = c + mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * d;
	vec2 p = uv * 1.6;
	vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3) - t));
	vec2 r = vec2(fbm(p + 2.0 * q + vec2(1.7, 9.2) + t * 1.3), fbm(p + 2.0 * q + vec2(8.3, 2.8) - t * 1.1));
	float f = fbm(p + 2.0 * r);
	vec3 col = mix(col_deep, col_a, smoothstep(0.25, 0.85, f));
	col = mix(col, col_b, smoothstep(0.35, 1.0, length(q)) * 0.75);
	col = mix(col, col_c, smoothstep(0.5, 1.1, r.x) * 0.5);
	col *= 0.35 + 0.75 * f * intensity;
	col += energy * vec3(0.25, 0.25, 0.35) * f;
	vec2 v = UV - 0.5; col *= 1.0 - dot(v, v) * 1.1;
	col += (hash(UV * 1543.0 + fract(TIME * 7.0)) - 0.5) * 0.022;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
"""

const HERO := """
shader_type canvas_item;
uniform float fade = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = smoothstep(0.08, 0.62, SCREEN_UV.x) * smoothstep(1.0, 0.5, SCREEN_UV.y);
	COLOR = vec4(c.rgb, c.a * m * fade);
}
"""

var sky: ColorRect
var _mat: ShaderMaterial
var _heroes: Array[TextureRect] = []
var _hero_idx := 0
var _hero_tex: Texture2D = null
var _veil: ColorRect
var _particles: CPUParticles2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	sky = ColorRect.new()
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	_mat.shader = sh
	_mat.set_shader_parameter("time_offset", randf() * 100.0)
	# Les valeurs par défaut des uniforms ne sont pas lisibles côté script : on les pose.
	_mat.set_shader_parameter("col_a", Color(0.20, 0.22, 0.62))
	_mat.set_shader_parameter("col_b", Color(0.47, 0.20, 0.70))
	_mat.set_shader_parameter("col_c", Color(0.05, 0.45, 0.55))
	_mat.set_shader_parameter("energy", 0.0)
	sky.material = _mat
	add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for i in 2:
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var m := ShaderMaterial.new()
		var s2 := Shader.new()
		s2.code = HERO
		m.shader = s2
		tr.material = m
		add_child(tr)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_heroes.append(tr)

	_particles = CPUParticles2D.new()
	_particles.amount = 46
	_particles.lifetime = 16.0
	_particles.preprocess = 16.0
	_particles.texture = _soft_dot()
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.direction = Vector2(0.2, -1)
	_particles.spread = 25.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 22.0
	_particles.scale_amount_min = 0.15
	_particles.scale_amount_max = 1.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 0.13))
	ramp.add_point(0.75, Color(1, 1, 1, 0.08))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	_particles.color_ramp = ramp
	add_child(_particles)

	_veil = ColorRect.new()
	_veil.color = Color(0.0, 0.0, 0.0, 1.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_particles.position = size / 2.0
	_particles.emission_rect_extents = size / 2.0 + Vector2(40, 40)


func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 96
	t.height = 96
	return t


## Lever de rideau au démarrage.
func reveal(d := 2.0) -> void:
	var tw := create_tween()
	tw.tween_property(_veil, "color:a", 0.0, d).set_trans(Tween.TRANS_SINE)


func blackout(alpha := 1.0, d := 0.8) -> Tween:
	var tw := create_tween()
	tw.tween_property(_veil, "color:a", alpha, d).set_trans(Tween.TRANS_SINE)
	return tw


## Teinte le ciel à partir d'une couleur (jeu sélectionné).
func tint(base: Color, d := 1.4) -> void:
	var a := base
	var b := Color.from_hsv(fposmod(base.h + 0.08, 1.0), clampf(base.s * 0.9, 0, 1), base.v * 0.85)
	var c := Color.from_hsv(fposmod(base.h - 0.12, 1.0), clampf(base.s * 0.8, 0, 1), base.v * 0.6)
	_tween_color("col_a", a, d)
	_tween_color("col_b", b, d)
	_tween_color("col_c", c, d)


func default_tint(d := 1.4) -> void:
	_tween_color("col_a", Color(0.20, 0.22, 0.62), d)
	_tween_color("col_b", Color(0.47, 0.20, 0.70), d)
	_tween_color("col_c", Color(0.05, 0.45, 0.55), d)


func _tween_color(param: String, to: Color, d: float) -> void:
	var from: Color = _mat.get_shader_parameter(param)
	var tw := create_tween()
	tw.tween_method(func(c: Color): _mat.set_shader_parameter(param, c), from, to, d).set_trans(Tween.TRANS_SINE)


func set_energy(v: float, d := 1.5) -> void:
	var from: float = _mat.get_shader_parameter("energy")
	var tw := create_tween()
	tw.tween_method(func(x: float): _mat.set_shader_parameter("energy", x), from, v, d).set_trans(Tween.TRANS_SINE)


## Illustration plein écran du jeu, fondu enchaîné + lent zoom arrière.
func set_hero(tex: Texture2D) -> void:
	if tex == _hero_tex:
		return
	_hero_tex = tex
	var old := _heroes[_hero_idx]
	_hero_idx = 1 - _hero_idx
	var nxt := _heroes[_hero_idx]
	_fade(old, 0.0, 0.7)
	if tex == null:
		return
	nxt.texture = tex
	nxt.pivot_offset = size / 2.0
	nxt.scale = Vector2(1.08, 1.08)
	move_child(nxt, 2)
	_fade(nxt, 0.62, 0.9)
	var tw := nxt.create_tween()
	tw.tween_property(nxt, "scale", Vector2.ONE, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func hero_strength(v: float, d := 0.6) -> void:
	_fade(_heroes[_hero_idx], v, d)


func _fade(tr: TextureRect, to: float, d: float) -> void:
	var m: ShaderMaterial = tr.material
	var from = m.get_shader_parameter("fade")
	if from == null:
		from = 0.0
	var tw := tr.create_tween()
	tw.tween_method(func(x: float): m.set_shader_parameter("fade", x), from, to, d).set_trans(Tween.TRANS_SINE)
