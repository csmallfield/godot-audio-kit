# SPDX-License-Identifier: Apache-2.0
@tool
## Flavor: a synth patch from a few knobs named for what you hear.
##
##   var patch := AKFlavor.build({lean_beefy = 0.6, shut_quack = 1.0, pump = true})
##
## Fourteen knobs and five switches (KNOBS, SWITCHES) sculpt one neutral base
## sound into an ordinary AKPatch: oscillators, filter, envelopes, LFOs, matrix
## rows and effects, ending in a limiter. Eight knobs are two-way (-1 .. 1, 0 is
## the base); six only add (0 .. 1). A knob moves many settings at once, and
## knobs that move the same setting add up. The values at each end were tuned by
## ear, one control at a time: docs/plans/flavor-tab.md records them and why.
##
## The patch remembers the settings it came from (`settings_of`), with a
## fingerprint, so a patch edited afterwards can be told apart (`is_stale`).
## `level` evens out loudness with one fixed gain; `randomise` and `mutate`
## make new settings.
class_name AKFlavor
extends RefCounted

## The knobs, in display order. `two_way`: rests in the middle and turns
## either way toward `low` or `high`; otherwise it rests at 0 and only turns up.
const KNOBS: Array[Dictionary] = [
	{id = "lean_beefy", low = "Lean", high = "Beefy", two_way = true,
		hint = "Low-end weight: sub oscillators, lows and compression, or the lows cut away."},
	{id = "silky_gritty", low = "Silky", high = "Gritty", two_way = true,
		hint = "A smooth triangle with a clean sheen, or a rough saw with noise and a buzzing overtone."},
	{id = "woody_glassy", low = "Woody", high = "Glassy", two_way = true,
		hint = "The material: a hollow, damped knock, or a bell that rings on."},
	{id = "murky_sparkly", low = "Murky", high = "Sparkly", two_way = true,
		hint = "Dark, closed and underwater, or open with shimmer and a ting on every note."},
	{id = "pluck_bloom", low = "Pluck", high = "Bloom", two_way = true,
		hint = "How a note moves: a hard strike that dies at once, or a slow swell."},
	{id = "solo_crowd", low = "Solo", high = "Crowd", two_way = true,
		hint = "One exposed voice with vibrato, or many players spread wide."},
	{id = "shut_quack", low = "Shut", high = "Quack", two_way = true,
		hint = "A wah pedal: parked closed and nasal, or rocked open on every note."},
	{id = "dry_drenched", low = "Dry", high = "Drenched", two_way = true,
		hint = "No room and notes that stop dead, or echoes and a wash that barely fades."},
	{id = "clean_filthy", low = "Clean", high = "Filthy", two_way = false,
		hint = "Dirt in stages: saturation, then growl, then a crush that falls apart."},
	{id = "still_swirl", low = "Still", high = "Swirl", two_way = false,
		hint = "Movement: phaser, then flanger, while each note swings across the stereo field."},
	{id = "note_chord", low = "Note", high = "Chord", two_way = false,
		hint = "Adds an octave, then a fifth, then a third, until one key plays a chord."},
	{id = "polite_farty", low = "Polite", high = "Farty", two_way = false,
		hint = "Flap, rasp, squelch and sag."},
	{id = "steady_wonky", low = "Steady", high = "Wonky", two_way = false,
		hint = "Slow random pitch drift, from analog warmth to a chewed tape."},
	{id = "stiff_slinky", low = "Stiff", high = "Slinky", two_way = false,
		hint = "One note at a time, gliding from each note to the next."},
]
## The switches, in display order.
const SWITCHES: Array[Dictionary] = [
	{id = "bounce", name = "Bounce", hint = "Held keys play one at a time, climbing two octaves in sixteenth notes."},
	{id = "pump", name = "Pump", hint = "The level ducks on every beat and swells back."},
	{id = "lofi", name = "Lo-Fi", hint = "Small, boxy and crushed, with hiss under every note."},
	{id = "wide", name = "Wide", hint = "Voices panned hard left and right, and a ping-pong delay."},
	{id = "minor", name = "Minor", hint = "The third that Note/Chord adds is minor, not major."},
]
## Where the settings are kept on a patch (Resource metadata, saved in its .tres).
const META_KEY := &"flavor"
const META_VERSION := 1
## The limiter that ends every Flavor patch.
const CEILING_DB := -1.0
## `level` leaves a patch alone within this many LU of the base sound.
const LOUDNESS_WINDOW := 3.0
## Ceilings for settings several knobs add to.
const MAX_RESONANCE := 0.8
const MAX_ENV_CUTOFF_OCT := 5.0

static var _base_lufs := NAN


## Every control at rest: the base sound.
static func defaults() -> Dictionary:
	var d := {}
	for k: Dictionary in KNOBS:
		d[k.id] = 0.0
	for sw: Dictionary in SWITCHES:
		d[sw.id] = false
	return d


## `settings` with every control present and in range (unknown keys dropped).
static func clean(settings: Dictionary) -> Dictionary:
	var d := defaults()
	for k: Dictionary in KNOBS:
		if settings.has(k.id):
			d[k.id] = clampf(float(settings[k.id]), -1.0 if k.two_way else 0.0, 1.0)
	for sw: Dictionary in SWITCHES:
		if settings.has(sw.id):
			var v: Variant = settings[sw.id]
			d[sw.id] = v if v is bool else float(v) > 0.5
	return d


## The patch for `settings` ({knob id: -1 .. 1 or 0 .. 1, switch id: bool}; missing
## controls are at rest). Controls apply in a fixed order, so the result does not
## depend on the order of the keys.
static func build(settings: Dictionary = {}) -> AKPatch:
	var v := clean(settings)
	var s := _base()
	s.minor = v.minor
	_lean_beefy(s, v.lean_beefy)
	_silky_gritty(s, v.silky_gritty)
	_woody_glassy(s, v.woody_glassy)
	_murky_sparkly(s, v.murky_sparkly)
	_solo_crowd(s, v.solo_crowd)
	_clean_filthy(s, v.clean_filthy)
	_shut_quack(s, v.shut_quack)
	_still_swirl(s, v.still_swirl)
	_note_chord(s, v.note_chord)
	_polite_farty(s, v.polite_farty)
	_steady_wonky(s, v.steady_wonky)
	_stiff_slinky(s, v.stiff_slinky)
	if v.bounce:
		_bounce(s)
	if v.pump:
		_pump(s)
	if v.lofi:
		_lofi(s)
	if v.wide:
		_wide(s)
	# The two that scale times other controls add to go last.
	_pluck_bloom(s, v.pluck_bloom)
	_dry_drenched(s, v.dry_drenched)
	var p := _assemble(s)
	p.category = "other"
	_stamp(p, v, 0.0)
	return p


## Rebuild `patch` in place from `settings`: the same object, so a synth that
## is playing it hears the change as an edit (its `changed` signal fires once).
## Its name and path stay; the level gain is dropped until `level` runs again.
static func apply_to(patch: AKPatch, settings: Dictionary) -> void:
	var built := build(settings)
	for prop: Dictionary in built.get_property_list():
		var usage: int = prop.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			patch.set(prop.name, built.get(prop.name))
	patch.set_meta(META_KEY, built.get_meta(META_KEY))
	patch.emit_changed()


## The settings a Flavor patch was built from, or {} for any other patch.
static func settings_of(patch: AKPatch) -> Dictionary:
	if patch == null or not patch.has_meta(META_KEY):
		return {}
	var m: Variant = patch.get_meta(META_KEY)
	if not (m is Dictionary) or not ((m as Dictionary).get("settings") is Dictionary):
		return {}
	return clean((m as Dictionary).settings)


## True when a Flavor patch has been edited since it was built, so its stored
## settings no longer describe it. False for a patch that isn't a Flavor patch.
static func is_stale(patch: AKPatch) -> bool:
	if patch == null or not patch.has_meta(META_KEY):
		return false
	var m: Variant = patch.get_meta(META_KEY)
	return not (m is Dictionary) or String((m as Dictionary).get("fingerprint", "")) != fingerprint(patch)


## A hash of everything in the patch that makes sound.
static func fingerprint(patch: AKPatch) -> String:
	return var_to_str(patch.compile()).md5_text()


## The notes `level` measures a patch with: two bass notes and a chord.
static func reference_notes() -> Array:
	var n: Array = [
		{time_s = 0.0, note = "C2", velocity = 0.85, length_s = 0.4},
		{time_s = 0.5, note = "G2", velocity = 0.85, length_s = 0.4},
	]
	for k: String in ["A3", "C4", "E4", "G4"]:
		n.append({time_s = 1.0, note = k, velocity = 0.7, length_s = 0.8})
	return n


## A patch's loudness and peak on the reference notes: {lufs, peak_db}, measured
## ahead of its final gain and limiter.
static func measure(patch: AKPatch) -> Dictionary:
	var q: AKPatch = patch.duplicate(true)
	var fx: Array[Dictionary] = []
	for e: Dictionary in q.effects:
		if String(e.get("type", "")) != "limiter" and not e.get("flavor_gain", false):
			fx.append(e)
	q.effects = fx
	var b := AKSynth.render_notes(q, reference_notes(), 2.6)
	return {lufs = AKDynamics.lufs(b), peak_db = linear_to_db(maxf(b.peak(), 1e-9))}


## The base sound's loudness on the reference notes (measured once).
static func base_lufs() -> float:
	if is_nan(_base_lufs):
		_base_lufs = float(measure(build()).lufs)
	return _base_lufs


## The fixed gain that brings a sound measuring `m` ({lufs, peak_db}) to within
## LOUDNESS_WINDOW of the base: down to the window's top when it is louder, up
## to its bottom when it is quieter, but never so far up that its peaks pass the
## limiter's ceiling. 0 inside the window.
static func gain_for(m: Dictionary, base := NAN) -> float:
	var b := base_lufs() if is_nan(base) else base
	var over := float(m.lufs) - b
	if over > LOUDNESS_WINDOW:
		return LOUDNESS_WINDOW - over
	if over < -LOUDNESS_WINDOW:
		return clampf(-LOUDNESS_WINDOW - over, 0.0, maxf(0.0, CEILING_DB - float(m.peak_db)))
	return 0.0


## Even out loudness: measure `patch` and set its one fixed gain (a gain stage
## just ahead of the limiter; nothing that reacts to the signal). Returns the
## gain in dB. The stored fingerprint is refreshed.
static func level(patch: AKPatch) -> float:
	var g := gain_for(measure(patch))
	_set_gain(patch, g)
	if patch.has_meta(META_KEY):
		_stamp(patch, settings_of(patch), g)
	return g


## New settings from scratch: most knobs near rest, a few pushed far, and now
## and then a switch.
static func randomise(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := defaults()
	for k: Dictionary in KNOBS:
		var x := rng.randfn(0.0, 0.12)
		d[k.id] = clampf(x if k.two_way else absf(x) - 0.08, -1.0 if k.two_way else 0.0, 1.0)
	var far := rng.randi_range(3, 4)
	var order := range(KNOBS.size())
	for i in far:
		var j := rng.randi_range(i, order.size() - 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
		var k: Dictionary = KNOBS[order[i]]
		var amount := rng.randf_range(0.5, 1.0)
		d[k.id] = amount * (-1.0 if k.two_way and rng.randf() < 0.5 else 1.0)
	for sw: Dictionary in SWITCHES:
		d[sw.id] = rng.randf() < 0.12
	return d


## A near neighbour of `settings`: each knob moves a little (`amount` 0 .. 1 is
## how far), and a switch rarely flips.
static func mutate(settings: Dictionary, seed: int, amount := 0.15) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := clean(settings)
	for k: Dictionary in KNOBS:
		d[k.id] = clampf(float(d[k.id]) + rng.randfn(0.0, amount * 0.6), -1.0 if k.two_way else 0.0, 1.0)
	for sw: Dictionary in SWITCHES:
		if rng.randf() < amount * 0.15:
			d[sw.id] = not d[sw.id]
	return d


# --- the base sound -------------------------------------------------------

static func _base() -> Dictionary:
	return {
		osc = [
			{shape = "morph", position = 0.55, level = 0.6},
			{shape = "sine", semitones = -12.0, level = 0.25},
		],
		unison = 2, detune_cents = 8.0, spread = 0.3, crowd = false, force_one = false,
		filter = {type = "ladder", cutoff_hz = 2500.0, resonance = 0.2, drive = 1.2},
		cutoff_oct = 0.0,
		amp_env = {attack_s = 0.01, decay_s = 0.5, sustain = 0.6, release_s = 0.25},
		env2 = {attack_s = 0.0, decay_s = 0.35, sustain = 0.15, release_s = 0.25, curve = "exp"},
		env3 = {}, envelopes = [], lfos = {},
		# Rows 0 .. 2 are the base's; knobs change their amounts by index.
		mods = [
			{source = "env2", dest = "cutoff", amount = 1.0},
			{source = "key", dest = "cutoff", amount = 0.4},
			{source = "velocity", dest = "cutoff", amount = 0.5},
		],
		gain_db = -6.0, pitch_cents = 0.0, minor = false, mode = "poly", glide_s = 0.0, arp = {},
		eq = {type = "eq", low_db = 0.0, low_hz = 150.0, mid_db = 0.0, mid_hz = 300.0, mid_q = 0.8, high_db = 0.0, high_hz = 5000.0},
		comp = {type = "compressor", threshold_db = -20.0, ratio = 1.0, makeup_db = 0.0},
		sat = {type = "saturate", drive_db = 4.0, tone_hz = 8000.0, mix = 0.5, output_db = 0.0, asymmetry = 0.0},
		mid_fx = [],
		delay = {type = "delay", time_sync = "1/8.", feedback = 0.2, damp_hz = 3500.0, mix = 0.08},
		reverb = {type = "reverb", room = 0.45, damp = 0.5, width = 1.0, mix = 0.12},
		post_fx = [],
	}


# --- the knobs (u: how far up, d: how far down, each 0 .. 1) ---------------

static func _lean_beefy(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	s.osc[1].level += 0.35 * u - 0.25 * d
	if u > 0.0:
		s.osc.append({shape = "square", semitones = -12.0, level = 0.6 * u})
	s.eq.low_hz += 100.0 * u + 550.0 * d
	s.eq.low_db += 9.0 * u - 24.0 * d
	s.eq.mid_hz += 100.0 * d + 200.0 * u
	s.eq.mid_db += 10.0 * u - 8.0 * d
	s.eq.high_db += 6.0 * d + 4.0 * u
	s.comp.ratio += 3.0 * u
	s.comp.attack_s = 0.01 + 0.02 * u
	s.comp.makeup_db += 5.0 * u
	s.sat.drive_db += 8.0 * u
	s.sat.mix += 0.4 * u
	s.sat.output_db += -5.0 * u + 2.5 * u * u
	if d >= 0.75:
		s.force_one = true
	s.gain_db += -8.0 * u + 8.0 * d


static func _silky_gritty(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	s.osc[0].position += 0.17 * u - 0.19 * d
	if d > 0.0:
		# Sheen: pure tones one and two octaves up.
		s.osc.append({shape = "sine", semitones = 12.0, level = 0.3 * d})
		s.osc.append({shape = "sine", semitones = 24.0, level = 0.12 * d})
	if u > 0.0:
		# Roughness at the source: noise bending the main oscillator's phase, and a
		# hard-synced overtone. (Ladder drive and oscillator feedback dull the tone.)
		s.osc.append({shape = "noise", level = 0.0})
		s.osc[0].fm = [{from = s.osc.size(), index = 0.8 * u}]
		s.osc.append({shape = "saw", semitones = 19.0, sync_to = 1, level = 0.35 * u})
	s.filter.drive += 1.8 * u - 0.6 * d
	s.filter.resonance += 0.25 * u - 0.15 * d
	s.cutoff_oct += 1.0 * u + 0.5 * d
	s.mods[0].amount += 0.5 * u - 0.7 * d
	s.sat.mix -= 0.4 * d
	s.eq.high_db += 6.0 * d
	s.amp_env.attack_s += 0.025 * d
	s.gain_db += 2.0 * u - 1.0 * d


static func _woody_glassy(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	s.osc[0].position += 0.35 * d - 0.40 * u
	if u > 0.0:
		# A bell: FM from 3.5 times the note, brightest at the strike.
		s.osc.append({shape = "sine", ratio = 3.5, level = 0.0})
		s.osc[0].fm_from = s.osc.size()
		s.osc[0].fm_index = 1.2 * u
		s.mods.append({source = "env2", dest = "osc1.fm", amount = 2.5 * u})
	s.cutoff_oct += 1.5 * u - 1.0 * d
	s.filter.resonance += 0.15 * d - 0.10 * u
	s.mods[0].amount += 1.5 * d
	s.env2.decay_s += -0.27 * d + 0.4 * u
	s.env2.sustain += -0.15 * d
	s.amp_env.decay_s += -0.25 * d + 1.0 * u
	s.amp_env.sustain += -0.45 * d - 0.25 * u
	s.amp_env.release_s += -0.13 * d + 1.25 * u
	s.eq.mid_hz += 150.0 * d
	s.eq.mid_db += 6.0 * d
	s.eq.high_db += -4.0 * d + 5.0 * u
	s.sat.mix -= 0.3 * u
	s.gain_db += -1.5 * u + 1.0 * d


static func _murky_sparkly(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	s.cutoff_oct += 2.5 * u - 3.0 * d
	s.mods[0].amount += -0.7 * d
	s.mods[1].amount += 0.6 * u - 0.4 * d
	s.mods[2].amount += 0.5 * u - 0.3 * d
	s.osc[0].position += 0.10 * u
	if u > 0.0:
		# Shimmer: beating upper octaves, a ting three octaves up on every note
		# (env3), chorus, and an octave-up copy into a slightly larger reverb.
		s.osc.append({shape = "saw", semitones = 12.0, stack = 2, stack_cents = 18.0, level = 0.30 * u})
		s.osc.append({shape = "saw", semitones = 24.0, cents = -6.0, level = 0.15 * u})
		s.osc.append({shape = "sine", semitones = 36.0, level = 0.30 * u, level_env = 3})
		s.env3 = {attack_s = 0.0, decay_s = 0.25, sustain = 0.0, release_s = 0.2, curve = "exp"}
		s.mid_fx.append({type = "chorus", rate_hz = 1.2, depth_ms = 3.0, delay_ms = 10.0, voices = 3, mix = 0.4 * u})
		s.mid_fx.append({type = "pitch", semitones = 12.0, window_ms = 40.0, mix = 0.25 * u})
		s.reverb.mix += 0.08 * u
		s.eq.high_hz -= 2000.0 * u
	s.eq.high_db += 10.0 * u - 12.0 * d
	s.eq.mid_hz += -50.0 * d
	s.eq.mid_db += 4.0 * d
	s.reverb.mix += 0.10 * d
	s.reverb.damp += 0.4 * d
	s.gain_db += 1.5 * u + 2.5 * d


static func _pluck_bloom(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	s.amp_env.attack_s = s.amp_env.attack_s * pow(0.1, d) + 0.5 * u + 0.7 * u * u
	s.amp_env.decay_s += -0.32 * d
	s.amp_env.sustain += 0.4 * u - 0.55 * d
	s.amp_env.release_s = s.amp_env.release_s * pow(6.0, u) * pow(0.6, d)
	s.env2.attack_s += 1.0 * u
	s.env2.decay_s += -0.23 * d
	s.env2.sustain += 0.85 * u - 0.15 * d
	s.env2.release_s += 1.0 * u
	s.mods[0].amount += 0.5 * u + 2.0 * d
	s.cutoff_oct += -1.0 * u
	s.gain_db += -0.5 * u + 3.5 * d


static func _solo_crowd(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	if u > 0.0:
		s.unison = int(floor(2.0 + 5.0 * u + 0.5))
		s.crowd = true
		s.mods.append({source = "random", dest = "pitch", amount = 0.12 * u})
		if u > 0.5:
			s.mid_fx.append({type = "chorus", rate_hz = 0.6, depth_ms = 4.0, delay_ms = 14.0, voices = 3, mix = 0.5 * (u - 0.5) * 2.0})
	if d >= 0.5:
		s.force_one = true
	if d > 0.0:
		# A soloist's delayed vibrato (lfo1).
		s.lfos[1] = {shape = "sine", rate_hz = 5.5, delay_s = 0.25}
		s.mods.append({source = "lfo1", dest = "pitch", amount = 0.3 * d})
	s.detune_cents += 37.0 * u - 8.0 * d
	s.spread += 0.7 * u - 0.3 * d
	s.reverb.width += -1.0 * d
	# Seven detuned voices partly cancel, and the chorus crossfades the dry away.
	s.gain_db += 5.0 * maxf(u - 0.5, 0.0) * 2.0


static func _clean_filthy(s: Dictionary, u: float) -> void:
	if u <= 0.0:
		return
	var t1 := clampf(u / 0.5, 0.0, 1.0)
	var t2 := clampf((u - 0.3) / 0.5, 0.0, 1.0)
	var t3 := clampf((u - 0.65) / 0.35, 0.0, 1.0)
	s.sat.drive_db += 20.0 * t1
	s.sat.mix += 0.5 * t1
	s.sat.asymmetry += 0.4 * t1
	s.sat.output_db += -11.0 * t1
	# A mid boost ahead of the saturation, so the dirt bites in the midrange.
	s.eq.mid_db += 8.0 * t1
	s.eq.mid_hz += 500.0 * t1
	if t2 > 0.0:
		s.mid_fx.append({type = "growl", rate_hz = 45.0, depth = 0.3 + 0.5 * t2, jitter = 0.5 + 0.5 * t3, mix = 0.8 * t2})
	if t3 > 0.0:
		s.mid_fx.append({type = "crush", bits = 12.0 - 9.0 * t3, hold = 1 + int(round(13.0 * t3)), mix = t3})


static func _shut_quack(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	s.cutoff_oct += -2.0 * u - 2.0 * d
	s.filter.resonance += 0.55 * u + 0.40 * d
	s.mods[0].amount += 4.0 * u - 1.0 * d
	s.mods[2].amount += 1.5 * u - 0.5 * d
	s.env2.attack_s += 0.04 * u
	s.env2.decay_s += -0.13 * u
	s.env2.sustain += -0.15 * u
	s.gain_db += 1.0 * u


static func _dry_drenched(s: Dictionary, k: float) -> void:
	var u := maxf(k, 0.0)
	var d := maxf(-k, 0.0)
	var t1 := clampf(u / 0.6, 0.0, 1.0)
	var t2 := clampf((u - 0.2) / 0.8, 0.0, 1.0)
	var t3 := clampf((u - 0.6) / 0.4, 0.0, 1.0)
	s.delay.mix += 0.62 * t1 - 0.08 * d
	s.delay.feedback += 0.60 * t1
	s.delay.damp_hz += -1700.0 * t1
	s.reverb.mix += 0.88 * t2 - 0.12 * d
	s.reverb.room += 0.53 * t2
	s.reverb.damp += 0.1 * t2
	if t3 > 0.0:
		# A second reverb fed by the first: the notes dissolve.
		s.post_fx.append({type = "reverb", room = 0.9, damp = 0.6, width = 1.0, mix = 0.8 * t3})
	s.amp_env.release_s *= pow(0.25, d)
	s.gain_db += -2.0 * u - 12.0 * u * u


static func _still_swirl(s: Dictionary, u: float) -> void:
	if u <= 0.0:
		return
	var t1 := clampf(u / 0.5, 0.0, 1.0)
	var t2 := clampf((u - 0.4) / 0.6, 0.0, 1.0)
	s.mid_fx.append({type = "phaser", rate_hz = 0.3 + 0.7 * u, stages = 4 + int(round(4.0 * t1)), center_hz = 800.0,
		range_octaves = 2.0 + 1.0 * t1, depth = 1.0, feedback = 0.4 + 0.2 * t1, mix = 0.6 * t1, spread = 1.0})
	if t2 > 0.0:
		s.mid_fx.append({type = "flanger", rate_hz = 0.25 + 0.5 * t2, depth_ms = 2.0 + 2.5 * t2, delay_ms = 1.0,
			feedback = 0.6 + 0.18 * t2, mix = 0.6 * t2, spread = 1.0})
	s.lfos[2] = {shape = "sine", rate_hz = 0.4 + 3.1 * u * u, delay_s = 0.0}
	s.mods.append({source = "lfo2", dest = "pan", amount = 0.8 * u})
	s.mods.append({source = "lfo2", dest = "osc.position", amount = 0.2 * u})
	s.mods.append({source = "lfo2", dest = "pitch", amount = 0.2 * t2})
	# The phaser and flanger partly cancel each other around three-quarters.
	s.gain_db += 2.0 * minf(u / 0.25, 1.0) + 2.0 * maxf(0.0, 1.0 - absf(u - 0.75) / 0.25)


static func _note_chord(s: Dictionary, u: float) -> void:
	if u <= 0.0:
		return
	var t1 := clampf(u / 0.35, 0.0, 1.0)
	var t2 := clampf((u - 0.25) / 0.4, 0.0, 1.0)
	var t3 := clampf((u - 0.6) / 0.4, 0.0, 1.0)
	# `follow`: these take the main oscillator's final shape.
	s.osc.append({shape = "morph", position = 0.55, semitones = 12.0, level = 0.6 * t1, follow = true})
	if t2 > 0.0:
		s.osc.append({shape = "morph", position = 0.55, semitones = 7.0, level = 0.6 * t2, follow = true})
	if t3 > 0.0:
		s.osc.append({shape = "morph", position = 0.55, semitones = 15.0 if s.minor else 16.0, level = 0.55 * t3, follow = true})
	s.gain_db += -4.5 * u


static func _polite_farty(s: Dictionary, u: float) -> void:
	if u <= 0.0:
		return
	# Flap: a ramp LFO (lfo3) chopping level and filter, slower as the knob rises.
	s.lfos[3] = {shape = "saw", rate_hz = 40.0 - 18.0 * u, delay_s = 0.0}
	s.mods.append({source = "lfo3", dest = "amp", amount = -0.9 * u})
	s.mods.append({source = "lfo3", dest = "cutoff", amount = 2.5 * u})
	s.mods.append({source = "random", dest = "lfo3.rate", amount = 0.4 * u})
	# Rasp: a square-leaning, brassy shape and a growl. (A narrow pulse carries a
	# constant offset, which the growl turns into a sub-bass thump.)
	s.osc[0].position += 0.4 * u
	s.mid_fx.append({type = "growl", rate_hz = 28.0, depth = 0.7 * u, jitter = 0.8, mix = 0.6 * u})
	# Squelch: a lower, more resonant filter for the flap to open.
	s.cutoff_oct += -1.2 * u
	s.filter.resonance += 0.45 * u
	# Sag: every oscillator is tuned flat and env4 adds it back while the key is
	# held, so notes scoop up from flat and droop when released.
	s.envelopes.append({attack_s = 0.04, decay_s = 0.0, sustain = 1.0, release_s = 0.3})
	s.mods.append({source = "env4", dest = "pitch", amount = 1.5 * u})
	s.pitch_cents += -150.0 * u
	s.mods.append({source = "random", dest = "pitch", amount = 0.3 * u})
	s.amp_env.release_s += 0.15 * u
	# The morph shape is quietest around 0.75 and loudest near square.
	s.gain_db += 3.0 * maxf(0.0, 1.0 - absf(u - 0.5) / 0.5) - 2.0 * clampf((u - 0.75) / 0.25, 0.0, 1.0)


static func _steady_wonky(s: Dictionary, u: float) -> void:
	if u <= 0.0:
		return
	s.lfos[4] = {shape = "smooth", rate_hz = 0.5 + 2.0 * u, delay_s = 0.0}
	s.mods.append({source = "lfo4", dest = "pitch", amount = 0.9 * u})
	s.mods.append({source = "lfo4", dest = "amp", amount = -0.2 * u})
	s.mods.append({source = "random", dest = "pitch", amount = 0.4 * u})
	s.mods.append({source = "random", dest = "cutoff", amount = 0.5 * u})


static func _stiff_slinky(s: Dictionary, u: float) -> void:
	if u <= 0.0:
		return
	# Mono, not legato: every note re-strikes, so Pluck, Quack and Farty are heard.
	s.mode = "mono"
	s.glide_s = 0.02 + 0.48 * u * u


# --- the switches ----------------------------------------------------------

static func _bounce(s: Dictionary) -> void:
	s.arp = {mode = "up", octaves = 2, rate = "1/16", gate = 0.5, on = true}


static func _pump(s: Dictionary) -> void:
	# lfo5, free-running, so the duck stays on the beat whenever a note starts.
	s.lfos[5] = {shape = "saw", rate_sync = "1/4", delay_s = 0.0, free = true}
	s.mods.append({source = "lfo5", dest = "amp", amount = 0.8})
	s.gain_db += -2.0


static func _lofi(s: Dictionary) -> void:
	s.eq.low_hz += 100.0
	s.eq.low_db += -10.0
	s.eq.mid_hz += 700.0
	s.eq.mid_db += 5.0
	s.eq.high_hz += -1500.0
	s.eq.high_db += -15.0
	s.osc.append({shape = "noise", level = 0.06})
	s.mid_fx.append({type = "crush", bits = 8.0, hold = 5, mix = 1.0})


static func _wide(s: Dictionary) -> void:
	s.spread += 0.7
	s.detune_cents += 6.0
	s.delay.mode = "pingpong"
	s.delay.mix += 0.17
	s.delay.feedback += 0.2


# --- from the summed state to a patch ---------------------------------------

static func _assemble(s: Dictionary) -> AKPatch:
	var p := AKPatch.new()
	# Silent oscillators stay, so the numbers FM and sync refer to never shift.
	var oscs: Array[Dictionary] = []
	var main_pos := clampf(float(s.osc[0].position), 0.0, 1.0)
	for o: Dictionary in s.osc:
		o.level = clampf(float(o.level), 0.0, 1.0)
		if o.has("position"):
			o.position = main_pos if o.get("follow", false) else clampf(float(o.position), 0.0, 1.0)
		o.erase("follow")
		if s.pitch_cents != 0.0:
			o.cents = float(o.get("cents", 0.0)) + s.pitch_cents
		oscs.append(o)
	p.oscillators = oscs
	# Crowd sets the voice count; full Lean or half Solo force one voice otherwise.
	p.unison = s.unison if s.crowd else (1 if s.force_one else s.unison)
	p.detune_cents = maxf(0.0, s.detune_cents)
	p.spread = clampf(s.spread, 0.0, 1.0)
	s.filter.cutoff_hz = clampf(s.filter.cutoff_hz * pow(2.0, s.cutoff_oct), 60.0, 18000.0)
	s.filter.resonance = clampf(s.filter.resonance, 0.0, MAX_RESONANCE)
	s.filter.drive = maxf(0.1, s.filter.drive)
	p.filter = s.filter
	for e: Dictionary in [s.amp_env, s.env2]:
		e.attack_s = maxf(0.0, e.attack_s)
		e.decay_s = maxf(0.01, e.decay_s)
		e.sustain = clampf(e.sustain, 0.0, 1.0)
		e.release_s = maxf(0.01, e.release_s)
	p.amp_env = s.amp_env
	p.env2 = s.env2
	if not s.env3.is_empty():
		p.env3 = s.env3
	if not s.envelopes.is_empty():
		var envs: Array[Dictionary] = []
		envs.assign(s.envelopes)
		p.envelopes = envs
	# Rows with the same source and destination merge; their amounts add.
	var merged := {}
	var mods: Array[Dictionary] = []
	for m: Dictionary in s.mods:
		var key := "%s>%s" % [m.source, m.dest]
		if merged.has(key):
			merged[key].amount += float(m.amount)
		else:
			merged[key] = m
			mods.append(m)
	merged["env2>cutoff"].amount = clampf(merged["env2>cutoff"].amount, 0.0, MAX_ENV_CUTOFF_OCT)
	p.mods = mods
	# lfo1 Solo, lfo2 Swirl, lfo3 Farty, lfo4 Wonky, lfo5 Pump. An LFO nothing
	# reads changes nothing, so gaps are filled with plain ones.
	if s.lfos.has(1):
		p.lfo1 = s.lfos[1]
	if s.lfos.has(2):
		p.lfo2 = s.lfos[2]
	var last := 2
	for i: int in s.lfos:
		last = maxi(last, i)
	var extra: Array[Dictionary] = []
	for i in range(3, last + 1):
		extra.append(s.lfos.get(i, {shape = "sine", rate_hz = 1.0, delay_s = 0.0}))
	p.lfos = extra
	p.velocity_sens = 0.5
	p.mode = s.mode
	p.glide_s = s.glide_s
	if not s.arp.is_empty():
		p.arp = s.arp
	p.gain_db = s.gain_db
	# The chain: eq, compressor, saturate, the knobs' effects, delay, reverb,
	# (second reverb), limiter.
	var fx: Array[Dictionary] = []
	var eq: Dictionary = s.eq
	if absf(eq.low_db) + absf(eq.mid_db) + absf(eq.high_db) > 0.01:
		eq.low_hz = clampf(eq.low_hz, 40.0, 2000.0)
		eq.mid_hz = clampf(eq.mid_hz, 100.0, 6000.0)
		eq.high_hz = clampf(eq.high_hz, 1000.0, 12000.0)
		fx.append(eq)
	if float(s.comp.ratio) > 1.01:
		fx.append(s.comp)
	s.sat.mix = clampf(s.sat.mix, 0.0, 1.0)
	fx.append(s.sat)
	# Sparkly's and Crowd's choruses become one.
	var chorus := {}
	for f: Dictionary in s.mid_fx:
		if f.type == "chorus":
			if chorus.is_empty():
				chorus = f
				fx.append(f)
			else:
				chorus.mix = minf(0.7, float(chorus.mix) + float(f.mix))
				chorus.depth_ms = maxf(float(chorus.depth_ms), float(f.depth_ms))
		else:
			fx.append(f)
	s.delay.mix = clampf(s.delay.mix, 0.0, 1.0)
	s.delay.feedback = clampf(s.delay.feedback, 0.0, 0.85)
	s.delay.damp_hz = maxf(800.0, s.delay.damp_hz)
	s.reverb.mix = clampf(s.reverb.mix, 0.0, 1.0)
	s.reverb.room = clampf(s.reverb.room, 0.0, 0.98)
	s.reverb.damp = clampf(s.reverb.damp, 0.0, 1.0)
	s.reverb.width = clampf(s.reverb.width, 0.0, 1.0)
	fx.append(s.delay)
	fx.append(s.reverb)
	fx.append_array(s.post_fx)
	fx.append({type = "limiter", ceiling_db = CEILING_DB, release_s = 0.08})
	p.effects = fx
	return p


## Set the one fixed gain: a ratio-1 compressor (so it never reacts to the
## signal) with makeup, just ahead of the limiter. 0 removes the stage.
static func _set_gain(patch: AKPatch, gain_db: float) -> void:
	var fx: Array[Dictionary] = []
	for e: Dictionary in patch.effects:
		if e.get("flavor_gain", false):
			continue
		if String(e.get("type", "")) == "limiter" and absf(gain_db) > 0.005:
			fx.append({type = "compressor", threshold_db = 0.0, ratio = 1.0, knee_db = 0.0, makeup_db = gain_db, flavor_gain = true})
		fx.append(e)
	patch.effects = fx


static func _stamp(patch: AKPatch, settings: Dictionary, gain_db: float) -> void:
	patch.set_meta(META_KEY, {version = META_VERSION, settings = settings, level_gain_db = gain_db, fingerprint = fingerprint(patch)})
