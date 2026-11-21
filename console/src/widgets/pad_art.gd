extends RefCounted
## Illustrations de manettes au trait (dessins originaux, sans logo de marque), générées en SVG.
## Repère : VIEW (600 × 420). Chaque modèle a sa silhouette et sa disposition.
## layout(family) donne la position de chaque bouton (halo du bouton central, écran de test).

const VIEW := Vector2(600, 420)

# Lettres des boutons en tracés (le rendu SVG intégré ne dessine pas le texte).
const LETTERS := {
	"A": "M-5 6 L0 -6 L5 6 M-3 2 H3",
	"B": "M-4 -6 V6 H1 Q5 6 5 2.8 Q5 0 1 0 H-4 M1 0 Q4.5 0 4.5 -3 Q4.5 -6 1 -6 H-4",
	"X": "M-5 -6 L5 6 M5 -6 L-5 6",
	"Y": "M-5 -6 L0 0 L5 -6 M0 0 V6",
}

# Demi-silhouettes (côté gauche, du haut-centre au bas-centre) ; le côté droit est le miroir.
const SHAPES := {
	"dualsense": "M300 92 C240 92 190 89 158 94 C110 100 80 122 68 162 C50 222 40 300 55 350 C68 394 112 402 130 372 C150 340 164 302 190 282 C216 263 256 258 300 258",
	"ds4": "M300 100 C232 100 184 96 152 99 C106 104 80 126 70 166 C57 226 44 302 61 352 C74 390 116 394 130 366 C146 332 160 302 184 284 C214 268 256 265 300 265",
	"xbox": "M300 108 C242 108 202 100 166 104 C116 110 86 132 76 172 C63 226 60 292 86 336 C106 372 152 372 170 340 C186 312 206 292 236 286 C260 282 282 282 300 282",
	"switch": "M300 104 C240 104 198 98 160 102 C110 108 80 130 70 172 C56 230 54 300 80 344 C100 380 150 380 168 346 C184 316 204 294 236 288 C260 284 282 284 300 284",
}

const STYLES := {
	"dualsense": {"shape": "dualsense", "body": "#f3f4f7", "line": "#0f1013", "panel": "#0f1013", "inner": "#f3f4f7", "accent": "#6f9bff"},
	"ds4": {"shape": "ds4", "body": "#16181e", "line": "#e7eaf0", "panel": "", "inner": "#16181e", "accent": "#4d8dff"},
	"ds3": {"shape": "ds4", "body": "#121316", "line": "#d9dce3", "panel": "", "inner": "#121316", "accent": ""},
	"xbox": {"shape": "xbox", "body": "#191b20", "line": "#e7eaf0", "panel": "", "inner": "#191b20", "accent": "#9be15d"},
	"xbox360": {"shape": "xbox", "body": "#eef0f3", "line": "#15171b", "panel": "", "inner": "#eef0f3", "accent": "#4cc04c"},
	"switch": {"shape": "switch", "body": "#1a1c21", "line": "#e7eaf0", "panel": "", "inner": "#1a1c21", "accent": ""},
	"steam": {"shape": "xbox", "body": "#1b2532", "line": "#e2e8f0", "panel": "", "inner": "#1b2532", "accent": ""},
	"generic": {"shape": "xbox", "body": "#2a2e37", "line": "#c9ced8", "panel": "", "inner": "#2a2e37", "accent": ""},
}


static func layout(family: String) -> Dictionary:
	var shape: String = STYLES.get(family, STYLES.generic).shape
	match shape:
		"dualsense":
			return {"dpad": Vector2(138, 178), "face": Vector2(462, 178), "ls": Vector2(232, 246), "rs": Vector2(368, 246),
				"select": Vector2(184, 118), "start": Vector2(416, 118), "home": Vector2(300, 238), "lb": Vector2(150, 84), "rb": Vector2(450, 84), "face_r": 32.0}
		"ds4":
			return {"dpad": Vector2(140, 182), "face": Vector2(460, 182), "ls": Vector2(232, 252), "rs": Vector2(368, 252),
				"select": Vector2(190, 120), "start": Vector2(410, 120), "home": Vector2(300, 246), "lb": Vector2(150, 90), "rb": Vector2(450, 90), "face_r": 32.0}
	return {"dpad": Vector2(240, 258), "face": Vector2(432, 176), "ls": Vector2(170, 176), "rs": Vector2(362, 258),
		"select": Vector2(260, 186), "start": Vector2(340, 186), "home": Vector2(300, 140), "lb": Vector2(158, 98), "rb": Vector2(442, 98), "face_r": 30.0}


static func home_pos(family: String) -> Vector2:
	return layout(family).home


static func _mirror(half: String) -> String:
	# Reconstruit la silhouette complète : moitié gauche + moitié droite en miroir (x → 600 − x).
	var tokens := half.replace("M", "M ").replace("C", "C ").split(" ", false)
	var pts: Array[Vector2] = []
	var nums := PackedFloat32Array()
	for t in tokens:
		if t.is_valid_float():
			nums.append(float(t))
	for i in range(0, nums.size(), 2):
		pts.append(Vector2(nums[i], nums[i + 1]))
	# pts[0] = départ, puis groupes de 3 (c1, c2, fin)
	var d := "M%.1f %.1f" % [pts[0].x, pts[0].y]
	for i in range(1, pts.size(), 3):
		d += " C%.1f %.1f %.1f %.1f %.1f %.1f" % [pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, pts[i + 2].x, pts[i + 2].y]
	# retour par le côté droit, en sens inverse
	var n := pts.size()
	var i2 := n - 1
	while i2 >= 3:
		var c1 := pts[i2 - 1]
		var c2 := pts[i2 - 2]
		var e := pts[i2 - 3]
		d += " C%.1f %.1f %.1f %.1f %.1f %.1f" % [600 - c1.x, c1.y, 600 - c2.x, c2.y, 600 - e.x, e.y]
		i2 -= 3
	return d + " Z"


static func svg(family: String) -> String:
	var st: Dictionary = STYLES.get(family, STYLES.generic)
	var L := layout(family)
	var line: String = st.line
	var body: String = st.body
	var shape: String = st.shape
	var outline := _mirror(SHAPES[shape])
	var s := PackedStringArray()
	s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 420" width="600" height="420" stroke-linecap="round" stroke-linejoin="round">')
	s.append('<defs><clipPath id="b"><path d="%s"/></clipPath></defs>' % outline)
	# gâchettes / bumpers derrière le corps
	for k in ["lb", "rb"]:
		var p: Vector2 = L[k]
		s.append('<rect x="%.1f" y="%.1f" width="84" height="30" rx="14" fill="%s" stroke="%s" stroke-width="5"/>' % [p.x - 42, p.y - 18, body, line])
	s.append('<path d="%s" fill="%s" stroke="%s" stroke-width="6"/>' % [outline, body, line])

	match shape:
		"dualsense":
			# panneau central noir qui descend vers les poignées
			s.append('<path d="M214 176 L386 176 C408 176 418 200 414 232 C411 252 402 266 390 272 C362 262 330 258 300 258 C270 258 238 262 210 272 C198 266 189 252 186 232 C182 200 192 176 214 176 Z" fill="%s"/>' % st.panel)
			# pavé tactile
			s.append('<path d="M206 96 L394 96 Q402 96 400 106 L388 180 Q386 190 376 190 L224 190 Q214 190 212 180 L200 106 Q198 96 206 96 Z" fill="%s" stroke="%s" stroke-width="5"/>' % [body, line])
			s.append('<path d="M201 112 L211 182" stroke="%s" stroke-width="3" opacity="0.9"/><path d="M399 112 L389 182" stroke="%s" stroke-width="3" opacity="0.9"/>' % [st.accent, st.accent])
			# micros
			for i in 5:
				s.append('<circle cx="%d" cy="212" r="2.6" fill="%s"/>' % [284 + i * 8, body])
			s.append('<rect x="288" y="262" width="24" height="5" rx="2.5" fill="%s"/>' % body)
		"ds4":
			s.append('<rect x="212" y="100" width="176" height="84" rx="14" fill="%s" stroke="%s" stroke-width="5"/>' % [body, line])
			if st.accent != "":
				s.append('<path d="M232 96 L368 96" stroke="%s" stroke-width="5"/>' % st.accent)
			s.append('<circle cx="300" cy="212" r="4" fill="%s" opacity="0.7"/>' % line)
		_:
			s.append('<path d="M200 128 C240 120 360 120 400 128" fill="none" stroke="%s" stroke-width="3" opacity="0.35"/>' % line)

	# croix directionnelle : 4 touches séparées
	var dp: Vector2 = L.dpad
	for rot in [0, 90, 180, 270]:
		s.append('<g transform="rotate(%d %.1f %.1f)"><path d="M%.1f %.1f h22 v18 l-11 11 l-11 -11 z" fill="%s" stroke="%s" stroke-width="4"/><path d="M%.1f %.1f l5 -6 l5 6" fill="none" stroke="%s" stroke-width="2.5"/></g>' % [
			rot, dp.x, dp.y, dp.x - 11, dp.y - 40, body, line, dp.x - 5, dp.y - 26, line])
	# boutons de façade (contour + symbole)
	var fc: Vector2 = L.face
	var r: float = L.face_r
	var faces := [[fc + Vector2(0, r), 0], [fc + Vector2(r, 0), 1], [fc + Vector2(-r, 0), 2], [fc + Vector2(0, -r), 3]]
	for f in faces:
		var c: Vector2 = f[0]
		s.append('<circle cx="%.1f" cy="%.1f" r="15" fill="%s" stroke="%s" stroke-width="4"/>' % [c.x, c.y, body, line])
		s.append(_symbol(family, f[1], c, line))
	# sticks
	for k in ["ls", "rs"]:
		var c: Vector2 = L[k]
		var ring := body if st.panel != "" else body
		var stroke := body if st.panel != "" else line
		s.append('<circle cx="%.1f" cy="%.1f" r="31" fill="%s" stroke="%s" stroke-width="5"/>' % [c.x, c.y, st.panel if st.panel != "" else body, stroke])
		s.append('<circle cx="%.1f" cy="%.1f" r="21" fill="%s" stroke="%s" stroke-width="4"/>' % [c.x, c.y, st.panel if st.panel != "" else ring, stroke])
	# select / start
	for k in ["select", "start"]:
		var c: Vector2 = L[k]
		var on_panel: bool = st.panel != "" and shape != "dualsense"
		s.append('<rect x="%.1f" y="%.1f" width="12" height="22" rx="6" fill="%s" stroke="%s" stroke-width="3.5" transform="rotate(%d %.1f %.1f)"/>' % [
			c.x - 6, c.y - 11, body, line, -18 if k == "select" else 18, c.x, c.y])
	# bouton central (générique : aucun logo de marque)
	var h: Vector2 = L.home
	var home_line := body if st.panel != "" else line
	if shape == "xbox" or shape == "switch":
		s.append('<circle cx="%.1f" cy="%.1f" r="17" fill="%s" stroke="%s" stroke-width="4"/>' % [h.x, h.y, body, line])
		s.append('<circle cx="%.1f" cy="%.1f" r="9" fill="none" stroke="%s" stroke-width="3"/>' % [h.x, h.y, st.accent if st.accent != "" else line])
	else:
		s.append('<circle cx="%.1f" cy="%.1f" r="12" fill="none" stroke="%s" stroke-width="3.5"/>' % [h.x, h.y, home_line])
	if family == "generic":
		# point d'interrogation discret : manette non reconnue
		s.append('<path d="M290 214 Q290 202 300 202 Q310 202 310 211 Q310 218 300 221 V226 M300 232 V233" fill="none" stroke="%s" stroke-width="4"/>' % line)
	s.append('</svg>')
	return "".join(s)


static func _symbol(family: String, idx: int, c: Vector2, line: String) -> String:
	var style := "ps" if family in ["ds4", "dualsense", "ds3"] else ("nin" if family == "switch" else ("plain" if family == "generic" else "xbox"))
	match style:
		"ps":
			var k := 6.0
			match idx:
				0: return '<path d="M%.1f %.1f l%.1f %.1f M%.1f %.1f l%.1f %.1f" stroke="%s" stroke-width="2.6"/>' % [c.x - k, c.y - k, 2 * k, 2 * k, c.x + k, c.y - k, -2 * k, 2 * k, line]
				1: return '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="2.6"/>' % [c.x, c.y, k, line]
				2: return '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="%s" stroke-width="2.6"/>' % [c.x - k + 0.5, c.y - k + 0.5, 2 * k - 1, 2 * k - 1, line]
				_: return '<path d="M%.1f %.1f l%.1f %.1f h%.1f z" fill="none" stroke="%s" stroke-width="2.6"/>' % [c.x, c.y - k - 1, k + 1, 2 * k, -2 * k - 2, line]
		"xbox", "nin":
			var labels := ["A", "B", "X", "Y"] if style == "xbox" else ["B", "A", "Y", "X"]
			return '<path transform="translate(%.1f %.1f)" d="%s" fill="none" stroke="%s" stroke-width="2.6"/>' % [c.x, c.y, LETTERS[labels[idx]], line]
	return '<circle cx="%.1f" cy="%.1f" r="3" fill="%s"/>' % [c.x, c.y, line]
