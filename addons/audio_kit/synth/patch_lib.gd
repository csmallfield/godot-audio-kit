# SPDX-License-Identifier: Apache-2.0
@tool
## Patches from today's synth-like voices, and the built-in presets.
##
##   var p := AKPatchLib.from_voice(&"wavetable", {position = 0.66, cutoff_hz = 600.0})
##   var buf := AKSynth.render_note(p, AKPatchLib.note_of(&"wavetable", params), 1.0, 0.25)
##   var epiano := AKPatchLib.preset(&"fm_epiano")     # or load("res://addons/audio_kit/patches/fm_epiano.tres")
##
## `from_voice` rebuilds `tone`, `wavetable` and `fm` in the patch engine,
## so a recipe written for one of those voices can move to a patch (and play
## live, polyphonically, from a keyboard). The rebuilt patch plays the voice's
## note at the voice's pitch; tests/test_synth.gd measures each against the
## voice. Known differences: an attack of exactly 0 starts at full level
## (the voices ramp over one sample); modulation (vibrato, filter and FM
## envelopes) moves every 8 samples rather than every sample; `tone`'s glide
## curves in semitones rather than in Hz (timed to agree halfway); `wavetable`'s unison phases and its sub (which the
## patch stacks with the unison) differ when unison is above 1.
class_name AKPatchLib
extends RefCounted

const VOICES: Array[StringName] = [&"tone", &"wavetable", &"fm"]
const PRESET_DIR := "res://addons/audio_kit/patches/"
## Each preset's AKPatch.category.
const PRESET_CATEGORY := {&"tone_beep": "lead", &"wavetable_bass": "bass", &"wavetable_pad": "pad", &"fm_epiano": "keys",
	&"fm_bell": "bell", &"saw_lead": "lead", &"sub_bass": "bass", &"brass": "brass", &"pluck": "pluck", &"strings": "strings",
	&"organ": "organ", &"wobble_bass": "bass", &"sync_lead": "lead", &"vowel_pad": "pad", &"ring_bell": "bell",
	&"pwm_strings": "strings", &"acid_bass": "bass"}
const TRIM_DB := {&"tone_beep": -6.0, &"wavetable_bass": -3.6, &"wavetable_pad": 0.2, &"fm_epiano": -5.8, &"fm_bell": -6.0,
	&"saw_lead": -4.6, &"sub_bass": -6.4, &"brass": -6.7, &"pluck": -0.9, &"strings": -0.2, &"organ": -5.7,
	&"wobble_bass": -10.4, &"sync_lead": -1.6, &"vowel_pad": -0.6, &"ring_bell": -7.2, &"pwm_strings": 8.1,
	&"acid_bass": -5.1}


## A patch that sounds like `voice` with `params` (unset ones take the
## voice's defaults). Null for voices that aren't synth-like.
static func from_voice(voice: StringName, params := {}) -> AKPatch:
	var v := AK.voice(voice)
	if v == null or not VOICES.has(voice):
		push_error("AKPatchLib: no patch version of '%s' (only %s)" % [voice, VOICES])
		return null
	var p := v.defaults()
	p.merge(params, true)
	var patch := AKPatch.new()
	patch.velocity_sens = 0.0
	patch.amp_env = {attack_s = float(p.attack_s), decay_s = float(p.decay_s), sustain = float(p.sustain),
		release_s = float(p.release_s), curve = "linear"}
	patch.filter = {type = "off"}
	match voice:
		&"tone":
			var shape := String(p.wave)
			patch.oscillators = [{shape = shape, level = 1.0, width = float(p.width)}]
			var mods: Array[Dictionary] = []
			if float(p.end_hz) > 0.0:
				# The glide: env3 falls from the start pitch to the end note.
				# The voice glides in Hz, the patch in semitones: the time
				# constant is stretched so both are halfway (in pitch) at the
				# same moment.
				var r := float(p.freq_hz) / float(p.end_hz)
				var tau := float(p.glide_s)
				if not is_equal_approx(r, 1.0):
					tau *= log((r - 1.0) / (sqrt(r) - 1.0)) / log(2.0)
				patch.env3 = {attack_s = 0.0, decay_s = tau, sustain = 0.0, release_s = 4.0, curve = "exp"}
				mods.append({source = "env3", dest = "pitch", amount = 12.0 * log(float(p.freq_hz) / float(p.end_hz)) / log(2.0)})
			if float(p.vibrato_hz) > 0.0:
				patch.lfo1 = {shape = "sine", rate_hz = float(p.vibrato_hz), delay_s = 0.0}
				mods.append({source = "lfo1", dest = "pitch", amount = float(p.vibrato_semitones)})
			patch.mods = mods
		&"wavetable":
			patch.oscillators = [{shape = "morph", position = float(p.position), level = 1.0}]
			if float(p.sub) > 0.0:
				patch.oscillators.append({shape = "sine", semitones = -12.0, level = float(p.sub)})
			patch.unison = int(p.unison)
			patch.detune_cents = float(p.detune_cents)
			patch.filter = {type = "lowpass", cutoff_hz = float(p.cutoff_hz), q = float(p.q), slope_db = 12.0}
			patch.env2 = {attack_s = 0.0, decay_s = float(p.filter_decay_s), sustain = 0.0, release_s = 4.0, curve = "exp"}
			patch.mods = [{source = "env2", dest = "cutoff", amount = float(p.env_octaves)}]
			patch.gain_db = linear_to_db(0.6)
		&"fm":
			var i0 := float(p.index)
			var i1 := float(p.index_end)
			patch.oscillators = [{shape = "sine", level = 1.0, fm_from = 2, fm_index = i1},
				{shape = "sine", level = 0.0, semitones = _semis(float(p.ratio))}]
			if float(p.ratio2) > 0.0:
				patch.oscillators[1].fm_from = 3
				patch.oscillators[1].fm_index = float(p.index2)
				patch.oscillators.append({shape = "sine", level = 0.0, semitones = _semis(float(p.ratio2))})
			patch.env2 = {attack_s = 0.0, decay_s = float(p.index_decay_s), sustain = 0.0, release_s = 4.0, curve = "exp"}
			patch.mods = [{source = "env2", dest = "osc1.fm", amount = i0 - i1}]
	patch.resource_name = "%s (from the voice)" % voice
	return patch


## The note number `from_voice`'s patch plays for these voice params.
static func note_of(voice: StringName, params := {}) -> float:
	var v := AK.voice(voice)
	var p := v.defaults()
	p.merge(params, true)
	var hz := float(p.end_hz) if voice == &"tone" and float(p.get("end_hz", 0.0)) > 0.0 else float(p.freq_hz)
	return 69.0 + 12.0 * log(hz / 440.0) / log(2.0)


## The names of the built-in presets.
static func preset_names() -> PackedStringArray:
	return PackedStringArray(["tone_beep", "wavetable_bass", "wavetable_pad", "fm_epiano", "fm_bell",
		"saw_lead", "sub_bass", "brass", "pluck", "strings", "organ", "wobble_bass",
		"sync_lead", "vowel_pad", "ring_bell", "pwm_strings", "acid_bass"])


## A built-in preset, built in code (the .tres files in PRESET_DIR are these,
## saved by tools/make_patches.gd).
static func preset(name: StringName) -> AKPatch:
	var p: AKPatch
	match name:
		&"tone_beep":
			p = from_voice(&"tone", {wave = &"square", attack_s = 0.002, decay_s = 0.08, sustain = 0.5, release_s = 0.05})
			p.polyphony = 4
		&"wavetable_bass":
			p = from_voice(&"wavetable", {position = 0.7, sub = 0.5, cutoff_hz = 300.0, env_octaves = 3.0, filter_decay_s = 0.15,
				q = 1.4, decay_s = 0.3, sustain = 0.7, release_s = 0.06})
			p.mode = "mono"
			p.glide_s = 0.03
		&"wavetable_pad":
			p = from_voice(&"wavetable", {position = 0.55, unison = 5, detune_cents = 18.0, cutoff_hz = 1400.0, env_octaves = 0.5,
				filter_decay_s = 1.5, attack_s = 0.6, decay_s = 1.0, sustain = 0.8, release_s = 0.8})
			p.lfo1 = {shape = "sine", rate_hz = 0.3, delay_s = 0.0}
			p.mods.append({source = "lfo1", dest = "cutoff", amount = 0.4})
			p.spread = 0.8
			p.effects = [{type = "chorus", rate_hz = 0.4, depth_ms = 4.0, mix = 0.35}]
		&"fm_epiano":
			p = from_voice(&"fm", {ratio = 1.0, index = 2.2, index_end = 0.4, index_decay_s = 0.5, ratio2 = 14.0, index2 = 0.12,
				attack_s = 0.002, decay_s = 1.4, sustain = 0.15, release_s = 0.25})
			p.velocity_sens = 0.7
			p.mods.append({source = "velocity", dest = "osc1.fm", amount = 1.2})
			p.effects = [{type = "chorus", rate_hz = 0.6, depth_ms = 2.5, delay_ms = 8.0, mix = 0.3}]
		&"fm_bell":
			p = from_voice(&"fm", {ratio = 3.5, index = 4.0, index_end = 0.6, index_decay_s = 1.2, attack_s = 0.001,
				decay_s = 3.0, sustain = 0.0, release_s = 1.5})
			p.velocity_sens = 0.5
		&"saw_lead":
			p = _new([{shape = "saw", level = 0.6}, {shape = "saw", cents = 9.0, level = 0.6}],
				{type = "ladder", cutoff_hz = 1800.0, resonance = 0.35, drive = 1.5},
				{attack_s = 0.01, decay_s = 0.3, sustain = 0.8, release_s = 0.12})
			p.mode = "legato"
			p.glide_s = 0.06
			p.env2 = {attack_s = 0.0, decay_s = 0.25, sustain = 0.2, release_s = 0.2, curve = "exp"}
			p.lfo1 = {shape = "sine", rate_hz = 5.5, delay_s = 0.35}
			p.mods = [{source = "env2", dest = "cutoff", amount = 1.5}, {source = "lfo1", dest = "pitch", amount = 0.18},
				{source = "mod_wheel", dest = "cutoff", amount = 1.5}, {source = "key", dest = "cutoff", amount = 0.5}]
			p.effects = [{type = "chorus", rate_hz = 0.5, depth_ms = 2.0, mix = 0.2}]
		&"sub_bass":
			p = _new([{shape = "sine", level = 0.9}, {shape = "triangle", semitones = 12.0, level = 0.25}],
				{type = "lowpass", cutoff_hz = 600.0, q = 0.7}, {attack_s = 0.004, decay_s = 0.2, sustain = 0.9, release_s = 0.08})
			p.mode = "mono"
		&"brass":
			p = _new([{shape = "saw", level = 0.7}, {shape = "saw", cents = -6.0, level = 0.5}],
				{type = "ladder", cutoff_hz = 500.0, resonance = 0.15, drive = 1.2}, {attack_s = 0.06, decay_s = 0.4, sustain = 0.75, release_s = 0.15})
			p.effects = [{type = "eq", mid_db = 3.0, mid_hz = 1400.0, mid_q = 0.8}]
			p.env2 = {attack_s = 0.08, decay_s = 0.5, sustain = 0.45, release_s = 0.2, curve = "linear"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 2.6}, {source = "velocity", dest = "cutoff", amount = 1.0},
				{source = "key", dest = "cutoff", amount = 0.6}]
			p.velocity_sens = 0.6
		&"pluck":
			p = _new([{shape = "saw", level = 0.7}, {shape = "square", semitones = 12.0, level = 0.2}],
				{type = "ladder", cutoff_hz = 300.0, resonance = 0.4}, {attack_s = 0.001, decay_s = 0.35, sustain = 0.0, release_s = 0.2})
			p.env2 = {attack_s = 0.0, decay_s = 0.12, sustain = 0.0, release_s = 0.2, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 4.0}, {source = "key", dest = "cutoff", amount = 0.8},
				{source = "velocity", dest = "cutoff", amount = 1.0}]
			p.velocity_sens = 0.7
		&"strings":
			p = _new([{shape = "saw", level = 0.7}], {type = "lowpass", cutoff_hz = 2500.0, q = 0.6},
				{attack_s = 0.35, decay_s = 0.5, sustain = 0.85, release_s = 0.5})
			p.unison = 5
			p.detune_cents = 14.0
			p.spread = 0.9
			p.lfo1 = {shape = "triangle", rate_hz = 5.0, delay_s = 0.4}
			p.mods = [{source = "lfo1", dest = "pitch", amount = 0.08}, {source = "aftertouch", dest = "cutoff", amount = 1.0}]
			p.effects = [{type = "chorus", rate_hz = 0.3, depth_ms = 3.0, mix = 0.3}, {type = "eq", high_db = -3.0, high_hz = 7000.0}]
		&"organ":
			p = _new([{shape = "sine", level = 0.6}, {shape = "sine", semitones = 12.0, level = 0.35},
				{shape = "sine", semitones = 19.02, level = 0.25}, {shape = "sine", semitones = -12.0, level = 0.3}],
				{type = "off"}, {attack_s = 0.008, decay_s = 0.05, sustain = 1.0, release_s = 0.03})
			p.lfo1 = {shape = "sine", rate_hz = 6.2, delay_s = 0.0}
			p.mods = [{source = "lfo1", dest = "amp", amount = 0.12}]
			p.velocity_sens = 0.0
			# A rotary-ish shimmer: fast chorus, then a little drive.
			p.effects = [{type = "chorus", rate_hz = 6.2, depth_ms = 1.2, delay_ms = 2.0, mix = 0.4}, {type = "saturate", drive_db = 4.0, mix = 0.4}]
		&"wobble_bass":
			p = _new([{shape = "saw", level = 0.6}, {shape = "square", semitones = -12.0, level = 0.5}],
				{type = "ladder", cutoff_hz = 250.0, resonance = 0.6, drive = 2.0}, {attack_s = 0.005, decay_s = 0.2, sustain = 0.9, release_s = 0.08})
			p.mode = "mono"
			p.lfo1 = {shape = "sine", rate_hz = 3.0, delay_s = 0.0}
			p.mods = [{source = "lfo1", dest = "cutoff", amount = 2.0}, {source = "mod_wheel", dest = "cutoff", amount = 1.5}]
			p.effects = [{type = "saturate", drive_db = 8.0, tone_hz = 4000.0, mix = 0.6}]
		&"sync_lead":
			# A saw hard-synced to a hidden sine: an envelope sweeps the saw's
			# pitch for the classic tearing sync sound.
			p = _new([{shape = "sine", level = 0.0}, {shape = "saw", level = 0.7, sync_to = 1, semitones = 7.0}],
				{type = "ladder", cutoff_hz = 3500.0, resonance = 0.2}, {attack_s = 0.005, decay_s = 0.3, sustain = 0.8, release_s = 0.15})
			p.env2 = {attack_s = 0.0, decay_s = 0.4, sustain = 0.2, release_s = 0.3, curve = "exp"}
			p.lfo1 = {shape = "sine", rate_hz = 5.5, delay_s = 0.3}
			p.mods = [{source = "env2", dest = "osc2.pitch", amount = 19.0}, {source = "mod_wheel", dest = "osc2.pitch", amount = 12.0},
				{source = "lfo1", dest = "pitch", amount = 0.15}]
			p.mode = "legato"
			p.glide_s = 0.04
		&"vowel_pad":
			p = _new([{shape = "table", table = "vowel", level = 0.7}], {type = "lowpass", cutoff_hz = 4000.0, q = 0.7},
				{attack_s = 0.4, decay_s = 0.8, sustain = 0.85, release_s = 0.7})
			p.unison = 3
			p.detune_cents = 10.0
			p.spread = 0.7
			p.lfo1 = {shape = "triangle", rate_hz = 0.15}
			p.mods = [{source = "lfo1", dest = "osc1.position", amount = 0.5}, {source = "mod_wheel", dest = "osc1.position", amount = 0.5}]
			p.oscillators[0].position = 0.5
			p.effects = [{type = "chorus", rate_hz = 0.3, mix = 0.3}]
		&"ring_bell":
			p = _new([{shape = "sine", level = 0.8, ring_from = 2}, {shape = "sine", level = 0.0, semitones = 12.0 * log(2.76) / log(2.0)},
				{shape = "sine", level = 0.35}], {type = "off"}, {attack_s = 0.001, decay_s = 2.5, sustain = 0.0, release_s = 1.2})
			p.velocity_sens = 0.6
		&"pwm_strings":
			p = _new([{shape = "table", table = "pwm", level = 0.6}], {type = "ladder", cutoff_hz = 2400.0, resonance = 0.1},
				{attack_s = 0.25, decay_s = 0.6, sustain = 0.85, release_s = 0.5})
			p.unison = 3
			p.detune_cents = 8.0
			p.spread = 0.8
			p.lfo1 = {shape = "triangle", rate_hz = 0.7}
			p.mods = [{source = "lfo1", dest = "osc1.position", amount = 0.4}]
			p.oscillators[0].position = 0.4
			p.effects = [{type = "chorus", rate_hz = 0.5, mix = 0.35}]
		&"acid_bass":
			p = _new([{shape = "saw", level = 0.8}], {type = "ladder", cutoff_hz = 220.0, resonance = 0.85, drive = 2.5},
				{attack_s = 0.002, decay_s = 0.25, sustain = 0.6, release_s = 0.06})
			p.env2 = {attack_s = 0.0, decay_s = 0.18, sustain = 0.0, release_s = 0.1, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 3.5}, {source = "velocity", dest = "cutoff", amount = 1.2},
				{source = "mod_wheel", dest = "q", amount = 0.3}]
			p.mode = "mono"
			p.glide_s = 0.05
		_:
			push_error("AKPatchLib: no preset '%s'" % name)
			return null
	# Levels: a single note peaks around -6 dBFS, leaving room for chords.
	p.gain_db += float(TRIM_DB.get(name, 0.0))
	p.resource_name = String(name)
	p.category = String(PRESET_CATEGORY.get(name, "other"))
	return p


## Load a preset's .tres (falling back to building it).
static func load_preset(name: StringName) -> AKPatch:
	var path := PRESET_DIR + String(name) + ".tres"
	if ResourceLoader.exists(path):
		return load(path)
	return preset(name)


static func _new(oscs: Array, filt: Dictionary, amp: Dictionary) -> AKPatch:
	var p := AKPatch.new()
	var o: Array[Dictionary] = []
	for d in oscs:
		o.append(d)
	p.oscillators = o
	p.filter = filt
	p.amp_env = amp
	p.mods = []
	return p


static func _semis(ratio: float) -> float:
	return 12.0 * log(ratio) / log(2.0)
