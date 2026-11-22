# SPDX-License-Identifier: Apache-2.0
@tool
## A synth patch: oscillators, a filter, three envelopes, two LFOs, a
## modulation matrix and voice settings, as readable text.
##
##   oscillators = [{shape = "saw", level = 0.8}, {shape = "square", semitones = -12.0, level = 0.4}]
##   filter = {type = "lowpass", cutoff_hz = 900.0, q = 1.2}
##   env2 = {attack_s = 0.0, decay_s = 0.3, sustain = 0.0, curve = "exp"}
##   mods = [{source = "env2", dest = "cutoff", amount = 3.0}, {source = "lfo1", dest = "pitch", amount = 0.15}]
##
## Play it live with an `AKSynthStream` (native core), bake notes with
## `AKSynth.render_notes`, or use it in a recipe through the `patch` voice.
## Live and baked go through the same engine, so they match.
##
## Oscillators (up to 8), each {shape, level, semitones, cents, width,
## position, fm_from, fm_index, sync_to, ring_from, table}: shape is sine,
## triangle, saw, square, pulse (`width`), noise, morph (`position` 0 sine ..
## 0.33 triangle .. 0.66 saw .. 1 square), or table (a wavetable, `table` =
## a built-in name or frames, see AKWavetables; `position` sweeps its
## frames). `fm_from` (1-based, 0 = none) phase-modulates this oscillator by
## another one's output, `fm_index` radians deep; `sync_to` restarts its
## cycle whenever that oscillator's does (hard sync); `ring_from` multiplies
## it by that oscillator (ring modulation). An oscillator listening to itself
## or an earlier one hears its previous sample (feedback). `level` 0 makes a
## pure modulator. FM graphs (docs/synth.md, Operators): `fm` = [{from,
## index}, ...] (several modulators), `feedback` (radians, on the average of
## the last two outputs), `level_env` (the oscillator's own envelope, 1-based),
## `ratio`, `fixed_hz`, `dx7_freq` (a DX7 operator's mode, coarse, fine,
## detune), `velocity_sens`, `key_scaling`.
##
## Filter {type, cutoff_hz, q, slope_db} for the state-variable types, or
## type "ladder" {cutoff_hz, resonance 0..1 (1 rings on its own), drive}:
## a four-pole (24 dB) ladder that saturates as it's driven; its `poles` (1..4)
## take the lowpass after fewer poles, `pole_mix` ([input, pole 1 .. pole 4]
## weights) makes highpasses, bandpasses and the rest from it. Type "mix"
## blends the state-variable outputs (`low`, `band`, `high`); "lowshelf",
## "highshelf", "bandshelf" boost or cut by `gain_db`. `pre_filter` =
## {lowpass_hz, highpass_hz}: one-pole filters before it.
##
## Envelopes {attack_s, decay_s, sustain, release_s, curve}: `amp_env` sets
## the level; `env2` and `env3` are free for the matrix. Attack is linear (0 =
## instant), decay linear or "exp" (a time constant toward sustain), release
## a time constant from wherever the level is when the note ends. An envelope
## can instead have `stages` ({time_s, level, curve}, with a `sustain` stage,
## a `loop`, release stages after the sustain, per-note time and level
## scaling), or be `mode = "dx7"` (a DX7 operator's rates, levels and scaling,
## exactly as msfa runs them). `envelopes` adds env4 to env8 for the matrix.
## See docs/synth.md.
##
## LFOs {shape, rate_hz, delay_s}: sine, triangle, saw, square, random
## (sample and hold), smooth or custom (`points`, one cycle, `interp` linear or
## step, `once`: hold the last point after one cycle), restarted on every note;
## `delay_s` fades them in. lfo3 and lfo4 are two more.
## `rate_sync` ("1/8", "1/8.", "1/8t", or beats) sets the rate from the tempo.
##
## Tempo: `tempo_bpm` (120) unless the player sets one (AKSynthStream.set_tempo,
## a {time_s, tempo_bpm} entry in render_notes). Tempo-synced LFOs, the delay
## effect's `time_sync` and the arpeggiator follow it.
##
## Arpeggiator: `arp` = {mode: up|down|updown|random, octaves 1..4, rate (a
## note length, "1/16"), gate 0..1 (1 ties notes together), on}. Held keys
## become the chord, played one note per step from the first key down.
##
## Matrix rows {source, dest, amount}. Sources: env1 (the amp envelope),
## env2, env3, lfo1, lfo2, velocity (0..1), key (octaves from middle C),
## mod_wheel, aftertouch (0..1), random (-1..1, new per note), bend (-1..1).
## Destinations and units: pitch (semitones), cutoff (octaves), q (octaves),
## amp (adds to a gain of 1), pan, and per oscillator oscN.pitch
## (semitones), oscN.level, oscN.fm (radians), oscN.width, oscN.position;
## "osc.<x>" means every oscillator.
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKPatch
extends Resource

const SHAPES := ["sine", "triangle", "saw", "square", "pulse", "noise", "morph", "table"]
const FILTERS := ["off", "lowpass", "highpass", "bandpass", "notch", "ladder", "mix", "lowshelf", "highshelf", "bandshelf"]
const LFO_SHAPES := ["sine", "triangle", "saw", "square", "random", "smooth", "custom"]
## How an oscillator's `fm_from` and `fm` modulators move it: phase modulation (radians), its pitch
## (semitones per unit of the modulator), or its frequency (Hz per unit, through zero).
const FM_MODES := ["phase", "pitch", "linear"]
# Newer sources and destinations come last so the older ones keep their numbers.
const SOURCES := ["env1", "env2", "env3", "lfo1", "lfo2", "velocity", "key", "mod_wheel", "aftertouch", "random", "bend",
	"env4", "env5", "env6", "env7", "env8", "lfo3", "lfo4"]
const DESTS := ["pitch", "cutoff", "q", "amp", "pan", "osc.pitch", "osc.level", "osc.fm", "osc.width", "osc.position",
	"lfo1.rate", "lfo2.rate", "lfo3.rate", "lfo4.rate"]
## Points in a custom LFO shape.
const MAX_POINTS := 256
## Voice slots (voice_pan, slop) taken in turn by new voices.
const MAX_SLOTS := 32
## The comb's longest period, in samples (12 Hz at 48 kHz).
const COMB_MAX := 4096
const MODES := ["poly", "mono", "legato"]
const ARP_MODES := ["up", "down", "updown", "random"]
const CATEGORIES := ["bass", "lead", "pad", "keys", "pluck", "bell", "strings", "brass", "organ", "fx", "voice", "other"]
const MAX_OSC := 8
const MAX_UNISON := 8
## Copies of one oscillator in each unison voice (an oscillator's `stack`).
const MAX_STACK := 8
const MAX_MODS := 16
const MAX_POLY := 32
## Envelopes per patch: amp_env, env2, env3 and up to five in `envelopes`.
const MAX_ENV := 8
## Stages per envelope (after delay_s and hold_s become stages).
const MAX_STAGES := 32
const CURVES := ["linear", "power", "hold", "exp"]
## How far an "exp" stage curves without an `amount`: power -5.
const EXP_AMOUNT := 5.0

## What kind of instrument this is, for the Sound Lab's preset browser
## (one of CATEGORIES, or anything else). Doesn't affect the sound.
@export var category := ""
## Up to eight oscillators: {shape, level, semitones, cents, width, position, fm_from, fm_index, pan,
## filtered (false: around the filter, straight to the amp), stack and stack_cents (this
## oscillator alone copied 1-8 times, detuned across stack_cents, inside each unison voice)}.
@export var oscillators: Array[Dictionary] = [{shape = "saw", level = 0.7}]
## Every oscillator stacked this many times, detuned across `detune_cents`.
@export_range(1, 8) var unison := 1
@export_range(0.0, 100.0) var detune_cents := 0.0
## Semitones the odd-numbered unison voices (the 2nd, 4th ...) sit above the
## others: 12 an octave, 7 a fifth, negative below.
@export_range(-24.0, 24.0) var unison_pitch := 0.0
## The stacked unison voices' level against the middle one (or two): 1 = all
## equal, lower for a quieter shimmer around a solid centre.
@export_range(0.0, 1.0) var unison_level := 1.0
## How far the unison voices spread across the stereo field (0 = mono).
@export_range(0.0, 1.0) var spread := 0.0
## {type: off|lowpass|highpass|bandpass|notch, cutoff_hz, q, slope_db: 12|24}.
@export var filter := {type = "lowpass", cutoff_hz = 18000.0, q = 0.707, slope_db = 12.0}
## The level envelope: {attack_s, decay_s, sustain, release_s, curve: linear|exp}. Optional second
## release stage: once the release falls to `release_knee` (0..1, a share of the level at key-up) it
## goes on with the time constant `release2_s` (a fast drop, then a quiet tail).
@export var amp_env := {attack_s = 0.005, decay_s = 0.2, sustain = 0.7, release_s = 0.15}
## A free envelope for the matrix.
@export var env2 := {attack_s = 0.0, decay_s = 0.3, sustain = 0.0, release_s = 0.2, curve = "exp"}
## Another free envelope.
@export var env3 := {attack_s = 0.0, decay_s = 0.5, sustain = 0.0, release_s = 0.2, curve = "exp"}
## More envelopes for the matrix: env4, env5 ... env8, in order. Each is an ADSR, a stages envelope or a
## dx7 envelope, as amp_env.
@export var envelopes: Array[Dictionary] = []
## {shape: sine|triangle|saw|square|random, rate_hz, delay_s, width (square: the part of a cycle it's high),
## phase (where each note starts it, in cycles), free (true: it runs from the start of playback rather than
## from each note-on, so every note picks it up where it is, as a hardware LFO or chorus does; phase is then
## its place at the start of playback; lfoN.rate rows still bend it per voice)}.
@export var lfo1 := {shape = "sine", rate_hz = 5.0, delay_s = 0.0}
@export var lfo2 := {shape = "triangle", rate_hz = 0.5, delay_s = 0.0}
## Two more LFOs, as lfo1 (empty: not running).
@export var lfo3 := {}
@export var lfo4 := {}
## One-pole filters on the filtered oscillators before the main filter: {lowpass_hz, highpass_hz} (absent: off).
@export var pre_filter := {}
## A comb tuned to the note, on the filtered oscillators before the filters: {semitones, cents, feedback
## (-0.99..0.99)}. Each sample adds feedback x the output one period (of the note moved by semitones and
## cents) back. Empty: off.
@export var comb := {}
## The pan of each voice slot (-1..1): new voices take the slots in turn.
@export var voice_pan: Array = []
## Each voice slot's own fixed offsets, within +- these (seeded by `seed`): {pitch_cents, cutoff_octaves,
## env_time (every envelope's times x 1 +- this), level_db}. The slots are voice_pan's, or 8.
@export var slop := {}
## Modulation matrix rows: {source, dest, amount}.
@export var mods: Array[Dictionary] = []
## poly, mono (one voice, envelopes restart on each note) or legato (one
## voice, envelopes carry on while notes overlap).
@export_enum("poly", "mono", "legato") var mode := "poly"
@export_range(1, 32) var polyphony := 8
## Portamento time constant: how fast the pitch moves to a new note (0 = jump).
@export_range(0.0, 2.0) var glide_s := 0.0
## Semitones the pitch bend reaches at full bend.
@export_range(0.0, 24.0) var bend_range := 2.0
## How much velocity scales the level (0 = not at all, 1 = fully).
@export_range(0.0, 1.0) var velocity_sens := 0.5
## How velocity maps to level: 1 linear (velocity 64 is 6 dB down at full
## sensitivity), 2 squared (12 dB), below 1 gentler.
@export_range(0.25, 4.0) var velocity_curve := 1.0
## Level by key: [[key, dB], ...] in key order, joined by straight lines in
## dB and held flat past the ends. Empty: the same level on every key.
@export var key_levels: Array = []
@export var gain_db := 0.0
@export_range(-1.0, 1.0) var pan := 0.0
## Seeds noise, unison phases and the random source; same seed, same sound.
@export var seed := 0
## The tempo, in beats per minute, when the player sets none: tempo-synced
## LFOs (`rate_sync`), a delay's `time_sync` and the arpeggiator follow it.
@export_range(20.0, 400.0) var tempo_bpm := 120.0
## The arpeggiator: {mode: up|down|updown|random, octaves (1..4), rate (a note
## length: "1/16", "1/8.", "1/8t", or beats), gate (0..1 of each step; 1 ties
## the notes), on (true)}. Empty: off. Held keys form the chord; it starts on
## the first key down and plays one note per step, at that key's velocity.
@export var arp := {}
## Effects on the patch's output, in order (see AKStreamFx): chorus,
## flanger, phaser, eq, compressor, saturate. They are part of the sound, so
## they bake, and the same effects exist as Godot bus effects (AKChorus ...).
@export var effects: Array[Dictionary] = []


## Everything that affects the sound, for hashing (AK.bake_key).
func describe() -> Dictionary:
	var d := {engine = AKSynthCore.VERSION, oscillators = oscillators, unison = unison, detune_cents = detune_cents,
		spread = spread, filter = filter, amp_env = amp_env, env2 = env2, env3 = env3, lfo1 = lfo1, lfo2 = lfo2, mods = mods,
		mode = mode, polyphony = polyphony, glide_s = glide_s, bend_range = bend_range,
		velocity_sens = velocity_sens, gain_db = gain_db, pan = pan, seed = seed, effects = effects}
	# Added later: only when set, so existing bakes keep their keys.
	if unison_level != 1.0:
		d.unison_level = unison_level
	if unison_pitch != 0.0:
		d.unison_pitch = unison_pitch
	if velocity_curve != 1.0:
		d.velocity_curve = velocity_curve
	if not key_levels.is_empty():
		d.key_levels = key_levels
	if not envelopes.is_empty():
		d.envelopes = envelopes
	if tempo_bpm != 120.0:
		d.tempo_bpm = tempo_bpm
	if not arp.is_empty():
		d.arp = arp
	for k: String in ["lfo3", "lfo4", "pre_filter", "comb", "slop"]:
		if not (get(k) as Dictionary).is_empty():
			d[k] = get(k)
	if not voice_pan.is_empty():
		d.voice_pan = voice_pan
	return d


## The tail after a note ends: five amp-release time constants (of the longer stage, with two); for a
## stages amp envelope, its release stages at their slowest scaling; for a dx7 one, its release from full level.
func tail_s() -> float:
	return env_tail_s(amp_env) + AKStreamFx.tail_s(effects)


## How long an envelope takes to finish after key-off.
static func env_tail_s(e: Dictionary) -> float:
	if String(e.get("mode", "")) == "dx7":
		return AKSynthCore.dx7_release_s(_compile_env(e))
	if e.has("stages"):
		var c := _compile_env(e)
		var t := 0.0
		var times: PackedFloat64Array = c.time
		var sus := int(c.sustain)
		if sus < 0:
			# A one-shot runs its stages whatever the key does.
			for x in times:
				t += x
		elif sus + 1 >= times.size():
			t = 5.0 * float(c.r)
		else:
			for i in range(sus + 1, times.size()):
				t += times[i]
		# The slowest a note can make it: five octaves down the keyboard, the softest velocity.
		var slow := maxf(1.0, pow(2.0, absf(float(c.tk)) * 5.0)) * maxf(1.0, pow(2.0, absf(float(c.tv))))
		return t * slow
	return 5.0 * maxf(float(e.get("release_s", 0.15)), float(e.get("release2_s", 0.0)))


## The patch as plain numbers for the engine (both the native one and
## AKSynthCore): names become indices, defaults are filled, ranges clamped.
## Unknown names are reported and ignored.
func compile() -> Dictionary:
	var osc := []
	var tables := []
	var table_keys := []
	for i in mini(MAX_OSC, oscillators.size()):
		var o: Dictionary = oscillators[i]
		var shape := SHAPES.find(String(o.get("shape", "sine")))
		if shape < 0:
			push_warning("AKPatch: unknown shape '%s'" % o.get("shape"))
			shape = 0
		osc.append({shape = shape, level = float(o.get("level", 1.0)),
			semis = float(o.get("semitones", 0.0)) + float(o.get("cents", 0.0)) / 100.0,
			width = clampf(float(o.get("width", 0.5)), 0.01, 0.99), position = clampf(float(o.get("position", 0.0)), 0.0, 1.0),
			fm_from = clampi(int(o.get("fm_from", 0)), 0, MAX_OSC) - 1, fm_index = float(o.get("fm_index", 0.0)),
			sync = clampi(int(o.get("sync_to", 0)), 0, MAX_OSC) - 1, ring = clampi(int(o.get("ring_from", 0)), 0, MAX_OSC) - 1, table = -1,
			pan = clampf(float(o.get("pan", 0.0)), -1.0, 1.0), filtered = bool(o.get("filtered", true)),
			stack = clampi(int(o.get("stack", 1)), 1, MAX_STACK), stack_cents = float(o.get("stack_cents", 0.0)),
			fm_mode = maxi(0, FM_MODES.find(String(o.get("fm_mode", "phase"))))})
		_compile_operator(o, osc.back())
		if shape == SHAPES.find("table"):
			var spec: Variant = o.get("table", "basic")
			var key := var_to_str(spec)
			var ti := table_keys.find(key)
			if ti < 0:
				ti = tables.size()
				table_keys.append(key)
				tables.append(AKWavetables.build(spec))
			osc.back().table = ti
	var ft := FILTERS.find(String(filter.get("type", "lowpass")))
	if ft < 0:
		push_warning("AKPatch: unknown filter '%s'" % filter.get("type"))
		ft = 0
	var envs := []
	var all_envs: Array = [amp_env, env2, env3]
	all_envs.append_array(envelopes)
	if all_envs.size() > MAX_ENV:
		push_warning("AKPatch: more than %d envelopes; the rest are ignored" % MAX_ENV)
		all_envs.resize(MAX_ENV)
	for e: Dictionary in all_envs:
		envs.append(_compile_env(e))
	var lfos := []
	for l: Dictionary in [lfo1, lfo2, lfo3, lfo4]:
		var ls := LFO_SHAPES.find(String(l.get("shape", "sine")))
		lfos.append({shape = maxi(0, ls), rate_hz = maxf(0.0, float(l.get("rate_hz", 1.0))), delay_s = maxf(0.0, float(l.get("delay_s", 0.0))),
			width = clampf(float(l.get("width", 0.5)), 0.01, 0.99), phase = float(l.get("phase", 0.0)), free = bool(l.get("free", false)),
			beats = sync_beats(l.get("rate_sync", 0.0))})
		if ls == LFO_SHAPES.find("custom"):
			var pts := PackedFloat64Array()
			for v: Variant in l.get("points", []):
				if pts.size() < MAX_POINTS:
					pts.append(clampf(float(v), -1.0, 1.0))
			while pts.size() < 2:
				pts.append(0.0)
			lfos.back().merge({points = pts, interp = 1 if String(l.get("interp", "linear")) == "step" else 0, once = bool(l.get("once", false))}, true)
		if String(l.get("mode", "")) == "dx7":
			# A DX7 LFO (msfa lfo.cc): raw 0..99 values; as a source, msfa's pitch modulation in octaves.
			lfos.back().merge({dx7 = true, speed = clampi(int(l.get("speed", 35)), 0, 99), delay = clampi(int(l.get("delay", 0)), 0, 99),
				wave = clampi(int(l.get("wave", 0)), 0, 5), sync = bool(l.get("sync", true)),
				pmd = clampi(int(l.get("pitch_mod_depth", 0)), 0, 99), pms = clampi(int(l.get("pitch_mod_sens", 0)), 0, 7),
				amd = clampi(int(l.get("amp_mod_depth", 0)), 0, 99)}, true)
	var rows := []
	for m in mods:
		if rows.size() >= MAX_MODS:
			push_warning("AKPatch: more than %d mod rows; the rest are ignored" % MAX_MODS)
			break
		var src := SOURCES.find(String(m.get("source", "")))
		var dest := String(m.get("dest", ""))
		var target := -1
		if dest.begins_with("osc"):
			var dot := dest.find(".")
			var num := dest.substr(3, dot - 3)
			target = num.to_int() - 1 if num != "" else -1
			dest = "osc" + dest.substr(dot)
		var dst := DESTS.find(dest)
		if src < 0 or dst < 0 or target >= MAX_OSC:
			push_warning("AKPatch: mod row %s doesn't name a known source and destination" % [m])
			continue
		rows.append({src = src, dst = dst, osc = target, amount = float(m.get("amount", 0.0))})
	var out := {osc = osc, tables = tables, unison = clampi(unison, 1, MAX_UNISON), detune_cents = detune_cents, spread = clampf(spread, 0.0, 1.0),
		unison_level = clampf(unison_level, 0.0, 1.0), unison_pitch = clampf(unison_pitch, -24.0, 24.0), vel_curve = clampf(velocity_curve, 0.25, 4.0), key_lv = _key_levels(),
		resonance = clampf(float(filter.get("resonance", 0.3)), 0.0, 1.2), drive = maxf(0.05, float(filter.get("drive", 1.0))),
		filter_type = ft, cutoff_hz = float(filter.get("cutoff_hz", 18000.0)), q = maxf(0.05, float(filter.get("q", 0.707))),
		stages = 2 if float(filter.get("slope_db", 12.0)) >= 24.0 else 1,
		env = envs, lfo = lfos, mods = rows,
		mode = maxi(0, MODES.find(mode)), poly = clampi(polyphony, 1, MAX_POLY), glide_s = maxf(0.0, glide_s),
		bend_range = bend_range, vel_sens = clampf(velocity_sens, 0.0, 1.0), gain = db_to_linear(gain_db),
		pan = clampf(pan, -1.0, 1.0), seed = seed, effects = effects.map(func(e: Dictionary) -> Dictionary: return AKStreamFx.compile(e)),
		tempo_bpm = clampf(tempo_bpm, 20.0, 400.0), arp = _compile_arp(),
		n_lfo = 4 if not (lfo3.is_empty() and lfo4.is_empty()) else 2}
	_compile_filter_extras(out)
	_compile_voice_extras(out)
	return out


## The newer filter fields: the ladder's poles and pole mix, the state-variable mix weights, the
## shelves' gain, the pre-filter, the comb. Absent, the filter runs as before.
func _compile_filter_extras(out: Dictionary) -> void:
	out.poles = clampf(float(filter.get("poles", 4.0)), 1.0, 4.0)
	var pm := PackedFloat64Array()
	var src: Variant = filter.get("pole_mix", [])
	if src is Array and (src as Array).size() > 0:
		for i in 5:
			pm.append(float(src[i]) if i < (src as Array).size() else 0.0)
	out.pole_mix = pm
	out.f_low = float(filter.get("low", 1.0))
	out.f_band = float(filter.get("band", 0.0))
	out.f_high = float(filter.get("high", 0.0))
	out.gain_db = clampf(float(filter.get("gain_db", 0.0)), -48.0, 48.0)
	out.pre_lp_hz = maxf(0.0, float(pre_filter.get("lowpass_hz", 0.0)))
	out.pre_hp_hz = maxf(0.0, float(pre_filter.get("highpass_hz", 0.0)))
	out.comb_on = not comb.is_empty()
	out.comb_semis = float(comb.get("semitones", 0.0)) + float(comb.get("cents", 0.0)) / 100.0
	out.comb_fb = clampf(float(comb.get("feedback", 0.0)), -0.99, 0.99)


## Voice slots: each one's pan and slop offsets.
func _compile_voice_extras(out: Dictionary) -> void:
	var vp := PackedFloat64Array()
	for v: Variant in voice_pan:
		if vp.size() < MAX_SLOTS:
			vp.append(clampf(float(v), -1.0, 1.0))
	out.voice_pan = vp
	out.slots = vp.size() if vp.size() > 0 else (8 if not slop.is_empty() else 0)
	out.slop_pitch = maxf(0.0, float(slop.get("pitch_cents", 0.0))) / 100.0
	out.slop_cut = maxf(0.0, float(slop.get("cutoff_octaves", 0.0)))
	out.slop_time = clampf(float(slop.get("env_time", 0.0)), 0.0, 0.9)
	out.slop_level = maxf(0.0, float(slop.get("level_db", 0.0)))


## The arpeggiator as numbers: {on, mode, octaves, beats, gate}.
func _compile_arp() -> Dictionary:
	var m := ARP_MODES.find(String(arp.get("mode", "up")))
	if m < 0:
		push_warning("AKPatch: unknown arp mode '%s'" % arp.get("mode"))
		m = 0
	var beats := sync_beats(arp.get("rate", "1/16"))
	return {on = not arp.is_empty() and bool(arp.get("on", true)) and beats > 0.0, mode = m,
		octaves = clampi(int(arp.get("octaves", 1)), 1, 4), beats = beats, gate = clampf(float(arp.get("gate", 0.5)), 0.01, 1.0)}


## A note length in beats (a beat is a quarter note): "1/4" 1, "1/8" 0.5,
## "1/8." (dotted) 0.75, "1/8t" (triplet) 1/3, "2/1" 8; a number is beats
## already. 0 for anything else.
static func sync_beats(v: Variant) -> float:
	if v is float or v is int:
		return maxf(0.0, float(v))
	var t := String(v).strip_edges().to_lower()
	if t.is_empty():
		return 0.0
	var mul := 1.0
	if t.ends_with("."):
		mul = 1.5
		t = t.left(-1)
	elif t.ends_with("t"):
		mul = 2.0 / 3.0
		t = t.left(-1)
	var parts := t.split("/")
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float() or float(parts[1]) <= 0.0:
		push_warning("AKPatch: '%s' isn't a note length" % v)
		return 0.0
	return maxf(0.0, 4.0 * float(parts[0]) / float(parts[1]) * mul)


## An oscillator's operator fields (phase 2), added to its compiled entry.
## Without them the entry runs as before.
static func _compile_operator(o: Dictionary, c: Dictionary) -> void:
	var src := PackedInt64Array()
	var amt := PackedFloat64Array()
	var fm: Variant = o.get("fm", [])
	if fm is Array:
		for m: Variant in fm:
			if m is Dictionary:
				var f := int((m as Dictionary).get("from", 0))
				if f >= 1 and f <= MAX_OSC:
					src.append(f - 1)
					amt.append(float((m as Dictionary).get("index", 0.0)))
	c.fm_src = src
	c.fm_amt = amt
	c.feedback = float(o.get("feedback", 0.0))
	c.ratio = maxf(0.0, float(o.get("ratio", 1.0)))
	c.fixed_hz = maxf(0.0, float(o.get("fixed_hz", 0.0)))
	var dx: Variant = o.get("dx7_freq", null)
	c.dx_mode = -1
	if dx is Dictionary:
		# Raw 7-bit values, unclamped beyond that, as msfa uses them (a factory voice has fine 100).
		c.dx_mode = clampi(int(dx.get("mode", 0)), 0, 1)
		c.dx_coarse = clampi(int(dx.get("coarse", 1)), 0, 127)
		c.dx_fine = clampi(int(dx.get("fine", 0)), 0, 127)
		c.dx_detune = clampi(int(dx.get("detune", 7)), 0, 127)
	c.level_env = clampi(int(o.get("level_env", 0)), 0, MAX_ENV) - 1
	c.vel_sens = clampf(float(o.get("velocity_sens", 0.0)), 0.0, 1.0)
	var ks: Variant = o.get("key_scaling", null)
	c.ks = ks is Dictionary
	if ks is Dictionary:
		c.ks_break = float(ks.get("break_key", 60.0))
		c.ks_l = float(ks.get("left_db_oct", 0.0))
		c.ks_r = float(ks.get("right_db_oct", 0.0))
		c.ks_lexp = String(ks.get("left_curve", "lin")) == "exp"
		c.ks_rexp = String(ks.get("right_curve", "lin")) == "exp"


## An envelope as numbers. `kind` 0 is today's ADSR (its fields unchanged, so
## old patches compile as before), 1 stages, 2 dx7, 3 dx7_pitch.
static func _compile_env(e: Dictionary) -> Dictionary:
	if String(e.get("mode", "")) == "dx7_pitch":
		var pr: Array = e.get("rates", [])
		var pl: Array = e.get("levels", [])
		var prs := PackedInt64Array()
		var pls := PackedInt64Array()
		for i in 4:
			prs.append(clampi(int(pr[i]) if i < pr.size() else 99, 0, 99))
			pls.append(clampi(int(pl[i]) if i < pl.size() else 50, 0, 99))
		return {kind = 3, rates = prs, levels = pls}
	if String(e.get("mode", "")) == "dx7":
		var ks: Dictionary = e.get("key_scaling", {})
		var r_in: Array = e.get("rates", [])
		var l_in: Array = e.get("levels", [])
		var rates := PackedInt64Array()
		var lvls := PackedInt64Array()
		for i in 4:
			rates.append(clampi(int(r_in[i]) if i < r_in.size() else 99, 0, 99))
			lvls.append(clampi(int(l_in[i]) if i < l_in.size() else 0, 0, 99))
		return {kind = 2, rates = rates, levels = lvls, ol = clampi(int(e.get("output_level", 99)), 0, 99),
			rs = clampi(int(e.get("rate_scaling", 0)), 0, 7), vs = clampi(int(e.get("velocity_sens", 0)), 0, 7),
			bp = clampi(int(ks.get("break_point", 39)), 0, 99), ld = clampi(int(ks.get("left_depth", 0)), 0, 99),
			rd = clampi(int(ks.get("right_depth", 0)), 0, 99), lc = clampi(int(ks.get("left_curve", 0)), 0, 3),
			rc = clampi(int(ks.get("right_curve", 0)), 0, 3), ams = clampi(int(e.get("amp_mod_sens", 0)), 0, 3),
			ko = int(e.get("key_offset", 0))}
	if e.has("stages"):
		return _compile_stages(e)
	return {kind = 0, a = maxf(0.0, float(e.get("attack_s", 0.0))), d = maxf(1e-4, float(e.get("decay_s", 0.2))),
		s = clampf(float(e.get("sustain", 0.0)), 0.0, 1.0), r = maxf(1e-4, float(e.get("release_s", 0.15))),
		r2 = maxf(0.0, float(e.get("release2_s", 0.0))), knee = clampf(float(e.get("release_knee", 0.0)), 0.0, 1.0),
		exp = String(e.get("curve", "linear")) == "exp"}


## A stages envelope as flat arrays. delay_s and hold_s become hold stages;
## stage numbers (sustain, loop, the scaling lists) are moved to match.
static func _compile_stages(e: Dictionary) -> Dictionary:
	var src: Array = e.get("stages", [])
	var time := PackedFloat64Array()
	var lvl := PackedFloat64Array()
	var curve := PackedInt64Array()
	var amount := PackedFloat64Array()
	var where := PackedInt64Array()   # each written stage's index in the compiled list
	var delay := maxf(0.0, float(e.get("delay_s", 0.0)))
	var hold := maxf(0.0, float(e.get("hold_s", 0.0)))
	if delay > 0.0:
		time.append(delay)
		lvl.append(0.0)
		curve.append(2)
		amount.append(0.0)
	for i in src.size():
		var st: Dictionary = src[i] if src[i] is Dictionary else {}
		var name := String(st.get("curve", "linear"))
		var cv := CURVES.find(name)
		if cv < 0:
			push_warning("AKPatch: unknown envelope curve '%s'" % name)
			cv = 0
		var am := float(st.get("amount", 0.0))
		if cv == 3:
			# exp: power bent the other way, landing exactly on time.
			cv = 1
			am = -float(st.get("amount", EXP_AMOUNT))
		where.append(time.size())
		time.append(maxf(0.0, float(st.get("time_s", 0.0))))
		lvl.append(float(st.get("level", 0.0)))
		curve.append(cv)
		amount.append(am)
		if i == 0 and hold > 0.0:
			time.append(hold)
			lvl.append(0.0)
			curve.append(2)
			amount.append(0.0)
	if time.size() > MAX_STAGES:
		push_warning("AKPatch: more than %d envelope stages; the rest are ignored" % MAX_STAGES)
		time.resize(MAX_STAGES)
		lvl.resize(MAX_STAGES)
		curve.resize(MAX_STAGES)
		amount.resize(MAX_STAGES)
	var n := time.size()
	# A hold stage's level is the one it holds: the stage before it ends there.
	for i in n:
		if curve[i] == 2:
			lvl[i] = lvl[i - 1] if i > 0 else float(e.get("start", 0.0))
	var map := func(i: int) -> int:
		return mini(where[clampi(i, 0, where.size() - 1)], n - 1) if where.size() > 0 else -1
	var sus := n - 1
	if e.has("sustain"):
		var s := int(e.sustain)
		sus = -1 if s < 0 else map.call(s)
	var la := -1
	var lb := -1
	var lp: Variant = e.get("loop", [])
	if lp is Array and lp.size() >= 2 and where.size() > 0:
		la = map.call(int(lp[0]))
		lb = map.call(int(lp[1]))
		if lb < la or sus < 0 or lb > sus:
			push_warning("AKPatch: an envelope loop must run forward and end by the sustain stage; ignored")
			la = -1
			lb = -1
	var mask := func(list: Variant) -> int:
		if not (list is Array) or (list as Array).is_empty():
			return (1 << n) - 1
		var m := 0
		for i: Variant in list:
			var j: int = map.call(int(i))
			if j >= 0:
				m |= 1 << j
		return m
	# Stages from `quiet` on all end below silence: a released voice there can finish.
	var quiet := n
	while quiet > 0 and absf(lvl[quiet - 1]) < AKSynthCore.SILENT:
		quiet -= 1
	return {kind = 1, time = time, level = lvl, curve = curve, amount = amount, sustain = sus, loop_a = la, loop_b = lb,
		start = float(e.get("start", 0.0)), r = maxf(1e-4, float(e.get("release_s", 0.15))),
		tk = float(e.get("time_key", 0.0)), tk_center = float(e.get("time_key_center", 60.0)), tk_mask = mask.call(e.get("time_key_stages", [])),
		tv = float(e.get("time_velocity", 0.0)), tv_mask = mask.call(e.get("time_velocity_stages", [])),
		lv = clampf(float(e.get("level_velocity", 0.0)), 0.0, 1.0), quiet = quiet}


## key_levels as [key, gain, key, gain, ...] (linear gains), sorted by key.
func _key_levels() -> PackedFloat64Array:
	var pts := []
	for kv: Variant in key_levels:
		if kv is Array and kv.size() >= 2:
			pts.append([float(kv[0]), float(kv[1])])
	pts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := PackedFloat64Array()
	for kv: Array in pts:
		out.append(kv[0])
		out.append(db_to_linear(kv[1]))
	return out
