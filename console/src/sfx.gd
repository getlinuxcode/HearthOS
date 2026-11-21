extends Node
## Sons d'interface synthétisés au démarrage (aucun fichier audio) : cloches cristallines,
## nappes douces, échos. Conçus pour être propres :
##  - aucun bruit blanc (les « souffles » sont des nappes tonales),
##  - chaque note s'éteint en douceur (pas de coupure → pas de clic),
##  - normalisation du niveau (pas d'écrêtage),
##  - lecture polyphonique : un son n'en coupe jamais un autre.

const RATE := 48000
const N := {
	"C5": 523.25, "E5": 659.25, "G5": 783.99, "A5": 880.0, "B5": 987.77,
	"C6": 1046.5, "D6": 1174.66, "E6": 1318.5, "G6": 1567.98, "A6": 1760.0, "B6": 1975.5, "C7": 2093.0,
}

var enabled := true
var streams := {}
var _player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var _last_move := 0


func _ready() -> void:
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 24
	_player = AudioStreamPlayer.new()
	_player.stream = poly
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()

	# [fréquence, départ, durée, amplitude, cloche, glissando vers, attaque]
	_add("move", [_bells([[N.G6, 0.0, 0.12, 0.2, true]], 0.14, 0.18)], 0.32)
	_add("move_soft", [_bells([[N.G6, 0.0, 0.09, 0.1, true]], 0.1, 0.12)], 0.18)
	_add("confirm", [_bells([[N.E6, 0.0, 0.4, 0.26, true], [N.B6, 0.055, 0.5, 0.2, true]], 0.6)], 0.5)
	_add("back", [_bells([[N.D6, 0.0, 0.24, 0.2, false, N.A5, 0.01]], 0.26, 0.18)], 0.4)
	_add("open", [_bells([[N.C6, 0.0, 0.34, 0.18, true], [N.G6, 0.045, 0.44, 0.13, true]], 0.5)], 0.42)
	_add("tick", [_bells([[N.C7, 0.0, 0.06, 0.08, false, N.C7, 0.004]], 0.07, 0.08)], 0.22)
	_add("error", [_bells([[330.0, 0.0, 0.18, 0.25, false, 330.0, 0.01], [262.0, 0.11, 0.26, 0.25, false, 262.0, 0.01]], 0.4, 0.1)], 0.5)
	_add("success", [_bells([[N.C6, 0.0, 0.7, 0.18, true], [N.E6, 0.075, 0.62, 0.18, true], [N.G6, 0.15, 0.54, 0.18, true], [N.C7, 0.225, 0.6, 0.16, true]], 0.9)], 0.6)
	_add("transition", [_swell(0.5, 330.0, 660.0, 0.12), _bells([[N.G5, 0.08, 0.6, 0.1, true, N.G5, 0.02]], 0.7)], 0.4)
	_add("transition_back", [_swell(0.45, 660.0, 330.0, 0.1), _bells([[N.E5, 0.06, 0.5, 0.09, true, N.E5, 0.02]], 0.6)], 0.36)
	_add("boot", [_swell(2.6, 130.8, 261.6, 0.14), _bells([
		[N.C5, 0.0, 2.8, 0.13, false, N.C5, 0.9], [N.G5, 0.12, 2.7, 0.11, false, N.G5, 0.9],
		[N.E6, 0.24, 2.6, 0.07, false, N.E6, 0.9], [N.C7, 1.0, 1.8, 0.06, true]], 3.0, 0.35)], 0.55)
	_add("launch", [_swell(2.0, 196.0, 523.0, 0.16), _bells([
		[N.C5, 0.0, 2.0, 0.13, false, N.C6, 0.6], [N.G5, 0.1, 1.9, 0.1, false, N.G6, 0.6], [N.C7, 1.2, 1.2, 0.1, true]], 2.4, 0.3)], 0.6)
	_add("overlay", [_swell(0.4, 440.0, 880.0, 0.1), _bells([[N.A5, 0.0, 0.38, 0.14, true], [N.E6, 0.05, 0.46, 0.12, true]], 0.5)], 0.45)
	_add("pad", [_bells([[N.G5, 0.0, 0.5, 0.2, true], [N.D6, 0.08, 0.5, 0.18, true], [N.G6, 0.16, 0.8, 0.18, true], [N.B6, 0.24, 0.9, 0.12, true]], 1.1)], 0.6)
	# Contrôle qualité : `-- --dump-sfx=<dossier>` écrit chaque son en WAV.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump-sfx="):
			var dir := a.trim_prefix("--dump-sfx=")
			for k in streams:
				streams[k].save_to_wav("%s/%s.wav" % [dir, k])


func play(name: String, volume_db := 0.0) -> void:
	if not enabled or not streams.has(name) or _playback == null:
		return
	if name == "move":
		var now := Time.get_ticks_msec()
		if now - _last_move < 110:
			name = "move_soft"
		_last_move = now
	_playback.play_stream(streams[name], 0.0, volume_db)


## Mixe des couches, normalise au niveau voulu (crête) et termine par un fondu.
func _add(name: String, layers: Array, peak: float) -> void:
	var n := 0
	for l in layers:
		n = maxi(n, l.size())
	var buf := PackedFloat32Array()
	buf.resize(n)
	for l in layers:
		for i in l.size():
			buf[i] += l[i]
	var mx := 0.0001
	for i in n:
		mx = maxf(mx, absf(buf[i]))
	var gain := peak / mx
	var fade := int(0.03 * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := buf[i] * gain
		if i > n - fade:
			v *= float(n - i) / fade
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	streams[name] = s


## Cloches : partiels (1, 2.01, 3.98, 5.43) qui s'éteignent plus vite dans l'aigu, puis écho.
func _bells(voices: Array, total: float, echo := 0.3) -> PackedFloat32Array:
	var n := int((total + 0.6) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for v in voices:
		var f0: float = v[0]
		var start := int(float(v[1]) * RATE)
		var dur: float = v[2]
		var amp: float = v[3]
		var bell: bool = v[4]
		var f1: float = v[5] if v.size() > 5 else f0
		var attack: float = v[6] if v.size() > 6 else 0.006
		var partials := [[1.0, 1.0], [2.01, 0.3], [3.98, 0.1], [5.43, 0.04]] if bell else [[1.0, 1.0]]
		for p in partials:
			var ratio: float = p[0]
			var pamp: float = p[1]
			var pdur := dur / (ratio * 0.9) if ratio > 1.0 else dur
			var len := mini(int(pdur * RATE), n - start)
			var tail := maxi(1, int(minf(0.04, pdur * 0.3) * RATE))
			var phase := 0.0
			for i in len:
				var t := float(i) / RATE
				var env := t / attack if t < attack else exp(-4.5 * (t - attack) / pdur)
				# fondu final : la note atteint exactement zéro
				if i > len - tail:
					env *= float(len - i) / tail
				phase += TAU * lerpf(f0, f1, t / dur) * ratio / RATE
				buf[start + i] += sin(phase) * env * amp * pamp
	var out := buf.duplicate()
	for tap in [[0.11, echo], [0.17, echo * 0.7], [0.29, echo * 0.4], [0.43, echo * 0.2]]:
		var d := int(float(tap[0]) * RATE)
		var g: float = tap[1]
		for i in range(d, n):
			out[i] += buf[i - d] * g
	return out


## Nappe douce glissante (remplace l'ancien souffle de bruit blanc) : deux sinus à la quinte,
## légèrement désaccordés, enveloppe en cloche (cosinus surélevé).
func _swell(dur: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph1 := 0.0
	var ph2 := 0.0
	var ph3 := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t * t * (3.0 - 2.0 * t))
		ph1 += TAU * f / RATE
		ph2 += TAU * f * 1.5 * 1.003 / RATE
		ph3 += TAU * f * 2.0 * 0.997 / RATE
		var env := 0.5 - 0.5 * cos(TAU * t)
		out[i] = (sin(ph1) + 0.5 * sin(ph2) + 0.25 * sin(ph3)) * env * amp
	return out
