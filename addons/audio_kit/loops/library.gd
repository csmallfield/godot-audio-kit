# SPDX-License-Identifier: Apache-2.0
@tool
## The kit-made sample library: about 120 one-shots synthesized by the kit's
## own voices, shipped as recipes (text, nothing binary to license) and
## rendered on demand, plus five drum kits built from them. All original
## designs, Apache-2.0.
##
## `tools/make_library.gd` writes them to DIR (a folder per category, kits
## in `kits/`); a test fails if the files go stale. Every sound ends with a
## DC block and a peak normalise to -3 dBFS, so sounds of one kind sit at one
## level and kits balance them with each piece's `gain_db`. Pitched sounds
## record the note they were made at as metadata `ak_root_note` (unpitched
## ones -1); `sample_for(path)` makes an AKSample with that root.
class_name AKLibrary
extends RefCounted

const DIR := "res://addons/audio_kit/library/"
const KITS_DIR := "res://addons/audio_kit/library/kits/"
## Bump when a sound's design changes (the recipes carry it as metadata).
const VERSION := 1
const FOLDERS := ["kicks", "snares", "claps", "hats", "cymbals", "toms", "perc", "bass", "keys", "pads", "fx", "vox"]
const KIT_NAMES := ["boom", "punch", "room", "lo-fi", "electro"]


## Every sound: [{folder, name, root (MIDI, -1 = unpitched), recipe}].
static func sounds() -> Array:
	var out := []
	for folder in FOLDERS:
		for e: Array in _defs(folder):
			var r: AKRecipe = e[2]
			var root := int(e[1])
			r.resource_name = String(e[0])
			r.fx.append({type = &"dcblock"})
			r.fx.append({type = &"normalize", peak_db = -3.0})
			r.set_meta(&"ak_category", folder)
			r.set_meta(&"ak_root_note", root)
			r.set_meta(&"ak_library_version", VERSION)
			out.append({folder = folder, name = String(e[0]), root = root, recipe = r})
	return out


static func path_of(folder: String, sound: String) -> String:
	return DIR + folder + "/" + sound + ".tres"


## Pitched samples play this much under the sounds' −3 dBFS, so one note
## peaks near −6 dBFS as a preset patch does, leaving room for chords.
const PITCHED_TRIM_DB := -3.0


## An AKSample of a library recipe (or any recipe file), rooted at its
## `ak_root_note` (C4 when it has none); pitched ones trimmed by PITCHED_TRIM_DB.
static func sample_for(path: String, mode := "oneshot") -> AKSample:
	var r: AKRecipe = load(path)
	if r == null:
		return null
	var root := int(r.get_meta(&"ak_root_note", -1))
	var s := AKSample.from_recipe(r, float(root) if root >= 0 else 60.0, mode)
	s.resource_name = r.resource_name
	if root >= 0:
		s.gain_db = PITCHED_TRIM_DB
	return s


# ------------------------------------------------------------------ sounds

static func _r(voice: StringName, params: Dictionary, fx: Array = [], layers: Array = [], transforms: Array = []) -> AKRecipe:
	var r := AKRecipe.new()
	r.voice = voice
	r.params = params
	for f: Dictionary in fx:
		r.fx.append(f.duplicate(true))
	for l: Dictionary in layers:
		r.layers.append(l.duplicate(true))
	for t: Dictionary in transforms:
		r.transforms.append(t.duplicate(true))
	return r


static func _hz(midi: int) -> float:
	return snappedf(440.0 * pow(2.0, (midi - 69) / 12.0), 0.001)


const _CRUSH := {type = &"bitcrush", bits = 8.0, hold = 3}
const _DUSTY := {type = &"lowpass", cutoff_hz = 4500.0, q = 0.6}
const _ROOM := {type = &"room", room = 0.45, damp = 0.4, mix = 0.28, quality = &"small"}


## [name, root, recipe] per sound in `folder`.
static func _defs(folder: String) -> Array:
	match folder:
		"kicks":
			return [
				["kick_round", -1, _r(&"kick", {tune_hz = 52.0, punch = 3.0, drop_s = 0.03, decay_s = 0.32, click = 0.4, drive = 0.2})],
				["kick_punch", -1, _r(&"kick", {tune_hz = 58.0, punch = 4.0, drop_s = 0.018, decay_s = 0.18, click = 0.7, drive = 0.35})],
				["kick_sub", -1, _r(&"kick", {tune_hz = 42.0, punch = 1.5, drop_s = 0.04, decay_s = 0.6, click = 0.1, drive = 0.05})],
				["kick_boom_long", -1, _r(&"kick", {tune_hz = 45.0, punch = 2.5, drop_s = 0.05, decay_s = 1.1, click = 0.2, drive = 0.15})],
				["kick_909", -1, _r(&"kick", {tune_hz = 55.0, punch = 5.0, drop_s = 0.012, decay_s = 0.28, click = 0.8, drive = 0.45})],
				["kick_tight", -1, _r(&"kick", {tune_hz = 65.0, punch = 3.5, drop_s = 0.01, decay_s = 0.09, click = 0.6, drive = 0.2})],
				["kick_click", -1, _r(&"kick", {tune_hz = 70.0, punch = 6.0, drop_s = 0.006, decay_s = 0.07, click = 1.0, drive = 0.1})],
				["kick_dusty", -1, _r(&"kick", {tune_hz = 50.0, punch = 2.5, drop_s = 0.03, decay_s = 0.3, click = 0.3, drive = 0.5}, [_DUSTY, _CRUSH])],
				["kick_room", -1, _r(&"kick", {tune_hz = 54.0, punch = 3.0, drop_s = 0.025, decay_s = 0.25, click = 0.5, drive = 0.25}, [_ROOM])],
				["kick_distorted", -1, _r(&"kick", {tune_hz = 50.0, punch = 4.0, drop_s = 0.02, decay_s = 0.4, click = 0.5, drive = 1.0}, [{type = &"saturate", drive_db = 10.0, tone_hz = 5000.0}])],
				["kick_soft", -1, _r(&"kick", {tune_hz = 60.0, punch = 1.2, drop_s = 0.03, decay_s = 0.2, click = 0.05, drive = 0.0})],
				["kick_deep", -1, _r(&"kick", {tune_hz = 38.0, punch = 2.0, drop_s = 0.06, decay_s = 0.8, click = 0.25, drive = 0.3})],
				["kick_electro", -1, _r(&"kick", {tune_hz = 48.0, punch = 7.0, drop_s = 0.015, decay_s = 0.45, click = 0.6, drive = 0.6})],
				["kick_thump", -1, _r(&"kick", {tune_hz = 75.0, punch = 1.8, drop_s = 0.02, decay_s = 0.12, click = 0.3, drive = 0.2}, [{type = &"lowpass", cutoff_hz = 2500.0}])],
			]
		"snares":
			return [
				["snare_tight", -1, _r(&"snare", {tone_hz = 210.0, tone = 0.5, tone_decay_s = 0.05, noise = 0.8, noise_hz = 6000.0, noise_decay_s = 0.1})],
				["snare_fat", -1, _r(&"snare", {tone_hz = 170.0, tone = 0.8, tone_decay_s = 0.12, noise = 0.7, noise_hz = 4500.0, noise_decay_s = 0.2})],
				["snare_crack", -1, _r(&"snare", {tone_hz = 250.0, tone = 0.4, tone_decay_s = 0.04, noise = 1.0, noise_hz = 8000.0, noise_decay_s = 0.08}, [{type = &"eq", high_db = 4.0}])],
				["snare_808", -1, _r(&"snare", {tone_hz = 180.0, tone = 0.7, tone_decay_s = 0.09, noise = 0.6, noise_hz = 7000.0, noise_decay_s = 0.15})],
				["snare_909", -1, _r(&"snare", {tone_hz = 195.0, tone = 0.55, tone_decay_s = 0.07, noise = 0.9, noise_hz = 6500.0, noise_decay_s = 0.18}, [{type = &"drive", amount = 0.3}])],
				["snare_room", -1, _r(&"snare", {tone_hz = 190.0, tone = 0.5, tone_decay_s = 0.08, noise = 0.8, noise_hz = 5200.0, noise_decay_s = 0.16}, [_ROOM])],
				["snare_dusty", -1, _r(&"snare", {tone_hz = 200.0, tone = 0.6, tone_decay_s = 0.07, noise = 0.8, noise_hz = 5000.0, noise_decay_s = 0.14}, [_DUSTY, _CRUSH])],
				["snare_brush", -1, _r(&"snare", {tone_hz = 220.0, tone = 0.15, tone_decay_s = 0.04, noise = 0.9, noise_hz = 3500.0, noise_decay_s = 0.3}, [{type = &"lowpass", cutoff_hz = 6000.0}])],
				["snare_rimshot", -1, _r(&"snare", {tone_hz = 330.0, tone = 0.7, tone_decay_s = 0.03, noise = 0.6, noise_hz = 7500.0, noise_decay_s = 0.06},
					[], [{voice = &"click", gain_db = -4.0, params = {mode = &"band", freq_hz = 1800.0, q = 6.0, decay_s = 0.01}}])],
				["snare_electro", -1, _r(&"snare", {tone_hz = 160.0, tone = 0.6, tone_decay_s = 0.1, noise = 0.9, noise_hz = 9000.0, noise_decay_s = 0.12}, [{type = &"bitcrush", bits = 10.0, hold = 2}])],
				["snare_soft", -1, _r(&"snare", {tone_hz = 185.0, tone = 0.4, tone_decay_s = 0.06, noise = 0.5, noise_hz = 3800.0, noise_decay_s = 0.12})],
				["snare_long", -1, _r(&"snare", {tone_hz = 175.0, tone = 0.6, tone_decay_s = 0.15, noise = 0.8, noise_hz = 5500.0, noise_decay_s = 0.45})],
			]
		"claps":
			return [
				["clap_classic", -1, _r(&"clap", {})],
				["clap_tight", -1, _r(&"clap", {bursts = 3, spacing_s = 0.008, tail_decay_s = 0.07, color_hz = 1400.0})],
				["clap_wide", -1, _r(&"clap", {bursts = 4, spacing_s = 0.014, tail_decay_s = 0.18, color_hz = 1100.0, q = 0.9})],
				["clap_808", -1, _r(&"clap", {bursts = 4, spacing_s = 0.01, tail_decay_s = 0.2, color_hz = 1000.0, q = 1.0})],
				["clap_room", -1, _r(&"clap", {bursts = 3, spacing_s = 0.011, tail_decay_s = 0.14, color_hz = 1300.0}, [_ROOM])],
				["clap_dusty", -1, _r(&"clap", {bursts = 3, spacing_s = 0.012, tail_decay_s = 0.12, color_hz = 1200.0}, [_DUSTY, _CRUSH])],
				["clap_snap", -1, _r(&"clap", {bursts = 1, burst_decay_s = 0.004, tail_decay_s = 0.05, color_hz = 2600.0, q = 2.0})],
				["clap_crowd", -1, _r(&"clap", {bursts = 6, spacing_s = 0.017, burst_decay_s = 0.008, tail_decay_s = 0.22, color_hz = 1200.0, q = 0.7})],
			]
		"hats":
			return [
				["hat_closed", -1, _r(&"hat", {decay_s = 0.045, tone_hz = 8500.0})],
				["hat_closed_tight", -1, _r(&"hat", {decay_s = 0.025, tone_hz = 9500.0, metal = 0.7})],
				["hat_closed_soft", -1, _r(&"hat", {decay_s = 0.05, tone_hz = 7000.0, metal = 0.4}, [{type = &"lowpass", cutoff_hz = 9000.0}])],
				["hat_closed_808", -1, _r(&"hat", {decay_s = 0.04, tone_hz = 8000.0, metal = 0.9, tune = 1.0})],
				["hat_closed_dusty", -1, _r(&"hat", {decay_s = 0.05, tone_hz = 7500.0, metal = 0.6}, [_DUSTY, _CRUSH])],
				["hat_open", -1, _r(&"hat", {decay_s = 0.35, tone_hz = 8000.0})],
				["hat_open_short", -1, _r(&"hat", {decay_s = 0.18, tone_hz = 8500.0, metal = 0.7})],
				["hat_open_808", -1, _r(&"hat", {decay_s = 0.4, tone_hz = 7800.0, metal = 0.9, tune = 1.0})],
				["hat_open_dusty", -1, _r(&"hat", {decay_s = 0.3, tone_hz = 7000.0, metal = 0.6}, [_DUSTY, _CRUSH])],
				["hat_pedal", -1, _r(&"hat", {decay_s = 0.06, tone_hz = 6500.0, metal = 0.5}, [{type = &"highpass", cutoff_hz = 3000.0}])],
				["hat_pedal_808", -1, _r(&"hat", {decay_s = 0.07, tone_hz = 7200.0, metal = 0.85, tune = 0.9}, [{type = &"highpass", cutoff_hz = 2500.0}])],
				["hat_room", -1, _r(&"hat", {decay_s = 0.06, tone_hz = 8200.0, metal = 0.6}, [_ROOM])],
				["hat_open_room", -1, _r(&"hat", {decay_s = 0.3, tone_hz = 7800.0, metal = 0.6}, [_ROOM])],
				["hat_noise", -1, _r(&"hat", {decay_s = 0.04, tone_hz = 10000.0, metal = 0.0})],
			]
		"cymbals":
			return [
				["crash", -1, _r(&"hat", {decay_s = 1.4, tone_hz = 6500.0, metal = 0.75, tune = 0.8})],
				["crash_bright", -1, _r(&"hat", {decay_s = 1.2, tone_hz = 8500.0, metal = 0.8, tune = 1.1})],
				["crash_dark", -1, _r(&"hat", {decay_s = 1.8, tone_hz = 5000.0, metal = 0.7, tune = 0.7}, [{type = &"lowpass", cutoff_hz = 7000.0}])],
				["ride", -1, _r(&"hat", {decay_s = 0.7, tone_hz = 9500.0, metal = 0.85, tune = 1.3})],
				["ride_dry", -1, _r(&"hat", {decay_s = 0.4, tone_hz = 10000.0, metal = 0.9, tune = 1.4})],
				["ride_bell", -1, _r(&"mallet", {freq_hz = 1900.0, material = &"metal", decay_s = 0.5, hardness = 0.7})],
				["splash", -1, _r(&"hat", {decay_s = 0.6, tone_hz = 9000.0, metal = 0.8, tune = 1.5})],
				["china", -1, _r(&"hat", {decay_s = 1.0, tone_hz = 5500.0, metal = 1.0, tune = 0.6}, [{type = &"drive", amount = 0.4}])],
			]
		"toms":
			var out := []
			for style in [["", 0.3, []], ["_electro", 0.6, [{type = &"drive", amount = 0.25}]], ["_room", 0.35, [_ROOM]]]:
				for t in [["low", 120.0, 80.0, 0.25], ["mid", 170.0, 115.0, 0.22], ["high", 240.0, 160.0, 0.2]]:
					var is_el: bool = style[0] == "_electro"
					out.append(["tom_%s%s" % [t[0], style[0]], -1, _r(&"boing", {start_hz = t[1] * (1.6 if is_el else 1.0), end_hz = t[2],
						drop_s = 0.12 if is_el else 0.07, decay_s = t[3] * (1.3 if is_el else 1.0), click = style[1], sub = 0.2 if t[0] == "low" else 0.0}, style[2])])
			return out
		"perc":
			return [
				["rim", -1, _r(&"click", {mode = &"band", freq_hz = 1700.0, q = 6.0, decay_s = 0.012, body_hz = 400.0, body = 0.4})],
				["rim_dry", -1, _r(&"click", {mode = &"band", freq_hz = 2200.0, q = 8.0, decay_s = 0.008, body_hz = 500.0, body = 0.3})],
				["cowbell", -1, _r(&"tone", {wave = &"square", freq_hz = 560.0, attack_s = 0.001, decay_s = 0.12, sustain = 0.0, gate_s = 0.1, release_s = 0.04},
					[{type = &"bandpass", cutoff_hz = 800.0, q = 1.5}],
					[{voice = &"tone", gain_db = -3.0, params = {wave = &"square", freq_hz = 845.0, attack_s = 0.001, decay_s = 0.1, sustain = 0.0, gate_s = 0.1, release_s = 0.04}}])],
				["cowbell_808", -1, _r(&"tone", {wave = &"square", freq_hz = 540.0, attack_s = 0.001, decay_s = 0.25, sustain = 0.0, gate_s = 0.2, release_s = 0.08},
					[{type = &"bandpass", cutoff_hz = 900.0, q = 1.2}],
					[{voice = &"tone", gain_db = -2.0, params = {wave = &"square", freq_hz = 800.0, attack_s = 0.001, decay_s = 0.22, sustain = 0.0, gate_s = 0.2, release_s = 0.08}}])],
				["clave", -1, _r(&"mallet", {freq_hz = 2500.0, material = &"wood", decay_s = 0.05, hardness = 0.9})],
				["wood_block_high", -1, _r(&"mallet", {freq_hz = 1100.0, material = &"wood", decay_s = 0.06, hardness = 0.8})],
				["wood_block_low", -1, _r(&"mallet", {freq_hz = 700.0, material = &"wood", decay_s = 0.07, hardness = 0.75})],
				["conga_high", -1, _r(&"boing", {start_hz = 340.0, end_hz = 260.0, drop_s = 0.03, decay_s = 0.15, click = 0.5})],
				["conga_low", -1, _r(&"boing", {start_hz = 260.0, end_hz = 190.0, drop_s = 0.035, decay_s = 0.2, click = 0.45})],
				["bongo_high", -1, _r(&"boing", {start_hz = 520.0, end_hz = 430.0, drop_s = 0.02, decay_s = 0.09, click = 0.6})],
				["bongo_low", -1, _r(&"boing", {start_hz = 400.0, end_hz = 320.0, drop_s = 0.025, decay_s = 0.11, click = 0.55})],
				["shaker", -1, _r(&"static", {length_s = 0.09, hiss = 0.8, color_hz = 7000.0, q = 0.8, crackles_per_s = 0.0, fade_s = 0.04})],
				["shaker_long", -1, _r(&"static", {length_s = 0.18, hiss = 0.8, color_hz = 6000.0, q = 0.7, crackles_per_s = 0.0, fade_s = 0.08})],
				["tambourine", -1, _r(&"hat", {decay_s = 0.12, tone_hz = 11000.0, metal = 0.9, tune = 1.6})],
				["triangle", -1, _r(&"mallet", {freq_hz = 3200.0, material = &"metal", decay_s = 0.9, damping = 0.3, hardness = 0.6})],
				["snap", -1, _r(&"click", {mode = &"band", freq_hz = 2800.0, q = 2.5, decay_s = 0.015})],
			]
		"bass":
			return [
				["bass_sub", 36, _r(&"tone", {wave = &"sine", freq_hz = _hz(36), attack_s = 0.003, decay_s = 0.6, sustain = 0.6, gate_s = 0.6, release_s = 0.15})],
				["bass_808", 36, _r(&"tone", {wave = &"sine", freq_hz = _hz(43), end_hz = _hz(36), glide_s = 0.03, attack_s = 0.001, decay_s = 1.2, sustain = 0.0, gate_s = 1.0, release_s = 0.3},
					[{type = &"saturate", drive_db = 6.0, tone_hz = 3000.0}])],
				["bass_saw", 36, _r(&"wavetable", {freq_hz = _hz(36), position = 0.66, cutoff_hz = 600.0, env_octaves = 3.0, filter_decay_s = 0.15, gate_s = 0.4})],
				["bass_square", 36, _r(&"wavetable", {freq_hz = _hz(36), position = 1.0, cutoff_hz = 500.0, env_octaves = 2.5, filter_decay_s = 0.12, gate_s = 0.4, sub = 0.4})],
				["bass_reese", 36, _r(&"wavetable", {freq_hz = _hz(36), position = 0.66, unison = 3, detune_cents = 25.0, cutoff_hz = 800.0, env_octaves = 1.0, gate_s = 0.8, sustain = 0.8})],
				["bass_fm", 36, _r(&"fm", {freq_hz = _hz(36), ratio = 1.0, index = 4.0, index_end = 0.8, index_decay_s = 0.15, decay_s = 0.5, sustain = 0.3, gate_s = 0.4})],
				["bass_fm_growl", 36, _r(&"fm", {freq_hz = _hz(36), ratio = 2.0, index = 6.0, index_end = 2.0, index_decay_s = 0.3, ratio2 = 3.0, index2 = 1.5, decay_s = 0.6, sustain = 0.5, gate_s = 0.5})],
				["bass_pluck", 36, _r(&"pluck", {freq_hz = _hz(36), decay_s = 0.6, brightness = 0.35, tone_hz = 2500.0})],
				["bass_acid", 36, _r(&"wavetable", {freq_hz = _hz(36), position = 0.66, cutoff_hz = 300.0, env_octaves = 5.0, filter_decay_s = 0.12, q = 6.0, gate_s = 0.3, sustain = 0.4},
					[{type = &"drive", amount = 0.4}])],
				["bass_wood", 36, _r(&"mallet", {freq_hz = _hz(36), material = &"wood", decay_s = 0.5, hardness = 0.3})],
				["bass_soft", 36, _r(&"tone", {wave = &"triangle", freq_hz = _hz(36), attack_s = 0.01, decay_s = 0.4, sustain = 0.5, gate_s = 0.5, release_s = 0.12})],
				["bass_pulse", 36, _r(&"tone", {wave = &"pulse", width = 0.25, freq_hz = _hz(36), attack_s = 0.002, decay_s = 0.3, sustain = 0.4, gate_s = 0.4, release_s = 0.1},
					[{type = &"lowpass", cutoff_hz = 1200.0, q = 1.2}])],
			]
		"keys":
			return [
				["pluck_bright", 60, _r(&"pluck", {freq_hz = _hz(60), decay_s = 0.8, brightness = 0.7, tone_hz = 9000.0})],
				["pluck_soft", 60, _r(&"pluck", {freq_hz = _hz(60), decay_s = 0.5, brightness = 0.3, tone_hz = 4000.0})],
				["harp", 60, _r(&"pluck", {freq_hz = _hz(60), decay_s = 1.6, brightness = 0.55, tone_hz = 7000.0})],
				["marimba", 60, _r(&"mallet", {freq_hz = _hz(60), material = &"bar", decay_s = 0.45, hardness = 0.45})],
				["vibes", 60, _r(&"mallet", {freq_hz = _hz(60), material = &"metal", decay_s = 1.4, damping = 0.9, hardness = 0.35})],
				["glass", 72, _r(&"mallet", {freq_hz = _hz(72), material = &"glass", decay_s = 1.0, hardness = 0.5})],
				["kalimba", 60, _r(&"mallet", {freq_hz = _hz(60), material = &"bar", decay_s = 0.7, damping = 1.2, hardness = 0.7})],
				["music_box", 72, _r(&"mallet", {freq_hz = _hz(72), material = &"metal", decay_s = 0.8, damping = 1.4, hardness = 0.8})],
				["epiano", 60, _r(&"fm", {freq_hz = _hz(60), ratio = 1.0, index = 2.0, index_end = 0.3, index_decay_s = 0.4, decay_s = 1.2, sustain = 0.0, gate_s = 1.0, release_s = 0.3})],
				["fm_bell", 72, _r(&"fm", {freq_hz = _hz(72), ratio = 3.5, index = 3.0, index_end = 0.5, index_decay_s = 0.8, decay_s = 2.0, sustain = 0.0, gate_s = 1.5, release_s = 0.5})],
				["steel_drum", 60, _r(&"fm", {freq_hz = _hz(60), ratio = 2.0, index = 1.5, index_end = 0.2, index_decay_s = 0.2, decay_s = 0.6, sustain = 0.0, gate_s = 0.5})],
				["organ_hit", 60, _r(&"tone", {wave = &"square", freq_hz = _hz(60), attack_s = 0.004, decay_s = 0.2, sustain = 0.7, gate_s = 0.4, release_s = 0.08},
					[{type = &"lowpass", cutoff_hz = 2500.0}, {type = &"chorus", rate_hz = 5.0, depth_ms = 1.5, mix = 0.4}],
					[{voice = &"tone", gain_db = -6.0, params = {wave = &"sine", freq_hz = _hz(72), attack_s = 0.004, decay_s = 0.2, sustain = 0.7, gate_s = 0.4, release_s = 0.08}}])],
			]
		"pads":
			return [
				["pad_warm", 48, _r(&"wavetable", {freq_hz = _hz(48), position = 0.5, unison = 3, detune_cents = 14.0, cutoff_hz = 1200.0, env_octaves = 0.5, attack_s = 0.6, sustain = 0.8, gate_s = 2.5, release_s = 0.8},
					[{type = &"chorus", mix = 0.4}])],
				["pad_bright", 48, _r(&"wavetable", {freq_hz = _hz(48), position = 0.66, unison = 5, detune_cents = 20.0, cutoff_hz = 3500.0, env_octaves = 0.5, attack_s = 0.4, sustain = 0.8, gate_s = 2.5, release_s = 0.8},
					[{type = &"chorus", mix = 0.5}])],
				["pad_glass", 60, _r(&"fm", {freq_hz = _hz(60), ratio = 2.0, index = 1.2, index_end = 0.6, index_decay_s = 1.5, attack_s = 0.5, decay_s = 2.0, sustain = 0.7, gate_s = 2.5, release_s = 0.8})],
				["pad_hollow", 48, _r(&"wavetable", {freq_hz = _hz(48), position = 0.2, unison = 2, detune_cents = 8.0, sub = 0.3, cutoff_hz = 900.0, env_octaves = 0.2, attack_s = 0.8, sustain = 0.9, gate_s = 2.5, release_s = 1.0})],
				["drone_low", 36, _r(&"wavetable", {freq_hz = _hz(36), position = 0.8, unison = 4, detune_cents = 10.0, cutoff_hz = 500.0, env_octaves = 0.3, attack_s = 1.0, sustain = 1.0, gate_s = 3.0, release_s = 1.0},
					[{type = &"phaser", rate_hz = 0.15, mix = 0.5}])],
				["texture_air", -1, _r(&"whoosh", {length_s = 2.5, low_hz = 1200.0, high_hz = 6000.0, peak = 0.5, shape = 1.0, q = 0.9, mode = &"band", noise = &"pink"})],
				["texture_vinyl", -1, _r(&"static", {length_s = 2.5, hiss = 0.3, color_hz = 3000.0, crackles_per_s = 25.0, crackle = 0.8, fade_s = 0.2})],
				["texture_wind", -1, _r(&"whoosh", {length_s = 3.0, low_hz = 300.0, high_hz = 1800.0, peak = 0.4, shape = 0.8, q = 2.0, mode = &"band", noise = &"brown"})],
			]
		"fx":
			return [
				["riser", -1, _r(&"whoosh", {length_s = 2.0, low_hz = 300.0, high_hz = 9000.0, peak = 0.92, shape = 2.0, q = 2.0, mode = &"band"})],
				["riser_tone", -1, _r(&"tone", {wave = &"saw", freq_hz = 200.0, end_hz = 1600.0, glide_s = 0.8, attack_s = 1.2, decay_s = 0.4, sustain = 1.0, gate_s = 1.8, release_s = 0.05},
					[{type = &"lowpass", cutoff_hz = 3000.0}])],
				["downlifter", -1, _r(&"whoosh", {length_s = 1.6, low_hz = 200.0, high_hz = 8000.0, peak = 0.08, shape = 1.5, q = 1.5, mode = &"band"})],
				["impact", -1, _r(&"kick", {tune_hz = 40.0, punch = 4.0, drop_s = 0.05, decay_s = 0.7, click = 0.8, drive = 0.6}, [{type = &"room", room = 0.7, damp = 0.4, mix = 0.35, quality = &"small"}],
					[{voice = &"static", gain_db = -6.0, params = {length_s = 0.6, hiss = 0.9, color_hz = 1500.0, crackles_per_s = 0.0, fade_s = 0.3}}])],
				["zap", -1, _r(&"tone", {wave = &"square", freq_hz = 2400.0, end_hz = 120.0, glide_s = 0.06, attack_s = 0.0, decay_s = 0.2, sustain = 0.0, gate_s = 0.15, release_s = 0.03})],
				["sweep_noise", -1, _r(&"whoosh", {length_s = 1.0, low_hz = 400.0, high_hz = 7000.0, peak = 0.5, q = 4.0, mode = &"band"})],
				["reverse_crash", -1, _r(&"hat", {decay_s = 0.8, tone_hz = 7000.0, metal = 0.75, tune = 0.8}, [], [], [{type = &"reverse"}])],
				["tape_stop", -1, _r(&"tone", {wave = &"saw", freq_hz = 220.0, attack_s = 0.0, decay_s = 0.5, sustain = 0.8, gate_s = 0.8, release_s = 0.05},
					[{type = &"lowpass", cutoff_hz = 2000.0}], [], [{type = &"varispeed", from = 1.0, to = 0.0}])],
				["glitch", -1, _r(&"ratchet", {length_s = 0.4, start_rate_hz = 60.0, end_rate_hz = 20.0, click_hz = 2000.0, q = 4.0, jitter = 0.3}, [{type = &"bitcrush", bits = 6.0, hold = 4}])],
			]
		"vox":
			var out := []
			for v in [["ah", 730.0, 1090.0], ["eh", 530.0, 1840.0], ["ee", 300.0, 2300.0], ["oh", 570.0, 840.0], ["oo", 340.0, 870.0]]:
				out.append(["vox_" + v[0], 57, _r(&"reed", {freq_hz = _hz(57), formant1_hz = v[1], formant2_hz = v[2], formants = 1.6, breath = 0.18, growl = 0.05,
					scoop_semitones = 0.4, vibrato_cents = 15.0, attack_s = 0.03, sustain = 0.7, gate_s = 0.5, release_s = 0.12})])
			out.append(["vox_hey", 57, _r(&"reed", {freq_hz = _hz(57), formant1_hz = 600.0, formant2_hz = 1900.0, formants = 1.8, breath = 0.35, growl = 0.3,
				scoop_semitones = 2.0, scoop_s = 0.04, vibrato_cents = 0.0, attack_s = 0.01, decay_s = 0.15, sustain = 0.3, gate_s = 0.2, release_s = 0.08})])
			return out
	return []


# ------------------------------------------------------------------ kits

## The five default kits, made from library paths:
## boom (long 808-style kick and sub), punch (tight and dry), room (in a
## small room), lo-fi (dusty and crushed), electro (bright 909-style).
static func kits() -> Array:
	var out := []
	var kick := {"boom": "kick_boom_long", "punch": "kick_punch", "room": "kick_room", "lo-fi": "kick_dusty", "electro": "kick_909"}
	var snare := {"boom": "snare_808", "punch": "snare_tight", "room": "snare_room", "lo-fi": "snare_dusty", "electro": "snare_909"}
	var clap := {"boom": "clap_808", "punch": "clap_tight", "room": "clap_room", "lo-fi": "clap_dusty", "electro": "clap_classic"}
	var ch := {"boom": "hat_closed_808", "punch": "hat_closed_tight", "room": "hat_room", "lo-fi": "hat_closed_dusty", "electro": "hat_closed"}
	var oh := {"boom": "hat_open_808", "punch": "hat_open_short", "room": "hat_open_room", "lo-fi": "hat_open_dusty", "electro": "hat_open"}
	var ph := {"boom": "hat_pedal_808", "punch": "hat_pedal", "room": "hat_pedal", "lo-fi": "hat_pedal", "electro": "hat_pedal_808"}
	var tom := {"boom": "", "punch": "", "room": "_room", "lo-fi": "", "electro": "_electro"}
	var cym := {"boom": ["crash", "ride"], "punch": ["crash_bright", "ride_dry"], "room": ["crash_dark", "ride"],
		"lo-fi": ["crash_dark", "ride_dry"], "electro": ["crash_bright", "ride"]}
	var extra := {"boom": ["cowbell_808", "rim"], "punch": ["rim_dry", "shaker"], "room": ["rim", "tambourine"],
		"lo-fi": ["rim", "shaker"], "electro": ["cowbell_808", "clave"]}
	for k in KIT_NAMES:
		var kit := AKKit.new()
		kit.resource_name = k
		kit.category = k
		kit.pieces.append(_piece("kick", "kicks", kick[k], -1.0))
		kit.pieces.append(_piece("snare", "snares", snare[k], -3.0))
		kit.pieces.append(_piece("clap", "claps", clap[k], -4.0))
		kit.pieces.append(_piece("closed_hat", "hats", ch[k], -9.0, 0.15, "hats"))
		kit.pieces.append(_piece("open_hat", "hats", oh[k], -10.0, 0.15, "hats"))
		kit.pieces.append(_piece("pedal_hat", "hats", ph[k], -11.0, 0.15, "hats"))
		kit.pieces.append(_piece("tom_low", "toms", "tom_low" + tom[k], -5.0, -0.3))
		kit.pieces.append(_piece("tom_mid", "toms", "tom_mid" + tom[k], -5.0, 0.0))
		kit.pieces.append(_piece("tom_high", "toms", "tom_high" + tom[k], -5.0, 0.3))
		kit.pieces.append(_piece("crash", "cymbals", cym[k][0], -10.0, -0.25))
		kit.pieces.append(_piece("ride", "cymbals", cym[k][1], -12.0, 0.25))
		kit.pieces.append(_piece(extra[k][0].split("_")[0] if extra[k][0] != "rim_dry" else "rim", "perc", extra[k][0], -9.0, -0.2))
		kit.pieces.append(_piece(extra[k][1].split("_")[0], "perc", extra[k][1], -10.0, 0.2))
		out.append(kit)
	return out


static func _piece(name: String, folder: String, sound: String, db: float, pan := 0.0, choke := "") -> Dictionary:
	var p := {name = name, sound = path_of(folder, sound), gain_db = db}
	if pan != 0.0:
		p[&"pan"] = pan
	if choke != "":
		p[&"choke"] = choke
	return p


static func kit_path(kit_name: String) -> String:
	return KITS_DIR + kit_name + ".tres"


## A shipped kit by name (boom, punch, room, lo-fi, electro).
static func kit(kit_name: String) -> AKKit:
	var p := kit_path(kit_name)
	return load(p) if ResourceLoader.exists(p) else null
