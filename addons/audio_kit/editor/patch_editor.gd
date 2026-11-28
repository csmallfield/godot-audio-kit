# SPDX-License-Identifier: Apache-2.0
## Panels for every part of an AKPatch, so an instrument can be built without
## editing the .tres: oscillators (shape, tuning, FM, sync, ring, tables),
## voice settings, the filter and filter 2, the envelopes (ADSR, stages, DX7 or CZ, with a
## picture of each, up to eight), two LFOs and up to six more (`lfos`), the macros,
## the modulation matrix and the effect chain. Oscillators show their operator fields
## (an FM list, ratio, their own envelopes, key scaling) when set, or on asking (Op).
##
## Every edit is an undoable action (in the editor, part of the editor's
## history, so Ctrl+Z works), and writes the patch at once, so a playing
## AKSynthStream hears it. Edits by path work from code too:
##
##   ed.set_param("filter.cutoff_hz", 800.0)
##   ed.set_param("oscillators.1.shape", "square")
##   ed.add_mod("env2", "cutoff", 3.0)
##   ed.add_effect("chorus")
@tool
class_name AKPatchEditor
extends ScrollContainer

## After any edit made here (the patch has already changed).
signal edited(path: String)

## Missing keys read as these (the same defaults AKPatch.compile uses).
const OSC_DEFAULTS := {shape = "sine", level = 1.0, semitones = 0.0, cents = 0.0, width = 0.5, position = 0.0, pan = 0.0, filtered = true,
	table = "basic", fm_from = 0, fm_index = 0.0, sync_to = 0, ring_from = 0,
	source = "sine", envelope = "hann", density = 20.0, grain_ms = 50.0, jitter = 0.0, spray = 0.0, pan_spread = 0.0, position_jitter = 0.0}
const FILTER_DEFAULTS := {type = "lowpass", cutoff_hz = 18000.0, q = 0.707, slope_db = 12.0, resonance = 0.3, drive = 1.0}
const ENV_DEFAULTS := {attack_s = 0.0, decay_s = 0.2, sustain = 0.0, release_s = 0.15, curve = "linear"}
const LFO_DEFAULTS := {shape = "sine", rate_hz = 1.0, delay_s = 0.0, width = 0.5}
const OP_DEFAULTS := {pd_wave = "saw", pd_wave2 = "", pd_window = "none", pd_amount = 0.0, pd_noise = false, level_env = 0,
	shape_env = 0, pitch_env = 0, ratio = 1.0, fixed_hz = 0.0, feedback = 0.0, velocity_sens = 0.0, filter = ""}
const DX7_ENV_DEFAULTS := {output_level = 99, rate_scaling = 0, velocity_sens = 0}
const CZ_ENV_DEFAULTS := {kind = "dca", sustain = -1}
## Keys that make an oscillator an operator (its panel shows them).
const OP_KEYS := ["fm", "feedback", "level_env", "shape_env", "pitch_env", "ratio", "fixed_hz", "dx7_freq", "velocity_sens", "key_scaling"]
const ENV_MODES := ["adsr", "stages", "dx7", "dx7_pitch", "cz"]
## A new envelope of each mode.
const ENV_TEMPLATES := {
	adsr = {attack_s = 0.01, decay_s = 0.3, sustain = 0.7, release_s = 0.3},
	stages = {stages = [{time_s = 0.01, level = 1.0}, {time_s = 0.3, level = 0.7}, {time_s = 0.3, level = 0.0}], sustain = 1},
	dx7 = {mode = "dx7", rates = [99, 50, 35, 40], levels = [99, 80, 60, 0], output_level = 99, rate_scaling = 0, velocity_sens = 0},
	dx7_pitch = {mode = "dx7_pitch", rates = [99, 99, 99, 99], levels = [50, 50, 50, 50]},
	cz = {mode = "cz", kind = "dca", steps = [[119, 127], [80, 110], [60, 0]], sustain = 1, end = 2},
}

## Slider ranges: key -> [min, max, options]. Shared by oscillators,
## envelopes, LFOs, the filter, voice settings and effects.
const RANGES := {
	level = [0.0, 1.5, {}], semitones = [-48.0, 48.0, {integer = true, unit = " st"}], cents = [-100.0, 100.0, {unit = " c"}],
	width = [0.01, 0.99, {}], position = [0.0, 1.0, {}], fm_index = [0.0, 20.0, {tip = "FM depth in radians"}],
	attack_s = [0.001, 10.0, {log = true, unit = " s"}], decay_s = [0.001, 10.0, {log = true, unit = " s"}],
	sustain = [0.0, 1.0, {}], release_s = [0.001, 10.0, {log = true, unit = " s"}],
	rate_hz = [0.01, 50.0, {log = true, unit = " Hz"}], delay_s = [0.0, 5.0, {unit = " s"}],
	cutoff_hz = [20.0, 20000.0, {log = true, unit = " Hz"}], q = [0.1, 20.0, {log = true}],
	resonance = [0.0, 1.2, {tip = "Near 1 the ladder rings at the cutoff; above, it oscillates"}],
	drive = [0.1, 10.0, {log = true}],
	unison = [1.0, 16.0, {integer = true}], detune_cents = [0.0, 100.0, {unit = " c"}], spread = [0.0, 1.0, {}],
	unison_level = [0.0, 1.0, {tip = "The stacked voices' level against the middle one"}],
	velocity_curve = [0.25, 4.0, {log = true, tip = "1 linear, 2 squared (velocity 64 is 12 dB down)"}],
	polyphony = [1.0, 32.0, {integer = true}], glide_s = [0.0, 2.0, {unit = " s"}], bend_range = [0.0, 24.0, {integer = true, unit = " st"}],
	velocity_sens = [0.0, 1.0, {}], gain_db = [-36.0, 12.0, {unit = " dB"}], pan = [-1.0, 1.0, {}],
	seed = [0.0, 9999.0, {integer = true}],
	# Phase 2-4 fields
	pd_amount = [0.0, 1.0, {tip = "0 a cosine .. 1 the full wave (the CZ's DCW)"}],
	density = [0.1, 1000.0, {log = true, unit = " /s", tip = "Grains a second"}], grain_ms = [1.0, 2000.0, {log = true, unit = " ms"}],
	spray = [0.0, 48.0, {unit = " st", tip = "Each grain's pitch, up to this far either way at random"}],
	pan_spread = [0.0, 1.0, {tip = "Each grain placed at random across this much of the field"}],
	position_jitter = [0.0, 1.0, {tip = "Where each grain reads, up to this far either way at random"}],
	op_ratio = [0.125, 32.0, {log = true, tip = "Multiplies the note's frequency"}],
	fixed_hz = [0.0, 8000.0, {unit = " Hz", tip = "0: follows the key"}],
	op_feedback = [0.0, 12.6, {tip = "Self-modulation in radians"}],
	break_key = [0.0, 127.0, {integer = true}], db_oct = [-24.0, 24.0, {unit = " dB"}],
	dx7_coarse = [0.0, 31.0, {integer = true}], dx7_fine = [0.0, 99.0, {integer = true}], dx7_detune = [0.0, 14.0, {integer = true}],
	time_s = [0.0005, 20.0, {log = true, unit = " s"}], stage_level = [0.0, 1.0, {}],
	dx7_99 = [0.0, 99.0, {integer = true}], dx7_7 = [0.0, 7.0, {integer = true}], cz_127 = [0.0, 127.0, {integer = true}],
	poles = [1.0, 4.0, {tip = "The ladder's slope: 1 to 4 poles, fractional between"}],
	comb_fb = [-0.99, 0.99, {}], filter_feedback = [-1.0, 1.0, {tip = "The filter block's output back into its input, through tanh"}],
	mix_low = [0.0, 1.0, {}], mix_band = [0.0, 1.0, {}], mix_high = [0.0, 1.0, {}], shelf_db = [-24.0, 24.0, {unit = " dB"}],
	# Effects
	depth_ms = [0.0, 20.0, {unit = " ms"}], delay_ms = [0.1, 50.0, {log = true, unit = " ms"}], voices = [1.0, 4.0, {integer = true}],
	mix = [0.0, 1.0, {}], feedback = [-0.95, 0.95, {}], stages = [1.0, 12.0, {integer = true}],
	center_hz = [50.0, 10000.0, {log = true, unit = " Hz"}], range_octaves = [0.0, 6.0, {}], depth = [0.0, 1.0, {}],
	low_db = [-18.0, 18.0, {unit = " dB"}], low_hz = [20.0, 1000.0, {log = true, unit = " Hz"}],
	mid_db = [-18.0, 18.0, {unit = " dB"}], mid_hz = [100.0, 10000.0, {log = true, unit = " Hz"}], mid_q = [0.1, 10.0, {log = true}],
	high_db = [-18.0, 18.0, {unit = " dB"}], high_hz = [1000.0, 18000.0, {log = true, unit = " Hz"}],
	threshold_db = [-60.0, 0.0, {unit = " dB"}], ratio = [1.0, 20.0, {log = true}],
	knee_db = [0.0, 24.0, {unit = " dB"}], makeup_db = [0.0, 24.0, {unit = " dB"}],
	drive_db = [0.0, 48.0, {unit = " dB"}], tone_hz = [500.0, 20000.0, {log = true, unit = " Hz"}],
	asymmetry = [-1.0, 1.0, {tip = "Even harmonics"}], output_db = [-24.0, 12.0, {unit = " dB"}],
}
## Effect attack and release need shorter ranges than envelopes.
const FX_RANGES := {attack_s = [0.0005, 0.5, {log = true, unit = " s"}], release_s = [0.005, 2.0, {log = true, unit = " s"}],
	ceiling_db = [-12.0, 0.0, {unit = " dB"}], predelay_ms = [0.0, 200.0, {unit = " ms"}],
	low_cut_hz = [0.0, 2000.0, {unit = " Hz", tip = "0: off"}], high_cut_hz = [0.0, 20000.0, {unit = " Hz", tip = "0: off"}],
	spread = [0.0, 2.0, {tip = "Left/right LFO offset, in quarter cycles"}],
	semitones = [-24.0, 24.0, {unit = " st"}], window_ms = [5.0, 200.0, {log = true, unit = " ms"}],
	freq_hz = [1.0, 16000.0, {log = true, unit = " Hz"}], jitter = [0.0, 1.0, {}], bits = [1.0, 16.0, {}],
	hold = [1.0, 32.0, {integer = true}], time_ms = [10.0, 2000.0, {log = true, unit = " ms"}],
	damp_hz = [200.0, 20000.0, {log = true, unit = " Hz"}], room = [0.0, 1.0, {}], damp = [0.0, 1.0, {}], width = [0.0, 1.0, {}],
	depth = [0.0, 2.0, {}], shift_hz = [-1000.0, 1000.0, {unit = " Hz"}], stereo = [0.0, 1.0, {tip = "1: the right channel shifts the other way"}],
	echo_ms = [0.0, 1000.0, {unit = " ms", tip = "The feedback's delay (0: a sample)"}],
	speed = [0.0, 1.0, {tip = "0 slow (chorale) .. 1 fast (tremolo)"}], horn_hz = [0.5, 15.0, {log = true, unit = " Hz"}],
	drum_hz = [0.5, 15.0, {log = true, unit = " Hz"}], accel_s = [0.01, 10.0, {log = true, unit = " s"}], drive = [0.0, 1.0, {}],
	crossover_hz = [100.0, 4000.0, {log = true, unit = " Hz"}], doppler = [0.0, 2.0, {}], tremolo = [0.0, 2.0, {}],
	resample_hz = [0.05, 100.0, {log = true, unit = " Hz", tip = "How often the stutter takes a new slice"}],
	softness = [0.0, 1.0, {tip = "0 hard edges .. 1 each repeat swells in and out"}],
	pitch = [-24.0, 24.0, {unit = " st", tip = "The repeats read faster (up) or slower (down)"}],
	bass_db = [-24.0, 24.0, {unit = " dB", tip = "A shelf at 200 Hz"}], treble_db = [-24.0, 24.0, {unit = " dB", tip = "A shelf at 4 kHz"}],
	balance = [-1.0, 1.0, {}], attack_ms = [0.1, 200.0, {log = true, unit = " ms"}], release_ms = [1.0, 3000.0, {log = true, unit = " ms"}],
	band1_db = [-12.0, 12.0, {unit = " dB"}], band2_db = [-12.0, 12.0, {unit = " dB"}], band3_db = [-12.0, 12.0, {unit = " dB"}], band4_db = [-12.0, 12.0, {unit = " dB"}], band5_db = [-12.0, 12.0, {unit = " dB"}], band6_db = [-12.0, 12.0, {unit = " dB"}], band7_db = [-12.0, 12.0, {unit = " dB"}], band8_db = [-12.0, 12.0, {unit = " dB"}], band9_db = [-12.0, 12.0, {unit = " dB"}], band10_db = [-12.0, 12.0, {unit = " dB"}], band11_db = [-12.0, 12.0, {unit = " dB"}],
	freq1_hz = [20.0, 20000.0, {log = true, unit = " Hz"}], freq2_hz = [20.0, 20000.0, {log = true, unit = " Hz"}],
	freq3_hz = [20.0, 20000.0, {log = true, unit = " Hz"}], q1 = [0.5, 100.0, {log = true}], q2 = [0.5, 100.0, {log = true}],
	q3 = [0.5, 100.0, {log = true}], gain1_db = [-48.0, 24.0, {unit = " dB"}], gain2_db = [-48.0, 24.0, {unit = " dB"}],
	gain3_db = [-48.0, 24.0, {unit = " dB"}], series = [0.0, 1.0, {integer = true, tip = "0 parallel, 1 series"}],
	curve = [0.0, 5.0, {integer = true, tip = "soft, hard, fold, sine, asym, digital"}], bias = [-1.0, 1.0, {}],
	pre_hp_hz = [0.0, 2000.0, {unit = " Hz", tip = "0: off"}], post_lp_hz = [0.0, 20000.0, {unit = " Hz", tip = "0: off"}],
	mid_db = [-48.0, 24.0, {unit = " dB"}], side_db = [-48.0, 24.0, {unit = " dB"}],
	side_hp_hz = [0.0, 2000.0, {unit = " Hz", tip = "0: off"}], mid_pan = [-1.0, 1.0, {}],
	slow_hz = [0.01, 10.0, {log = true, unit = " Hz"}], slow_depth = [0.0, 1.0, {}], fast_hz = [0.5, 20.0, {log = true, unit = " Hz"}],
	fast_depth = [0.0, 1.0, {}], center_ms = [2.0, 30.0, {log = true, unit = " ms"}],
	tune_hz = [20.0, 4000.0, {log = true, unit = " Hz"}], offset2 = [-24.0, 24.0, {unit = " st"}], offset3 = [-24.0, 24.0, {unit = " st"}],
	resonance = [-0.995, 0.995, {tip = "The combs' feedback; negative: odd harmonics, an octave down"}],
	noise = [0.0, 1.0, {tip = "Input swapped for noise that follows its envelope"}],
	hyst = [0.0, 1.0, {tip = "Hysteresis: rising and falling halves saturate differently"}], wow = [0.0, 1.0, {}], flutter = [0.0, 1.0, {}],
	bump_hz = [30.0, 250.0, {log = true, unit = " Hz"}], bump_db = [0.0, 12.0, {unit = " dB"}], hf_hz = [1000.0, 20000.0, {log = true, unit = " Hz"}],
	glide_ms = [0.0, 500.0, {unit = " ms"}], track_lp_hz = [100.0, 8000.0, {log = true, unit = " Hz"}],
	track_hp_hz = [10.0, 1000.0, {log = true, unit = " Hz"}],
	chirp = [0.0, 0.85, {tip = "How far the lows lag the highs in each echo (the drip)"}], length_ms = [10.0, 80.0, {log = true, unit = " ms"}],
	bass_hz = [40.0, 400.0, {log = true, unit = " Hz"}], boost_db = [0.0, 18.0, {unit = " dB"}], harmonics = [0.0, 1.0, {}],
	flip = [0.0, 1.0, {integer = true, tip = "0 crushes the positive side, 1 the negative"}],
	size_ms = [2.0, 250.0, {log = true, unit = " ms"}], regen = [0.0, 1.2, {tip = "Above 1 it keeps going on its own"}],
	wobble = [0.0, 1.0, {}], wobble_hz = [0.01, 10.0, {log = true, unit = " Hz"}]}
## How far a matrix row can push each destination (the amount slider's range).
const MOD_RANGES := {"pitch": 24.0, "cutoff": 8.0, "q": 4.0, "amp": 1.0, "pan": 1.0, "lfo1.rate": 6.0, "lfo2.rate": 6.0,
	"cutoff2": 8.0, "q2": 4.0, "env1.time": 4.0, "feedback": 1.0, "env1.attack": 4.0,
	"comb.feedback": 0.99, "comb.pitch": 24.0, "comb.damp": 4.0, "vowel": 1.0, "vowel2": 1.0, "osc.pitch": 24.0, "osc.level": 1.0, "osc.fm": 10.0, "osc.width": 0.5, "osc.position": 1.0}
const NICE := {fm_index = "FM depth", fm_from = "FM from", sync_to = "Sync to", ring_from = "Ring from", cutoff_hz = "Cutoff",
	q = "Q", attack_s = "Attack", decay_s = "Decay", release_s = "Release", rate_hz = "Rate", delay_s = "Delay",
	detune_cents = "Detune", glide_s = "Glide", bend_range = "Bend range", velocity_sens = "Velocity", gain_db = "Gain",
	unison_level = "Side voices", velocity_curve = "Vel. curve",
	slope_db = "Slope", depth_ms = "Depth", delay_ms = "Delay", range_octaves = "Range", center_hz = "Centre",
	low_db = "Low", low_hz = "Low freq", mid_db = "Mid", mid_hz = "Mid freq", mid_q = "Mid Q", high_db = "High",
	high_hz = "High freq", threshold_db = "Threshold", knee_db = "Knee", makeup_db = "Make-up", drive_db = "Drive",
	tone_hz = "Tone", output_db = "Output", window_ms = "Window", freq_hz = "Frequency", time_ms = "Time",
	damp_hz = "Damping"}

## The patch being edited.
var patch: AKPatch
## An UndoRedo or EditorUndoRedoManager (the Sound Lab passes the editor's);
## null makes edits immediate (not undoable). A local UndoRedo by default.
var undo: Object
## Panels flow into columns this wide.
var panel_width := 300.0

var _flow: HFlowContainer
var _quiet := false          # a slider edit in progress: don't rebuild under it
var _rebuild_queued := false
var _own_undo: UndoRedo      # the local history, until the editor's replaces it
var _show_ops := {}          # oscillator index -> operator fields shown though none are set


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_flow)
	_own_undo = UndoRedo.new()
	undo = _own_undo


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _own_undo:
		_own_undo.free()


## Edit `p` (or nothing with null).
func edit(p: AKPatch) -> void:
	if patch and patch.changed.is_connected(_on_patch_changed):
		patch.changed.disconnect(_on_patch_changed)
	patch = p
	if patch:
		patch.changed.connect(_on_patch_changed)
	rebuild()


# ------------------------------------------------------------------ reading

## The value at `path` ("filter.cutoff_hz", "oscillators.2.shape",
## "mods.0.amount", "unison"), with the defaults filled in.
func get_param(path: String) -> Variant:
	if patch == null:
		return null
	var parts := path.split(".")
	var v: Variant = patch.get(parts[0])
	for i in range(1, parts.size()):
		if v is Array:
			var idx := parts[i].to_int()
			if idx < 0 or idx >= v.size():
				return null
			v = v[idx]
		elif v is Dictionary:
			v = v.get(parts[i], _default_for(parts, i))
		else:
			return null
	return v


func _default_for(parts: PackedStringArray, i: int) -> Variant:
	var key := parts[i]
	match parts[0]:
		"oscillators":
			if i == 2:
				return OSC_DEFAULTS.get(key, OP_DEFAULTS.get(key))
			return {from = 1, index = 0.0, break_key = 60, left_db_oct = 0.0, right_db_oct = 0.0, left_curve = "lin",
				right_curve = "lin", mode = 0, coarse = 1, fine = 0, detune = 7}.get(key)
		"filter", "filter2":
			return FILTER_DEFAULTS.get(key, {poles = 4.0, low = 1.0, band = 0.0, high = 0.0, gain_db = 0.0}.get(key))
		"amp_env", "env2", "env3", "envelopes":
			var root: Variant = patch.get(parts[0])
			var e: Variant = root[parts[1].to_int()] if (root is Array and parts.size() > 2) else root
			if e is Dictionary:
				match env_mode(e):
					"dx7":
						return DX7_ENV_DEFAULTS.get(key)
					"cz":
						return CZ_ENV_DEFAULTS.get(key)
					"stages":
						return {curve = "linear", level = 0.0, time_s = 0.0, sustain = -1}.get(key)
			return ENV_DEFAULTS.get(key)
		"lfo1", "lfo2", "lfos":
			return LFO_DEFAULTS.get(key)
		"effects":
			var e: Dictionary = patch.effects[parts[1].to_int()]
			return AKStreamFx.DEFAULTS.get(String(e.get("type", "")), {}).get(key)
	return null


# ------------------------------------------------------------------ editing

## Set the value at `path` as one undoable edit.
func set_param(path: String, value: Variant) -> void:
	if patch == null:
		return
	var parts := path.split(".")
	var prop := parts[0]
	if parts.size() == 1:
		_commit(prop, value, path)
		return
	var root: Variant = _copy(patch.get(prop))
	var node: Variant = root
	for i in range(1, parts.size() - 1):
		node = node[parts[i].to_int()] if node is Array else node[parts[i]]
	var last := parts[parts.size() - 1]
	if node is Array:
		node[last.to_int()] = value
	else:
		node[StringName(last)] = value   # keys as the .tres files write them (&"cutoff_hz")
	_commit(prop, root, path)


## Add an oscillator (up to four): a copy of the last one, an octave down by
## default when there is one, else a saw.
func add_oscillator(o := {}) -> void:
	if patch == null or patch.oscillators.size() >= AKPatch.MAX_OSC:
		return
	var a: Array[Dictionary] = _copy(patch.oscillators)
	a.append(o if not o.is_empty() else {shape = "saw", level = 0.5})
	_commit("oscillators", a, "Add oscillator")


## Remove oscillator `i` (0-based). FM, sync and ring links to it are cleared
## and links to later oscillators renumbered; matrix rows aimed at it go.
func remove_oscillator(i: int) -> void:
	if patch == null or i < 0 or i >= patch.oscillators.size() or patch.oscillators.size() <= 1:
		return
	var a: Array[Dictionary] = _copy(patch.oscillators)
	a.remove_at(i)
	var gone := i + 1
	for o in a:
		for k in ["fm_from", "sync_to", "ring_from"]:
			var n := int(o.get(k, 0))
			if n == gone:
				o.erase(k)
				if k == "fm_from":
					o.erase("fm_index")
			elif n > gone:
				o[k] = n - 1
	var m: Array[Dictionary] = []
	for row in patch.mods:
		var d := String(row.get("dest", ""))
		var r: Dictionary = row.duplicate()
		if d.begins_with("osc") and d.find(".") > 3:
			var n := d.substr(3, d.find(".") - 3).to_int()
			if n == gone:
				continue
			if n > gone:
				r.dest = "osc%d%s" % [n - 1, d.substr(d.find("."))]
		m.append(r)
	_commit_many({oscillators = a, mods = m}, "Remove oscillator")


func add_mod(source := "lfo1", dest := "pitch", amount := 0.0) -> void:
	if patch == null or patch.mods.size() >= AKPatch.MAX_MODS:
		return
	var m: Array[Dictionary] = _copy(patch.mods)
	m.append({source = source, dest = dest, amount = amount})
	_commit("mods", m, "Add modulation")


## Add an LFO (lfo3 .. lfo8), a sine at 1 Hz unless `l` says otherwise.
func add_lfo(l := {}) -> void:
	if patch == null or patch.lfos.size() >= AKPatch.MAX_LFO - 2:
		return
	var a: Array[Dictionary] = _copy(patch.lfos)
	a.append(l if not l.is_empty() else {shape = "sine", rate_hz = 1.0})
	_commit("lfos", a, "Add LFO")


## Remove extra LFO `i` (0-based in `lfos`: lfo3 is 0). Matrix rows reading it or
## bending its rate go; rows on later LFOs are renumbered.
func remove_lfo(i: int) -> void:
	if patch == null or i < 0 or i >= patch.lfos.size():
		return
	var a: Array[Dictionary] = _copy(patch.lfos)
	a.remove_at(i)
	var gone := i + 3
	var renum := func(name: String) -> String:
		if not name.begins_with("lfo"):
			return name
		var dot := name.find(".")
		var n := (name.substr(3) if dot < 0 else name.substr(3, dot - 3)).to_int()
		if n == gone:
			return ""
		if n > gone:
			return "lfo%d%s" % [n - 1, "" if dot < 0 else name.substr(dot)]
		return name
	var m: Array[Dictionary] = []
	for row in patch.mods:
		var r: Dictionary = row.duplicate()
		var s: String = renum.call(String(row.get("source", "")))
		var d: String = renum.call(String(row.get("dest", "")))
		if s == "" or d == "":
			continue
		r.source = s
		r.dest = d
		m.append(r)
	_commit_many({lfos = a, mods = m}, "Remove LFO")


func remove_mod(i: int) -> void:
	if patch == null or i < 0 or i >= patch.mods.size():
		return
	var m: Array[Dictionary] = _copy(patch.mods)
	m.remove_at(i)
	_commit("mods", m, "Remove modulation")


## Append an effect of `type` (any of AKStreamFx.DEFAULTS) with its default settings.
func add_effect(type: String) -> void:
	if patch == null or not AKStreamFx.DEFAULTS.has(type):
		return
	var e: Array[Dictionary] = _copy(patch.effects)
	var spec := {type = type}
	spec.merge(AKStreamFx.DEFAULTS[type])
	e.append(spec)
	_commit("effects", e, "Add %s" % type)


func remove_effect(i: int) -> void:
	if patch == null or i < 0 or i >= patch.effects.size():
		return
	var e: Array[Dictionary] = _copy(patch.effects)
	e.remove_at(i)
	_commit("effects", e, "Remove effect")


## Move effect `i` earlier (-1) or later (+1) in the chain.
func move_effect(i: int, by: int) -> void:
	var j := i + by
	if patch == null or i < 0 or j < 0 or i >= patch.effects.size() or j >= patch.effects.size():
		return
	var e: Array[Dictionary] = _copy(patch.effects)
	var t := e[i]
	e[i] = e[j]
	e[j] = t
	_commit("effects", e, "Move effect")


func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if (v is Array or v is Dictionary) else v


func _commit(prop: String, value: Variant, label: String) -> void:
	_commit_many({prop: value}, label)


func _commit_many(props: Dictionary, label: String) -> void:
	var action := "Patch: " + label
	if undo == null:
		for k in props:
			patch.set(k, props[k])
		patch.emit_changed()
	elif undo is UndoRedo:
		undo.create_action(action, UndoRedo.MERGE_ENDS)
		for k in props:
			undo.add_do_property(patch, k, props[k])
			undo.add_undo_property(patch, k, _copy(patch.get(k)))
		undo.add_do_method(patch.emit_changed)
		undo.add_undo_method(patch.emit_changed)
		undo.commit_action()
	else:
		undo.call(&"create_action", action, UndoRedo.MERGE_ENDS, patch)
		for k in props:
			undo.call(&"add_do_property", patch, k, props[k])
			undo.call(&"add_undo_property", patch, k, _copy(patch.get(k)))
		undo.call(&"add_do_method", patch, &"emit_changed")
		undo.call(&"add_undo_method", patch, &"emit_changed")
		undo.call(&"commit_action")
	edited.emit(label)


## Undo / redo the last patch edit (the local history outside the editor).
func undo_last() -> void:
	if undo is UndoRedo:
		undo.undo()


func redo_last() -> void:
	if undo is UndoRedo:
		undo.redo()


# ------------------------------------------------------------------ building

func _on_patch_changed() -> void:
	if _quiet or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Rebuild every panel from the patch.
func rebuild() -> void:
	_rebuild_queued = false
	for c in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	if patch == null:
		var l := Label.new()
		l.text = "Pick a patch, or New for a blank one."
		_flow.add_child(l)
		return
	for i in patch.oscillators.size():
		_osc_panel(i)
	if patch.oscillators.size() < AKPatch.MAX_OSC:
		var b := Button.new()
		b.text = "+ Oscillator"
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(func() -> void: add_oscillator())
		_flow.add_child(b)
	_voice_panel()
	_filter_panel()
	_filter2_panel()
	_env_panel("amp_env", "Amp envelope (env1)")
	_env_panel("env2", "Envelope 2")
	_env_panel("env3", "Envelope 3")
	for i in patch.envelopes.size():
		_env_panel("envelopes.%d" % i, "Envelope %d" % (i + 4), i)
	if env_count() < AKPatch.MAX_ENV:
		var eb := Button.new()
		eb.text = "+ Envelope"
		eb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		eb.pressed.connect(func() -> void: add_envelope())
		_flow.add_child(eb)
	_lfo_panel("lfo1", "LFO 1")
	_lfo_panel("lfo2", "LFO 2")
	for i in patch.lfos.size():
		var box := _lfo_panel("lfos.%d" % i, "LFO %d" % (i + 3))
		_head_button(box, "x", "Remove this LFO (and matrix rows using it)", func() -> void: remove_lfo(i))
	if patch.lfos.size() < AKPatch.MAX_LFO - 2:
		var lb := Button.new()
		lb.text = "+ LFO"
		lb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		lb.pressed.connect(func() -> void: add_lfo())
		_flow.add_child(lb)
	_macros_panel()
	_matrix_panel()
	_effects_panel()


func _panel(title: String, wide := false) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size.x = panel_width * (2.0 if wide else 1.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.9)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	pc.add_theme_stylebox_override(&"panel", sb)
	_flow.add_child(pc)
	var box := VBoxContainer.new()
	pc.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var l := Label.new()
	l.text = title
	l.modulate = Color(1.0, 0.81, 0.23)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	box.set_meta(&"head", head)
	return box


## A slider bound to `path`; `key` picks the range.
func _slider(box: Control, path: String, key: String, ranges := RANGES, label := "") -> AKParamSlider:
	var r: Array = ranges.get(key, RANGES.get(key, [0.0, 1.0, {}]))
	var v: Variant = get_param(path)
	var s := AKParamSlider.make(label if label != "" else String(NICE.get(key, key.capitalize())), r[0], r[1],
		float(v if v != null else r[0]), r[2])
	s.name = path.replace(".", "_")
	s.set_meta(&"path", path)
	s.changed.connect(func(x: float) -> void:
		_quiet = true
		set_param(path, int(x) if s.integer else x)
		_quiet = false)
	box.add_child(s)
	return s


## A menu bound to `path`, choosing among `items` (the stored values) shown as `labels`.
func _menu(box: Control, path: String, text: String, items: Array, labels := []) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 92
	row.add_child(l)
	var ob := OptionButton.new()
	ob.name = path.replace(".", "_")
	ob.set_meta(&"path", path)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cur: Variant = get_param(path)
	for i in items.size():
		ob.add_item(String(labels[i]) if i < labels.size() else str(items[i]))
		if _same(items[i], cur):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: set_param(path, items[i]))
	row.add_child(ob)
	return ob


func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


func _head_button(box: VBoxContainer, text: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.pressed.connect(f)
	(box.get_meta(&"head") as HBoxContainer).add_child(b)
	return b


func _osc_panel(i: int) -> void:
	var p := "oscillators.%d." % i
	var box := _panel("Oscillator %d" % (i + 1))
	if patch.oscillators.size() > 1:
		_head_button(box, "x", "Remove this oscillator", func() -> void: remove_oscillator(i))
	var shape := String(get_param(p + "shape"))
	var o: Dictionary = patch.oscillators[i]
	var has_ops := OP_KEYS.any(func(k: String) -> bool: return o.has(k))
	if not has_ops:
		_head_button(box, "Op", "Operator fields: an FM list, ratio, fixed frequency, its own envelopes, key scaling",
			func() -> void:
				_show_ops[i] = not bool(_show_ops.get(i, false))
				rebuild())
	_menu(box, p + "shape", "Shape", AKPatch.SHAPES)
	if shape == "table":
		var tables: Array = AKWavetables.BUILTIN.duplicate()
		var cur: Variant = get_param(p + "table")
		if not (cur is String) or not tables.has(cur):
			tables.append(cur)
		var labels := tables.map(func(t: Variant) -> String: return t if t is String else "(custom)")
		_menu(box, p + "table", "Table", tables, labels)
	if shape == "pd":
		_menu(box, p + "pd_wave", "Wave", AKPatch.PD_WAVES)
		var w2: Array = [""]
		w2.append_array(AKPatch.PD_WAVES)
		var w2_labels: Array = ["(none)"]
		w2_labels.append_array(AKPatch.PD_WAVES)
		_menu(box, p + "pd_wave2", "Second wave", w2, w2_labels)
		_menu(box, p + "pd_window", "Window", AKPatch.PD_WINDOWS)
		_slider(box, p + "pd_amount", "pd_amount")
		_menu(box, p + "pd_noise", "Noise mod", [false, true], ["off", "on"])
	if shape == "grains":
		_menu(box, p + "source", "Source", AKPatch.GRAIN_SOURCES.keys())
		_menu(box, p + "envelope", "Grain window", AKPatch.GRAIN_ENVS)
		_slider(box, p + "density", "density")
		_slider(box, p + "grain_ms", "grain_ms")
		_slider(box, p + "jitter", "jitter")
		_slider(box, p + "spray", "spray")
		_slider(box, p + "pan_spread", "pan_spread")
		if String(get_param(p + "source")) == "sample":
			_slider(box, p + "position", "position")
			_slider(box, p + "position_jitter", "position_jitter")
	_slider(box, p + "level", "level")
	_slider(box, p + "semitones", "semitones")
	_slider(box, p + "cents", "cents")
	_slider(box, p + "pan", "pan")
	if patch.filter2.is_empty():
		_menu(box, p + "filtered", "Filter", [true, false], ["through it", "around it"])
	else:
		_menu(box, p + "filter", "Filter", ["", "1", "2", "both", "none"],
			["default (%s)" % ("both" if patch.filter_routing == "parallel" else "1, then 2"), "filter 1", "filter 2 only", "both", "none"])
	if shape == "pulse":
		_slider(box, p + "width", "width")
	if shape == "morph" or shape == "table":
		_slider(box, p + "position", "position")
	var others := [0]
	var names := ["none"]
	for j in patch.oscillators.size():
		if j != i:
			others.append(j + 1)
			names.append("osc %d" % (j + 1))
	if patch.oscillators.size() > 1 or int(get_param(p + "fm_from")) != 0:
		var fm_items := others.duplicate()
		var fm_names := names.duplicate()
		fm_items.append(i + 1)
		fm_names.append("itself (feedback)")
		_menu(box, p + "fm_from", "FM from", fm_items, fm_names)
		if int(get_param(p + "fm_from")) != 0:
			_slider(box, p + "fm_index", "fm_index")
		_menu(box, p + "sync_to", "Sync to", others, names)
		_menu(box, p + "ring_from", "Ring from", others, names)
	if has_ops or bool(_show_ops.get(i, false)):
		_op_section(box, i)


## An oscillator's operator fields (phase 2 and 4): its own envelopes, frequency, FM list,
## feedback, velocity and key scaling, and a DX7 operator's raw frequency.
func _op_section(box: VBoxContainer, i: int) -> void:
	var p := "oscillators.%d." % i
	var o: Dictionary = patch.oscillators[i]
	var sep := Label.new()
	sep.text = "Operator"
	sep.modulate = Color(1, 1, 1, 0.6)
	box.add_child(sep)
	var env_items := [0]
	var env_names := ["none"]
	for k in env_count():
		env_items.append(k + 1)
		env_names.append("env%d%s" % [k + 1, " (amp)" if k == 0 else ""])
	_menu(box, p + "level_env", "Level env", env_items, env_names)
	_menu(box, p + "shape_env", "Shape env", env_items, env_names).tooltip_text = "Added to pd amount or position"
	_menu(box, p + "pitch_env", "Pitch env", env_items, env_names).tooltip_text = "Added to the pitch, in semitones"
	_slider(box, p + "ratio", "op_ratio", RANGES, "Ratio")
	_slider(box, p + "fixed_hz", "fixed_hz")
	_slider(box, p + "feedback", "op_feedback", RANGES, "Feedback")
	_slider(box, p + "velocity_sens", "velocity_sens")
	var fm: Array = o.get("fm", [])
	var srcs := []
	var src_names := []
	for j in patch.oscillators.size():
		srcs.append(j + 1)
		src_names.append("osc %d%s" % [j + 1, " (self)" if j == i else ""])
	for m in fm.size():
		var row := HBoxContainer.new()
		box.add_child(row)
		_menu(row, p + "fm.%d.from" % m, "FM %d from" % (m + 1), srcs, src_names)
		var s := _slider(row, p + "fm.%d.index" % m, "fm_index", RANGES, "index")
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var x := Button.new()
		x.text = "x"
		x.flat = true
		x.tooltip_text = "Remove this modulator"
		var mm := m
		x.pressed.connect(func() -> void:
			var a: Array = (patch.oscillators[i].get("fm", []) as Array).duplicate(true)
			a.remove_at(mm)
			set_param(p + "fm", a))
		row.add_child(x)
	var add := Button.new()
	add.text = "+ FM modulator"
	add.pressed.connect(func() -> void:
		var a: Array = (patch.oscillators[i].get("fm", []) as Array).duplicate(true)
		a.append({from = (i + 2) if i + 1 < patch.oscillators.size() else 1, index = 1.0})
		set_param(p + "fm", a))
	box.add_child(add)
	if o.get("key_scaling") is Dictionary:
		_slider(box, p + "key_scaling.break_key", "break_key")
		_slider(box, p + "key_scaling.left_db_oct", "db_oct", RANGES, "Left dB/oct")
		_slider(box, p + "key_scaling.right_db_oct", "db_oct", RANGES, "Right dB/oct")
		_menu(box, p + "key_scaling.left_curve", "Left curve", ["lin", "exp"])
		_menu(box, p + "key_scaling.right_curve", "Right curve", ["lin", "exp"])
	else:
		var ks := Button.new()
		ks.text = "+ Key scaling"
		ks.pressed.connect(func() -> void: set_param(p + "key_scaling", {break_key = 60, left_db_oct = 0.0, right_db_oct = 0.0}))
		box.add_child(ks)
	if o.get("dx7_freq") is Dictionary:
		_menu(box, p + "dx7_freq.mode", "DX7 mode", [0, 1], ["ratio", "fixed"])
		for k in ["coarse", "fine", "detune"]:
			_slider(box, p + "dx7_freq." + k, "dx7_" + k, RANGES, "DX7 " + k)


func _voice_panel() -> void:
	var box := _panel("Voice")
	_menu(box, "mode", "Mode", AKPatch.MODES)
	_slider(box, "polyphony", "polyphony")
	_slider(box, "unison", "unison")
	_slider(box, "detune_cents", "detune_cents")
	_slider(box, "unison_level", "unison_level")
	_slider(box, "spread", "spread")
	_slider(box, "glide_s", "glide_s")
	_slider(box, "bend_range", "bend_range")
	_slider(box, "velocity_sens", "velocity_sens")
	_slider(box, "velocity_curve", "velocity_curve")
	_slider(box, "gain_db", "gain_db")
	_slider(box, "pan", "pan")
	var row := HBoxContainer.new()
	box.add_child(row)
	var s := _slider(row, "seed", "seed")
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Button.new()
	b.text = "New"
	b.tooltip_text = "A new seed: new noise, unison phases and random values"
	b.pressed.connect(func() -> void: set_param("seed", randi() % 10000))
	row.add_child(b)


func _filter_panel() -> void:
	var box := _panel("Filter")
	var t := String(get_param("filter.type"))
	_menu(box, "filter.type", "Type", AKPatch.FILTERS)
	if t == "off":
		return
	_filter_controls(box, "filter", t)
	_slider(box, "filter_feedback", "filter_feedback", RANGES, "Feedback loop")


func _filter_controls(box: VBoxContainer, prop: String, t: String) -> void:
	_slider(box, prop + ".cutoff_hz", "cutoff_hz")
	if t == "ladder":
		_slider(box, prop + ".resonance", "resonance")
		_slider(box, prop + ".drive", "drive")
		_slider(box, prop + ".poles", "poles")
	else:
		_slider(box, prop + ".q", "q")
		_menu(box, prop + ".slope_db", "Slope", [12.0, 24.0], ["12 dB/oct", "24 dB/oct"])
	if t == "mix":
		for k in ["low", "band", "high"]:
			_slider(box, prop + "." + k, "mix_" + k, RANGES, k.capitalize())
	if t.ends_with("shelf"):
		_slider(box, prop + ".gain_db", "shelf_db", RANGES, "Gain")
	if t == "comb":
		_slider(box, prop + ".comb_feedback", "comb_fb", RANGES, "Feedback")


## Filter 2 (phase 3): off (empty), or the main filter's types, in series after filter 1 or
## in parallel with it.
func _filter2_panel() -> void:
	var box := _panel("Filter 2")
	var on := not patch.filter2.is_empty()
	var types: Array = AKPatch.FILTERS.duplicate()
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = "Type"
	l.custom_minimum_size.x = 92
	row.add_child(l)
	var ob := OptionButton.new()
	ob.name = "filter2_type"
	ob.set_meta(&"path", "filter2.type")
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cur := String(patch.filter2.get("type", "lowpass")) if on else "off"
	for k in types.size():
		ob.add_item(types[k])
		if types[k] == cur:
			ob.select(k)
	ob.item_selected.connect(func(k: int) -> void:
		if types[k] == "off":
			_commit("filter2", {}, "Filter 2 off")
		elif not on:
			_commit("filter2", {type = types[k], cutoff_hz = 2000.0, q = 0.707}, "Filter 2 on")
		else:
			set_param("filter2.type", types[k]))
	row.add_child(ob)
	if not on:
		return
	_menu(box, "filter_routing", "Routing", ["series", "parallel"], ["series (1, then 2)", "parallel"])
	_filter_controls(box, "filter2", cur)


## The patch's four macros (sources macro1 .. macro4), 0..1.
func _macros_panel() -> void:
	var box := _panel("Macros")
	for k in 4:
		var v := float(patch.macros[k]) if k < patch.macros.size() else 0.0
		var s := AKParamSlider.make("Macro %d" % (k + 1), 0.0, 1.0, v, {})
		s.name = "macros_%d" % k
		s.set_meta(&"path", "macros.%d" % k)
		var kk := k
		s.changed.connect(func(x: float) -> void:
			var m: Array = patch.macros.duplicate()
			while m.size() < 4:
				m.append(0.0)
			m[kk] = x
			_quiet = true
			_commit("macros", m, "Macro %d" % (kk + 1))
			_quiet = false)
		box.add_child(s)


## How many envelopes the patch has (amp_env, env2, env3, then `envelopes`).
func env_count() -> int:
	return 3 + patch.envelopes.size()


## An envelope's mode: adsr, stages, dx7, dx7_pitch or cz.
static func env_mode(e: Dictionary) -> String:
	var m := String(e.get("mode", ""))
	if m in ["dx7", "dx7_pitch", "cz"]:
		return m
	return "stages" if e.has("stages") else "adsr"


func _env_panel(prop: String, title: String, removable := -1) -> void:
	var box := _panel(title)
	if removable >= 0:
		_head_button(box, "x", "Remove this envelope (and what uses it)", func() -> void: remove_envelope(removable))
	var e: Dictionary = get_param(prop) if get_param(prop) is Dictionary else {}
	var mode := env_mode(e)
	var mrow := HBoxContainer.new()
	box.add_child(mrow)
	var ml := Label.new()
	ml.text = "Mode"
	ml.custom_minimum_size.x = 92
	mrow.add_child(ml)
	var mob := OptionButton.new()
	mob.name = prop.replace(".", "_") + "_mode"
	mob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ENV_MODES.size():
		mob.add_item(ENV_MODES[k])
		if ENV_MODES[k] == mode:
			mob.select(k)
	mob.item_selected.connect(func(k: int) -> void: set_env_mode(prop, ENV_MODES[k]))
	mrow.add_child(mob)
	var view := AKEnvView.new()
	box.add_child(view)
	var redraw := func() -> void:
		var cur: Dictionary = get_param(prop)
		view.env = cur
		view.curve = PackedFloat32Array() if env_mode(cur) == "adsr" else env_curve(cur)
		view.queue_redraw()
	redraw.call()
	var watch := func(s: Control) -> void:
		if s is AKParamSlider:
			(s as AKParamSlider).changed.connect(func(_x: float) -> void: redraw.call())
	match mode:
		"adsr":
			for k in ["attack_s", "decay_s", "sustain", "release_s"]:
				watch.call(_slider(box, prop + "." + k, k))
			_menu(box, prop + ".curve", "Decay curve", ["linear", "exp"], ["linear", "exponential"])
		"stages":
			var st: Array = e.get("stages", [])
			for k in st.size():
				var row := HBoxContainer.new()
				box.add_child(row)
				var t := _slider(row, prop + ".stages.%d.time_s" % k, "time_s", RANGES, "%d time" % (k + 1))
				t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				watch.call(t)
				var lv := _slider(row, prop + ".stages.%d.level" % k, "stage_level", RANGES, "level")
				lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				watch.call(lv)
				_menu(box, prop + ".stages.%d.curve" % k, "  curve", AKPatch.CURVES)
			var sus_items := [-1]
			var sus_names := ["none (one-shot)"]
			for k in st.size():
				sus_items.append(k)
				sus_names.append("stage %d" % (k + 1))
			_menu(box, prop + ".sustain", "Sustain at", sus_items, sus_names)
			_list_buttons(box, prop + ".stages", st, {time_s = 0.2, level = 0.0}, AKPatch.MAX_STAGES, "stage")
		"dx7", "dx7_pitch":
			for k in 4:
				var row := HBoxContainer.new()
				box.add_child(row)
				var r := _slider(row, prop + ".rates.%d" % k, "dx7_99", RANGES, "R%d" % (k + 1))
				r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				watch.call(r)
				var lv := _slider(row, prop + ".levels.%d" % k, "dx7_99", RANGES, "L%d" % (k + 1))
				lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				watch.call(lv)
			if mode == "dx7":
				watch.call(_slider(box, prop + ".output_level", "dx7_99", RANGES, "Output level"))
				_slider(box, prop + ".rate_scaling", "dx7_7", RANGES, "Rate scaling")
				_slider(box, prop + ".velocity_sens", "dx7_7", RANGES, "Velocity")
		"cz":
			_menu(box, prop + ".kind", "Drives", AKPatch.CZ_KINDS, ["level (DCA)", "pd amount (DCW)", "pitch (DCO)"])
			var steps: Array = e.get("steps", [])
			for k in steps.size():
				var row := HBoxContainer.new()
				box.add_child(row)
				var r := _slider(row, prop + ".steps.%d.0" % k, "cz_127", RANGES, "%d rate" % (k + 1))
				r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				watch.call(r)
				var lv := _slider(row, prop + ".steps.%d.1" % k, "cz_127", RANGES, "level")
				lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				watch.call(lv)
			var items := [-1]
			var labels := ["none"]
			var ends := []
			var end_labels := []
			for k in steps.size():
				items.append(k)
				labels.append("step %d" % (k + 1))
				ends.append(k)
				end_labels.append("step %d" % (k + 1))
			_menu(box, prop + ".sustain", "Sustain at", items, labels)
			if not ends.is_empty():
				_menu(box, prop + ".end", "End at", ends, end_labels)
			_list_buttons(box, prop + ".steps", steps, [60, 0], 8, "step")


## + / - buttons for a list inside the patch (stages, cz steps).
func _list_buttons(box: VBoxContainer, path: String, list: Array, item: Variant, most: int, what: String) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	if list.size() < most:
		var a := Button.new()
		a.text = "+ " + what
		a.pressed.connect(func() -> void:
			var l: Array = (get_param(path) as Array).duplicate(true)
			l.append(item.duplicate() if (item is Dictionary or item is Array) else item)
			set_param(path, l))
		row.add_child(a)
	if list.size() > 1:
		var r := Button.new()
		r.text = "- " + what
		r.pressed.connect(func() -> void:
			var l: Array = (get_param(path) as Array).duplicate(true)
			l.remove_at(l.size() - 1)
			set_param(path, l))
		row.add_child(r)


## Switch the envelope at `prop` to `mode`, starting from that mode's template.
func set_env_mode(prop: String, mode: String) -> void:
	var cur: Variant = get_param(prop)
	if cur is Dictionary and env_mode(cur) == mode:
		return
	set_param(prop, (ENV_TEMPLATES[mode] as Dictionary).duplicate(true))


## Add an envelope (env4 .. env8), an ADSR unless `e` says otherwise.
func add_envelope(e := {}) -> void:
	if patch == null or env_count() >= AKPatch.MAX_ENV:
		return
	var a: Array[Dictionary] = _copy(patch.envelopes)
	a.append(e if not e.is_empty() else (ENV_TEMPLATES.adsr as Dictionary).duplicate(true))
	_commit("envelopes", a, "Add envelope")


## Remove extra envelope `i` (0-based in `envelopes`: env4 is 0). Oscillators following it
## follow nothing; matrix rows reading it or moving its times go; later ones are renumbered.
func remove_envelope(i: int) -> void:
	if patch == null or i < 0 or i >= patch.envelopes.size():
		return
	var a: Array[Dictionary] = _copy(patch.envelopes)
	a.remove_at(i)
	var gone := i + 4
	var oscs: Array[Dictionary] = _copy(patch.oscillators)
	for o in oscs:
		for k in ["level_env", "shape_env", "pitch_env"]:
			var n := int(o.get(k, 0))
			if n == gone:
				o.erase(k)
			elif n > gone:
				o[k] = n - 1
	var renum := func(name: String) -> String:
		if not name.begins_with("env"):
			return name
		var dot := name.find(".")
		var n := (name.substr(3) if dot < 0 else name.substr(3, dot - 3)).to_int()
		if n == gone:
			return ""
		if n > gone:
			return "env%d%s" % [n - 1, "" if dot < 0 else name.substr(dot)]
		return name
	var m: Array[Dictionary] = []
	for row in patch.mods:
		var r: Dictionary = row.duplicate()
		var s: String = renum.call(String(row.get("source", "")))
		var d: String = renum.call(String(row.get("dest", "")))
		var v: String = renum.call(String(row.get("via", ""))) if row.has("via") else "-"
		if s == "" or d == "" or v == "":
			continue
		r.source = s
		r.dest = d
		if row.has("via"):
			r.via = v
		m.append(r)
	_commit_many({envelopes = a, oscillators = oscs, mods = m}, "Remove envelope")


## The envelope's levels over time (a note held 1 s, then released), as the engine runs it:
## for the picture of modes the ADSR drawing doesn't cover. Scaled to its own peak, so a quiet
## envelope (a CZ level 72 is 2% of full) still shows its shape.
func env_curve(e: Dictionary, points := 160) -> PackedFloat32Array:
	var p := AKPatch.new()
	# A pulse this slow stays high: its output is the envelope (centred, so 1/sqrt(2)).
	p.oscillators = [{shape = "pulse", width = 0.99, fixed_hz = 0.01, level = 1.0, filtered = false}]
	p.filter = {type = "off"}
	p.velocity_sens = 0.0
	p.amp_env = e
	var sr := 2000
	var ev := AKSynth.events_for([{time_s = 0.0, note = 60, velocity = 1.0, length_s = 1.0}], sr)
	var b := AKSynth.render_events(p.compile(), ev, roundi(sr * 2.5), sr)
	var out := PackedFloat32Array()
	out.resize(points)
	var top := 1e-9
	var per := floori(b.l.size() / float(points))
	for k in points:
		var m := 0.0
		for j in range(k * per, (k + 1) * per):
			m = maxf(m, absf(b.l[j]))
		out[k] = m
		top = maxf(top, m)
	for k in points:
		out[k] /= top
	return out


func _lfo_panel(prop: String, title: String) -> VBoxContainer:
	var box := _panel(title)
	_menu(box, prop + ".shape", "Shape", AKPatch.LFO_SHAPES)
	_slider(box, prop + ".rate_hz", "rate_hz")
	_slider(box, prop + ".delay_s", "delay_s")
	if String(get_param(prop + ".shape")) == "square":
		_slider(box, prop + ".width", "width")
	return box


## Destinations as the matrix menu offers them: the global ones, then each
## oscillator's own (osc1.pitch ...), then all oscillators (osc.pitch ...).
func mod_destinations() -> Array:
	var out := ["pitch", "cutoff", "q", "amp", "pan", "lfo1.rate", "lfo2.rate"]
	for i in patch.lfos.size():
		out.append("lfo%d.rate" % (i + 3))
	if not patch.comb.is_empty():
		out.append_array(["comb.feedback", "comb.pitch", "comb.damp"])
	if not patch.filter2.is_empty():
		out.append_array(["cutoff2", "q2"])
	if String(patch.filter.get("type", "")) == "formant":
		out.append("vowel")
	if String(patch.filter2.get("type", "")) == "formant":
		out.append("vowel2")
	out.append("feedback")
	for k in env_count():
		var e: Variant = get_param(["amp_env", "env2", "env3"][k] if k < 3 else "envelopes.%d" % (k - 3))
		if e is Dictionary and env_mode(e) == "stages":
			for part in ["time", "attack", "decay", "release"]:
				out.append("env%d.%s" % [k + 1, part])
	for i in patch.oscillators.size():
		for k in ["pitch", "level", "fm", "width", "position"]:
			out.append("osc%d.%s" % [i + 1, k])
	for k in ["pitch", "level", "fm", "width", "position"]:
		out.append("osc." + k)
	# fxN.key: the settings each effect lets the matrix move.
	for i in patch.effects.size():
		var keys := AKStreamFx.mod_keys(String(patch.effects[i].get("type", ""))).keys()
		keys.sort()
		for k: String in keys:
			out.append("fx%d.%s" % [i + 1, k])
	return out


## An fxN.key row's amount range (4 octaves for a log setting, else the setting's span); 0 if it isn't one.
func _fx_mod_range(dest: String) -> float:
	if not dest.begins_with("fx") or dest.find(".") < 3:
		return 0.0
	var n := dest.substr(2, dest.find(".") - 2).to_int() - 1
	if n < 0 or n >= patch.effects.size():
		return 0.0
	var r: Variant = AKStreamFx.mod_keys(String(patch.effects[n].get("type", ""))).get(dest.substr(dest.find(".") + 1))
	if r == null:
		return 0.0
	return 4.0 if bool(r[2]) else float(r[1]) - float(r[0])


func _matrix_panel() -> void:
	var box := _panel("Modulation matrix", true)
	if patch.mods.size() < AKPatch.MAX_MODS:
		_head_button(box, "+ Row", "Add a modulation row", func() -> void: add_mod())
	if patch.mods.is_empty():
		var l := Label.new()
		l.text = "Each row adds amount × source to a destination."
		l.modulate = Color(1, 1, 1, 0.6)
		box.add_child(l)
	var dests := mod_destinations()
	for i in patch.mods.size():
		var p := "mods.%d." % i
		var row := HBoxContainer.new()
		box.add_child(row)
		var src := OptionButton.new()
		src.name = "mods_%d_source" % i
		src.set_meta(&"path", p + "source")
		for s in AKPatch.SOURCES:
			src.add_item(s)
		src.select(AKPatch.SOURCES.find(String(get_param(p + "source"))))
		src.item_selected.connect(func(k: int) -> void: set_param(p + "source", AKPatch.SOURCES[k]))
		row.add_child(src)
		var arrow := Label.new()
		arrow.text = "→"
		row.add_child(arrow)
		var dst := OptionButton.new()
		dst.name = "mods_%d_dest" % i
		dst.set_meta(&"path", p + "dest")
		var cur := String(get_param(p + "dest"))
		var list := dests.duplicate()
		if not list.has(cur):
			list.append(cur)
		for d in list:
			dst.add_item(d)
		dst.select(list.find(cur))
		dst.item_selected.connect(func(k: int) -> void: set_param(p + "dest", list[k]))
		row.add_child(dst)
		var generic := cur
		if cur.begins_with("osc") and cur.find(".") > 0:
			generic = "osc" + cur.substr(cur.find("."))
		elif cur.begins_with("lfo") and cur.ends_with(".rate"):
			generic = "lfo1.rate"
		elif cur.begins_with("env") and cur.find(".") > 0:
			generic = "env1.time"
		if cur == "feedback":
			generic = "feedback"
		var fx_rng := _fx_mod_range(cur)
		var via := OptionButton.new()
		via.name = "mods_%d_via" % i
		via.set_meta(&"path", p + "via")
		via.tooltip_text = "A second source multiplying this row"
		var vias: Array = [""]
		vias.append_array(AKPatch.SOURCES)
		var cv := String(patch.mods[i].get("via", ""))
		for k in vias.size():
			via.add_item("×" + vias[k] if vias[k] != "" else "× 1")
			if vias[k] == cv:
				via.select(k)
		via.item_selected.connect(func(k: int) -> void:
			var m: Array[Dictionary] = _copy(patch.mods)
			if vias[k] == "":
				m[i].erase("via")
			else:
				m[i].via = vias[k]
			_commit("mods", m, "Matrix via"))
		row.add_child(via)
		var rng := fx_rng if fx_rng > 0.0 else float(MOD_RANGES.get(generic, 1.0))
		var amt := _slider(row, p + "amount", "amount", {amount = [-rng, rng, {width = 54}]})
		amt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var x := Button.new()
		x.text = "x"
		x.flat = true
		x.tooltip_text = "Remove this row"
		x.pressed.connect(func() -> void: remove_mod(i))
		row.add_child(x)


func _effects_panel() -> void:
	for i in patch.effects.size():
		var e: Dictionary = patch.effects[i]
		var t := String(e.get("type", ""))
		var box := _panel("Effect %d: %s" % [i + 1, t])
		if i > 0:
			_head_button(box, "↑", "Earlier in the chain", func() -> void: move_effect(i, -1))
		if i < patch.effects.size() - 1:
			_head_button(box, "↓", "Later in the chain", func() -> void: move_effect(i, 1))
		_head_button(box, "x", "Remove this effect", func() -> void: remove_effect(i))
		for k in AKStreamFx.DEFAULTS.get(t, {}):
			if t == "flanger" and k == "voices":
				continue
			var ranges := FX_RANGES.duplicate()
			ranges.merge(RANGES)
			_slider(box, "effects.%d.%s" % [i, k], k, ranges)
	var add := _panel("Add effect")
	var row := HFlowContainer.new()
	add.add_child(row)
	for t in AKStreamFx.DEFAULTS:
		var b := Button.new()
		b.text = t
		b.name = "add_" + t
		var tt: String = t
		b.pressed.connect(func() -> void: add_effect(tt))
		row.add_child(b)


## Every control bound to a patch path, by path (for tests and tools).
func controls() -> Dictionary:
	var out := {}
	_collect(_flow, out)
	return out


func _collect(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c.has_meta(&"path"):
			out[String(c.get_meta(&"path"))] = c
		_collect(c, out)
