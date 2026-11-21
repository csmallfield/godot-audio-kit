# SPDX-License-Identifier: Apache-2.0
## Synth1 patch -> AKPatch, by direct parameter conversion through the curves measured
## from Synth1 itself (tools/synth1_ref/data, docs/plans/synth-expansion-phase0-synth1.md).
##
##   var Synth1 := preload("res://tools/patch_convert/synth1.gd")
##   var patch: AKPatch = Synth1.convert(sidecar.content.synth1.params)
##   var notes: Array = Synth1.caveats(sidecar.content.synth1.params)
##
## The patch: osc1 (with its 8-voice detune as a stack), osc2 (pitch, fine, fixed when
## untracked, sync, ring, FM into osc1), the sub as a third oscillator, unison, the filter
## and its envelope (env2), the amp envelope, both LFOs and the mod envelope (env3) as
## matrix rows, the arpeggiator, and the effect, EQ, delay and chorus as effects.
extends RefCounted

const VERSION := 1
const DATA := "res://tools/synth1_ref/data/"
## GAK's level against Synth1's (dB), set from the subset's median level error (+6.1 dB before it).
const CAL_DB := -5.6
## The key FM depth is matched at (Synth1's FM is a fixed deviation in Hz, GAK's a fixed index).
const FM_KEY := 60.0
const LN10 := 2.302585092994046
## Synth1's pulse is quieter than GAK's full-scale one: 2.5 dB under its saw (measured rms at
## width 64), where GAK's sits 4.8 dB over its saw: 0.43 by that, 0.30 by the subset's level errors.
const PULSE_LEVEL := 0.30
## Fitted from the subset's level errors: the 8-voice detune and the sub play louder in GAK,
## the chorus quieter.
const STACK_LEVEL := 0.69
const SUB_LEVEL := 0.75
const CHORUS_DB := 2.4

static var _t := {}


## The measured tables, loaded once.
static func tables() -> Dictionary:
	if _t.is_empty():
		for n in ["amp_env", "filter", "lfo", "osc", "fx_texts", "fx_eq", "sync"]:
			_t[n] = JSON.parse_string(FileAccess.get_file_as_string(DATA + n + ".json"))
	return _t


## Linear interpolation in a {"value": number} table (null entries skipped).
static func _lerp_table(table: Dictionary, v: float, field := "") -> float:
	var ks := []
	for k: String in table:
		var y: Variant = table[k] if field == "" else (table[k].get(field) if table[k] is Dictionary else null)
		if y != null:
			ks.append([float(k), float(y)])
	ks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if ks.is_empty():
		return 0.0
	if v <= ks[0][0]:
		return ks[0][1]
	for i in range(1, ks.size()):
		if v <= ks[i][0]:
			var a: Array = ks[i - 1]
			var b: Array = ks[i]
			return lerpf(a[1], b[1], (v - a[0]) / maxf(1e-9, b[0] - a[0]))
	return ks[ks.size() - 1][1]


static func _num(text: String) -> float:
	return float(text.strip_edges().split(" ")[0])


static func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 1e-9)) / LN10


# --- curves ----------------------------------------------------------------------------

static func attack_s(v: int) -> float:
	# A linear ramp: its time to 90 %, over 0.9.
	return maxf(0.0005, float(tables().amp_env.attack[str(clampi(v, 0, 127))].t90) / 0.9)


static func decay_tau(v: int) -> float:
	# Exponential: -20 dB is ln(10) time constants.
	return maxf(0.0003, float(tables().amp_env.decay[str(clampi(v, 0, 127))].db20) / LN10)


static func release_tau(v: int) -> float:
	return maxf(0.0003, float(tables().amp_env.release[str(clampi(v, 0, 127))].db20) / LN10)


static func sustain_level(v: int) -> float:
	if v <= 0:
		return 0.0
	return pow(10.0, float(tables().amp_env.sustain[str(clampi(v, 0, 127))]) / 20.0)


static func cutoff_hz(v: float) -> float:
	return clampf(715.0 * pow(2.0, (v - 64.0) * 0.0795), 20.0, 20000.0)


## The SVF q whose resonant peak is `peak_db` (a two-pole low-pass: G = q / sqrt(1 - 1/(4 q^2))).
static func q_for_peak(peak_db: float) -> float:
	var g := pow(10.0, peak_db / 20.0)
	if g <= 1.0:
		return 0.707
	var lo := 0.708
	var hi := 40.0
	for i in 40:
		var m := (lo + hi) * 0.5
		if m / sqrt(1.0 - 1.0 / (4.0 * m * m)) < g:
			lo = m
		else:
			hi = m
	return lo


static func osc2_semitones(v: int) -> float:
	return float(tables().osc.osc2_pitch_semitones[clampi(v, 0, 127)])


static func cents(v: int) -> float:
	return (v - 64) * 0.969


## Pulse duty (share of each cycle high) per pulse-width value.
static func duty(v: float) -> float:
	return _lerp_table(tables().osc.pulse_width, clampf(v, 0.0, 127.0))


## FM: Synth1's fixed deviation (Hz) for a knob value, as a GAK index for a modulator at mod_hz.
static func fm_index(knob: float, mod_hz: float) -> float:
	if knob <= 0.0:
		return 0.0
	var dev := 0.0
	var t: Dictionary = tables().osc.fm_dev_hz
	var ks := []
	for k: String in t:
		ks.append([float(k), float(t[k][0])])
	ks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	dev = ks[ks.size() - 1][1] if knob >= ks[ks.size() - 1][0] else 0.0
	for i in range(1, ks.size()):
		if knob <= ks[i][0]:
			dev = lerpf(ks[i - 1][1], ks[i][1], (knob - ks[i - 1][0]) / (ks[i][0] - ks[i - 1][0]))
			break
	return dev / maxf(mod_hz, 1.0)


static func lfo_rate_hz(v: int) -> float:
	return 3.325 * pow(2.0, (v - 64) / 12.0)


## A synced LFO's cycle in beats (at 120 bpm a beat is 0.5 s). Below 39 Synth1's cycles are
## longer than the measurement could read; they're taken as 4 bars.
static func lfo_sync_beats(v: int) -> float:
	var p: Variant = tables().sync.lfo_sync_period_s.get(str(clampi(v, 0, 127)))
	if p == null or float(p) < 0.01:
		return 16.0
	return snappedf(float(p) / 0.5, 0.0001)


static func arp_beats(v: int) -> float:
	var p: Variant = tables().sync.arp_step_s.get(str(clampi(v, 0, 19)))
	return 0.5 if p == null else snappedf(float(p) / 0.5, 0.0001)


## LFO depth to pitch: semitones of swing either way.
static func lfo_semitones(depth: int) -> float:
	return _lerp_table(tables().lfo.depth, float(depth), "pitch_cents_pp") / 200.0


## LFO depth to amp: the matrix amount a whose (1 + a) / (1 - a) is the measured swing.
static func lfo_amp(depth: int) -> float:
	var r := pow(10.0, _lerp_table(tables().lfo.depth, float(depth), "level_max_min_db") / 20.0)
	return (r - 1.0) / (r + 1.0)


const DELAY_NOTES := {1: "1/64t", 2: "1/32t", 3: "1/32", 4: "1/16t", 5: "1/16", 6: "1/8t", 7: "1/16.", 8: "1/8",
	9: "1/4t", 10: "1/8.", 11: "1/8..", 12: "1/4", 13: "1/2t", 14: "1/4.", 15: "1/4..", 16: "1/2", 17: "1/2.",
	18: "1/2..", 19: "1/1"}
const OSC1_SHAPES := ["sine", "saw", "pulse", "triangle"]
const OSC2_SHAPES := {1: "saw", 2: "pulse", 3: "triangle", 4: "noise"}
const SUB_SHAPES := ["sine", "triangle", "saw", "square"]
const LFO_SHAPES := ["saw", "triangle", "square", "random", "smooth", "sine"]
const ARP_MODES := ["updown", "updown", "up", "down", "random"]
const CHORUS_VOICES := [1, 1, 2, 2, 4]
## Chorus depth: the delay's swing as a share of its time.
const CHORUS_DEPTH := {0: 0.0, 32: 0.033, 48: 0.057, 64: 0.097, 80: 0.18, 96: 0.33, 112: 0.59, 127: 1.0}
const UNISON_CENTS := {0: 0.0, 8: 0.0, 16: 2.1, 32: 5.0, 64: 13.6, 96: 27.6, 127: 50.0}


static func _tbl(d: Dictionary, v: float) -> float:
	var s := {}
	for k: int in d:
		s[str(k)] = d[k]
	return _lerp_table(s, v)


## An integer parameter (0 when absent).
static func _i(p: Dictionary, k: String) -> int:
	return int(p.get(k, 0))


# --- conversion ------------------------------------------------------------------------

## A Synth1 patch's named parameters (the prep tool's content.synth1.params) as a patch.
static func convert(p: Dictionary) -> AKPatch:
	var out := AKPatch.new()
	var ks := float(_i(p, "key_shift"))
	var tune := cents(_i(p, "osc_tune"))
	var m := clampf(_i(p, "osc_mix") / 127.0, 0.0, 1.0)
	var sub_g := float(_i(p, "sub_gain"))
	var osc1_share := 32.0 / (sub_g + 32.0)
	var oscs: Array[Dictionary] = []

	# osc1
	var o1 := {shape = OSC1_SHAPES[clampi(_i(p, "osc1_shape"), 0, 3)], level = (1.0 - m) * osc1_share}
	if o1.shape == "pulse":
		o1.width = duty(_i(p, "pulse_width"))
		o1.level *= PULSE_LEVEL
	if ks != 0.0:
		o1.semitones = ks
	if tune != 0.0:
		o1.cents = tune
	if _i(p, "osc1_detune") > 0:
		o1.stack = 8
		o1.stack_cents = 1.1 * _i(p, "osc1_detune")
		o1.level *= STACK_LEVEL
	# osc2
	var o2 := {shape = OSC2_SHAPES.get(_i(p, "osc2_shape"), "saw"), level = m}
	var semi := osc2_semitones(_i(p, "osc2_pitch"))
	var fine := cents(_i(p, "osc2_fine")) + tune
	if o2.shape == "pulse":
		o2.width = duty(_i(p, "pulse_width"))
		o2.level *= PULSE_LEVEL
	var mod_hz := 0.0
	if _i(p, "osc2_track") == 0:
		o2.fixed_hz = 220.0 * pow(2.0, (semi + fine / 100.0) / 12.0)
		mod_hz = o2.fixed_hz
	else:
		if semi + ks != 0.0:
			o2.semitones = semi + ks
		if fine != 0.0:
			o2.cents = fine
		mod_hz = 440.0 * pow(2.0, (FM_KEY + ks + semi + fine / 100.0 - 69.0) / 12.0)
	if _i(p, "osc2_sync") != 0:
		o2.sync_to = 1
	if _i(p, "osc2_ring") != 0:
		o2.ring_from = 1
	var fm := fm_index(_i(p, "osc1_fm"), mod_hz)
	if fm > 0.0:
		o1.fm_from = 2
		o1.fm_index = fm
	oscs.append(o1)
	oscs.append(o2)
	# sub: a third oscillator under osc1 (its level taken from osc1's), with osc1's FM and stack
	if sub_g > 0.0:
		var o3 := {shape = SUB_SHAPES[clampi(_i(p, "sub_shape"), 0, 3)], level = (1.0 - m) * sub_g / (sub_g + 32.0) * SUB_LEVEL}
		var s3 := ks - (12.0 if _i(p, "sub_octave") != 0 else 0.0)
		if s3 != 0.0:
			o3.semitones = s3
		if tune != 0.0:
			o3.cents = tune
		if fm > 0.0:
			o3.fm_from = 2
			o3.fm_index = fm
		if o1.has("stack"):
			o3.stack = o1.stack
			o3.stack_cents = o1.stack_cents
			o3.level *= STACK_LEVEL
		oscs.append(o3)
	out.oscillators = oscs

	# unison
	var gain_db := float(_lerp_table(tables().osc.gain_db, _i(p, "a_gain"))) + CAL_DB
	if _i(p, "unison_on") != 0:
		var n := clampi(_i(p, "unison_voices"), 1, 8)
		out.unison = n
		out.detune_cents = _tbl(UNISON_CENTS, _i(p, "unison_detune"))
		out.spread = clampf(_i(p, "unison_spread") / 127.0, 0.0, 1.0)
		out.unison_pitch = clampf(_i(p, "unison_pitch") - 24.0, -24.0, 24.0)
		gain_db += 10.0 * log(float(n)) / LN10   # Synth1's voices add in power; GAK keeps it

	# filter
	var ft := _i(p, "filter_type")
	var fv := float(_i(p, "f_freq"))
	var track := 0.0
	if _i(p, "f_track") > 0:
		var c: Array = tables().filter.key_track.get(str(clampi(_i(p, "f_track") / 8 * 8, 0, 120)), [715.0, 715.0])
		track = log(float(c[1]) / float(c[0])) / log(2.0) / 2.0
	var cut := cutoff_hz(fv) * pow(2.0, track)   # Synth1 pivots at note 48, GAK's key source at 60
	var res: Dictionary = tables().filter.resonance
	var rv := float(_i(p, "f_res"))
	var peak12 := _lerp_res(res, rv, "0")
	var peak24 := _lerp_res(res, rv, "1")
	match ft:
		1:
			out.filter = {type = "lowpass", cutoff_hz = cut, q = maxf(0.5, q_for_peak(peak24 * 0.5)), slope_db = 24.0}
		2:
			out.filter = {type = "highpass", cutoff_hz = cut, q = q_for_peak(peak12), slope_db = 12.0}
		3:
			out.filter = {type = "bandpass", cutoff_hz = cut, q = q_for_peak(peak12), slope_db = 12.0}
		4, 5:
			out.filter = {type = "ladder", cutoff_hz = cut, resonance = clampf(rv / 127.0 * 0.95, 0.0, 1.0),
				drive = 1.0 + _i(p, "f_sat") / 32.0}
		_:
			out.filter = {type = "lowpass", cutoff_hz = cut, q = q_for_peak(peak12), slope_db = 12.0}
	var mods: Array[Dictionary] = []
	if track != 0.0:
		mods.append({source = "key", dest = "cutoff", amount = track})
	# filter envelope (env2): the amp envelope's curves, sustain linear
	out.env2 = {attack_s = attack_s(_i(p, "f_attack")), decay_s = decay_tau(_i(p, "f_decay")),
		sustain = clampf(_i(p, "f_sustain") / 127.0, 0.0, 1.0), release_s = release_tau(_i(p, "f_release")), curve = "exp"}
	var amt := (clampf(_i(p, "f_amount"), 0.0, 127.0) - 64.0) * 0.157
	if _i(p, "f_vel") != 0:
		amt *= 100.0 / 127.0   # the switch scales the amount by velocity; matched at the reference's 100
	if absf(amt) > 0.001:
		mods.append({source = "env2", dest = "cutoff", amount = amt})

	# amp envelope
	out.amp_env = {attack_s = attack_s(_i(p, "a_attack")), decay_s = decay_tau(_i(p, "a_decay")),
		sustain = sustain_level(_i(p, "a_sustain")), release_s = release_tau(_i(p, "a_release")), curve = "exp"}

	# LFOs
	for k in [1, 2]:
		var pre := "lfo%d_" % k
		if _i(p, pre + "on") == 0 or _i(p, pre + "depth") == 0:
			continue
		var l := {shape = LFO_SHAPES[clampi(_i(p, pre + "type"), 0, 5)], free = _i(p, pre + "keysync") == 0}
		if _i(p, pre + "sync") != 0:
			l.rate_sync = lfo_sync_beats(_i(p, pre + "speed"))
		else:
			l.rate_hz = lfo_rate_hz(_i(p, pre + "speed"))
		if k == 1:
			out.lfo1 = l
		else:
			out.lfo2 = l
		var d: int = _i(p, pre + "depth")
		var src := "lfo%d" % k
		match _i(p, pre + "dest"):
			0, 1:
				mods.append({source = src, dest = "osc2.pitch", amount = lfo_semitones(d)})
			2:
				mods.append({source = src, dest = "pitch", amount = lfo_semitones(d)})
			3:
				mods.append({source = src, dest = "cutoff", amount = lfo_semitones(d) / 12.0})
			4:
				mods.append({source = src, dest = "amp", amount = lfo_amp(d)})
			5:
				mods.append({source = src, dest = "osc1.width", amount = d / 127.0 * 0.5})
				mods.append({source = src, dest = "osc2.width", amount = d / 127.0 * 0.5})
			6:
				mods.append({source = src, dest = "osc1.fm", amount = fm_index(d, mod_hz)})
			7:
				mods.append({source = src, dest = "pan", amount = d / 127.0})

	# mod envelope (env3): attack, then a decay to nothing
	if _i(p, "modenv_on") != 0 and _i(p, "modenv_amount") != 64:
		out.env3 = {attack_s = attack_s(_i(p, "modenv_attack")), decay_s = decay_tau(_i(p, "modenv_decay")),
			sustain = 0.0, release_s = decay_tau(_i(p, "modenv_decay")), curve = "exp"}
		var mm := (_i(p, "modenv_amount") - 64) / 64.0
		match _i(p, "modenv_dest"):
			0:
				mods.append({source = "env3", dest = "osc2.pitch", amount = (_i(p, "modenv_amount") - 64) * 0.95})
			1:
				var k0 := float(_i(p, "osc1_fm"))
				var k1 := k0 + (127.0 - k0) * mm if mm > 0.0 else k0 * (1.0 + mm)
				mods.append({source = "env3", dest = "osc1.fm", amount = fm_index(k1, mod_hz) - fm_index(k0, mod_hz)})
			2:
				var d0 := duty(_i(p, "pulse_width"))
				var d1 := d0 * (1.0 - 0.96 * mm) if mm > 0.0 else d0 + (1.0 - d0) * 0.95 * -mm
				mods.append({source = "env3", dest = "osc1.width", amount = d1 - d0})
				mods.append({source = "env3", dest = "osc2.width", amount = d1 - d0})
	out.mods = mods

	# playing
	out.mode = ["poly", "mono", "legato"][clampi(_i(p, "play_mode"), 0, 2)]
	out.polyphony = clampi(int(p.get("polyphony", 16)), 1, 32)
	out.bend_range = float(_i(p, "bend_range"))
	if _i(p, "porta_time") > 0:
		out.glide_s = _porta(_i(p, "porta_time"))
	var sens: int = _i(p, "a_vel")
	if sens <= 0:
		out.velocity_sens = 0.0
	else:
		var drop64 := 63.0 / 126.0 * sens * 0.234
		var c := drop64 / (20.0 * log(127.0 / 64.0) / LN10)
		if c >= 0.25:
			out.velocity_sens = 1.0
			out.velocity_curve = minf(c, 4.0)
		else:
			out.velocity_sens = (1.0 - pow(10.0, -drop64 / 20.0)) / (1.0 - 64.0 / 127.0)
	out.pan = clampf((_i(p, "pan") - 64) / 64.0, -1.0, 1.0)
	out.tempo_bpm = 120.0

	# arpeggiator
	if _i(p, "arp_on") != 0:
		out.arp = {mode = ARP_MODES[clampi(_i(p, "arp_type"), 0, 4)], octaves = clampi(_i(p, "arp_oct") + 1, 1, 4),
			rate = arp_beats(_i(p, "arp_beat")), gate = clampf(_i(p, "arp_gate") / 127.0, 0.01, 1.0)}

	# effects: the effect, EQ, delay, chorus
	var fx: Array[Dictionary] = []
	if _i(p, "fx_on") != 0:
		var e := _effect(_i(p, "fx_type"), _i(p, "fx_ctl1"), _i(p, "fx_ctl2"), _i(p, "fx_mix") / 127.0)
		if not e.is_empty():
			fx.append(e)
	var eq := _eq(_i(p, "eq_tone"), _i(p, "eq_freq"), _i(p, "eq_level"), _i(p, "eq_q"))
	if not eq.is_empty():
		fx.append(eq)
	if _i(p, "delay_on") != 0:
		var mv := _i(p, "delay_mix") / 127.0
		var wet := minf(1.0, 2.0 * mv)
		var dry := minf(1.0, 2.0 - 2.0 * mv)
		var dl := {type = "delay", feedback = clampf(_i(p, "delay_fb") / 127.0, 0.0, 0.99),
			mix = minf(1.0, wet / maxf(dry, 1e-3)), mode = ["stereo", "cross", "pingpong"][clampi(_i(p, "delay_type"), 0, 2)]}
		var tv := _i(p, "delay_time")
		if tv == 0:
			dl.time_ms = 0.1
		else:
			dl.time_sync = DELAY_NOTES.get(mini(tv, 19), "1/1")
		var tone := _i(p, "delay_tone")
		dl.damp_hz = 200.0 * pow(100.0, tone / 64.0) if tone < 64 else 20000.0
		var sp: String = tables().fx_texts.delay_spread.get(str(clampi(_i(p, "delay_spread"), 0, 127)), "0.0 : 0.0 msec")
		var lr := sp.replace("msec", "").split(":")
		if lr.size() == 2:
			dl.spread_ms = clampf(float(lr[1]) - float(lr[0]), -100.0, 100.0)
		gain_db += _db(dry if dl.mix < 1.0 else wet)
		fx.append(dl)
	if _i(p, "chorus_on") != 0:
		var t: Dictionary = tables().fx_texts
		var dms := _num(t.ch_delay[str(clampi(_i(p, "ch_delay"), 0, 127))])
		var lv := clampf(_i(p, "ch_level") / 127.0, 0.0, 1.0)
		var ty := clampi(_i(p, "ch_type"), 0, 4)
		fx.append({type = "chorus", rate_hz = _num(t.ch_rate[str(clampi(_i(p, "ch_rate"), 0, 127))]),
			depth_ms = dms * _tbl(CHORUS_DEPTH, _i(p, "ch_depth")), delay_ms = dms, voices = CHORUS_VOICES[ty],
			mix = lv / (1.0 + lv), spread = 0.0 if CHORUS_VOICES[ty] == 1 else 2.0,
			feedback = clampf(_num(t.ch_fb[str(clampi(_i(p, "ch_fb"), 0, 127))]) / 100.0, -0.95, 0.95)})
		gain_db += _db(1.0 + lv) + CHORUS_DB
	out.effects = fx
	out.gain_db = gain_db
	out.resource_name = String(p.get("name", ""))
	return out


static func _lerp_res(res: Dictionary, v: float, typ: String) -> float:
	var s := {}
	for k: String in res:
		s[k] = float(res[k][typ][0])
	return _lerp_table(s, v)


## Portamento: an exponential glide; GAK's glide is a time constant (half the way in ln 2 of them).
static func _porta(v: int) -> float:
	var t: Dictionary = tables().osc.portamento
	var s := {}
	for k: String in t:
		if t[k][0] != null:
			s[k] = float(t[k][0])
	return _lerp_table(s, float(v)) / log(2.0)


static func _effect(ty: int, c1: int, c2: int, mix: float) -> Dictionary:
	var tone := clampf(470.0 * pow(2.0, c2 / 24.0), 200.0, 20000.0)
	match ty:
		0:
			return {type = "saturate", drive_db = 6.0 + c1 / 127.0 * 30.0, tone_hz = tone, asymmetry = 0.5, mix = mix}
		1:
			return {type = "saturate", drive_db = c1 / 127.0 * 30.0, tone_hz = tone, asymmetry = 0.0, mix = mix}
		2:
			return {type = "saturate", drive_db = 6.0 + c1 / 127.0 * 42.0, tone_hz = tone, asymmetry = 0.0, mix = mix}
		3:
			return {type = "crush", bits = 4.0 + c2 / 127.0 * 12.0, hold = 1 + roundi((127 - c1) / 127.0 * 31.0), mix = mix}
		4:
			return {type = "ring", freq_hz = clampf(92.6 * pow(2.0, (c1 - 64) / 9.5), 1.0, 5000.0), mix = mix}
		5:
			return {type = "compressor", threshold_db = -24.0 - c1 / 127.0 * 12.0, ratio = 10.0,
				attack_s = 0.001 + c2 / 127.0 * 0.05, release_s = 0.1, knee_db = 6.0, makeup_db = 6.0 + c1 / 127.0 * 6.0}
		6, 7, 8, 9:
			return {type = "phaser", rate_hz = 0.65 * pow(2.0, (c2 - 64) / 13.0), stages = [2, 4, 8, 12][ty - 6],
				depth = c1 / 127.0, feedback = 0.3, mix = 0.5 * mix, center_hz = 800.0, range_octaves = 2.0}
	return {}


static func _eq(tone: int, freq: int, level: int, q: int) -> Dictionary:
	var e := {type = "eq"}
	var any := false
	if level != 64:
		var bw := _lerp_table(_bw_table(), float(q))
		var r := pow(2.0, bw)
		e.mid_db = (level - 64) * 0.39
		e.mid_hz = 50.0 * pow(320.0, freq / 127.0)
		e.mid_q = sqrt(r) / (r - 1.0)
		any = true
	var fc := 200.0 * pow(2.0, tone / 32.0 * 3.46)
	var fh := 280.0 * pow(2.0, (tone - 96) / 24.0 * 3.56)
	if tone < 60 and fc * 1.5 < 16000.0:
		# A 6 dB/octave low-pass, approximated by a high shelf at its corner.
		e.high_hz = fc * 1.5
		e.high_db = -minf(24.0, 3.0 * log(20000.0 / fc) / log(2.0))
		any = true
	elif tone > 68 and fh / 1.5 > 20.0:
		e.low_hz = fh / 1.5
		e.low_db = -minf(24.0, 3.0 * log(fh / 20.0) / log(2.0))
		any = true
	return e if any else {}


static func _bw_table() -> Dictionary:
	var s := {}
	var t: Dictionary = tables().fx_eq.q
	for k: String in t:
		s[k] = float(t[k].bw_oct)
	return s


## What the conversion only approximates, for this patch.
static func caveats(p: Dictionary) -> Array:
	var out := []
	if _i(p, "osc1_fm") > 0 or (_i(p, "modenv_on") != 0 and _i(p, "modenv_dest") == 1 and _i(p, "modenv_amount") != 64):
		out.append("fm: Synth1's depth is fixed in Hz, GAK's index fixed; matched at middle C")
	for k in [1, 2]:
		var pre := "lfo%d_" % k
		if _i(p, pre + "on") != 0 and _i(p, pre + "depth") > 0:
			if _i(p, pre + "dest") in [3, 5, 6]:
				out.append("lfo%d to %s: depth curve not measured" % [k, ["", "", "", "cutoff", "", "pulse width", "fm"][_i(p, pre + "dest")]])
			if _i(p, pre + "sync") != 0 and _i(p, pre + "speed") < 39:
				out.append("lfo%d: synced slower than 2 bars, taken as 4" % k)
	if _i(p, "f_vel") != 0:
		out.append("filter velocity switch matched at velocity 100")
	if _i(p, "f_sat") > 0 and _i(p, "filter_type") < 4:
		out.append("filter saturation not converted")
	if _i(p, "fx_on") != 0:
		out.append("effect %d (%s) approximated" % [_i(p, "fx_type"), ["analog distortion 1", "analog distortion 2",
			"digital distortion", "decimator", "ring modulator", "compressor", "phaser", "phaser", "phaser", "phaser"][clampi(_i(p, "fx_type"), 0, 9)]])
	if absi(_i(p, "eq_tone") - 64) > 4:
		out.append("eq tone approximated by a shelf")
	if _i(p, "delay_on") != 0 and _i(p, "delay_mix") > 64:
		out.append("delay mix above half: dry level approximated")
	if _i(p, "delay_on") != 0 and _i(p, "delay_tone") > 72:
		out.append("delay tone high-pass not converted")
	if _i(p, "porta_auto") != 0 and _i(p, "porta_time") > 0:
		out.append("auto portamento not converted (glides always)")
	if _i(p, "osc2_shape") == 4 or _i(p, "unison_on") != 0 or _i(p, "lfo1_type") in [3, 4] or _i(p, "lfo2_type") in [3, 4]:
		out.append("random parts (noise, unison phases, random LFOs) differ from Synth1's")
	return out
