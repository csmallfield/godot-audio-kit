# SPDX-License-Identifier: Apache-2.0
# LAST FERRY: a music video for the Audio Kit's original ballad, made with the
# Motion Kit. Needs the motion kit linked (tools/link_motion_kit.sh).
#
# A harbour at night, seen from the water. The reed lead writes a glowing
# ribbon across the sky as it plays (the melody, scrolling right to left); the
# city's windows light up on the electric piano's chords; the water pulses on
# the kick; the lighthouse flashes on the snare (a small blink on the verse
# rim); a ferry crosses the bay over the whole song. The sky warms in the
# choruses, turns violet for the solo, flares at the key change, and the
# outro fades to black.
#
# Everything is a pure function of the frame. The music's notes come from the
# song resource itself (AKSong.events()), so picture and sound share one
# source; the AKCueBridge bakes the song and locks the clock to it.
#
# Beats (30 fps): follow the song's sections (AKSong.layout()): intro 0.2 s,
# verse1 12.2, chorus1 36.2, verse2 60.2, chorus2 84.2, solo 108.2,
# chorus3 132.2 (a semitone up), outro 156.2, end ~172 s.
@tool
extends MotionComposition

const SONG := "res://demo/song/last_ferry/last_ferry.tres"
const FONT_TITLE := "res://demo/song/last_ferry/fonts/big-shoulders-display-latin-800-normal.woff2"
const FONT_TEXT := "res://demo/song/last_ferry/fonts/inter-latin-400-normal.woff2"
const HORIZON := 720.0
const PLAYHEAD := 1240.0     # where the ribbon is being written
const PX_PER_S := 150.0
const TAIL_S := 4.0

# Sky moods per section: top, middle, horizon.
const MOODS := {
	"intro": [Color("#05060f"), Color("#151338"), Color("#3b2752")],
	"verse": [Color("#060819"), Color("#1a1a46"), Color("#4b2d63")],
	"chorus": [Color("#0b0717"), Color("#3a1748"), Color("#a3405e")],
	"solo": [Color("#06051a"), Color("#2b1158"), Color("#2f6b88")],
	"chorus3": [Color("#120716"), Color("#5a1a4a"), Color("#e2704f")],
	"outro": [Color("#030409"), Color("#0d0d24"), Color("#2a1f3c")],
}
const INK := Color("#07060d")
const WINDOW := Color("#ffd27a")
const RIBBON := Color("#7ff0ff")
const RIBBON_HOT := Color("#ff8fd0")

var _built := false
var _sections: Array = []     # {name, start, end}
var _lead: Array = []         # {t0, t1, midi}
var _ep: PackedFloat32Array
var _kick: PackedFloat32Array
var _snare: PackedFloat32Array
var _rim: PackedFloat32Array
var _end_s := 0.0

var _sky: MotionGradient
var _sky_canvas: MotionCanvas
var _city: MotionCanvas
var _water: MotionGradient
var _water_canvas: MotionCanvas
var _ribbon_fx: MotionFX
var _ribbon: MotionCanvas
var _title: MotionText
var _subtitle: MotionText
var _label: MotionText
var _black: ColorRect
var _buildings: Array = []
var _windows: Array = []      # {r: Rect2, seed}
var _lit: Array = []          # per piano chord: the window indices it lights
var _stars: Array = []


func _init() -> void:
	fps = 30
	_read_song()
	duration = ceili((_end_s + 1.0) * fps)
	fit_to_viewport = true
	for s in _sections:
		cue(float(s.start) * fps, StringName("section." + String(s.name)), 1.0)


func _read_song() -> void:
	var song: AKSong = load(SONG)
	for L in song.layout():
		_sections.append({name = String(L.name), start = float(L.start_s), end = float(L.end_s)})
	_end_s = song.length_s() + 3.0
	var ep := []
	var kick := []
	var snare := []
	var rim := []
	for e in song.events():
		var lane := String(e.lane)
		var t := float(e.time_s)
		if lane == "lead":
			_lead.append({t0 = t, t1 = t + float(e.gate_s), midi = int(e.midi)})
		elif lane == "ep0":
			ep.append(t)
		elif lane == "kick":
			kick.append(t)
		elif lane == "snare":
			snare.append(t)
		elif lane == "rim":
			rim.append(t)
	_ep = PackedFloat32Array(ep)
	_kick = PackedFloat32Array(kick)
	_snare = PackedFloat32Array(snare)
	_rim = PackedFloat32Array(rim)


func _ready() -> void:
	if not _built:
		_build()
	super._ready()


# ------------------------------------------------------------------ build

func _build() -> void:
	_built = true
	_seed_lights()
	_sky = MotionGradient.linear(size, 180.0, MOODS.intro, [0.0, 0.55, 1.0])
	_sky.size = Vector2(size.x, HORIZON)
	add_child(_sky)
	_sky_canvas = MotionCanvas.new()
	_sky_canvas.draw_fn = _draw_sky
	add_child(_sky_canvas)
	# The melody ribbon glows: drawn offscreen, a blurred copy blooms under it.
	_ribbon_fx = MotionFX.new()
	_ribbon_fx.size = size
	_ribbon_fx.glow = 9.0
	_ribbon_fx.glow_strength = 1.2
	_ribbon_fx.render_scale = 0.75   # a cheaper blur; the glow hides the softness
	add_child(_ribbon_fx)
	_ribbon = MotionCanvas.new()
	_ribbon.draw_fn = _draw_ribbon
	_ribbon_fx.content.add_child(_ribbon)
	_city = MotionCanvas.new()
	_city.draw_fn = _draw_city
	add_child(_city)
	_water = MotionGradient.linear(Vector2(size.x, size.y - HORIZON), 180.0, [Color("#0b0b22"), Color("#020208")], [0.0, 1.0])
	_water.position = Vector2(0, HORIZON)
	add_child(_water)
	_water_canvas = MotionCanvas.new()
	_water_canvas.draw_fn = _draw_water
	add_child(_water_canvas)
	_title = _text(FONT_TITLE, 168, Color("#ffe6c4"), "LAST FERRY", 0.08)
	_title.align = HORIZONTAL_ALIGNMENT_CENTER
	_title.box_width = size.x
	_title.position = Vector2(0, 300)
	_subtitle = _text(FONT_TEXT, 26, Color("#c9b8ff"), "an original ballad  ·  Godot Audio Kit × Motion Kit", 0.18)
	_subtitle.align = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.box_width = size.x
	_subtitle.position = Vector2(0, 500)
	_label = _text(FONT_TEXT, 22, Color("#e8e0ff"), "", 0.35)
	_label.position = Vector2(72, 1000)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.size = size
	add_child(_black)


func _text(font: String, px: int, col: Color, s: String, tracking: float) -> MotionText:
	var t := MotionText.new()
	t.font = MotionFonts.font(font)
	t.font_size = px
	t.color = col
	t.tracking = tracking
	t.text = s
	add_child(t)
	return t


func _seed_lights() -> void:
	_seed_scene()
	# Which windows each piano chord lights, decided once.
	for k in _ep.size():
		var on := PackedInt32Array()
		for wi in _windows.size():
			if MK.rand(float(k) * 13.7 + float(_windows[wi].seed) * 97.0) < 0.22:
				on.append(wi)
		_lit.append(on)


func _seed_scene() -> void:
	for i in 180:
		_stars.append({p = Vector2(MK.rand(i * 1.7 + 3.0) * size.x, MK.rand(i * 2.3 + 11.0) * (HORIZON - 120.0)),
			r = 0.6 + 1.6 * MK.rand(i * 5.1 + 2.0), rate = 0.5 + 2.0 * MK.rand(i * 0.7 + 9.0), ph = MK.rand(i * 3.9) * TAU})
	# The skyline: a few hundred pixels of city on the far shore, with windows.
	var x := 0.0
	var i := 0
	while x < size.x:
		var w := 40.0 + 90.0 * MK.rand(i * 4.4 + 1.0)
		var h := 30.0 + 150.0 * pow(MK.rand(i * 6.1 + 5.0), 1.6)
		if absf(x - 1600.0) < 140.0:
			h *= 0.4   # the headland under the lighthouse stays low
		var r := Rect2(x, HORIZON - h, w - 4.0, h)
		_buildings.append(r)
		var cols := int(w / 14.0)
		var rows := int(h / 18.0)
		for cy in rows:
			for cx in cols:
				var s := MK.rand(i * 31.0 + cy * 7.0 + cx * 3.0)
				if s < 0.55:
					_windows.append({r = Rect2(r.position.x + 5.0 + cx * 14.0, r.position.y + 7.0 + cy * 18.0, 6.0, 8.0), seed = s})
		x += w
		i += 1


# ------------------------------------------------------------------ frame

func _frame(f: float) -> void:
	if not _built:
		return
	var t := f / fps
	var mood := _mood(t)
	_sky.colors = PackedColorArray(mood)
	# Title card over the intro; a section label after that.
	var title_o := MK.win(f, 0.6 * fps, 9.5 * fps, 30)
	_title.modulate.a = title_o
	_title.scale = Vector2.ONE * (1.0 + 0.04 * MK.prog(f, 0.0, 10.0 * fps, MK.linear))
	_subtitle.modulate.a = MK.win(f, 2.0 * fps, 9.5 * fps, 30)
	var si := _section_at(t)
	var s: Dictionary = _sections[si] if si >= 0 else {}
	var pretty := {"intro": "", "verse1": "verse", "chorus1": "chorus", "verse2": "verse", "chorus2": "chorus",
		"solo": "solo", "chorus3": "chorus, a semitone up", "outro": "outro"}
	_label.text = String(pretty.get(s.get("name", ""), ""))
	_label.modulate.a = 0.0 if s.is_empty() else MK.win(f, float(s.start) * fps + 6, float(s.start) * fps + 4.0 * fps, 18) * 0.8
	# The fades: up from black, a flash at the key change, down to black at the end.
	var key_change := _section_start("chorus3")
	var flash := exp(-maxf(0.0, t - key_change) / 0.25) if t >= key_change else 0.0
	var up := 1.0 - MK.prog(f, 0.0, 2.0 * fps)
	var down := MK.prog(f, (_end_s - 6.0) * fps, 6.0 * fps, MK.linear)
	_black.color = Color(1, 1, 1) if flash > 0.02 and up < 0.01 and down < 0.01 else Color.BLACK
	_black.modulate.a = maxf(maxf(up, down), flash * 0.7)


func _mood(t: float) -> Array:
	# Each section's mood, crossfaded over two seconds into the next.
	var si := _section_at(t)
	if si < 0:
		return MOODS.outro if t > 1.0 else MOODS.intro
	var cur: Array = MOODS[_mood_name(_sections[si].name)]
	var into := t - float(_sections[si].start)
	if si > 0 and into < 2.0:
		var prev: Array = MOODS[_mood_name(_sections[si - 1].name)]
		var k := MK.ease_in_out.call(into / 2.0) as float
		return [prev[0].lerp(cur[0], k), prev[1].lerp(cur[1], k), prev[2].lerp(cur[2], k)]
	return cur


static func _mood_name(n: String) -> String:
	if n == "chorus3":
		return "chorus3"
	for k in ["intro", "verse", "chorus", "solo", "outro"]:
		if n.begins_with(k):
			return k
	return "verse"


func _section_at(t: float) -> int:
	for i in _sections.size():
		if t >= float(_sections[i].start) and t < float(_sections[i].end):
			return i
	return -1


func _section_start(n: String) -> float:
	for s in _sections:
		if s.name == n:
			return float(s.start)
	return INF


## How strongly a hit at any of `times` still rings at `t` (newest hit,
## exponential decay with time constant `tau`).
static func _ring(times: PackedFloat32Array, t: float, tau: float) -> float:
	var i := times.bsearch(t, false) - 1
	if i < 0:
		return 0.0
	return exp(-(t - times[i]) / tau)


# ------------------------------------------------------------------ drawing

func _draw_sky(c: MotionCanvas, f: float) -> void:
	var t := f / fps
	var night := 1.0 - 0.55 * _chorus_amount(t)
	for s in _stars:
		var tw := 0.55 + 0.45 * sin(t * float(s.rate) + float(s.ph))
		c.circle(s.p, float(s.r), Color(1, 0.95, 0.9), tw * night * 0.9)
	# The moon, drifting slowly across the sky over the song.
	var moon := Vector2(lerpf(300.0, 620.0, t / _end_s), lerpf(250.0, 190.0, t / _end_s))
	c.circle(moon, 120.0, Color("#fff1d6"), 0.05)
	c.circle(moon, 80.0, Color("#fff1d6"), 0.08)
	c.circle(moon, 46.0, Color("#fff4e0"), 1.0)
	c.circle(moon + Vector2(14, -8), 40.0, Color("#e9dcc2"), 0.35)


func _chorus_amount(t: float) -> float:
	var si := _section_at(t)
	if si < 0:
		return 0.0
	var n: String = _sections[si].name
	var on := 1.0 if (n.begins_with("chorus") or n == "solo") else 0.0
	var into := t - float(_sections[si].start)
	if si > 0 and into < 2.0:
		var pn: String = _sections[si - 1].name
		var prev := 1.0 if (pn.begins_with("chorus") or pn == "solo") else 0.0
		return lerpf(prev, on, into / 2.0)
	return on


func _draw_ribbon(c: MotionCanvas, f: float) -> void:
	var t := f / fps
	if _lead.is_empty():
		return
	var hot := RIBBON.lerp(RIBBON_HOT, _chorus_amount(t))
	# Sample the melody back in time from the playhead: x is time, y is pitch.
	var pts := PackedVector2Array()
	var step := 5.0
	var x := PLAYHEAD
	var widths := []
	while x > -20.0:
		var tau := t - (PLAYHEAD - x) / PX_PER_S
		var p := _pitch_at(tau)
		if is_nan(p):
			if pts.size() > 1:
				_stroke(c, pts, hot, widths)
			pts = PackedVector2Array()
			widths = []
		else:
			var y := _pitch_y(p) + 3.0 * sin(tau * TAU * 5.3) * _held(tau)
			pts.append(Vector2(x, y))
			# Older notes thin and fade.
			widths.append(clampf(1.0 - (PLAYHEAD - x) / (PX_PER_S * 9.0), 0.0, 1.0))
		x -= step
	if pts.size() > 1:
		_stroke(c, pts, hot, widths)
	# The pen: a bright dot at the playhead while a note sounds.
	var now := _pitch_at(t)
	if not is_nan(now):
		var y := _pitch_y(now) + 3.0 * sin(t * TAU * 5.3) * _held(t)
		c.circle(Vector2(PLAYHEAD, y), 9.0, Color.WHITE, 1.0)
		c.circle(Vector2(PLAYHEAD, y), 20.0, hot, 0.35)


func _stroke(c: MotionCanvas, pts: PackedVector2Array, col: Color, widths: Array) -> void:
	# Draw in short runs so width and opacity can fade along the trail.
	var run := 12
	var i := 0
	while i < pts.size() - 1:
		var j := mini(i + run, pts.size() - 1)
		var a: float = widths[i]
		if a > 0.01:
			c.polyline(pts.slice(i, j + 1), col, 2.0 + 5.0 * a, a)
		i = j


## Index of the last lead note starting at or before `tau`, or -1.
func _note_index(tau: float) -> int:
	var lo := 0
	var hi := _lead.size() - 1
	var k := -1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(_lead[mid].t0) <= tau:
			k = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return k


func _pitch_at(tau: float) -> float:
	# The sounding lead note at song time `tau` (with a quick scoop into it).
	var k := _note_index(tau)
	if k < 0:
		return NAN
	var n: Dictionary = _lead[k]
	if tau > float(n.t1):
		return NAN
	var into := tau - float(n.t0)
	# Drawn with a short glide from the previous note when they join (legato),
	# else the reed's scoop up from just below.
	if k > 0 and float(n.t0) - float(_lead[k - 1].t1) < 0.08:
		var g := MK.ease_in_out.call(clampf(into / 0.12, 0.0, 1.0)) as float
		return lerpf(float(_lead[k - 1].midi), float(n.midi), g)
	return float(n.midi) - 0.8 * exp(-into / 0.05)


func _held(tau: float) -> float:
	# Vibrato arrives after a note settles, as the reed voice's does.
	var i := _note_index(tau)
	if i < 0 or tau > float(_lead[i].t1):
		return 0.0
	return clampf((tau - float(_lead[i].t0) - 0.3) / 0.35, 0.0, 1.0)


func _pitch_y(midi: float) -> float:
	return HORIZON - 150.0 - (midi - 58.0) * 17.0


func _draw_city(c: MotionCanvas, f: float) -> void:
	var t := f / fps
	for r: Rect2 in _buildings:
		c.rect(r, INK, 1.0)
	# Windows answer the piano: each chord lights a seeded handful that dim.
	var glow := PackedFloat32Array()
	glow.resize(_windows.size())
	for wi in _windows.size():
		glow[wi] = 0.08 + 0.12 * float(_windows[wi].seed)
	var i := _ep.bsearch(t, false) - 1
	for k in range(maxi(0, i - 5), i + 1):
		var g := exp(-(t - _ep[k]) / 1.6)
		for wi in _lit[k]:
			glow[wi] = maxf(glow[wi], g)
	for wi in _windows.size():
		c.rect(_windows[wi].r, WINDOW, glow[wi])
	# The lighthouse on the headland: flashes on the snare, blinks on the rim.
	var base := Vector2(1600, HORIZON - 30)
	c.polygon(PackedVector2Array([base + Vector2(-14, 0), base + Vector2(14, 0), base + Vector2(8, -120), base + Vector2(-8, -120)]),
		Color("#d8d2e6"), Color(0, 0, 0, 0), 0.0, 1.0)
	var lamp := base + Vector2(0, -132)
	var flash := maxf(_ring(_snare, t, 0.35), 0.45 * _ring(_rim, t, 0.12))
	c.circle(lamp, 10.0, Color("#fff2b0"), 0.4 + 0.6 * flash)
	if flash > 0.02:
		# The beam sweeps a quarter turn per bar.
		var ang := PI + 0.9 * sin(t / 3.0 * TAU * 0.25)
		var d1 := Vector2.from_angle(ang - 0.06) * 1400.0
		var d2 := Vector2.from_angle(ang + 0.06) * 1400.0
		c.polygon(PackedVector2Array([lamp, lamp + d1, lamp + d2]), Color("#fff2b0"), Color(0, 0, 0, 0), 0.0, 0.18 * flash)
		c.circle(lamp, 60.0, Color("#fff2b0"), 0.25 * flash)


func _draw_water(c: MotionCanvas, f: float) -> void:
	var t := f / fps
	var pulse := _ring(_kick, t, 0.25)
	# The moon's path on the water: shimmering dashes.
	var moon_x := lerpf(300.0, 620.0, t / _end_s)
	for k in 26:
		var y := HORIZON + 10.0 + k * 13.0
		var w := 40.0 + k * 9.0
		var jx := 30.0 * sin(t * 1.3 + k * 0.9) * (0.3 + k / 26.0)
		var o := (0.25 + 0.2 * sin(t * 3.0 + k * 1.7)) * (1.0 - k / 30.0)
		c.line(Vector2(moon_x - w * 0.5 + jx, y), Vector2(moon_x + w * 0.5 + jx, y), Color("#fff1d6"), 2.0, o)
	# Ripples light up with the kick.
	for k in 18:
		var y := HORIZON + 6.0 + pow(k / 18.0, 1.6) * 340.0
		var x0 := fposmod(MK.rand(k * 2.7) * size.x - t * (12.0 + k * 3.0), size.x + 400.0) - 200.0
		c.line(Vector2(x0, y), Vector2(x0 + 120.0 + k * 10.0, y), Color("#8fa8ff"), 1.5, 0.06 + 0.22 * pulse)
	# The ferry crosses the bay over the song, its lights doubled in the water.
	var fx := lerpf(-260.0, size.x + 260.0, clampf(t / (_end_s - 4.0), 0.0, 1.0))
	var fy := HORIZON + 34.0 + 2.0 * sin(t * 1.1)
	var hull := PackedVector2Array([Vector2(fx - 120, fy), Vector2(fx + 130, fy), Vector2(fx + 105, fy + 22), Vector2(fx - 100, fy + 22)])
	c.polygon(hull, INK, Color(0, 0, 0, 0), 0.0, 1.0)
	c.rect(Rect2(fx - 70, fy - 26, 140, 26), INK, 1.0)
	c.rect(Rect2(fx - 30, fy - 44, 50, 18), INK, 1.0)
	for k in 9:
		var lx := fx - 60.0 + k * 15.0
		var lit := 0.6 + 0.4 * sin(t * 2.0 + k)
		c.rect(Rect2(lx, fy - 18, 6, 6), WINDOW, lit)
		c.line(Vector2(lx + 3, fy + 26), Vector2(lx + 3, fy + 60 + 10.0 * sin(t * 4.0 + k)), WINDOW, 2.0, 0.25 * lit)
	c.circle(Vector2(fx + 125, fy - 6), 4.0, Color("#ff6a5a"), 0.9)
