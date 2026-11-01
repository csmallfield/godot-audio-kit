# SPDX-License-Identifier: Apache-2.0
@tool
## The synth engine in GDScript: the reference for the native engine
## (native/src/synth.cpp) and the fallback that bakes patches when the
## native core isn't installed. Both follow the same steps in the same order,
## so they agree to float rounding (tests/test_synth.gd holds them to it).
##
##   var core := AKSynthCore.new(patch.compile())
##   core.note_on(0, 60.0, 0.8)
##   core.note_off(24000, 60.0)
##   var lr := core.render(48000)      # [PackedFloat32Array l, r]
##
## Events carry an absolute frame; render() applies each at its exact sample.
## Per voice and sample: envelopes, then LFOs, then the matrix, then pitch and
## oscillators (last to first, so an oscillator hears the ones after it this
## sample and the ones before it from the previous sample), filter, amp, pan,
## with the modulation worked out every CONTROL samples.
class_name AKSynthCore
extends RefCounted

## Bumped when the engine's output changes (part of every patch's bake key).
const VERSION := 3
const MAX_OSC := 4
const MAX_U := 7

enum { E_ON, E_OFF, E_BEND, E_MOD, E_TOUCH, E_ALL_OFF, E_PANIC, E_SUSTAIN }
enum { ATTACK, DECAY, SUSTAIN, RELEASE, IDLE }
enum { SRC_ENV1, SRC_ENV2, SRC_ENV3, SRC_LFO1, SRC_LFO2, SRC_VEL, SRC_KEY, SRC_MOD, SRC_TOUCH, SRC_RANDOM, SRC_BEND }
enum { D_PITCH, D_CUTOFF, D_Q, D_AMP, D_PAN, D_OPITCH, D_OLEVEL, D_OFM, D_OWIDTH, D_OPOS, D_LFO1R, D_LFO2R }
enum { SH_SINE, SH_TRI, SH_SAW, SH_SQUARE, SH_PULSE, SH_NOISE, SH_MORPH, SH_TABLE }
enum { F_OFF, F_LOW, F_HIGH, F_BAND, F_NOTCH, F_LADDER }
## Modulation (LFOs, the matrix, pitch, filter coefficients, levels) is
## worked out every CONTROL samples and held between; envelopes, oscillators
## and the filter run every sample.
const CONTROL := 8
## A stolen voice fades out with this time constant instead of cutting.
const STEAL_FADE_S := 0.003
## A legato note's new velocity reaches the level over this time constant
## (a jump in level is a click).
const VEL_GLIDE_S := 0.004
## The mod wheel and aftertouch, as a voice hears them, follow the controller
## over this time constant (a step in cutoff or FM depth is a crackle).
const CTL_GLIDE_S := 0.006
## Below this amp-envelope level a releasing voice is finished.
const SILENT := 1e-5

var sr := 48000
var frame := 0
var bend := 0.0
var mod_wheel := 0.0
var aftertouch := 0.0
## The sustain pedal: while down, released notes keep sounding.
var sustain := false
var voices: Array[_Voice] = []

var _p := {}
# Per-patch numbers derived once (sample counts, coefficients).
var _env_a := PackedInt64Array([0, 0, 0])
var _env_d := PackedInt64Array([1, 1, 1])
var _env_s := PackedFloat64Array([0.0, 0.0, 0.0])
var _env_kd := PackedFloat64Array([0.0, 0.0, 0.0])
var _env_kr := PackedFloat64Array([0.0, 0.0, 0.0])
var _env_exp := [false, false, false]
var _lfo_shape := PackedInt64Array([0, 0])
var _lfo_inc := PackedFloat64Array([0.0, 0.0])
var _lfo_delay := PackedFloat64Array([0.0, 0.0])
var _lfo_width := PackedFloat64Array([0.5, 0.5])
## Any oscillator around the filter.
var _bypass := false
var _ratio := PackedFloat64Array()
var _inv_su := 1.0
## Unison voices' stereo weights (equal power across `spread`).
var _uwl := PackedFloat64Array()
var _uwr := PackedFloat64Array()
## Unison voices' levels (unison_level for all but the middle one or two).
var _uw := PackedFloat64Array()
## Oscillators' stereo weights (equal power across their pan).
var _opl := PackedFloat64Array()
var _opr := PackedFloat64Array()
var _stereo := false
## Wavetables: per table {frames, size, levels, data}.
var _tables: Array = []
var _kg := 0.0
var _kill_k := 0.0
var _vel_k := 0.0
var _ctl_k := 0.0
var _events: Array = []   # [frame, seq, type, a, b], sorted
var _seq := 0
var _serial := 0
var _last_note := -1.0
var _held: Array = []      # mono/legato note stack: [note, velocity]
var _fx: AKStreamFx.Chain
var _fx_spec: Array = []
var _io := PackedFloat64Array([0.0, 0.0])


func _init(compiled := {}, sample_rate := 48000) -> void:
	sr = sample_rate
	if not compiled.is_empty():
		set_patch(compiled)


## Use a compiled patch (AKPatch.compile()). Playing voices carry on with it.
func set_patch(c: Dictionary) -> void:
	# Effects keep running when an edit leaves their settings alone.
	var fx_spec: Array = c.get("effects", [])
	if _fx == null or var_to_str(fx_spec) != var_to_str(_fx_spec):
		_fx = AKStreamFx.Chain.new(fx_spec, sr)
		_fx_spec = fx_spec.duplicate(true)
	_p = c
	for k in 3:
		var e: Dictionary = c.env[k]
		_env_a[k] = roundi(float(e.a) * sr)
		_env_d[k] = maxi(1, roundi(float(e.d) * sr))
		_env_s[k] = float(e.s)
		_env_kd[k] = exp(-1.0 / (float(e.d) * sr))
		_env_kr[k] = exp(-1.0 / (float(e.r) * sr))
		_env_exp[k] = bool(e.exp)
	for k in 2:
		var l: Dictionary = c.lfo[k]
		_lfo_shape[k] = int(l.shape)
		_lfo_inc[k] = float(l.rate_hz) / sr
		_lfo_delay[k] = float(l.delay_s) * sr
		_lfo_width[k] = float(l.get("width", 0.5))
	_bypass = false
	for o: Dictionary in c.osc:
		_bypass = _bypass or not bool(o.get("filtered", true))
	var u := int(c.unison)
	_ratio.resize(MAX_U)
	for i in MAX_U:
		var spread := 0.0 if u == 1 else (float(i) / (u - 1) - 0.5) * 2.0
		_ratio[i] = pow(2.0, spread * float(c.detune_cents) / 1200.0)
	_uw.resize(MAX_U)
	var side := float(c.get("unison_level", 1.0))
	var power := 0.0
	for i in MAX_U:
		var mid := absf(float(i) - (u - 1) * 0.5) <= 0.5
		_uw[i] = 1.0 if mid or i >= u else side
		if i < u:
			power += _uw[i] * _uw[i]
	_inv_su = 1.0 / sqrt(power)
	_uwl.resize(MAX_U)
	_uwr.resize(MAX_U)
	var spr := float(c.get("spread", 0.0))
	_stereo = spr > 0.0
	for i in MAX_U:
		var p := 0.0 if u == 1 else spr * (float(i) / (u - 1) * 2.0 - 1.0)
		var ang := (p + 1.0) * PI * 0.25
		_uwl[i] = cos(ang) * sqrt(2.0) * _uw[i]
		_uwr[i] = sin(ang) * sqrt(2.0) * _uw[i]
	var oscs: Array = c.osc
	_opl.resize(oscs.size())
	_opr.resize(oscs.size())
	for j in oscs.size():
		var op := float(oscs[j].get("pan", 0.0))
		_stereo = _stereo or op != 0.0
		var ang := (op + 1.0) * PI * 0.25
		_opl[j] = 1.0 if op == 0.0 else cos(ang) * sqrt(2.0)
		_opr[j] = 1.0 if op == 0.0 else sin(ang) * sqrt(2.0)
	_tables = c.get("tables", [])
	_kg = exp(-float(CONTROL) / (float(c.glide_s) * sr)) if float(c.glide_s) > 0.0 else 0.0
	_kill_k = exp(-1.0 / (STEAL_FADE_S * sr))
	_vel_k = 1.0 - exp(-1.0 / (VEL_GLIDE_S * sr))
	_ctl_k = 1.0 - exp(-float(CONTROL) / (CTL_GLIDE_S * sr))


func note_on(at: int, note: float, velocity := 1.0) -> void:
	_queue(at, E_ON, note, velocity)


func note_off(at: int, note: float) -> void:
	_queue(at, E_OFF, note, 0.0)


func set_bend(at: int, value: float) -> void:
	_queue(at, E_BEND, value, 0.0)


func set_mod_wheel(at: int, value: float) -> void:
	_queue(at, E_MOD, value, 0.0)


func set_aftertouch(at: int, value: float) -> void:
	_queue(at, E_TOUCH, value, 0.0)


## The sustain pedal down (true) or up.
func set_sustain(at: int, down: bool) -> void:
	_queue(at, E_SUSTAIN, 1.0 if down else 0.0, 0.0)


## Release every note (and lift the pedal).
func all_notes_off(at: int) -> void:
	_queue(at, E_ALL_OFF, 0.0, 0.0)


## Silence at once.
func panic(at: int) -> void:
	_queue(at, E_PANIC, 0.0, 0.0)


func voice_count() -> int:
	var n := 0
	for v in voices:
		if v.active:
			n += 1
	return n


## Render `n` frames: [l, r].
func render(n: int) -> Array:
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	for i in n:
		while not _events.is_empty() and int(_events[0][0]) <= frame:
			var e: Array = _events.pop_front()
			_apply(int(e[2]), float(e[3]), float(e[4]))
		var sl := 0.0
		var sr_ := 0.0
		for v in voices:
			if v.active:
				var y := v.tick(self)
				sl += y * v.gl
				sr_ += (v.yr if _stereo else y) * v.gr
		if _fx and not _fx.is_empty():
			_io[0] = sl
			_io[1] = sr_
			_fx.tick(_io)
			sl = _io[0]
			sr_ = _io[1]
		l[i] = sl
		r[i] = sr_
		frame += 1
	return [l, r]


# ------------------------------------------------------------------ events

func _queue(at: int, type: int, a: float, b: float) -> void:
	var e := [at, _seq, type, a, b]
	_seq += 1
	var i := _events.size()
	while i > 0 and int(_events[i - 1][0]) > at:
		i -= 1
	_events.insert(i, e)


func _apply(type: int, a: float, b: float) -> void:
	match type:
		E_ON: _on(a, b)
		E_OFF: _off(a)
		E_BEND: bend = clampf(a, -1.0, 1.0)
		E_MOD: mod_wheel = clampf(a, 0.0, 1.0)
		E_TOUCH: aftertouch = clampf(a, 0.0, 1.0)
		E_ALL_OFF:
			_held.clear()
			sustain = false
			for v in voices:
				if v.active and v.gated:
					v.release()
		E_SUSTAIN:
			sustain = a >= 0.5
			if not sustain:
				for v in voices:
					if v.active and v.pedal:
						v.release()
		E_PANIC:
			_held.clear()
			for v in voices:
				v.active = false


func _on(note: float, vel: float) -> void:
	var mode := int(_p.mode)
	if mode != 0:
		var v := _mono_voice()
		_held.append([note, vel])
		if v.active and v.gated:
			v.target = note
			v.vel = vel
			v.pedal = false
			if mode == 1:
				v.retrigger()
			_last_note = note
			return
		if v.active and not v.killing:
			# Still ringing out: take the voice from where it is (envelopes
			# rise from their level, phases and filters carry on). Starting
			# it afresh would cut the tail in one sample: a click.
			v.target = note
			v.vel = vel
			v.pedal = false
			v.retrigger()
			_last_note = note
			return
		var from := v.cur if v.active else _last_note
		v.start(self, note, vel, from)
		_last_note = note
		return
	for v in voices:
		if v.active and v.gated and v.note == note:
			v.release()
	# Past the polyphony, the oldest voice fades out over a few ms (a stolen
	# voice doesn't click) while the new note starts in a free slot.
	var live := 0
	for w in voices:
		if w.active and not w.killing:
			live += 1
	var victim: _Voice = null
	if live >= int(_p.poly):
		victim = _steal()
		victim.kill()
	var v: _Voice = null
	for w in voices:
		if not w.active:
			v = w
			break
	if v == null:
		if voices.size() < 2 * int(_p.poly):
			v = _Voice.new()
			voices.append(v)
		else:
			v = victim if victim else _steal()
	v.start(self, note, vel, _last_note)
	_last_note = note


func _off(note: float) -> void:
	var mode := int(_p.mode)
	if mode != 0:
		var top := -1.0 if _held.is_empty() else float(_held.back()[0])
		for i in range(_held.size() - 1, -1, -1):
			if float(_held[i][0]) == note:
				_held.remove_at(i)
		if voices.is_empty() or not voices[0].active:
			return
		var v := voices[0]
		if _held.is_empty():
			if sustain:
				v.pedal = true
			else:
				v.release()
		elif note == top:
			v.target = float(_held.back()[0])
			_last_note = v.target
		return
	for v in voices:
		if v.active and v.gated and v.note == note:
			if sustain:
				v.pedal = true
			else:
				v.release()


func _mono_voice() -> _Voice:
	if voices.is_empty():
		voices.append(_Voice.new())
	return voices[0]


## The voice to replace when all are busy: the oldest releasing one, else
## the oldest.
func _steal() -> _Voice:
	var best: _Voice = null
	for v in voices:
		if v.active and not v.killing and not v.gated and (best == null or v.serial < best.serial):
			best = v
	if best:
		return best
	for v in voices:
		if v.active and not v.killing and (best == null or v.serial < best.serial):
			best = v
	return best


func _next_serial() -> int:
	_serial += 1
	return _serial


## The key_levels gain at a key: [key, gain, ...] joined by straight lines in
## dB, flat past the ends.
static func key_level(kl: PackedFloat64Array, key: float) -> float:
	var n := kl.size() / 2
	if key <= kl[0] or n == 1:
		return kl[1]
	for i in range(1, n):
		if key < kl[2 * i]:
			var t := (key - kl[2 * i - 2]) / (kl[2 * i] - kl[2 * i - 2])
			return kl[2 * i - 1] * pow(kl[2 * i + 1] / kl[2 * i - 1], t)
	return kl[2 * n - 1]


static func _blep(t: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0


## A wavetable read: frames blended by `pos`, band-limit level `lv`, linear
## between samples; `zone` picks a key zone's frames.
static func _table(t: Dictionary, pos: float, lv: int, ph: float, zone: int = 0) -> float:
	var data: PackedFloat32Array = t.data
	var n: int = t.size
	var frames: int = t.frames
	var levels: int = t.levels
	var lv0: int = t.get("lv0", 0)
	lv = clampi(lv, lv0, lv0 + levels - 1) - lv0
	var fp := pos * (frames - 1)
	var f0 := mini(frames - 1, floori(fp))
	var ff := fp - f0
	var x := ph * n
	var i0 := int(x)
	var fr := x - i0
	var i1 := (i0 + 1) % n
	i0 = i0 % n
	f0 += zone * frames
	frames += zone * frames
	var b0 := (f0 * levels + lv) * n
	var v := data[b0 + i0] * (1.0 - fr) + data[b0 + i1] * fr
	if ff > 0.0 and f0 + 1 < frames:
		var b1 := ((f0 + 1) * levels + lv) * n
		var v1 := data[b1 + i0] * (1.0 - fr) + data[b1 + i1] * fr
		v = v * (1.0 - ff) + v1 * ff
	return v


static func _shape(shape: int, ph: float, dt: float, width: float) -> float:
	match shape:
		SH_SINE:
			return sin(TAU * ph)
		SH_TRI:
			return 1.0 - 4.0 * absf(ph - 0.5)
		SH_SAW:
			return 2.0 * ph - 1.0 - _blep(ph, dt)
		_:
			var v := 1.0 if ph < width else -1.0
			v += _blep(ph, dt)
			var p2 := ph - width
			p2 -= floorf(p2)
			return v - _blep(p2, dt)


## One voice of the engine.
class _Voice:
	var active := false
	var gated := false
	## Held only by the sustain pedal.
	var pedal := false
	## Stolen: fading out fast.
	var killing := false
	var serial := 0
	var note := 60.0
	var target := 60.0
	var cur := 60.0
	var vel := 1.0
	## The velocity as heard: follows vel over VEL_GLIDE_S.
	var gvel := 1.0
	## The mod wheel and aftertouch as heard: follow the core's over CTL_GLIDE_S.
	var gmod := 0.0
	var gtouch := 0.0
	var rnd := 0.0
	var rng := 1
	var gl := 1.0
	var gr := 1.0
	var stage := PackedInt64Array([4, 4, 4])
	var t := PackedInt64Array([0, 0, 0])
	var level := PackedFloat64Array([0.0, 0.0, 0.0])
	var start_level := PackedFloat64Array([0.0, 0.0, 0.0])
	var ev := PackedFloat64Array([1.0, 1.0, 1.0])
	var lfo_ph := PackedFloat64Array([0.0, 0.0])
	var lfo_sh := PackedFloat64Array([0.0, 0.0])
	## The matrix's push on each LFO's rate, in octaves (from the last control step).
	var lfo_oct := PackedFloat64Array([0.0, 0.0])
	var age := 0
	var phase := PackedFloat64Array()
	var raw := PackedFloat64Array()
	var last_semi := PackedFloat64Array()
	var freq := PackedFloat64Array()
	var ic1 := PackedFloat64Array([0.0, 0.0])
	var ic2 := PackedFloat64Array([0.0, 0.0])
	var last_c := -1.0
	var last_q := -1.0
	var fk := 1.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	var src := PackedFloat64Array()
	## Matrix sums per oscillator: pitch, level, fm, width, position.
	var mo := PackedFloat64Array()
	# Held between control steps.
	var o_level := PackedFloat64Array()
	var o_idx := PackedFloat64Array()
	var o_width := PackedFloat64Array()
	var o_pos := PackedFloat64Array()
	var amp_mod := 1.0
	var dt := PackedFloat64Array()
	## The right channel's sample when the patch spreads (tick returns the left).
	var yr := 0.0
	## Time since each oscillator (x unison) last wrapped, in samples, or -1.
	var wrap_t := PackedFloat64Array()
	## Wavetable reads: band-limit level per oscillator, and the key zone and
	## the blend toward the next one.
	var o_mip := PackedInt64Array()
	var o_zone := PackedInt64Array()
	var o_zw := PackedFloat64Array()
	# Right-channel SVF states and the ladder's four stages per channel.
	var ic1r := PackedFloat64Array([0.0, 0.0])
	var ic2r := PackedFloat64Array([0.0, 0.0])
	var lad := PackedFloat64Array()
	var lg := 0.0
	var lG := 0.0
	var lbeta := 0.0
	var lk := 0.0
	var _core_p: Dictionary

	func _init() -> void:
		dt.resize(MAX_OSC * MAX_U)
		wrap_t.resize(MAX_OSC * MAX_U)
		o_mip.resize(MAX_OSC)
		o_zone.resize(MAX_OSC)
		o_zw.resize(MAX_OSC)
		lad.resize(8)
		mo.resize(5 * MAX_OSC)
		o_level.resize(MAX_OSC)
		o_idx.resize(MAX_OSC)
		o_width.resize(MAX_OSC)
		o_pos.resize(MAX_OSC)
		phase.resize(MAX_OSC * MAX_U)
		raw.resize(MAX_OSC * MAX_U)
		last_semi.resize(MAX_OSC)
		freq.resize(MAX_OSC)
		src.resize(11)

	## 32-bit xorshift, the same sequence as the native engine.
	func white01() -> float:
		rng ^= (rng << 13) & 0xFFFFFFFF
		rng ^= rng >> 17
		rng ^= (rng << 5) & 0xFFFFFFFF
		return float(rng) / 4294967295.0

	func start(core: AKSynthCore, p_note: float, p_vel: float, from_note: float) -> void:
		var c: Dictionary = core._p
		active = true
		gated = true
		pedal = false
		killing = false
		serial = core._next_serial()
		note = p_note
		target = p_note
		cur = from_note if (core._kg > 0.0 and from_note >= 0.0) else p_note
		vel = p_vel
		gvel = p_vel
		gmod = core.mod_wheel
		gtouch = core.aftertouch
		rng = (int(c.seed) * 73856093 ^ serial * 19349663 ^ 83492791) & 0xFFFFFFFF
		if rng == 0:
			rng = 0x9E3779B9
		rnd = white01() * 2.0 - 1.0
		phase.fill(0.0)
		raw.fill(0.0)
		last_semi.fill(-1e9)
		var u := int(c.unison)
		if u > 1:
			for j in (c.osc as Array).size():
				for k in u:
					phase[j * MAX_U + k] = white01()
		for k in 2:
			lfo_ph[k] = 0.0
			lfo_oct[k] = 0.0
			lfo_sh[k] = white01() * 2.0 - 1.0 if core._lfo_shape[k] == 4 else 0.0
		age = 0
		for k in 3:
			stage[k] = ATTACK
			t[k] = 0
			level[k] = 0.0
			start_level[k] = 0.0
			ev[k] = 1.0
		ic1.fill(0.0)
		ic2.fill(0.0)
		ic1r.fill(0.0)
		ic2r.fill(0.0)
		lad.fill(0.0)
		wrap_t.fill(-1.0)
		last_c = -1.0
		last_q = -1.0

	func retrigger() -> void:
		for k in 3:
			stage[k] = ATTACK
			t[k] = 0
			start_level[k] = level[k]
			ev[k] = 1.0
		gated = true

	func release() -> void:
		gated = false
		pedal = false
		for k in 3:
			stage[k] = RELEASE

	func kill() -> void:
		release()
		killing = true

	func env_tick(core: AKSynthCore, k: int) -> float:
		if stage[k] == ATTACK:
			if t[k] < core._env_a[k]:
				level[k] = start_level[k] + (1.0 - start_level[k]) * float(t[k]) / core._env_a[k]
				t[k] += 1
				return level[k]
			stage[k] = DECAY
			t[k] = 0
			ev[k] = 1.0
		if stage[k] == DECAY:
			var s := core._env_s[k]
			if core._env_exp[k]:
				level[k] = s + (1.0 - s) * ev[k]
				ev[k] *= core._env_kd[k]
				return level[k]
			if t[k] < core._env_d[k]:
				level[k] = 1.0 - (1.0 - s) * float(t[k]) / core._env_d[k]
				t[k] += 1
				return level[k]
			stage[k] = SUSTAIN
		if stage[k] == SUSTAIN:
			level[k] = core._env_s[k]
		elif stage[k] == RELEASE:
			level[k] *= core._kill_k if killing else core._env_kr[k]
		return level[k]

	## An LFO's value now; its phase then moves on a whole control period.
	func lfo_tick(core: AKSynthCore, k: int) -> float:
		var ph := lfo_ph[k]
		var shape := core._lfo_shape[k]
		var v := 0.0
		match shape:
			0: v = sin(TAU * ph)
			1: v = 1.0 - 4.0 * absf(ph - 0.5)
			2: v = 2.0 * ph - 1.0
			3: v = 1.0 if ph < core._lfo_width[k] else -1.0
			_: v = lfo_sh[k]
		var d := core._lfo_delay[k]
		if d > 0.0 and age < d:
			v *= float(age) / d
		ph += core._lfo_inc[k] * CONTROL * (1.0 if lfo_oct[k] == 0.0 else pow(2.0, lfo_oct[k]))
		if ph >= 1.0:
			ph -= floorf(ph)
			if shape == 4:
				lfo_sh[k] = white01() * 2.0 - 1.0
		lfo_ph[k] = ph
		return v

	## The control step (every CONTROL samples): LFOs, the matrix, glide,
	## pitches, oscillator settings, filter coefficients, amp and pan.
	func control(core: AKSynthCore, e0: float, e1: float, e2: float) -> void:
		var c: Dictionary = core._p
		src[SRC_ENV1] = e0
		src[SRC_ENV2] = e1
		src[SRC_ENV3] = e2
		src[SRC_LFO1] = lfo_tick(core, 0)
		src[SRC_LFO2] = lfo_tick(core, 1)
		src[SRC_VEL] = gvel
		src[SRC_KEY] = (target - 60.0) / 12.0
		gmod += (core.mod_wheel - gmod) * core._ctl_k
		gtouch += (core.aftertouch - gtouch) * core._ctl_k
		src[SRC_MOD] = gmod
		src[SRC_TOUCH] = gtouch
		src[SRC_RANDOM] = rnd
		src[SRC_BEND] = core.bend
		var m_pitch := 0.0
		var m_cut := 0.0
		var m_q := 0.0
		var m_amp := 0.0
		var m_pan := 0.0
		var oscs: Array = c.osc
		var no := oscs.size()
		mo.fill(0.0)
		lfo_oct[0] = 0.0
		lfo_oct[1] = 0.0
		for row: Dictionary in c.mods:
			var x := float(row.amount) * src[int(row.src)]
			match int(row.dst):
				D_PITCH: m_pitch += x
				D_CUTOFF: m_cut += x
				D_Q: m_q += x
				D_AMP: m_amp += x
				D_PAN: m_pan += x
				D_LFO1R: lfo_oct[0] += x
				D_LFO2R: lfo_oct[1] += x
				_:
					var slot := (int(row.dst) - D_OPITCH) * MAX_OSC
					var o := int(row.osc)
					if o < 0:
						for j in no:
							mo[slot + j] += x
					elif o < no:
						mo[slot + o] += x
		var semi := cur + core.bend * float(c.bend_range) + m_pitch
		cur = target + (cur - target) * core._kg
		for j in no:
			var o: Dictionary = oscs[j]
			var s := semi + float(o.semis) + mo[j]
			if s != last_semi[j]:
				last_semi[j] = s
				freq[j] = 440.0 * pow(2.0, (s - 69.0) / 12.0)
			o_level[j] = float(o.level) + mo[MAX_OSC + j]
			o_idx[j] = float(o.fm_index) + mo[2 * MAX_OSC + j]
			o_width[j] = clampf(float(o.width) + mo[3 * MAX_OSC + j], 0.01, 0.99)
			o_pos[j] = clampf(float(o.position) + mo[4 * MAX_OSC + j], 0.0, 1.0)
			for k in int(c.unison):
				dt[j * MAX_U + k] = freq[j] * core._ratio[k] / core.sr
			if int(o.table) >= 0:
				# The richest band-limit level whose top harmonic stays below
				# Nyquist for the highest unison voice.
				var top := 0.5 / (dt[j * MAX_U] * maxf(core._ratio[0], core._ratio[int(c.unison) - 1]))
				var lv := 0
				while lv + 1 < AKWavetables.LEVELS and AKWavetables.level_limit(lv + 1) <= top:
					lv += 1
				o_mip[j] = lv
				var tb: Dictionary = core._tables[int(o.table)]
				var keys: PackedFloat64Array = tb.get("keys", PackedFloat64Array())
				var z := 0
				var zw := 0.0
				if keys.size() > 1:
					while z + 1 < keys.size() and keys[z + 1] <= cur:
						z += 1
					if z + 1 < keys.size() and cur > keys[z]:
						zw = (cur - keys[z]) / (keys[z + 1] - keys[z])
					if not bool(tb.get("blend", true)):
						z += 1 if zw > 0.5 else 0
						zw = 0.0
				o_zone[j] = z
				o_zw[j] = zw
		if int(c.filter_type) == F_LADDER:
			var cut := float(c.cutoff_hz)
			if m_cut != 0.0:
				cut *= pow(2.0, m_cut)
			var res := float(c.resonance)
			if m_q != 0.0:
				res = clampf(res * pow(2.0, m_q), 0.0, 1.2)
			if cut != last_c or res != last_q:
				last_c = cut
				last_q = res
				lg = tan(PI * clampf(cut, 10.0, 0.49 * core.sr) / core.sr)
				lG = lg / (1.0 + lg)
				lbeta = 1.0 / (1.0 + lg)
				lk = 4.0 * res
		elif int(c.filter_type) > 0:
			var cut := float(c.cutoff_hz)
			if m_cut != 0.0:
				cut *= pow(2.0, m_cut)
			var q := float(c.q)
			if m_q != 0.0:
				q *= pow(2.0, m_q)
			if cut != last_c or q != last_q:
				last_c = cut
				last_q = q
				fk = 1.0 / maxf(0.05, q)
				var g := tan(PI * clampf(cut, 10.0, 0.49 * core.sr) / core.sr)
				a1 = 1.0 / (1.0 + g * (g + fk))
				a2 = g * a1
				a3 = g * a2
		amp_mod = maxf(0.0, 1.0 + m_amp)
		var kl: PackedFloat64Array = c.get("key_lv", PackedFloat64Array())
		if kl.size() >= 2:
			amp_mod *= AKSynthCore.key_level(kl, target)
		var pp := clampf(float(c.pan) + m_pan, -1.0, 1.0)
		if pp == 0.0:
			gl = 1.0
			gr = 1.0
		else:
			var ang := (pp + 1.0) * PI * 0.25
			gl = cos(ang) * sqrt(2.0)
			gr = sin(ang) * sqrt(2.0)

	## One sample, mono (pan goes to gl, gr).
	func tick(core: AKSynthCore) -> float:
		var c: Dictionary = core._p
		_core_p = c
		var e0 := env_tick(core, 0)
		var e1 := env_tick(core, 1)
		var e2 := env_tick(core, 2)
		if age % CONTROL == 0:
			control(core, e0, e1, e2)
		age += 1
		var oscs: Array = c.osc
		var no := oscs.size()
		var u := int(c.unison)
		var stereo := core._stereo
		var mix := 0.0
		var mix_r := 0.0
		var dry := 0.0
		var dry_r := 0.0
		for j in range(no - 1, -1, -1):
			var o: Dictionary = oscs[j]
			var shape := int(o.shape)
			var acc := 0.0
			var acc_r := 0.0
			if shape == SH_NOISE:
				acc = white01() * 2.0 - 1.0
				for k in u:
					raw[j * MAX_U + k] = acc
				acc_r = acc
			else:
				var fm_from := int(o.fm_from)
				var sync := int(o.sync)
				var ring := int(o.ring)
				var idx := o_idx[j]
				var width := o_width[j]
				var pos := o_pos[j]
				var tab: Dictionary = core._tables[int(o.table)] if int(o.table) >= 0 else {}
				for k in u:
					var d := dt[j * MAX_U + k]
					var ph := phase[j * MAX_U + k]
					if sync >= 0 and wrap_t[sync * MAX_U + k] >= 0.0:
						ph = wrap_t[sync * MAX_U + k] * d
						ph -= floorf(ph)
					var pm := idx * raw[fm_from * MAX_U + k] if fm_from >= 0 else 0.0
					var x := 0.0
					if shape == SH_SINE:
						x = sin(TAU * ph + pm)
					else:
						var q := ph
						if pm != 0.0:
							q = ph + pm / TAU
							q -= floorf(q)
						if shape == SH_MORPH:
							var p3 := pos * 3.0
							var a := mini(2, floori(p3))
							var w := p3 - a
							x = AKSynthCore._shape(a, q, d, 0.5)
							if w > 0.0:
								x = x * (1.0 - w) + AKSynthCore._shape(a + 1, q, d, 0.5) * w
						elif shape == SH_TABLE:
							x = AKSynthCore._table(tab, pos, o_mip[j], q, o_zone[j])
							if o_zw[j] > 0.0:
								x += (AKSynthCore._table(tab, pos, o_mip[j], q, o_zone[j] + 1) - x) * o_zw[j]
						else:
							x = AKSynthCore._shape(shape, q, d, width if shape == SH_PULSE else 0.5)
					if ring >= 0:
						x *= raw[ring * MAX_U + k]
					raw[j * MAX_U + k] = x
					ph += d
					if ph >= 1.0:
						ph -= floorf(ph)
						wrap_t[j * MAX_U + k] = ph / d
					else:
						wrap_t[j * MAX_U + k] = -1.0
					phase[j * MAX_U + k] = ph
					if stereo:
						acc += x * core._uwl[k]
						acc_r += x * core._uwr[k]
					else:
						acc += x * core._uw[k]
				acc *= core._inv_su
				acc_r *= core._inv_su
			if core._bypass and not bool(o.get("filtered", true)):
				dry += o_level[j] * acc * core._opl[j]
				dry_r += o_level[j] * acc_r * core._opr[j]
			else:
				mix += o_level[j] * acc * core._opl[j]
				mix_r += o_level[j] * acc_r * core._opr[j]
		var y := mix
		var ft := int(c.filter_type)
		if ft == F_LADDER:
			y = _ladder(y, 0)
			if stereo:
				mix_r = _ladder(mix_r, 4)
		elif ft > 0:
			for st in int(c.stages):
				var v3 := y - ic2[st]
				var v1 := a1 * ic1[st] + a2 * v3
				var v2 := ic2[st] + a2 * ic1[st] + a3 * v3
				ic1[st] = 2.0 * v1 - ic1[st]
				ic2[st] = 2.0 * v2 - ic2[st]
				match ft:
					1: y = v2
					2: y = y - fk * v1 - v2
					3: y = v1
					_: y = y - fk * v1
				if stereo:
					var r3 := mix_r - ic2r[st]
					var r1 := a1 * ic1r[st] + a2 * r3
					var r2 := ic2r[st] + a2 * ic1r[st] + a3 * r3
					ic1r[st] = 2.0 * r1 - ic1r[st]
					ic2r[st] = 2.0 * r2 - ic2r[st]
					match ft:
						1: mix_r = r2
						2: mix_r = mix_r - fk * r1 - r2
						3: mix_r = r1
						_: mix_r = mix_r - fk * r1
		if core._bypass:
			y += dry
			mix_r += dry_r if stereo else dry
		gvel += (vel - gvel) * core._vel_k
		var vc := float(c.get("vel_curve", 1.0))
		var gv := gvel if vc == 1.0 else pow(gvel, vc)
		var amp := e0 * (1.0 - float(c.vel_sens) * (1.0 - gv)) * amp_mod * float(c.gain)
		y *= amp
		yr = mix_r * amp
		if stage[0] == RELEASE and level[0] < SILENT:
			active = false
		return y

	## The four-pole ladder (zero-delay feedback, solved per sample), states
	## lad[s0 .. s0 + 3], with tanh saturation at its input.
	func _ladder(x: float, s0: int) -> float:
		var c: Dictionary = _core_p
		var G := lG
		var b := lbeta
		var S := G * G * G * b * lad[s0] + G * G * b * lad[s0 + 1] + G * b * lad[s0 + 2] + b * lad[s0 + 3]
		var drive := float(c.drive)
		var u := (x - lk * S) / (1.0 + lk * G * G * G * G)
		# Soft saturation, linear until |u| nears 2 / drive.
		u = tanh(u * drive * 0.5) * 2.0 / drive
		for i in 4:
			var v := (u - lad[s0 + i]) * G
			var yy := v + lad[s0 + i]
			lad[s0 + i] = yy + v
			u = yy
		# Make up some of the bass a resonant ladder loses.
		return u * (1.0 + 0.5 * lk)
