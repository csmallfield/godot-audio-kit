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
	&"pwm_strings": "strings", &"acid_bass": "bass", &"speech_blip": "voice", &"speech_critter": "voice",
	&"speech_hollow": "voice", &"speech_drone": "voice",
	&"GAK_wavetable_bass": "bass", &"GAK_sub_bass": "bass", &"GAK_wobble_bass": "bass", &"GAK_acid_bass": "bass",
	&"GAK_tone_beep": "lead", &"GAK_saw_lead": "lead", &"GAK_sync_lead": "lead", &"GAK_brass": "brass", &"GAK_pluck": "pluck", &"GAK_strings": "strings", &"GAK_pwm_strings": "strings", &"GAK_wavetable_pad": "pad", &"GAK_vowel_pad": "pad", &"GAK_organ": "organ", &"GAK_fm_epiano": "keys", &"GAK_fm_bell": "bell", &"GAK_ring_bell": "bell"}
const TRIM_DB := {&"tone_beep": -6.0, &"wavetable_bass": -3.6, &"wavetable_pad": 0.2, &"fm_epiano": -5.8, &"fm_bell": -6.0,
	&"saw_lead": -4.6, &"sub_bass": -6.4, &"brass": -6.7, &"pluck": -0.9, &"strings": -0.2, &"organ": -5.7,
	&"wobble_bass": -10.4, &"sync_lead": -1.6, &"vowel_pad": -0.6, &"ring_bell": -7.2, &"pwm_strings": 8.1,
	&"acid_bass": -5.1, &"speech_blip": 0.0, &"speech_critter": -5.0, &"speech_hollow": -5.4,
	&"speech_drone": 0.0,
	&"GAK_wavetable_bass": -5.5, &"GAK_sub_bass": -7.6, &"GAK_wobble_bass": -9.7, &"GAK_acid_bass": -10.3,
	&"GAK_tone_beep": -4.9, &"GAK_saw_lead": -1.3, &"GAK_sync_lead": -6.8, &"GAK_brass": -6.2, &"GAK_pluck": -6.6, &"GAK_strings": -4.2, &"GAK_pwm_strings": -3.2, &"GAK_wavetable_pad": -1.0, &"GAK_vowel_pad": -0.9, &"GAK_organ": -7.9, &"GAK_fm_epiano": -5.2, &"GAK_fm_bell": -6.0, &"GAK_ring_bell": -7.3}


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
		"sync_lead", "vowel_pad", "ring_bell", "pwm_strings", "acid_bass", "speech_blip", "speech_critter", "speech_hollow", "speech_drone",
		"GAK_wavetable_bass", "GAK_sub_bass", "GAK_wobble_bass", "GAK_acid_bass",
		"GAK_tone_beep", "GAK_saw_lead", "GAK_sync_lead", "GAK_brass", "GAK_pluck", "GAK_strings", "GAK_pwm_strings", "GAK_wavetable_pad", "GAK_vowel_pad", "GAK_organ", "GAK_fm_epiano", "GAK_fm_bell", "GAK_ring_bell"])


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
		&"speech_blip":
			# The Blip pseudo-speech voice (AKSpeechVoice): a short square blip
			# per syllable. Pitch comes from the note and the bend (12
			# semitones wide), intensity from velocity; aftertouch (the
			# line's brightness) opens the filter a little on accents.
			p = _new([{shape = "square", level = 0.6}], {type = "lowpass", cutoff_hz = 3200.0, q = 0.7},
				{attack_s = 0.002, decay_s = 0.06, sustain = 0.55, release_s = 0.02})
			p.mode = "mono"
			p.polyphony = 1
			p.bend_range = 12.0
			p.velocity_sens = 0.8
			p.mods = [{source = "aftertouch", dest = "cutoff", amount = 1.2}, {source = "velocity", dest = "cutoff", amount = 0.8}]
		&"speech_critter":
			# The Critter voice: a squeaky pulse with a little FM. The mod wheel
			# (the line's formant) sweeps the filter like a vowel; aftertouch
			# (brightness) adds FM edge on accents.
			p = _new([{shape = "pulse", width = 0.35, level = 0.6, fm_from = 2, fm_index = 0.4},
				{shape = "sine", level = 0.0, semitones = 12.0}], {type = "lowpass", cutoff_hz = 1800.0, q = 1.6},
				{attack_s = 0.003, decay_s = 0.07, sustain = 0.7, release_s = 0.03})
			p.mode = "mono"
			p.polyphony = 1
			p.glide_s = 0.012
			p.bend_range = 12.0
			p.velocity_sens = 0.7
			p.mods = [{source = "mod_wheel", dest = "cutoff", amount = 1.8}, {source = "aftertouch", dest = "osc1.fm", amount = 1.2},
				{source = "velocity", dest = "cutoff", amount = 0.6}]
		&"speech_hollow":
			# The Hollow voice: breath through one formant band, barely pitched.
			# The mod wheel moves the band from a dark u to a bright i.
			p = _new([{shape = "noise", level = 0.9}, {shape = "sine", level = 0.12}],
				{type = "bandpass", cutoff_hz = 700.0, q = 4.0}, {attack_s = 0.025, decay_s = 0.12, sustain = 0.8, release_s = 0.09})
			p.mode = "mono"
			p.polyphony = 1
			p.bend_range = 12.0
			p.velocity_sens = 0.6
			p.mods = [{source = "mod_wheel", dest = "cutoff", amount = 1.6}, {source = "aftertouch", dest = "cutoff", amount = 0.4}]
		&"speech_drone":
			# The Drone Priest voice: low detuned saws and a sub through a
			# resonant ladder, the mod wheel opening it vowel by vowel.
			p = _new([{shape = "saw", level = 0.6}, {shape = "saw", cents = -8.0, level = 0.45},
				{shape = "sine", semitones = -12.0, level = 0.5}], {type = "ladder", cutoff_hz = 260.0, resonance = 0.55, drive = 1.4},
				{attack_s = 0.05, decay_s = 0.3, sustain = 0.85, release_s = 0.25})
			p.mode = "legato"
			p.polyphony = 1
			p.glide_s = 0.06
			p.bend_range = 12.0
			p.velocity_sens = 0.5
			p.mods = [{source = "mod_wheel", dest = "cutoff", amount = 2.0}, {source = "aftertouch", dest = "cutoff", amount = 0.6},
				{source = "velocity", dest = "cutoff", amount = 0.5}]
			p.effects = [{type = "chorus", rate_hz = 0.2, depth_ms = 3.0, mix = 0.25}]
		# The GAK_ presets: richer versions of the originals above, made with
		# what the engine has gained since (stacks, a second filter, stages
		# envelopes, operators, macros, tempo sync, slop, more effects). The
		# originals stay as they were, since songs, demos and tests use them.
		# Each GAK_ preset is meant to sound good with its macros at 0; the
		# macros add range.
		&"GAK_wavetable_bass":
			# The wavetable bass, thicker and growlier: a stacked morph wave,
			# a clean sub around the filter, and a digital edge an octave up.
			# Macro 1: the edge's wavetable position (growl). Macro 2: the
			# filter envelope's depth (pluck).
			p = _new([{shape = "morph", position = 0.7, level = 0.6, stack = 3, stack_cents = 10.0},
				{shape = "sine", semitones = -12.0, level = 0.45, filter = "none"},
				{shape = "table", table = "digital", position = 0.25, semitones = 12.0, level = 0.18}],
				{type = "ladder", cutoff_hz = 260.0, resonance = 0.35, drive = 1.6, sat_gain_db = 4.0, sat_ceiling = 0.9},
				{attack_s = 0.002, decay_s = 0.3, sustain = 0.75, release_s = 0.07})
			p.env2 = {attack_s = 0.0, decay_s = 0.16, sustain = 0.1, release_s = 0.2, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 3.0}, {source = "velocity", dest = "cutoff", amount = 0.8},
				{source = "key", dest = "cutoff", amount = 0.5}, {source = "mod_wheel", dest = "cutoff", amount = 1.5},
				{source = "macro1", dest = "osc3.position", amount = 0.7}, {source = "macro1", dest = "osc3.level", amount = 0.15},
				{source = "env2", dest = "cutoff", amount = 2.0, via = "macro2"}]
			p.mode = "mono"
			p.glide_s = 0.03
			p.velocity_sens = 0.5
			p.slop = {pitch_cents = 3.0, cutoff_octaves = 0.05}
			p.effects = [{type = "compressor", threshold_db = -20.0, ratio = 3.0, attack_s = 0.005, release_s = 0.1, makeup_db = 2.0},
				{type = "eq", low_db = 1.5, low_hz = 90.0, mid_db = -2.0, mid_hz = 350.0, mid_q = 1.0}]
		&"GAK_sub_bass":
			# The sub bass, made to carry on small speakers: a clean sine sub
			# around the filter, a filtered saw an octave up for harmonics a
			# laptop can play, a short pitch thump at the start, and gentle
			# saturation. Low notes are lifted a little, high ones eased off.
			# Macro 1: more of the saw (grit).
			p = _new([{shape = "sine", level = 0.85, filter = "none"},
				{shape = "triangle", semitones = 12.0, level = 0.18, filter = "none"},
				{shape = "saw", semitones = 12.0, level = 0.12}],
				{type = "ladder", cutoff_hz = 380.0, resonance = 0.2, drive = 1.3},
				{attack_s = 0.004, decay_s = 0.25, sustain = 0.9, release_s = 0.09})
			p.env2 = {attack_s = 0.0, decay_s = 0.12, sustain = 0.15, release_s = 0.2, curve = "exp"}
			p.env3 = {attack_s = 0.0, decay_s = 0.035, sustain = 0.0, release_s = 0.05, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 2.0}, {source = "env3", dest = "pitch", amount = 2.5},
				{source = "velocity", dest = "cutoff", amount = 0.6}, {source = "macro1", dest = "osc3.level", amount = 0.3},
				{source = "mod_wheel", dest = "cutoff", amount = 1.5}]
			p.mode = "mono"
			p.glide_s = 0.02
			p.velocity_sens = 0.4
			p.key_levels = [[24, 1.5], [48, 0.0], [72, -3.0]]
			p.effects = [{type = "saturate", drive_db = 9.0, tone_hz = 2500.0, asymmetry = 0.2, mix = 0.35},
				{type = "compressor", threshold_db = -18.0, ratio = 2.5, attack_s = 0.01, release_s = 0.15, makeup_db = 1.5}]
		&"GAK_wobble_bass":
			# The wobble bass, tempo-synced and talking: a wide saw stack and a
			# square an octave down through a driven ladder, then a bell boost
			# that moves with the wobble for a vowel-ish "yoy", and a clean sub
			# around both. The wobble is an eighth note at the tempo; the mod
			# wheel deepens it, macro 1 speeds it up (to 16ths, then 32nds).
			# No compressor: it would even the wobble out.
			p = _new([{shape = "saw", level = 0.5, stack = 5, stack_cents = 18.0},
				{shape = "square", semitones = -12.0, level = 0.45},
				{shape = "sine", semitones = -12.0, level = 0.35, filter = "none"}],
				{type = "ladder", cutoff_hz = 200.0, resonance = 0.62, drive = 2.0, sat_gain_db = 3.0, sat_ceiling = 0.95, sat_curve = "tanh"},
				{attack_s = 0.004, decay_s = 0.2, sustain = 0.9, release_s = 0.08})
			p.filter2 = {type = "bandshelf", cutoff_hz = 650.0, q = 2.0, gain_db = 9.0}
			p.filter_routing = "series"
			p.lfo1 = {shape = "sine", rate_hz = 3.0, rate_sync = "1/8", delay_s = 0.0}
			p.mods = [{source = "lfo1", dest = "cutoff", amount = 2.0}, {source = "lfo1", dest = "cutoff2", amount = 1.0},
				{source = "lfo1", dest = "cutoff", amount = 1.2, via = "mod_wheel"},
				{source = "macro1", dest = "lfo1.rate", amount = 2.0}]
			p.mode = "legato"
			p.glide_s = 0.04
			p.effects = [{type = "saturate", drive_db = 8.0, tone_hz = 5000.0, mix = 0.4},
				{type = "eq", low_db = 1.0, low_hz = 80.0, high_db = -3.0, high_hz = 8000.0}]
		&"GAK_acid_bass":
			# The acid bass, closer to the box it's named for: an 18 dB ladder
			# screaming near self-oscillation, a decay envelope whose depth
			# grows with velocity (accents), legato slides, and a distortion
			# pedal and a dotted-eighth echo after it. Macro 1: saw to square.
			# Macro 2: a longer filter decay.
			p = _new([{shape = "saw", level = 0.8}, {shape = "square", level = 0.0}],
				{type = "ladder", cutoff_hz = 200.0, resonance = 0.88, drive = 2.8, poles = 3.0, sat_gain_db = 3.0, sat_ceiling = 0.95},
				{attack_s = 0.002, decay_s = 0.3, sustain = 0.65, release_s = 0.05})
			p.env2 = {stages = [{time_s = 0.002, level = 1.0}, {time_s = 0.22, level = 0.0, curve = "exp"}], sustain = 1}
			p.mods = [{source = "env2", dest = "cutoff", amount = 3.0}, {source = "env2", dest = "cutoff", amount = 1.8, via = "velocity"},
				{source = "velocity", dest = "cutoff", amount = 0.6}, {source = "mod_wheel", dest = "q", amount = 0.3},
				{source = "macro1", dest = "osc1.level", amount = -0.8}, {source = "macro1", dest = "osc2.level", amount = 0.7},
				{source = "macro2", dest = "env2.time", amount = 1.5}, {source = "key", dest = "cutoff", amount = 0.4}]
			p.mode = "legato"
			p.glide_s = 0.06
			p.velocity_sens = 0.45
			p.effects = [{type = "saturate", drive_db = 10.0, tone_hz = 4500.0, asymmetry = 0.3, mix = 0.5},
				{type = "delay", time_ms = 375.0, time_sync = "1/8.", feedback = 0.3, damp_hz = 2500.0, mix = 0.14},
				{type = "eq", low_db = 1.0, low_hz = 100.0, mid_db = 1.5, mid_hz = 1200.0, mid_q = 0.9}]
		&"GAK_tone_beep":
			# The beep as a chiptune lead: two pulses, one swept by an LFO (PWM)
			# and one narrow and detuned, a chirp up at each note's start, a
			# delayed vibrato, a soft ping-pong echo and a touch of bit grit.
			# Macro 1: deeper PWM. Macro 2: a bigger chirp.
			p = _new([{shape = "pulse", width = 0.5, level = 0.55}, {shape = "pulse", width = 0.25, cents = 7.0, level = 0.25}],
				{type = "lowpass", cutoff_hz = 9000.0, q = 0.7}, {attack_s = 0.002, decay_s = 0.1, sustain = 0.6, release_s = 0.06})
			p.env3 = {attack_s = 0.0, decay_s = 0.025, sustain = 0.0, release_s = 0.05, curve = "exp"}
			p.lfo1 = {shape = "triangle", rate_hz = 3.5, free = true}
			p.lfo2 = {shape = "sine", rate_hz = 5.8, delay_s = 0.25}
			p.mods = [{source = "lfo1", dest = "osc1.width", amount = 0.18}, {source = "lfo1", dest = "osc1.width", amount = 0.2, via = "macro1"},
				{source = "env3", dest = "pitch", amount = 7.0}, {source = "env3", dest = "pitch", amount = 5.0, via = "macro2"},
				{source = "lfo2", dest = "pitch", amount = 0.15}, {source = "lfo2", dest = "pitch", amount = 0.3, via = "mod_wheel"}]
			p.polyphony = 6
			p.effects = [{type = "crush", bits = 10.0, hold = 1.0, mix = 0.3},
				{type = "delay", time_ms = 250.0, time_sync = "1/8", feedback = 0.25, damp_hz = 5000.0, mix = 0.15, mode = "pingpong"}]
		&"GAK_saw_lead":
			# The saw lead, bigger: a stacked saw, a second detuned saw and a
			# square an octave down, a driven ladder with a filter envelope,
			# vibrato that deepens on the mod wheel, and a dotted echo and a room.
			# Macro 1: brighter. Macro 2: the second saw up a fifth (power lead).
			p = _new([{shape = "saw", level = 0.45, stack = 3, stack_cents = 12.0}, {shape = "saw", cents = 9.0, level = 0.4},
				{shape = "square", semitones = -12.0, level = 0.22}],
				{type = "ladder", cutoff_hz = 1600.0, resonance = 0.35, drive = 1.8, sat_gain_db = 3.0, sat_ceiling = 0.95},
				{attack_s = 0.008, decay_s = 0.3, sustain = 0.8, release_s = 0.15})
			p.env2 = {attack_s = 0.0, decay_s = 0.3, sustain = 0.3, release_s = 0.2, curve = "exp"}
			p.lfo1 = {shape = "sine", rate_hz = 5.5, delay_s = 0.35}
			p.mods = [{source = "env2", dest = "cutoff", amount = 1.8}, {source = "key", dest = "cutoff", amount = 0.5},
				{source = "velocity", dest = "cutoff", amount = 0.6}, {source = "mod_wheel", dest = "cutoff", amount = 1.0},
				{source = "lfo1", dest = "pitch", amount = 0.15}, {source = "lfo1", dest = "pitch", amount = 0.3, via = "mod_wheel"},
				{source = "macro1", dest = "cutoff", amount = 1.5}, {source = "macro2", dest = "osc2.pitch", amount = 7.0}]
			p.mode = "legato"
			p.glide_s = 0.06
			p.slop = {pitch_cents = 4.0}
			p.effects = [{type = "chorus", rate_hz = 0.5, depth_ms = 2.0, mix = 0.15},
				{type = "delay", time_ms = 375.0, time_sync = "1/8.", feedback = 0.3, damp_hz = 3500.0, mix = 0.18, mode = "pingpong"},
				{type = "reverb", room = 0.6, damp = 0.5, mix = 0.14, predelay_ms = 15.0}]
		&"GAK_sync_lead":
			# The sync lead, with a body under the tear: the synced saw (smoothed
			# resets) swept by a stages envelope and a slow LFO, an unsynced saw
			# beneath it, a high-pass to keep it lean, and drive, echo and room.
			# Velocity sweeps further. Macro 1: more sync. Macro 2: more body.
			p = _new([{shape = "sine", level = 0.0}, {shape = "saw", level = 0.55, sync_to = 1, semitones = 7.0},
				{shape = "saw", cents = -7.0, level = 0.3}],
				{type = "ladder", cutoff_hz = 4000.0, resonance = 0.25, drive = 1.4},
				{attack_s = 0.004, decay_s = 0.3, sustain = 0.8, release_s = 0.15})
			p.band_limited_sync = true
			p.filter2 = {type = "highpass", cutoff_hz = 120.0, q = 0.7}
			p.env2 = {stages = [{time_s = 0.001, level = 1.0}, {time_s = 0.4, level = 0.25, curve = "exp"},
				{time_s = 1.5, level = 0.12, curve = "power", amount = -2.0}], sustain = 2, release_s = 0.3}
			p.lfo1 = {shape = "sine", rate_hz = 5.5, delay_s = 0.3}
			p.lfo2 = {shape = "triangle", rate_hz = 0.4}
			p.mods = [{source = "env2", dest = "osc2.pitch", amount = 16.0}, {source = "velocity", dest = "osc2.pitch", amount = 5.0},
				{source = "mod_wheel", dest = "osc2.pitch", amount = 12.0}, {source = "lfo2", dest = "osc2.pitch", amount = 3.0},
				{source = "lfo1", dest = "pitch", amount = 0.15}, {source = "macro1", dest = "osc2.pitch", amount = 12.0},
				{source = "macro2", dest = "osc3.level", amount = 0.3}]
			p.mode = "legato"
			p.glide_s = 0.04
			p.effects = [{type = "saturate", drive_db = 6.0, tone_hz = 7000.0, mix = 0.4},
				{type = "delay", time_ms = 375.0, time_sync = "1/8.", feedback = 0.28, damp_hz = 4000.0, mix = 0.16, mode = "pingpong"},
				{type = "reverb", room = 0.55, damp = 0.5, mix = 0.12}]
		&"GAK_brass":
			# A brass section rather than one horn: a stacked saw and a pulse,
			# a stages filter envelope with the swell's blat (slower when played
			# softly), a scoop up into each note, voices placed across the stereo
			# field with a little slop each, a bell boost, and a hall.
			# Macro 1: brighter (fortissimo). Macro 2: slower swells.
			p = _new([{shape = "saw", level = 0.5, stack = 4, stack_cents = 14.0}, {shape = "pulse", width = 0.3, level = 0.28}],
				{type = "ladder", cutoff_hz = 450.0, resonance = 0.15, drive = 1.4},
				{attack_s = 0.05, decay_s = 0.4, sustain = 0.8, release_s = 0.2})
			p.filter2 = {type = "bandshelf", cutoff_hz = 1400.0, q = 0.9, gain_db = 3.0}
			p.env2 = {stages = [{time_s = 0.07, level = 1.0, curve = "power", amount = 1.5}, {time_s = 0.35, level = 0.55, curve = "exp"}],
				sustain = 1, release_s = 0.25, time_velocity = 0.6}
			p.env3 = {attack_s = 0.0, decay_s = 0.06, sustain = 0.0, release_s = 0.1, curve = "exp"}
			p.lfo1 = {shape = "sine", rate_hz = 5.0, delay_s = 0.5}
			p.mods = [{source = "env2", dest = "cutoff", amount = 2.6}, {source = "velocity", dest = "cutoff", amount = 1.2},
				{source = "key", dest = "cutoff", amount = 0.6}, {source = "aftertouch", dest = "cutoff", amount = 0.8},
				{source = "env3", dest = "pitch", amount = -0.6}, {source = "lfo1", dest = "pitch", amount = 0.1},
				{source = "macro1", dest = "cutoff", amount = 1.2}, {source = "macro2", dest = "env2.time", amount = 1.0}]
			p.velocity_sens = 0.6
			p.voice_pan = [-0.45, 0.45, -0.2, 0.2, -0.6, 0.6, 0.0, -0.3]
			p.slop = {pitch_cents = 6.0, cutoff_octaves = 0.1, env_time = 0.1, level_db = 0.5}
			p.effects = [{type = "eq", low_db = -1.0, low_hz = 120.0, high_db = -2.0, high_hz = 9000.0},
				{type = "reverb", room = 0.72, damp = 0.5, mix = 0.18, predelay_ms = 15.0}]
		&"GAK_pluck":
			# The pluck as a plucked string: a pick transient (a burst of noise),
			# a comb tuned to the note that rings like a string, the ladder's snap
			# deeper the harder you play, and a ping-pong echo and a room.
			# Macro 1: more string ring. Macro 2: brighter.
			p = _new([{shape = "saw", level = 0.6, stack = 2, stack_cents = 8.0}, {shape = "square", semitones = 12.0, level = 0.18},
				{shape = "noise", color = "pink", level = 0.3, level_env = 3}],
				{type = "ladder", cutoff_hz = 280.0, resonance = 0.4, drive = 1.3},
				{attack_s = 0.001, decay_s = 0.45, sustain = 0.0, release_s = 0.25, curve = "exp"})
			p.comb = {semitones = 0.0, cents = 0.0, feedback = 0.45}
			p.env2 = {attack_s = 0.0, decay_s = 0.14, sustain = 0.0, release_s = 0.2, curve = "exp"}
			p.env3 = {attack_s = 0.0, decay_s = 0.012, sustain = 0.0, release_s = 0.02, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 3.5}, {source = "env2", dest = "cutoff", amount = 1.5, via = "velocity"},
				{source = "key", dest = "cutoff", amount = 0.8}, {source = "macro1", dest = "comb.feedback", amount = 0.4},
				{source = "macro2", dest = "cutoff", amount = 1.5}]
			p.velocity_sens = 0.7
			p.effects = [{type = "chorus", rate_hz = 0.4, depth_ms = 2.0, mix = 0.12},
				{type = "delay", time_ms = 250.0, time_sync = "1/8", feedback = 0.3, damp_hz = 3000.0, mix = 0.16, mode = "pingpong"},
				{type = "reverb", room = 0.5, damp = 0.5, mix = 0.14}]
		&"GAK_strings":
			# A string ensemble: a stacked, unison saw with an octave above for
			# the violins, a high-pass and a 24 dB low-pass, voices that each sit
			# a little apart (slop, placed across the field), a slow free-running
			# movement in the tone, delayed vibrato, and a hall.
			# Macro 1: more octave shimmer. Macro 2: brighter (towards the bridge).
			p = _new([{shape = "saw", level = 0.5, stack = 3, stack_cents = 12.0}, {shape = "saw", semitones = 12.0, level = 0.2}],
				{type = "lowpass", cutoff_hz = 2600.0, q = 0.6, slope_db = 24.0},
				{attack_s = 0.4, decay_s = 0.5, sustain = 0.9, release_s = 0.7})
			p.unison = 4
			p.detune_cents = 12.0
			p.spread = 0.9
			p.filter2 = {type = "highpass", cutoff_hz = 180.0, q = 0.7}
			p.lfo1 = {shape = "triangle", rate_hz = 5.2, delay_s = 0.5}
			p.lfo2 = {shape = "smooth", rate_hz = 0.2, free = true}
			p.mods = [{source = "lfo1", dest = "pitch", amount = 0.07}, {source = "lfo2", dest = "cutoff", amount = 0.25},
				{source = "velocity", dest = "cutoff", amount = 0.8}, {source = "aftertouch", dest = "cutoff", amount = 1.0},
				{source = "macro1", dest = "osc2.level", amount = 0.35}, {source = "macro2", dest = "cutoff", amount = 1.0}]
			p.voice_pan = [-0.3, 0.3, -0.15, 0.15, -0.45, 0.45, 0.0, 0.2]
			p.slop = {pitch_cents = 5.0, cutoff_octaves = 0.08, env_time = 0.15}
			p.effects = [{type = "chorus", rate_hz = 0.3, depth_ms = 3.0, mix = 0.3},
				{type = "eq", low_db = -2.0, low_hz = 150.0, high_db = -3.0, high_hz = 8000.0},
				{type = "reverb", room = 0.82, damp = 0.45, mix = 0.28, predelay_ms = 20.0}]
		&"GAK_pwm_strings":
			# String machine, Juno style: a pulse whose width two free-running
			# LFOs sweep, a square sub, a high-pass and a 24 dB low-pass, the two
			# chorus modes at once, and a little room.
			# Macro 1: brighter. Macro 2: faster PWM.
			p = _new([{shape = "pulse", width = 0.5, level = 0.5}, {shape = "square", semitones = -12.0, level = 0.18}],
				{type = "lowpass", cutoff_hz = 2800.0, q = 0.8, slope_db = 24.0},
				{attack_s = 0.3, decay_s = 0.6, sustain = 0.88, release_s = 0.6})
			p.unison = 2
			p.detune_cents = 8.0
			p.spread = 0.7
			p.filter2 = {type = "highpass", cutoff_hz = 220.0, q = 0.7}
			p.lfo1 = {shape = "triangle", rate_hz = 0.6, free = true}
			p.lfo2 = {shape = "triangle", rate_hz = 0.83, free = true}
			p.mods = [{source = "lfo1", dest = "osc1.width", amount = 0.25}, {source = "lfo2", dest = "osc1.width", amount = 0.12},
				{source = "velocity", dest = "cutoff", amount = 0.5}, {source = "macro1", dest = "cutoff", amount = 1.2},
				{source = "macro2", dest = "lfo1.rate", amount = 1.5}, {source = "macro2", dest = "lfo2.rate", amount = 1.5}]
			p.slop = {pitch_cents = 3.0, cutoff_octaves = 0.05}
			p.effects = [{type = "chorus", rate_hz = 0.5, depth_ms = 3.5, delay_ms = 10.0, mix = 0.4},
				{type = "chorus", rate_hz = 0.83, depth_ms = 2.5, delay_ms = 7.0, mix = 0.3},
				{type = "reverb", room = 0.6, damp = 0.5, mix = 0.15}]
		&"GAK_wavetable_pad":
			# The pad, alive: a stacked morph wave with unison, a bright table
			# an octave up, a breath of noise, a slow filter swell on a stages
			# envelope, three free-running LFOs drifting the tone and both
			# wave positions, a dotted echo and a long hall.
			# Macro 1: open the filter. Macro 2: more shimmer.
			p = _new([{shape = "morph", position = 0.55, level = 0.5, stack = 3, stack_cents = 16.0},
				{shape = "table", table = "bright", position = 0.2, semitones = 12.0, level = 0.22},
				{shape = "noise", color = "red", level = 0.03}],
				{type = "lowpass", cutoff_hz = 1300.0, q = 1.2, slope_db = 24.0},
				{attack_s = 0.6, decay_s = 1.0, sustain = 0.85, release_s = 1.6})
			p.unison = 3
			p.detune_cents = 10.0
			p.spread = 0.9
			p.filter2 = {type = "highpass", cutoff_hz = 120.0, q = 0.7}
			p.env2 = {stages = [{time_s = 1.5, level = 1.0, curve = "power", amount = 2.0}, {time_s = 3.0, level = 0.6}], sustain = 1, release_s = 1.5}
			p.lfo1 = {shape = "smooth", rate_hz = 0.25, free = true}
			p.lfo2 = {shape = "triangle", rate_hz = 0.09, free = true}
			p.lfos = [{shape = "triangle", rate_hz = 0.13, free = true}]
			p.mods = [{source = "env2", dest = "cutoff", amount = 1.2}, {source = "lfo1", dest = "cutoff", amount = 0.5},
				{source = "lfo2", dest = "osc1.position", amount = 0.25}, {source = "lfo3", dest = "osc2.position", amount = 0.5},
				{source = "macro1", dest = "cutoff", amount = 1.5}, {source = "macro2", dest = "osc2.level", amount = 0.4}]
			p.effects = [{type = "chorus", rate_hz = 0.4, depth_ms = 4.0, mix = 0.3},
				{type = "delay", time_ms = 750.0, time_sync = "1/4.", feedback = 0.4, damp_hz = 3000.0, mix = 0.15, mode = "pingpong"},
				{type = "reverb", room = 0.9, damp = 0.5, mix = 0.35, predelay_ms = 30.0}]
		&"GAK_vowel_pad":
			# A choir from the vowel table: a stacked voice and a lower one an
			# octave down, each drifting through the vowels at its own pace,
			# voices a little apart from each other (slop), a presence lift,
			# slow vibrato and a large hall. The mod wheel moves the vowels.
			# Macro 1: shift the vowel. Macro 2: brighter.
			p = _new([{shape = "table", table = "vowel", position = 0.5, level = 0.5, stack = 3, stack_cents = 10.0},
				{shape = "table", table = "vowel", position = 0.2, semitones = -12.0, level = 0.35}],
				{type = "lowpass", cutoff_hz = 3500.0, q = 0.7},
				{attack_s = 0.5, decay_s = 0.8, sustain = 0.88, release_s = 1.0})
			p.unison = 2
			p.detune_cents = 6.0
			p.spread = 0.8
			p.filter2 = {type = "bandshelf", cutoff_hz = 2800.0, q = 1.0, gain_db = 3.0}
			p.lfo1 = {shape = "triangle", rate_hz = 0.15, free = true}
			p.lfo2 = {shape = "sine", rate_hz = 0.11, free = true}
			p.lfos = [{shape = "sine", rate_hz = 4.8, delay_s = 0.6}]
			p.mods = [{source = "lfo1", dest = "osc1.position", amount = 0.45}, {source = "lfo2", dest = "osc2.position", amount = 0.4},
				{source = "lfo3", dest = "pitch", amount = 0.06}, {source = "mod_wheel", dest = "osc1.position", amount = 0.5},
				{source = "macro1", dest = "osc.position", amount = 0.4}, {source = "macro2", dest = "cutoff", amount = 1.0}]
			p.slop = {pitch_cents = 6.0, env_time = 0.15}
			p.effects = [{type = "chorus", rate_hz = 0.3, depth_ms = 3.0, mix = 0.3},
				{type = "reverb", room = 0.88, damp = 0.5, mix = 0.35, predelay_ms = 25.0}]
		&"GAK_organ":
			# A drawbar organ: seven sine drawbars (16' to 1'), a third-harmonic
			# percussion that fades, a key click, a rotary speaker from a
			# free-running LFO (level, pan and a little pitch), and a tube's drive.
			# Macro 1: the upper drawbars out (a brighter registration).
			# Macro 2: the rotor from slow to fast.
			p = _new([{shape = "sine", semitones = -12.0, level = 0.3}, {shape = "sine", level = 0.5},
				{shape = "sine", semitones = 7.02, level = 0.25}, {shape = "sine", semitones = 12.0, level = 0.3},
				{shape = "sine", semitones = 19.02, level = 0.0}, {shape = "sine", semitones = 24.0, level = 0.0},
				{shape = "sine", semitones = 36.0, level = 0.0},
				{shape = "sine", semitones = 19.02, level = 0.3, level_env = 2},
				{shape = "noise", level = 0.12, level_env = 3}],
				{type = "lowpass", cutoff_hz = 7000.0, q = 0.5},
				{attack_s = 0.005, decay_s = 0.05, sustain = 1.0, release_s = 0.04})
			p.env2 = {attack_s = 0.0, decay_s = 0.25, sustain = 0.0, release_s = 0.1, curve = "exp"}
			p.env3 = {attack_s = 0.0, decay_s = 0.008, sustain = 0.0, release_s = 0.01, curve = "exp"}
			p.lfo1 = {shape = "sine", rate_hz = 0.8, free = true}
			p.mods = [{source = "lfo1", dest = "amp", amount = 0.08}, {source = "lfo1", dest = "pan", amount = 0.25},
				{source = "lfo1", dest = "pitch", amount = 0.04},
				{source = "macro1", dest = "osc5.level", amount = 0.25}, {source = "macro1", dest = "osc6.level", amount = 0.25},
				{source = "macro1", dest = "osc7.level", amount = 0.2}, {source = "macro2", dest = "lfo1.rate", amount = 3.0}]
			p.velocity_sens = 0.0
			p.effects = [{type = "saturate", drive_db = 6.0, tone_hz = 6000.0, mix = 0.4},
				{type = "chorus", rate_hz = 0.8, depth_ms = 1.0, delay_ms = 2.0, mix = 0.25},
				{type = "eq", low_db = 1.0, low_hz = 120.0},
				{type = "reverb", room = 0.5, damp = 0.5, mix = 0.12}]
		&"GAK_fm_epiano":
			# A two-pair FM electric piano in the DX7 manner: a body pair whose
			# modulator fades with its own envelope and bites harder with
			# velocity, and a tine pair (ratio 14) that pings at the start and
			# thins out up the keyboard, slightly detuned against the body; a
			# chorus and a small room. Macro 1: stereo tremolo. Macro 2: bark.
			p = _new([{shape = "sine", level = 0.6, fm_from = 2, fm_index = 1.3},
				{shape = "sine", level = 0.0, ratio = 1.0, level_env = 2, velocity_sens = 0.8},
				{shape = "sine", level = 0.32, ratio = 1.0, cents = 4.0, fm_from = 4, fm_index = 2.0},
				{shape = "sine", level = 0.0, ratio = 14.0, level_env = 3, velocity_sens = 0.9,
					key_scaling = {break_key = 60, left_db_oct = 0.0, right_db_oct = -4.0, left_curve = "lin", right_curve = "lin"}}],
				{type = "off"}, {attack_s = 0.001, decay_s = 3.0, sustain = 0.1, release_s = 0.3, curve = "exp"})
			p.env2 = {attack_s = 0.0, decay_s = 1.2, sustain = 0.15, release_s = 0.3, curve = "exp"}
			p.env3 = {attack_s = 0.0, decay_s = 0.06, sustain = 0.0, release_s = 0.1, curve = "exp"}
			p.lfo1 = {shape = "sine", rate_hz = 4.5, free = true}
			p.mods = [{source = "velocity", dest = "osc1.fm", amount = 1.0}, {source = "macro2", dest = "osc1.fm", amount = 1.5},
				{source = "lfo1", dest = "pan", amount = 0.5, via = "macro1"}]
			p.velocity_sens = 0.7
			p.key_levels = [[36, 1.0], [60, 0.0], [96, -3.0]]
			p.effects = [{type = "chorus", rate_hz = 0.6, depth_ms = 2.5, delay_ms = 8.0, mix = 0.25},
				{type = "eq", mid_db = 1.5, mid_hz = 900.0, mid_q = 0.8},
				{type = "reverb", room = 0.45, damp = 0.5, mix = 0.12}]
		&"GAK_fm_bell":
			# A bell with depth: two inharmonic FM pairs (3.5 and 5.19) each
			# with its own fading brightness, the second detuned so they beat,
			# a hum an octave below, placed apart in stereo, a dotted echo and a
			# hall. Velocity makes it more metallic. Macro 1: more metal.
			# Macro 2: more hum.
			p = _new([{shape = "sine", level = 0.5, pan = -0.2, fm_from = 2, fm_index = 1.5},
				{shape = "sine", level = 0.0, ratio = 3.5, level_env = 2},
				{shape = "sine", level = 0.28, pan = 0.3, cents = 7.0, fm_from = 4, fm_index = 2.5},
				{shape = "sine", level = 0.0, ratio = 5.19, level_env = 3},
				{shape = "sine", ratio = 0.5, level = 0.15}],
				{type = "off"}, {attack_s = 0.001, decay_s = 4.0, sustain = 0.0, release_s = 2.0, curve = "exp"})
			p.env2 = {attack_s = 0.0, decay_s = 1.5, sustain = 0.1, release_s = 1.0, curve = "exp"}
			p.env3 = {attack_s = 0.0, decay_s = 0.4, sustain = 0.0, release_s = 0.5, curve = "exp"}
			p.mods = [{source = "velocity", dest = "osc1.fm", amount = 1.5}, {source = "macro1", dest = "osc1.fm", amount = 2.0},
				{source = "macro1", dest = "osc3.fm", amount = 1.5}, {source = "macro2", dest = "osc5.level", amount = 0.3}]
			p.velocity_sens = 0.5
			p.effects = [{type = "delay", time_ms = 750.0, time_sync = "1/4.", feedback = 0.3, damp_hz = 3500.0, mix = 0.12, mode = "pingpong"},
				{type = "reverb", room = 0.85, damp = 0.45, mix = 0.3, predelay_ms = 20.0}]
		&"GAK_ring_bell":
			# A metallophone, gamelan-like: two ring-modulated partials (2.76
			# and 5.4), a fundamental paired with a twin a few cents away so
			# they beat (ombak), a mallet strike of noise and a bright overtone
			# that die at once, and a hall. Macro 1: more of the high partial.
			# Macro 2: a different metal (the ring partial moves).
			p = _new([{shape = "sine", level = 0.5, ring_from = 2}, {shape = "sine", level = 0.0, semitones = 12.0 * log(2.76) / log(2.0)},
				{shape = "sine", level = 0.28, cents = 6.0, pan = -0.3}, {shape = "sine", level = 0.25, cents = -6.0, pan = 0.3},
				{shape = "sine", level = 0.18, ring_from = 6}, {shape = "sine", level = 0.0, semitones = 12.0 * log(5.4) / log(2.0)},
				{shape = "triangle", semitones = 24.0, level = 0.08, level_env = 3}, {shape = "noise", level = 0.12, level_env = 3}],
				{type = "lowpass", cutoff_hz = 9000.0, q = 0.7},
				{attack_s = 0.001, decay_s = 3.0, sustain = 0.0, release_s = 1.5, curve = "exp"})
			p.env3 = {attack_s = 0.0, decay_s = 0.012, sustain = 0.0, release_s = 0.02, curve = "exp"}
			p.mods = [{source = "macro1", dest = "osc5.level", amount = 0.3}, {source = "macro2", dest = "osc2.pitch", amount = 3.0}]
			p.velocity_sens = 0.6
			p.effects = [{type = "eq", low_db = -1.0, low_hz = 150.0, high_db = 1.0, high_hz = 5000.0},
				{type = "reverb", room = 0.8, damp = 0.45, mix = 0.3, predelay_ms = 15.0}]
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


## msfa's algorithm table (fm_core.cc, Dexed, Apache-2.0): per algorithm, six
## operators' bus flags in the order msfa runs them (OP6 first). Bits: out bus
## 1/2 (0x01, 0x02), add to it (0x04), in bus 1/2 (0x10, 0x20), feedback (0xc0).
const DX7_ALGORITHMS := [
	[0xc1, 0x11, 0x11, 0x14, 0x01, 0x14], [0x01, 0x11, 0x11, 0x14, 0xc1, 0x14], [0xc1, 0x11, 0x14, 0x01, 0x11, 0x14],
	[0xc1, 0x11, 0x94, 0x01, 0x11, 0x14], [0xc1, 0x14, 0x01, 0x14, 0x01, 0x14], [0xc1, 0x94, 0x01, 0x14, 0x01, 0x14],
	[0xc1, 0x11, 0x05, 0x14, 0x01, 0x14], [0x01, 0x11, 0xc5, 0x14, 0x01, 0x14], [0x01, 0x11, 0x05, 0x14, 0xc1, 0x14],
	[0x01, 0x05, 0x14, 0xc1, 0x11, 0x14], [0xc1, 0x05, 0x14, 0x01, 0x11, 0x14], [0x01, 0x05, 0x05, 0x14, 0xc1, 0x14],
	[0xc1, 0x05, 0x05, 0x14, 0x01, 0x14], [0xc1, 0x05, 0x11, 0x14, 0x01, 0x14], [0x01, 0x05, 0x11, 0x14, 0xc1, 0x14],
	[0xc1, 0x11, 0x02, 0x25, 0x05, 0x14], [0x01, 0x11, 0x02, 0x25, 0xc5, 0x14], [0x01, 0x11, 0x11, 0xc5, 0x05, 0x14],
	[0xc1, 0x14, 0x14, 0x01, 0x11, 0x14], [0x01, 0x05, 0x14, 0xc1, 0x14, 0x14], [0x01, 0x14, 0x14, 0xc1, 0x14, 0x14],
	[0xc1, 0x14, 0x14, 0x14, 0x01, 0x14], [0xc1, 0x14, 0x14, 0x01, 0x14, 0x04], [0xc1, 0x14, 0x14, 0x14, 0x04, 0x04],
	[0xc1, 0x14, 0x14, 0x04, 0x04, 0x04], [0xc1, 0x05, 0x14, 0x01, 0x14, 0x04], [0x01, 0x05, 0x14, 0xc1, 0x14, 0x04],
	[0x04, 0xc1, 0x11, 0x14, 0x01, 0x14], [0xc1, 0x14, 0x01, 0x14, 0x04, 0x04], [0x04, 0xc1, 0x11, 0x14, 0x04, 0x04],
	[0xc1, 0x14, 0x04, 0x04, 0x04, 0x04], [0xc4, 0x04, 0x04, 0x04, 0x04, 0x04],
]


## A DX7 algorithm (1..32) as an operator graph: {carriers: [operator numbers],
## mods: {operator: [its modulators]}, feedback: the operator that feeds back
## on itself (0: none)}, worked out by running msfa's buses: an operator hears
## whatever its input bus holds when it runs, and replaces (or adds to) its
## output bus. Operator N is oscillator N of a converted patch.
static func dx7_algorithm(n: int) -> Dictionary:
	var flags: Array = DX7_ALGORITHMS[clampi(n, 1, 32) - 1]
	var bus := [[], [], []]
	var carriers := []
	var mods := {}
	var fb := 0
	for i in 6:
		var f: int = flags[i]
		var op := 6 - i
		var inbus := (f >> 4) & 3
		var outbus := f & 3
		mods[op] = (bus[inbus] as Array).duplicate() if inbus != 0 else []
		if (f & 0xc0) == 0xc0:
			fb = op
		if outbus == 0:
			carriers.append(op)
		elif f & 0x04:
			(bus[outbus] as Array).append(op)
		else:
			bus[outbus] = [op]
	carriers.sort()
	return {carriers = carriers, mods = mods, feedback = fb}
