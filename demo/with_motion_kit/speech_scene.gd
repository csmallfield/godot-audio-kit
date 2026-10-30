# SPDX-License-Identifier: Apache-2.0
# THE HAIRCUT: two characters argue in pseudo-speech. Needs the motion kit
# linked (tools/link_motion_kit.sh).
#
# Dusk on a little hill. The King (tall, purple, a gold crown; the Scratch
# King voice) and a Critter (small, round, pink; the Critter voice) spring in
# from either side. The King demands to know where the Critter came from; the
# Critter says it always lived here; the King, outraged, insults its haircut
# (twice, the second one shouted); the Critter whispers that it's a very nice
# haircut; the King huffs. Each speaker's mouth opens on its syllables, its
# body squashes on accents and its head tilts with the pitch of its line;
# the listener leans back. A subtitle bar names the speaker and lights each
# word as it's heard. Both spring away and the frame ends on black.
#
# Everything is a pure function of the frame: the lines are compiled once
# (AKSpeechLine: text and voice in, timed syllables and curves out) and the
# picture reads their events and curves. The same lines are the cue map's
# `speech` recipes, so the AKCueBridge bakes exactly what the picture shows.
#
# Beats (30 fps): 0-24 both spring in (whoosh); lines from frame 30, each
# starting 16 frames after the last ends; outro 30 frames after the last
# line, 24 frames to black.
@tool
extends MotionComposition

const VOICES := "res://addons/audio_kit/speech/voices/"
const FONT_NAME := "res://demo/song/last_ferry/fonts/big-shoulders-display-latin-800-normal.woff2"
const FONT_TEXT := "res://demo/song/last_ferry/fonts/inter-latin-700-normal.woff2"
## [who, text with markup]: 0 = the King, 1 = the Critter.
const SCRIPT := [
	[0, "Hey! Where did you come from?"],
	[1, "I live here. I *always* lived here~."],
	[0, "Get out of here with that stupid **stupid** haircut!"],
	[1, "{whisper} It's a very nice haircut..."],
	[0, "_Hmph."],
]
const WHO := [
	{name = "THE KING", voice = "scratch_king.tres", body = Color("#5b3fa8"), dark = Color("#3b2873"), accent = Color("#ffc94a")},
	{name = "CRITTER", voice = "critter.tres", body = Color("#ff7fa6"), dark = Color("#d9577f"), accent = Color("#ffe3ec")},
]
const HOME := [Vector2(700, 790), Vector2(1230, 790)]
const FIRST_LINE := 30.0
const LINE_GAP := 16.0
const IN_AT := 0.0
const SKY_TOP := Color("#1d1640")
const SKY_LOW := Color("#f08a5d")
const HILL := Color("#2b2350")
const INK := Color("#0b0a14")
const SUB_BG := Color(0.04, 0.035, 0.08, 0.82)
const WORD_ON := Color("#ffd75e")

var lines: Array[AKSpeechLine] = []
var starts: Array[float] = []        # frame each line starts
var out_at := 0.0

var _built := false
var _stage: Node2D
var _chars: Array[Node2D] = []        # pivot at the feet
var _canvases: Array[MotionCanvas] = []
var _sky: MotionGradient
var _bar: Node2D
var _subs: Array[MotionText] = []
var _pills: Array[MotionPill] = []
var _fade: ColorRect


func _init() -> void:
	fps = 30
	for i in SCRIPT.size():
		var who: Dictionary = WHO[int(SCRIPT[i][0])]
		var l := AKSpeechLine.make(String(SCRIPT[i][1]), load(VOICES + String(who.voice))).compile()
		lines.append(l)
	var at := FIRST_LINE
	for l in lines:
		starts.append(at)
		at += ceilf(l.duration * fps) + LINE_GAP
	out_at = at + 18.0
	duration = out_at + 30.0
	markers = {"in": 0.0, "talk": FIRST_LINE, "out": out_at}
	cue(IN_AT, &"whoosh.in", 0.7)
	cue(IN_AT + 6.0, &"pop", 0.6)
	for i in lines.size():
		cue(starts[i], StringName("line.%d" % i), 1.0)
	cue(out_at, &"whoosh.out", 0.8)
	# The sound: the same lines as speech recipes, baked into one track.
	var map := AKCueMap.new()
	map.sounds = {"whoosh.in": load("res://demo/recipes/whoosh_in.tres"), "whoosh.out": load("res://demo/recipes/whoosh_out.tres"),
		"pop": load("res://demo/recipes/pop.tres")}
	for i in lines.size():
		map.sounds["line.%d" % i] = AKRecipe.make(&"speech", {text = lines[i].source_text, voice = lines[i].voice.resource_path})
	var bridge := AKCueBridge.new()
	bridge.name = "Sound"
	bridge.cue_map = map
	add_child(bridge)


func _ready() -> void:
	if not _built:
		_build()
	super._ready()


# ------------------------------------------------------------------ build

func _build() -> void:
	_built = true
	_sky = MotionGradient.linear(size, 180.0, [SKY_TOP, Color("#6b3f8a"), SKY_LOW], [0.0, 0.62, 1.0])
	add_child(_sky)
	_stage = Node2D.new()
	add_child(_stage)
	var hill := MotionCanvas.new()
	hill.draw_fn = func(c: MotionCanvas, _f: float) -> void:
		var pts := PackedVector2Array()
		for i in 65:
			var x := -40.0 + i * 31.25
			pts.append(Vector2(x, 790.0 - 40.0 * sin(x / 1920.0 * PI)))
		pts.append(Vector2(1960, 1120))
		pts.append(Vector2(-40, 1120))
		c.polygon(pts, HILL, HILL, 0.0)
	_stage.add_child(hill)
	for who in 2:
		var pivot := Node2D.new()
		pivot.position = HOME[who]
		pivot.scale = Vector2.ONE * (1.2 if who == 0 else 1.4)
		_stage.add_child(pivot)
		var cv := MotionCanvas.new()
		var w := who
		cv.draw_fn = func(c: MotionCanvas, f: float) -> void: _draw_character(c, f, w)
		pivot.add_child(cv)
		_chars.append(pivot)
		_canvases.append(cv)
	# The subtitle bar: a name pill and one text per line.
	_bar = Node2D.new()
	_bar.position = Vector2(960, 950)
	add_child(_bar)
	var bg := MotionShape.pill(1560, 140, SUB_BG)
	_bar.add_child(bg)
	var font_text := MotionFonts.font(FONT_TEXT)
	var font_name := MotionFonts.font(FONT_NAME)
	for who in 2:
		var p := MotionPill.new()
		p.text = String(WHO[who].name)
		p.font = font_name
		p.font_size = 36
		p.tracking = 0.08
		p.text_color = INK
		p.background = WHO[who].accent if who == 0 else WHO[who].body
		p.position = Vector2(-780 + 50 + p.get_box_size().x * 0.5, -70)
		_bar.add_child(p)
		_pills.append(p)
	for i in lines.size():
		var t := MotionText.new()
		t.font = font_text
		t.font_size = 56
		t.color = Color.WHITE
		t.text = lines[i].display_text
		t.position = Vector2(-t.get_text_size().x * 0.5, -t.get_text_size().y * 0.5 + 8)
		var li := i
		t.glyph_fn = func(ci: int, f: float) -> Variant: return _glyph(li, ci, f)
		_bar.add_child(t)
		_subs.append(t)
	_fade = ColorRect.new()
	_fade.color = INK
	_fade.size = size
	add_child(_fade)


# ------------------------------------------------------------------ frame

func _frame(f: float) -> void:
	if not _built:
		return
	var out := MK.map(f, [out_at, out_at + 24.0], [0.0, 1.0], MK.ease_in_quad)
	for who in 2:
		var s := MK.spring(f, IN_AT + who * 6.0, 11, 170)
		var side := -1.0 if who == 0 else 1.0
		var home: Vector2 = HOME[who]
		_chars[who].position = home + Vector2(side * (1.0 - s) * 900.0 + side * out * 1100.0, 0.0)
		_chars[who].visible = s > 0.001 and out < 0.999
		_canvases[who].queue_redraw()
	# Subtitles: the line being spoken (or just spoken) and its speaker's pill.
	var shown := _shown_line(f)
	var bar_in := MK.spring(f, FIRST_LINE - 8.0, 14, 200) * (1.0 - MK.map(f, [out_at - 6.0, out_at + 8.0], [0.0, 1.0]))
	_bar.scale = Vector2(lerpf(0.92, 1.0, bar_in), lerpf(0.6, 1.0, bar_in))
	_bar.modulate.a = clampf(bar_in, 0.0, 1.0)
	_bar.visible = bar_in > 0.01
	for i in _subs.size():
		var on := i == shown
		_subs[i].visible = on
		if on:
			var pop := MK.spring(f, starts[i] - 3.0, 14, 260)
			_subs[i].modulate.a = clampf(pop, 0.0, 1.0)
	for who in 2:
		var on := shown >= 0 and int(SCRIPT[shown][0]) == who
		_pills[who].visible = on
		if on:
			_pills[who].scale = Vector2.ONE * MK.spring(f, starts[shown] - 3.0, 10, 220)
	_stage.position = MK.shake(f, starts[2] + _first_shout_frame(2), 10.0, 8.0) if lines.size() > 2 else Vector2.ZERO
	_fade.modulate.a = MK.map(f, [out_at + 14.0, out_at + 28.0], [0.0, 1.0]) + (1.0 - MK.map(f, [0.0, 6.0], [0.0, 1.0]))
	_fade.visible = _fade.modulate.a > 0.001


## The line being spoken at frame f (-1 between lines).
func _line_at(f: float) -> int:
	for i in lines.size():
		if f >= starts[i] and f < starts[i] + lines[i].duration * fps:
			return i
	return -1


## The line whose subtitle shows: the current one, held until the next starts.
func _shown_line(f: float) -> int:
	var shown := -1
	for i in lines.size():
		if f >= starts[i] - 3.0:
			shown = i
	if f >= out_at:
		return -1
	return shown


## Seconds into line i at frame f.
func _t(i: int, f: float) -> float:
	return (f - starts[i]) / fps


## How open a speaker's mouth is: each syllable's note opens it (shaped by
## its intensity), shut in the gaps; 0 when that character isn't speaking.
func _mouth(who: int, f: float) -> float:
	var i := _line_at(f)
	if i < 0 or int(SCRIPT[i][0]) != who:
		return 0.0
	var l := lines[i]
	var t := _t(i, f)
	for e in l.events:
		var a := float(e.t_start)
		var b := a + (float(e.t_end) - a) * l.voice.gate
		if t >= a and t <= b:
			return sin(PI * clampf((t - a) / maxf(1e-3, b - a), 0.0, 1.0)) * clampf(l.curve_at("intensity", t) * 1.3, 0.2, 1.0)
	return 0.0


## A squash on each accented syllable, scaled by its stress.
func _accent(who: int, f: float) -> float:
	var i := _line_at(f)
	if i < 0 or int(SCRIPT[i][0]) != who:
		return 0.0
	var t := _t(i, f)
	var s := 0.0
	for e in lines[i].events:
		var st := float(e.stress)
		if st <= 0.0:
			continue
		var d := t - float(e.t_start)
		if d >= 0.0 and d < 0.25:
			s = maxf(s, st * sin(PI * d / 0.25))
	return s


## The head's tilt from the line's pitch (degrees; up = pitch up).
func _tilt(who: int, f: float) -> float:
	var i := _line_at(f)
	if i < 0 or int(SCRIPT[i][0]) != who:
		return 0.0
	var l := lines[i]
	return clampf(l.curve_at("pitch", _t(i, f)) / maxf(1.0, l.voice.range_semitones), -1.0, 1.5) * 7.0


func _first_shout_frame(i: int) -> float:
	for e in lines[i].events:
		if int(e.get("emphasis", 0)) == 2:
			return float(e.t_start) * fps
	return 0.0


func _glyph(li: int, ci: int, f: float) -> Variant:
	var l := lines[li]
	var t := _t(li, f)
	var word := -1
	for wi in l.words.size():
		var w: Dictionary = l.words[wi]
		if ci >= int(w.start) and ci < int(w.end):
			word = wi
			break
	var heard := l.word_at(t) if t >= 0.0 else -1
	if word < 0:
		# Punctuation and spaces follow the word before them.
		for wi in l.words.size():
			if int(l.words[wi].end) <= ci:
				word = wi
		return {o = 1.0 if word <= heard else 0.4}
	if t > l.duration + 0.1:
		return {}
	if word == heard:
		return {color = WORD_ON, s = 1.0 + 0.12 * maxf(0.0, 1.0 - MK.prog(f, starts[li] + float(_word_start(l, word)) * fps, 8.0)), ty = -4.0}
	return {o = 1.0 if word < heard else 0.4}


func _word_start(l: AKSpeechLine, word: int) -> float:
	for e in l.events:
		if int(e.word_index) == word:
			return float(e.t_start)
	return 0.0


# ------------------------------------------------------------------ drawing

func _ellipse(c: MotionCanvas, centre: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	c.polygon(pts, col, col, 0.0)


func _draw_character(c: MotionCanvas, f: float, who: int) -> void:
	var w: Dictionary = WHO[who]
	var mouth := _mouth(who, f)
	var acc := _accent(who, f)
	var listening := _line_at(f) >= 0 and int(SCRIPT[_line_at(f)][0]) != who
	var lean := (-1.0 if who == 1 else 1.0) * (6.0 if listening else 0.0)
	# The Critter flinches at the shouted word.
	var flinch := 0.0
	if who == 1:
		var at := starts[2] + _first_shout_frame(2)
		flinch = sin(PI * clampf((f - at) / 12.0, 0.0, 1.0)) * (1.0 - MK.prog(f, at, 30.0))
	var breathe := sin(f / fps * TAU * 0.4 + who) * 0.015
	var sq := 1.0 + breathe - 0.08 * acc
	var face := 1.0 if who == 0 else -1.0     # the King faces right, the Critter left
	var tilt := deg_to_rad(-_tilt(who, f) * face + lean * 0.4)
	var body: Color = w.body
	var dark: Color = w.dark
	var acc_c: Color = w.accent
	# Shadow.
	_ellipse(c, Vector2(0, 6), 130.0 if who == 0 else 90.0, 16.0, Color(0, 0, 0, 0.28))
	if who == 0:
		# The King: a tall robe, a big head, a crown.
		var h := 300.0 * sq
		var robe := PackedVector2Array([Vector2(-120, 0), Vector2(120, 0), Vector2(70, -h), Vector2(-70, -h)])
		c.polygon(robe, dark, dark, 0.0)
		c.rect(Rect2(-120, -40, 240, 14), acc_c)
		var head := Vector2(lean * 2.0, -h - 95.0)
		var tr := Transform2D(tilt, head)
		c.draw_set_transform_matrix(tr)
		_ellipse(c, Vector2.ZERO, 110.0, 100.0 * (1.0 + 0.04 * acc), body)
		# Crown.
		var crown := PackedVector2Array([Vector2(-70, -82), Vector2(-80, -150), Vector2(-40, -112), Vector2(0, -165),
			Vector2(40, -112), Vector2(80, -150), Vector2(70, -82)])
		c.polygon(crown, acc_c, acc_c, 0.0)
		c.circle(Vector2(0, -165), 9.0, Color("#ff6b6b"))
		_face(c, f, who, Vector2(25, -10), mouth, acc)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		# The Critter: a round body, ears, a fluffy tuft (the haircut).
		var r := 105.0
		sq *= 1.0 - 0.18 * flinch
		var centre := Vector2(lean * 2.0 + 30.0 * flinch, -r * sq - 70.0 * flinch)
		var tr := Transform2D(tilt, centre)
		c.draw_set_transform_matrix(tr)
		_ellipse(c, Vector2(-62, -78), 26.0, 48.0, dark)
		_ellipse(c, Vector2(62, -78), 26.0, 48.0, dark)
		_ellipse(c, Vector2.ZERO, r * (1.0 + 0.06 * acc), r * sq, body)
		for k in 5:
			var a := -PI * 0.5 + (k - 2) * 0.32
			_ellipse(c, Vector2(cos(a), sin(a)) * (r - 6.0) + Vector2(0, -6), 24.0, 30.0, acc_c)
		_face(c, f, who, Vector2(-18, 8), mouth, acc)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)


func _face(c: MotionCanvas, f: float, who: int, at: Vector2, mouth: float, acc: float) -> void:
	var face := 1.0 if who == 0 else -1.0
	var blink := 1.0 - MK.win(fmod(f + who * 47.0, 97.0), 0.0, 4.0, 2.0)
	var eye_y := at.y - 22.0
	var ex := 34.0 if who == 0 else 30.0
	for k in [-1.0, 1.0]:
		var e := Vector2(at.x + k * ex, eye_y)
		_ellipse(c, e, 15.0, 17.0 * maxf(0.12, blink), Color.WHITE)
		c.circle(e + Vector2(face * 5.0, 2.0), 7.0 * maxf(0.12, blink), INK)
	# Brows: angry for the King when accenting.
	if who == 0:
		var down := 8.0 + 14.0 * acc
		c.line(Vector2(at.x - 52, eye_y - 26), Vector2(at.x - 16, eye_y - 26 + down), INK, 7.0)
		c.line(Vector2(at.x + 52, eye_y - 26), Vector2(at.x + 16, eye_y - 26 + down), INK, 7.0)
	var mw := (38.0 if who == 0 else 26.0) * (1.0 + 0.25 * mouth)
	var mh := 4.0 + (46.0 if who == 0 else 34.0) * mouth
	_ellipse(c, Vector2(at.x, at.y + 34.0), mw, mh * 0.5 + 2.0, Color("#3a0f1c"))
	if mouth > 0.25:
		_ellipse(c, Vector2(at.x, at.y + 34.0 + mh * 0.22), mw * 0.55, mh * 0.18, Color("#e85a7a"))
