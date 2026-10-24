# SPDX-License-Identifier: Apache-2.0
# A racing-game sound kit and its title track, made with the Audio Kit.
#
#   godot --headless --path . -s res://demo/racing/make_racing.gd            (write resources)
#   godot --headless --path . -s res://demo/racing/make_racing.gd -- --bake  (and bake WAVs to out/racing/)
#
# Writes, all as text:
#   demo/racing/patches/   engine, screech and the song's synth patches
#   demo/racing/sfx/       one recipe per sound effect (see README.md)
#   demo/racing/song/      "Neon Circuit": drum recipes, one pattern per section, the song
# Everything is original; every sound is synthesized.
extends SceneTree

const D := "res://demo/racing/"
const OUT := "res://out/racing/"

var bake := false


func _init() -> void:
	bake = OS.get_cmdline_user_args().has("--bake")
	for d in ["patches", "sfx", "song"]:
		DirAccess.make_dir_recursive_absolute(D + d)
	_patches()
	_sfx()
	_song()
	if bake:
		_bake()
	quit()


func _save(r: Resource, path: String) -> void:
	r.resource_name = path.get_file().get_basename()
	if ResourceSaver.save(r, path) != OK:
		push_error("couldn't save " + path)
	else:
		print("wrote ", path)


func _rec(voice: StringName, params: Dictionary, extra := {}) -> AKRecipe:
	var r := AKRecipe.new()
	r.voice = voice
	r.params = params
	for k in extra:
		var v: Variant = extra[k]
		if k == "layers" or k == "fx" or k == "transforms":
			var a: Array[Dictionary] = []
			for e in v:
				a.append(e)
			r.set(k, a)
		else:
			r.set(k, v)
	return r


func _patch(oscs: Array, filt: Dictionary, amp: Dictionary, more := {}) -> AKPatch:
	var p := AKPatch.new()
	var o: Array[Dictionary] = []
	for d in oscs:
		o.append(d)
	p.oscillators = o
	p.filter = filt
	p.amp_env = amp
	for k in more:
		var v: Variant = more[k]
		if k == "mods" or k == "effects":
			var a: Array[Dictionary] = []
			for e in v:
				a.append(e)
			p.set(k, a)
		else:
			p.set(k, v)
	return p


# ------------------------------------------------------------------ patches

func _patches() -> void:
	# A four-stroke engine: a saw for the exhaust buzz, a pulse an octave down
	# ring-modulated by a sine at half the firing rate (the uneven "chug" of
	# the cylinders), a little noise, through a driven ladder that opens with
	# the pitch, plus random roughness.
	_save(_patch([{shape = "saw", level = 0.55}, {shape = "pulse", width = 0.3, semitones = -12.0, level = 0.7, ring_from = 3},
			{shape = "sine", semitones = -12.0, level = 0.0}, {shape = "noise", level = 0.12}],
		{type = "ladder", cutoff_hz = 380.0, resonance = 0.25, drive = 2.0},
		{attack_s = 0.03, decay_s = 0.2, sustain = 1.0, release_s = 0.12},
		{category = "fx", unison = 2, detune_cents = 9.0, seed = 7, polyphony = 2, gain_db = -14.0,
			lfo1 = {shape = "random", rate_hz = 22.0, delay_s = 0.0}, lfo2 = {shape = "sine", rate_hz = 0.7, delay_s = 0.0},
			mods = [{source = "key", dest = "cutoff", amount = 0.9}, {source = "lfo1", dest = "amp", amount = 0.18},
				{source = "lfo1", dest = "pitch", amount = 0.12}, {source = "lfo2", dest = "pitch", amount = 0.06},
				{source = "env2", dest = "pitch", amount = 0.0}],
			effects = [{type = "saturate", drive_db = 14.0, tone_hz = 3200.0, asymmetry = 0.3},
				{type = "eq", low_db = 4.0, low_hz = 110.0, mid_db = -3.0, mid_hz = 900.0, high_db = -4.0}]}),
		D + "patches/engine.tres")
	# The same engine with an envelope on its pitch and filter: a rev.
	var rev: AKPatch = load(D + "patches/engine.tres").duplicate(true)
	rev.env2 = {attack_s = 0.45, decay_s = 0.55, sustain = 0.0, release_s = 0.4, curve = "exp"}
	var m: Array[Dictionary] = []
	for row in rev.mods:
		m.append(row)
	m[4] = {source = "env2", dest = "pitch", amount = 21.0}
	m.append({source = "env2", dest = "cutoff", amount = 1.5})
	rev.mods = m
	_save(rev, D + "patches/engine_rev.tres")
	# Tyres: a squealing triangle wobbling at random, through a band-pass, with
	# rubbery noise; the pitch sags as the slide dies.
	_save(_patch([{shape = "triangle", level = 0.6}, {shape = "triangle", semitones = 7.02, level = 0.25}, {shape = "noise", level = 0.35}],
		{type = "bandpass", cutoff_hz = 1700.0, q = 2.2},
		{attack_s = 0.04, decay_s = 0.3, sustain = 0.9, release_s = 0.18},
		{category = "fx", seed = 11, gain_db = -6.0,
			lfo1 = {shape = "random", rate_hz = 34.0, delay_s = 0.0}, lfo2 = {shape = "sine", rate_hz = 6.5, delay_s = 0.0},
			env2 = {attack_s = 0.0, decay_s = 1.2, sustain = 0.0, release_s = 0.3, curve = "exp"},
			mods = [{source = "lfo1", dest = "pitch", amount = 1.3}, {source = "lfo2", dest = "pitch", amount = 0.5},
				{source = "env2", dest = "pitch", amount = 2.0}, {source = "lfo1", dest = "amp", amount = 0.55}, {source = "lfo1", dest = "cutoff", amount = 0.4}],
			effects = [{type = "saturate", drive_db = 8.0, tone_hz = 7000.0}]}),
		D + "patches/screech.tres")
	# The song's synths (synthwave): a pumping octave bass, a plucky arp, a
	# wide pad and a singing lead.
	_save(_patch([{shape = "saw", level = 0.6}, {shape = "square", semitones = -12.0, level = 0.45}],
		{type = "ladder", cutoff_hz = 260.0, resonance = 0.35, drive = 1.6},
		{attack_s = 0.002, decay_s = 0.18, sustain = 0.55, release_s = 0.05},
		{category = "bass", mode = "poly", polyphony = 4, velocity_sens = 0.6, gain_db = -4.0,
			env2 = {attack_s = 0.0, decay_s = 0.12, sustain = 0.0, release_s = 0.1, curve = "exp"},
			mods = [{source = "env2", dest = "cutoff", amount = 3.2}, {source = "velocity", dest = "cutoff", amount = 0.8}]}),
		D + "patches/neon_bass.tres")
	_save(_patch([{shape = "pulse", width = 0.35, level = 0.5}, {shape = "saw", cents = 8.0, level = 0.35}],
		{type = "ladder", cutoff_hz = 900.0, resonance = 0.3, drive = 1.0},
		{attack_s = 0.001, decay_s = 0.16, sustain = 0.15, release_s = 0.12},
		{category = "pluck", polyphony = 8, velocity_sens = 0.7, gain_db = -7.0, spread = 0.5, unison = 2, detune_cents = 6.0,
			env2 = {attack_s = 0.0, decay_s = 0.14, sustain = 0.0, release_s = 0.1, curve = "exp"},
			mods = [{source = "env2", dest = "cutoff", amount = 2.6}],
			effects = [{type = "chorus", rate_hz = 0.6, depth_ms = 2.5, mix = 0.35}]}),
		D + "patches/neon_arp.tres")
	_save(_patch([{shape = "table", table = "pwm", position = 0.2, level = 0.5}, {shape = "saw", semitones = 12.0, level = 0.15}],
		{type = "lowpass", cutoff_hz = 2400.0, q = 0.6},
		{attack_s = 0.6, decay_s = 1.0, sustain = 0.85, release_s = 1.0},
		{category = "pad", polyphony = 12, unison = 3, detune_cents = 14.0, spread = 0.9, velocity_sens = 0.2, gain_db = -11.0,
			lfo1 = {shape = "triangle", rate_hz = 0.25, delay_s = 0.0},
			mods = [{source = "lfo1", dest = "osc1.position", amount = 0.3}, {source = "lfo1", dest = "cutoff", amount = 0.3}],
			effects = [{type = "chorus", rate_hz = 0.4, depth_ms = 4.0, mix = 0.5}]}),
		D + "patches/neon_pad.tres")
	_save(_patch([{shape = "saw", level = 0.55}, {shape = "pulse", width = 0.4, cents = -9.0, level = 0.35}],
		{type = "ladder", cutoff_hz = 2200.0, resonance = 0.2, drive = 1.2},
		{attack_s = 0.01, decay_s = 0.3, sustain = 0.8, release_s = 0.2},
		{category = "lead", mode = "legato", glide_s = 0.035, velocity_sens = 0.4, gain_db = -7.0,
			lfo1 = {shape = "sine", rate_hz = 5.6, delay_s = 0.35},
			mods = [{source = "lfo1", dest = "pitch", amount = 0.18}, {source = "velocity", dest = "cutoff", amount = 0.6}],
			effects = [{type = "chorus", rate_hz = 0.9, depth_ms = 2.0, mix = 0.25}, {type = "eq", mid_db = 2.0, mid_hz = 1800.0}]}),
		D + "patches/neon_lead.tres")


# ------------------------------------------------------------------ sound effects

## name -> recipe; also a one-line description for the README.
var SFX := {}


func _sfx() -> void:
	var P := D + "patches/"
	var loop := {gate_s = 2.4, length_s = 2.4}
	# Engine loops at three speeds (seamless after AKLive.make_loop / LOOP in Godot's import).
	_fx("engine_idle", "Engine at idle, a 2 s loop", _rec(&"patch", _merge({patch = P + "engine.tres", freq_hz = 30.0, velocity = 0.7}, loop), {fx = _level(-16.0)}))
	_fx("engine_mid", "Engine at cruising revs, a 2 s loop", _rec(&"patch", _merge({patch = P + "engine.tres", freq_hz = 62.0, velocity = 0.85}, loop), {fx = _level(-15.0)}))
	_fx("engine_high", "Engine near the redline, a 2 s loop", _rec(&"patch", _merge({patch = P + "engine.tres", freq_hz = 118.0, velocity = 1.0}, loop), {fx = _level(-14.0)}))
	_fx("engine_rev", "A blip of the throttle: up and back to idle",
		_rec(&"patch", {patch = P + "engine_rev.tres", freq_hz = 34.0, gate_s = 1.6, length_s = 2.1}, {fx = [{type = &"normalize", peak_db = -1.0}]}))
	_fx("engine_start", "Starter motor cranking, then the engine catches",
		_rec(&"ratchet", {length_s = 0.7, start_rate_hz = 9.0, end_rate_hz = 13.0, click_hz = 900.0, q = 2.0, click_decay_s = 0.03, jitter = 0.15, fade = 0.0},
			{layers = [{voice = &"patch", params = {patch = P + "engine_rev.tres", freq_hz = 30.0, gate_s = 1.4, length_s = 1.9, velocity = 0.9}, offset_s = 0.62, gain_db = -2.0},
				{voice = &"static", params = {length_s = 0.7, hiss = 0.25, color_hz = 400.0, q = 1.0, crackles_per_s = 60.0, crackle = 0.3}, gain_db = -10.0}],
			fx = [{type = &"normalize", peak_db = -1.0}]}))
	_fx("gear_shift", "A gear change: the lever's clack and the drivetrain's thunk",
		_rec(&"click", {freq_hz = 2200.0, q = 5.0, mode = &"band", decay_s = 0.012, body_hz = 140.0, body = 0.7},
			{layers = [{voice = &"boing", params = {start_hz = 220.0, end_hz = 70.0, drop_s = 0.03, decay_s = 0.07, click = 0.2}, offset_s = 0.035, gain_db = -4.0},
				{voice = &"click", params = {freq_hz = 3500.0, q = 8.0, mode = &"band", decay_s = 0.006}, offset_s = 0.06, gain_db = -8.0}],
			fx = [{type = &"room", room = 0.25, damp = 0.6, mix = 0.12, quality = &"small"}, {type = &"normalize", peak_db = -1.0}],
			vary = {freq_hz = 0.08, start_hz = 0.06}, vary_variants = 4}))
	_fx("turbo_blowoff", "Turbo blow-off valve: a sharp falling pssh",
		_rec(&"whoosh", {length_s = 0.6, low_hz = 1200.0, high_hz = 9000.0, peak = 0.06, shape = 2.6, mode = &"band", q = 1.4, noise = &"white"},
			{layers = [{voice = &"tone", params = {wave = &"triangle", freq_hz = 2600.0, end_hz = 900.0, glide_s = 0.12, attack_s = 0.0, decay_s = 0.25, gate_s = 0.05}, gain_db = -16.0}],
			fx = [{type = &"normalize", peak_db = -1.0}], vary = {high_hz = 0.1}, vary_variants = 3}))
	_fx("tire_screech", "A long tyre squeal in a hard corner",
		_rec(&"patch", {patch = P + "screech.tres", freq_hz = 1450.0, gate_s = 1.5, length_s = 1.9}, {fx = _level(-13.0),
			vary = {freq_hz = 0.06}, vary_variants = 4}))
	_fx("skid_short", "A short skid or a brake lock",
		_rec(&"patch", {patch = P + "screech.tres", freq_hz = 1250.0, gate_s = 0.42, length_s = 0.75}, {fx = _level(-13.0),
			vary = {freq_hz = 0.08}, vary_variants = 4}))
	_fx("crash_heavy", "A big crash: the hit, crumpling metal, debris",
		_rec(&"kick", {tune_hz = 46.0, punch = 4.0, decay_s = 0.16, click = 0.8, drive = 0.7},
			{layers = [{voice = &"static", params = {length_s = 1.3, hiss = 0.9, color_hz = 1600.0, q = 0.5, crackles_per_s = 500.0, crackle = 1.0, flicker_hz = 18.0, flicker_depth = 0.5, fade_s = 0.4}, gain_db = -3.0},
				{voice = &"mallet", params = {freq_hz = 410.0, material = &"metal", decay_s = 0.5, damping = 0.4, hardness = 1.0}, gain_db = -5.0},
				{voice = &"mallet", params = {freq_hz = 1130.0, material = &"metal", decay_s = 0.35, damping = 0.5, hardness = 1.0}, offset_s = 0.04, gain_db = -8.0},
				{voice = &"ratchet", params = {length_s = 1.1, start_rate_hz = 45.0, end_rate_hz = 5.0, click_hz = 4200.0, q = 4.0, jitter = 0.45, fade = 0.9}, offset_s = 0.09, gain_db = -9.0}],
			fx = [{type = &"drive", amount = 0.35}, {type = &"room", room = 0.4, damp = 0.5, mix = 0.15, quality = &"small"}, {type = &"normalize", peak_db = -1.0}],
			transforms = [{type = &"trim", length_s = 2.4}, {type = &"fade", out_s = 0.6}],
			vary = {freq_hz = 0.1, tune_hz = 0.08}, vary_variants = 3}))
	_fx("bump", "A light knock between cars",
		_rec(&"boing", {start_hz = 260.0, end_hz = 80.0, drop_s = 0.04, decay_s = 0.09, click = 0.7, click_hz = 3000.0},
			{layers = [{voice = &"mallet", params = {freq_hz = 620.0, material = &"metal", decay_s = 0.12, hardness = 0.8}, gain_db = -10.0}],
			fx = [{type = &"normalize", peak_db = -1.0}], vary = {start_hz = 0.12, freq_hz = 0.12}, vary_variants = 4}))
	_fx("wall_scrape", "Grinding along a barrier",
		_rec(&"static", {length_s = 1.3, hiss = 0.6, color_hz = 2800.0, q = 1.8, crackles_per_s = 700.0, crackle = 0.9, flicker_hz = 28.0, flicker_depth = 0.6, fade_s = 0.08},
			{layers = [{voice = &"ratchet", params = {length_s = 1.3, start_rate_hz = 85.0, end_rate_hz = 55.0, click_hz = 5200.0, q = 9.0, jitter = 0.35, fade = 0.4}, gain_db = -4.0}],
			fx = [{type = &"bandpass", cutoff_hz = 3000.0, q = 0.8}] + _level(-13.0)}))
	_fx("countdown_beep", "Start lights: 3, 2, 1",
		_rec(&"tone", {wave = &"square", freq_hz = 880.0, attack_s = 0.002, decay_s = 0.05, sustain = 0.8, release_s = 0.04, gate_s = 0.22},
			{fx = [{type = &"lowpass", cutoff_hz = 5000.0}, {type = &"room", room = 0.3, damp = 0.5, mix = 0.12, quality = &"small"}, {type = &"normalize", peak_db = -3.0}]}))
	_fx("countdown_go", "Start lights: GO",
		_rec(&"tone", {wave = &"square", freq_hz = 1760.0, attack_s = 0.002, decay_s = 0.1, sustain = 0.85, release_s = 0.12, gate_s = 0.75},
			{layers = [{voice = &"tone", params = {wave = &"square", freq_hz = 880.0, attack_s = 0.002, decay_s = 0.1, sustain = 0.85, release_s = 0.12, gate_s = 0.75}, gain_db = -6.0}],
			fx = [{type = &"lowpass", cutoff_hz = 6000.0}, {type = &"room", room = 0.35, damp = 0.5, mix = 0.15, quality = &"small"}, {type = &"normalize", peak_db = -3.0}]}))
	_fx("nitro_boost", "Nitro: a rising rush",
		_rec(&"whoosh", {length_s = 1.3, low_hz = 300.0, high_hz = 9000.0, peak = 0.82, shape = 1.4, mode = &"band", q = 1.6, noise = &"pink"},
			{layers = [{voice = &"follow", params = {wave = &"saw", length_s = 1.3, pitch = [[0.0, 110.0], [1.1, 520.0], [1.3, 560.0]], level = [[0.0, 0.0], [0.9, 0.8], [1.3, 0.0]], glide = 0.3}, gain_db = -9.0}],
			fx = [{type = &"flanger", rate_hz = 0.8, depth_ms = 2.5, feedback = 0.6, mix = 0.45}, {type = &"drive", amount = 0.2}] + _level(-12.0)}))
	_fx("pass_by", "Another car passing close (left to right)",
		_rec(&"follow", {wave = &"saw", length_s = 1.8, pitch = [[0.0, 170.0], [0.75, 158.0], [1.0, 110.0], [1.8, 100.0]],
				level = [[0.0, 0.05], [0.8, 1.0], [0.95, 1.0], [1.8, 0.0]], glide = 0.35},
			{layers = [{voice = &"whoosh", params = {length_s = 1.8, low_hz = 200.0, high_hz = 2600.0, peak = 0.48, shape = 2.2, noise = &"brown"}, gain_db = -2.0},
				{voice = &"follow", params = {wave = &"square", length_s = 1.8, pitch = [[0.0, 85.0], [0.75, 79.0], [1.0, 55.0], [1.8, 50.0]],
					level = [[0.0, 0.05], [0.8, 0.8], [0.95, 0.8], [1.8, 0.0]], glide = 0.35}, gain_db = -6.0}],
			fx = [{type = &"lowpass", cutoff_hz = 1800.0}, {type = &"drive", amount = 0.4}] + _level(-12.0),
			transforms = [{type = &"width", amount = 1.6}]}))
	_fx("horn", "A car horn",
		_rec(&"tone", {wave = &"square", freq_hz = 415.0, attack_s = 0.01, decay_s = 0.05, sustain = 1.0, release_s = 0.04, gate_s = 0.55},
			{layers = [{voice = &"tone", params = {wave = &"square", freq_hz = 523.0, attack_s = 0.01, decay_s = 0.05, sustain = 1.0, release_s = 0.04, gate_s = 0.55}}],
			fx = [{type = &"bandpass", cutoff_hz = 1100.0, q = 0.9}, {type = &"drive", amount = 0.5}] + _level(-13.0)}))
	_fx("checkpoint", "Through a checkpoint: a bright glass run",
		_rec(&"mallet", {freq_hz = 1318.5, material = &"glass", decay_s = 0.35, hardness = 0.7},
			{layers = [{voice = &"mallet", params = {freq_hz = 1760.0, material = &"glass", decay_s = 0.35, hardness = 0.7}, offset_s = 0.07},
				{voice = &"mallet", params = {freq_hz = 2637.0, material = &"glass", decay_s = 0.6, hardness = 0.7}, offset_s = 0.14}],
			fx = [{type = &"room", room = 0.5, damp = 0.4, mix = 0.2}, {type = &"normalize", peak_db = -3.0}],
			transforms = [{type = &"trim", length_s = 1.8}, {type = &"fade", out_s = 0.5}]}))
	_fx("lap_complete", "Lap complete: two bells and a shimmer",
		_rec(&"fm", {freq_hz = 1046.5, ratio = 3.5, index = 3.0, index_end = 0.3, index_decay_s = 0.4, decay_s = 0.9, gate_s = 0.1},
			{layers = [{voice = &"fm", params = {freq_hz = 1568.0, ratio = 3.5, index = 3.0, index_end = 0.3, index_decay_s = 0.5, decay_s = 1.4, gate_s = 0.1}, offset_s = 0.14},
				{voice = &"hat", params = {decay_s = 0.6, tone_hz = 11000.0, metal = 0.3}, offset_s = 0.14, gain_db = -14.0}],
			fx = [{type = &"room", room = 0.55, damp = 0.4, mix = 0.22}, {type = &"normalize", peak_db = -3.0}],
			transforms = [{type = &"trim", length_s = 2.4}, {type = &"fade", out_s = 0.6}]}))
	var brass := "res://addons/audio_kit/patches/brass.tres"
	_fx("finish_fanfare", "Race won: a brass fanfare",
		_rec(&"patch", {patch = brass, freq_hz = 261.63, gate_s = 0.13, velocity = 0.8},
			{layers = [{voice = &"patch", params = {patch = brass, freq_hz = 329.63, gate_s = 0.13, velocity = 0.8}, offset_s = 0.16},
				{voice = &"patch", params = {patch = brass, freq_hz = 392.0, gate_s = 0.13, velocity = 0.85}, offset_s = 0.32},
				{voice = &"patch", params = {patch = brass, freq_hz = 523.25, gate_s = 1.0, velocity = 1.0}, offset_s = 0.48},
				{voice = &"patch", params = {patch = brass, freq_hz = 392.0, gate_s = 1.0, velocity = 0.8}, offset_s = 0.48, gain_db = -3.0},
				{voice = &"patch", params = {patch = brass, freq_hz = 329.63, gate_s = 1.0, velocity = 0.8}, offset_s = 0.48, gain_db = -3.0},
				{voice = &"hat", params = {decay_s = 1.2, tone_hz = 6500.0, metal = 0.75, tune = 0.8}, offset_s = 0.48, gain_db = -12.0}],
			fx = [{type = &"room", room = 0.6, damp = 0.4, mix = 0.2}, {type = &"normalize", peak_db = -1.0}],
			transforms = [{type = &"trim", length_s = 3.2}, {type = &"fade", out_s = 0.9}]}))
	_fx("item_pickup", "Collect a power-up (from the SFX generator, seed 304)", AKSfxGen.generate(&"pickup", 304))
	_fx("menu_select", "Menu: confirm (SFX generator, seed 12)", AKSfxGen.generate(&"ui_confirm", 12))
	_fx("menu_back", "Menu: back (SFX generator, seed 12)", AKSfxGen.generate(&"ui_cancel", 12))
	_fx("menu_move", "Menu: move between items (SFX generator, seed 5)", AKSfxGen.generate(&"ui_click", 5))


## Sustained sounds are levelled by loudness (so a screech and a horn sit
## together), then limited; short hits are peak-normalised instead.
func _level(lufs: float) -> Array:
	return [{type = &"loudness", target_lufs = lufs}, {type = &"limit", ceiling_db = -1.0}]


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var c := a.duplicate()
	c.merge(b, true)
	return c


func _fx(name: String, about: String, r: AKRecipe) -> void:
	SFX[name] = [r, about]
	_save(r, D + "sfx/" + name + ".tres")


# ------------------------------------------------------------------ the song

# "Neon Circuit": synthwave in A minor, 128 bpm, about a minute. Am F C G.
const BPM := 128.0
const PROG := ["Am", "F", "C", "G"]
const ROOT := {"Am": 33, "F": 29, "C": 36, "G": 31}               # bass, MIDI
const ARP := {"Am": [69, 72, 76, 81], "F": [65, 69, 72, 77], "C": [67, 72, 76, 79], "G": [67, 71, 74, 79]}
const PAD := {"Am": [57, 60, 64, 69], "F": [57, 60, 65, 69], "C": [55, 60, 64, 67], "G": [55, 59, 62, 67]}
const ARP_ORDER := [0, 1, 2, 3, 2, 1, 0, 1, 0, 1, 2, 3, 2, 1, 2, 3]
# The hook: (bar, beat, beats, midi) over two rounds of the progression.
const HOOK := [
	[0, 0.0, 1.5, 76], [0, 1.5, 0.5, 74], [0, 2.0, 1.0, 72], [0, 3.0, 1.0, 74],
	[1, 0.0, 1.5, 72], [1, 1.5, 0.5, 69], [1, 2.0, 2.0, 72],
	[2, 0.0, 1.0, 67], [2, 1.0, 1.0, 72], [2, 2.0, 1.5, 76], [2, 3.5, 0.5, 79],
	[3, 0.0, 2.0, 74], [3, 2.0, 1.0, 71], [3, 3.0, 1.0, 74],
	[4, 0.0, 1.0, 76], [4, 1.0, 1.5, 81], [4, 2.5, 0.5, 79], [4, 3.0, 1.0, 76],
	[5, 0.0, 1.5, 77], [5, 1.5, 0.5, 76], [5, 2.0, 2.0, 72],
	[6, 0.0, 1.0, 76], [6, 1.0, 1.0, 79], [6, 2.0, 2.0, 84],
	[7, 0.0, 1.5, 83], [7, 1.5, 0.5, 81], [7, 2.0, 1.0, 79], [7, 3.0, 1.0, 74],
]
# The break's answer: long notes, lower.
const BREAK := [[0, 0.0, 3.0, 69], [0, 3.0, 1.0, 72], [1, 0.0, 4.0, 69], [2, 0.0, 2.0, 67], [2, 2.0, 2.0, 72], [3, 0.0, 4.0, 71]]


func _song() -> void:
	var S := D + "song/"
	_save(_rec(&"kick", {tune_hz = 48.0, punch = 3.2, decay_s = 0.32, click = 0.35, drive = 0.3},
		{bind = {intensity = {gain_db = [-9.0, 0.0]}}}), S + "kick.tres")
	_save(_rec(&"snare", {tone_hz = 190.0, tone = 0.5, noise = 0.9, noise_hz = 6500.0, noise_decay_s = 0.18},
		{send = 0.15, fx = [{type = &"room", room = 0.85, damp = 0.35, mix = 0.7, quality = &"small", tail_s = 0.45}],
			transforms = [{type = &"trim", length_s = 0.36}, {type = &"fade", out_s = 0.05}], bind = {intensity = {gain_db = [-9.0, 0.0]}}}),
		S + "snare.tres")
	_save(_rec(&"clap", {bursts = 4, spacing_s = 0.01, tail_decay_s = 0.16, color_hz = 1400.0}, {send = 0.2}), S + "clap.tres")
	_save(_rec(&"hat", {decay_s = 0.045, tone_hz = 9000.0, metal = 0.5},
		{vary = {decay_s = 0.2}, vary_variants = 4, bind = {intensity = {gain_db = [-10.0, 0.0]}}}), S + "hat.tres")
	_save(_rec(&"hat", {decay_s = 0.28, tone_hz = 8000.0, metal = 0.6}, {}), S + "open_hat.tres")
	_save(_rec(&"hat", {decay_s = 1.6, tone_hz = 6500.0, metal = 0.75, tune = 0.8}, {send = 0.4}), S + "crash.tres")
	# A riser that lands on the downbeat with a crash (stingers play one recipe).
	_save(_rec(&"whoosh", {length_s = 1.9, low_hz = 300.0, high_hz = 9500.0, peak = 0.97, shape = 2.2, noise = &"pink"},
		{send = 0.5, offset_s = -1.85, layers = [{voice = &"hat", params = {decay_s = 1.6, tone_hz = 6500.0, metal = 0.75, tune = 0.8}, offset_s = 1.85, gain_db = -2.0}]}),
		S + "riser.tres")
	var tempo := AKTempoMap.new()
	tempo.bpm = BPM
	_save(tempo, S + "tempo.tres")

	var P := D + "patches/"
	var drums_full := [
		{name = "kick", recipe = S + "kick.tres", steps = "X...X...X...X...", length = 16},
		{name = "snare", recipe = S + "snare.tres", steps = "....X.......X...", length = 16},
		{name = "clap", recipe = S + "clap.tres", steps = "....x.......x...", length = 16, gain_db = -6.0},
		{name = "hat", recipe = S + "hat.tres", steps = "x.X.x.X.x.X.x.Xx", length = 16, gain_db = -5.0},
		{name = "open_hat", recipe = S + "open_hat.tres", steps = "..............x.", length = 16, gain_db = -9.0},
	]
	var sections := [
		["intro", 4, ["pad", "arp"]],
		["build", 4, ["pad", "arp", "bass", "hat_only"]],
		["race", 8, ["pad", "arp", "bass", "drums", "lead"]],
		["break", 4, ["pad", "arp_soft", "break_lead"]],
		["final_lap", 8, ["pad", "arp", "bass", "drums", "lead_high"]],
		["finish", 4, ["pad", "arp_soft", "end_hit"]],
	]
	var secs: Array[Dictionary] = []
	for s in sections:
		var name: String = s[0]
		var bars: int = s[1]
		var parts: Array = s[2]
		var pat := AKPattern.new()
		pat.steps = bars * 16
		var lanes: Array[Dictionary] = []
		if parts.has("pad"):
			lanes.append({name = "pad", patch = P + "neon_pad.tres", events = _pad(bars, name == "finish"), send = 0.35})
		if parts.has("arp") or parts.has("arp_soft"):
			lanes.append({name = "arp", patch = P + "neon_arp.tres", events = _arp(bars, 0.55 if parts.has("arp_soft") else 0.8), send = 0.25,
				gain_db = -3.0 if parts.has("arp_soft") else 0.0})
		if parts.has("bass"):
			lanes.append({name = "bass", patch = P + "neon_bass.tres", events = _bass(bars)})
		if parts.has("hat_only"):
			lanes.append({name = "hat", recipe = S + "hat.tres", steps = "..x...x...x...x.", length = 16, gain_db = -5.0})
			lanes.append({name = "kick", recipe = S + "kick.tres", steps = ".".repeat(48) + "X...X...X.X.XXXX", gain_db = -2.0})
		if parts.has("drums"):
			for d in drums_full:
				lanes.append(d.duplicate())
		if parts.has("lead"):
			lanes.append({name = "lead", patch = P + "neon_lead.tres", events = _melody(HOOK, 0, 0.9), send = 0.3})
		if parts.has("lead_high"):
			lanes.append({name = "lead", patch = P + "neon_lead.tres", events = _melody(HOOK, 12, 1.0), send = 0.3})
			lanes.append({name = "lead_low", patch = P + "neon_lead.tres", events = _melody(HOOK, 0, 0.6), send = 0.3, gain_db = -7.0})
		if parts.has("break_lead"):
			lanes.append({name = "lead", patch = P + "neon_lead.tres", events = _melody(BREAK, 0, 0.65), send = 0.45, gain_db = -2.0})
		if parts.has("end_hit"):
			lanes.append({name = "kick", recipe = S + "kick.tres", steps = "X" + ".".repeat(bars * 16 - 1)})
			lanes.append({name = "crash", recipe = S + "crash.tres", steps = "X" + ".".repeat(bars * 16 - 1), gain_db = -6.0})
			lanes.append({name = "bass", patch = P + "neon_bass.tres", events = [[0.0, 3.0, 33, 1.0]]})
		pat.lanes = lanes
		_save(pat, S + "p_%s.tres" % name)
		var sec := {name = name, bars = bars, patterns = [S + "p_%s.tres" % name]}
		secs.append(sec)
	var song := AKSong.new()
	song.tempo = load(S + "tempo.tres")
	song.sections = secs
	song.mix = {"pad": {gain_db = 7.0}, "arp": {gain_db = 5.0}, "bass": {gain_db = 0.0}, "lead": {gain_db = 1.0},
		"kick": {gain_db = 0.0}, "snare": {gain_db = -3.0}}
	song.reverb = {room = 0.7, damp = 0.45, width = 1.0, quality = &"full", return_db = -2.0}
	var st: Array[Dictionary] = [{to = "race", recipe = S + "riser.tres", gain_db = -6.0}, {to = "final_lap", recipe = S + "riser.tres", gain_db = -6.0}]
	song.stingers = st
	_save(song, S + "neon_circuit.tres")


## Pad chords: one per bar, held the whole bar.
func _pad(bars: int, last := false) -> Array:
	var ev := []
	for b in bars:
		var c: String = PROG[b % 4] if not last or b < bars - 1 else "Am"
		var len := 4.0 if not (last and b == bars - 1) else 6.0
		for n in PAD[c]:
			ev.append([b * 4.0, len - 0.05, n, 0.7])
	return ev


## Sixteenth-note arpeggio over each bar's chord, accents on the beat.
func _arp(bars: int, vel: float) -> Array:
	var ev := []
	for b in bars:
		var c: String = PROG[b % 4]
		for i in 16:
			var accent := 1.0 if i % 4 == 0 else 0.8
			ev.append([b * 4.0 + i * 0.25, 0.2, ARP[c][ARP_ORDER[i]], vel * accent])
	return ev


## Eighth-note octave bass, the root then its octave, pumping.
func _bass(bars: int) -> Array:
	var ev := []
	for b in bars:
		var r: int = ROOT[PROG[b % 4]]
		for i in 8:
			ev.append([b * 4.0 + i * 0.5, 0.4, r + (12 if i % 2 == 1 else 0), 1.0 if i % 2 == 0 else 0.75])
	return ev


## A melody table (bar, beat, beats, midi) as events, repeated to fill.
func _melody(table: Array, transpose: int, vel: float) -> Array:
	var ev := []
	for n in table:
		ev.append([n[0] * 4.0 + n[1], n[2] * 0.95, n[3] + transpose, vel])
	return ev


# ------------------------------------------------------------------ baking

func _bake() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "sfx")
	var lines := []
	for name in SFX:
		var r: AKRecipe = SFX[name][0]
		var buf := AK.render(r)
		if name.begins_with("engine_") and name != "engine_rev" and name != "engine_start":
			buf = AKLive.make_loop(buf, 0.3)
		AK.save_wav(buf, OUT + "sfx/%s.wav" % name)
		var f := AKSoundFeatures.of(buf)
		lines.append("%-15s %5.2f s  %6.1f LUFS  peak %5.1f dB  centroid %5.0f Hz" % [name, buf.seconds(), float(f.get("lufs", 0.0)),
			linear_to_db(buf.peak()), float(f.get("centroid_hz", 0.0))])
	var song: AKSong = load(D + "song/neon_circuit.tres")
	var t := Time.get_ticks_msec()
	var res := song.render()
	var mix: AKBuffer = res.mix
	AK.save_wav(mix, OUT + "neon_circuit.wav")
	lines.append("neon_circuit    %5.2f s  peak %5.1f dB  (%d ms to render)" % [mix.seconds(), linear_to_db(mix.peak()), Time.get_ticks_msec() - t])
	for l in lines:
		print(l)
