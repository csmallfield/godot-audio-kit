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
## Oscillators (up to 4), each {shape, level, semitones, cents, width,
## position, fm_from, fm_index, sync_to, ring_from, table}: shape is sine,
## triangle, saw, square, pulse (`width`), noise, morph (`position` 0 sine ..
## 0.33 triangle .. 0.66 saw .. 1 square), or table (a wavetable, `table` =
## a built-in name or frames, see AKWavetables; `position` sweeps its
## frames). `fm_from` (1-based, 0 = none) phase-modulates this oscillator by
## another one's output, `fm_index` radians deep; `sync_to` restarts its
## cycle whenever that oscillator's does (hard sync); `ring_from` multiplies
## it by that oscillator (ring modulation). An oscillator listening to itself
## or an earlier one hears its previous sample (feedback). `level` 0 makes a
## pure modulator.
##
## Filter {type, cutoff_hz, q, slope_db} for the state-variable types, or
## type "ladder" {cutoff_hz, resonance 0..1 (1 rings on its own), drive}:
## a four-pole (24 dB) ladder that saturates as it's driven.
##
## Envelopes {attack_s, decay_s, sustain, release_s, curve}: `amp_env` sets
## the level; `env2` and `env3` are free for the matrix. Attack is linear (0 =
## instant), decay linear or "exp" (a time constant toward sustain), release
## a time constant from wherever the level is when the note ends.
##
## LFOs {shape, rate_hz, delay_s}: sine, triangle, saw, square or random
## (sample and hold), restarted on every note; `delay_s` fades them in.
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
const FILTERS := ["off", "lowpass", "highpass", "bandpass", "notch", "ladder"]
const LFO_SHAPES := ["sine", "triangle", "saw", "square", "random"]
const SOURCES := ["env1", "env2", "env3", "lfo1", "lfo2", "velocity", "key", "mod_wheel", "aftertouch", "random", "bend"]
const DESTS := ["pitch", "cutoff", "q", "amp", "pan", "osc.pitch", "osc.level", "osc.fm", "osc.width", "osc.position"]
const MODES := ["poly", "mono", "legato"]
const CATEGORIES := ["bass", "lead", "pad", "keys", "pluck", "bell", "strings", "brass", "organ", "fx", "voice", "other"]
const MAX_OSC := 4
const MAX_UNISON := 7
const MAX_MODS := 16
const MAX_POLY := 32

## What kind of instrument this is, for the Sound Lab's preset browser
## (one of CATEGORIES, or anything else). Doesn't affect the sound.
@export var category := ""
## Up to four oscillators: {shape, level, semitones, cents, width, position, fm_from, fm_index, pan}.
@export var oscillators: Array[Dictionary] = [{shape = "saw", level = 0.7}]
## Every oscillator stacked this many times, detuned across `detune_cents`.
@export_range(1, 7) var unison := 1
@export_range(0.0, 100.0) var detune_cents := 0.0
## The stacked unison voices' level against the middle one (or two): 1 = all
## equal, lower for a quieter shimmer around a solid centre.
@export_range(0.0, 1.0) var unison_level := 1.0
## How far the unison voices spread across the stereo field (0 = mono).
@export_range(0.0, 1.0) var spread := 0.0
## {type: off|lowpass|highpass|bandpass|notch, cutoff_hz, q, slope_db: 12|24}.
@export var filter := {type = "lowpass", cutoff_hz = 18000.0, q = 0.707, slope_db = 12.0}
## The level envelope: {attack_s, decay_s, sustain, release_s, curve: linear|exp}.
@export var amp_env := {attack_s = 0.005, decay_s = 0.2, sustain = 0.7, release_s = 0.15}
## A free envelope for the matrix.
@export var env2 := {attack_s = 0.0, decay_s = 0.3, sustain = 0.0, release_s = 0.2, curve = "exp"}
## Another free envelope.
@export var env3 := {attack_s = 0.0, decay_s = 0.5, sustain = 0.0, release_s = 0.2, curve = "exp"}
## {shape: sine|triangle|saw|square|random, rate_hz, delay_s}.
@export var lfo1 := {shape = "sine", rate_hz = 5.0, delay_s = 0.0}
@export var lfo2 := {shape = "triangle", rate_hz = 0.5, delay_s = 0.0}
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
@export var gain_db := 0.0
@export_range(-1.0, 1.0) var pan := 0.0
## Seeds noise, unison phases and the random source; same seed, same sound.
@export var seed := 0
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
	if velocity_curve != 1.0:
		d.velocity_curve = velocity_curve
	return d


## The tail after a note ends: five amp-release time constants.
func tail_s() -> float:
	return 5.0 * float(amp_env.get("release_s", 0.15)) + AKStreamFx.tail_s(effects)


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
			pan = clampf(float(o.get("pan", 0.0)), -1.0, 1.0)})
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
	for e: Dictionary in [amp_env, env2, env3]:
		envs.append({a = maxf(0.0, float(e.get("attack_s", 0.0))), d = maxf(1e-4, float(e.get("decay_s", 0.2))),
			s = clampf(float(e.get("sustain", 0.0)), 0.0, 1.0), r = maxf(1e-4, float(e.get("release_s", 0.15))),
			exp = String(e.get("curve", "linear")) == "exp"})
	var lfos := []
	for l: Dictionary in [lfo1, lfo2]:
		var ls := LFO_SHAPES.find(String(l.get("shape", "sine")))
		lfos.append({shape = maxi(0, ls), rate_hz = maxf(0.0, float(l.get("rate_hz", 1.0))), delay_s = maxf(0.0, float(l.get("delay_s", 0.0)))})
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
	return {osc = osc, tables = tables, unison = clampi(unison, 1, MAX_UNISON), detune_cents = detune_cents, spread = clampf(spread, 0.0, 1.0),
		unison_level = clampf(unison_level, 0.0, 1.0), vel_curve = clampf(velocity_curve, 0.25, 4.0),
		resonance = clampf(float(filter.get("resonance", 0.3)), 0.0, 1.2), drive = maxf(0.05, float(filter.get("drive", 1.0))),
		filter_type = ft, cutoff_hz = float(filter.get("cutoff_hz", 18000.0)), q = maxf(0.05, float(filter.get("q", 0.707))),
		stages = 2 if float(filter.get("slope_db", 12.0)) >= 24.0 else 1,
		env = envs, lfo = lfos, mods = rows,
		mode = maxi(0, MODES.find(mode)), poly = clampi(polyphony, 1, MAX_POLY), glide_s = maxf(0.0, glide_s),
		bend_range = bend_range, vel_sens = clampf(velocity_sens, 0.0, 1.0), gain = db_to_linear(gain_db),
		pan = clampf(pan, -1.0, 1.0), seed = seed, effects = effects.map(func(e: Dictionary) -> Dictionary: return AKStreamFx.compile(e))}
