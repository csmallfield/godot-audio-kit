# SPDX-License-Identifier: Apache-2.0
@tool
## General MIDI: instrument and family names, and the kit's starter bank:
## one original patch per GM family plus a drum kit built from the kit's
## drum voices. `tools/make_bank.gd` writes them to BANK_DIR; this file is
## their source.
class_name AKGeneralMidi
extends RefCounted

const BANK_DIR := "res://addons/audio_kit/bank/"
const DEFAULT_BANK := "res://addons/audio_kit/bank/gm_bank.tres"

const FAMILIES: Array[String] = ["piano", "chromatic_percussion", "organ", "guitar", "bass", "strings", "ensemble", "brass",
	"reed", "pipe", "synth_lead", "synth_pad", "synth_effects", "ethnic", "percussive", "sound_effects"]
## Each family patch's AKPatch.category, by family.
const FAMILY_CATEGORY: Array[String] = ["keys", "bell", "organ", "pluck", "bass", "strings", "pad", "brass",
	"lead", "lead", "lead", "pad", "fx", "pluck", "bell", "fx"]

## The 128 GM program names (program number = index).
const PROGRAMS: Array[String] = [
	"Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano", "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
	"Celesta", "Glockenspiel", "Music Box", "Vibraphone", "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
	"Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
	"Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)", "Electric Guitar (clean)", "Electric Guitar (muted)", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
	"Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass", "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
	"Violin", "Viola", "Cello", "Contrabass", "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
	"String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2", "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
	"Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
	"Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe", "English Horn", "Bassoon", "Clarinet",
	"Piccolo", "Flute", "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
	"Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)", "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass + lead)",
	"Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)", "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",
	"FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)", "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
	"Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bagpipe", "Fiddle", "Shanai",
	"Tinkle Bell", "Agogo", "Steel Drums", "Woodblock", "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
	"Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet", "Telephone Ring", "Helicopter", "Applause", "Gunshot"]

## Drum lanes: name -> [GM notes]. Notes not listed go to "perc".
const DRUM_LANES := {
	"kick": [35, 36], "snare": [38, 40], "rim": [37], "clap": [39], "hat": [42, 44], "open_hat": [46],
	"tom_low": [41, 43], "tom_mid": [45, 47], "tom_high": [48, 50], "crash": [49, 52, 55, 57], "ride": [51, 59], "ride_bell": [53],
	"tambourine": [54], "cowbell": [56], "shaker": [69, 70, 82], "wood": [75, 76, 77], "conga": [60, 61, 62, 63, 64, 65, 66, 67, 68]}

## Levels so one note of each family patch peaks near -6 dBFS (measured).
const FAMILY_TRIM_DB := {0: -4.8, 3: -0.8, 4: -1.9, 6: -2.1, 8: -3.4, 9: -4.5, 12: 4.1, 13: -1.2, 15: -1.3}


static func program_name(program: int) -> String:
	return PROGRAMS[clampi(program, 0, 127)]


static func family_of(program: int) -> int:
	return clampi(program, 0, 127) / 8


## The starter patch for a family (0-15).
static func family_patch(family: int) -> AKPatch:
	var p: AKPatch
	match family:
		0:   # piano: a struck FM tone, brighter and louder with velocity, decaying
			p = _new([{shape = "sine", level = 0.8, fm_from = 2, fm_index = 0.4}, {shape = "sine", level = 0.0, fm_index = 0.0},
				{shape = "sine", semitones = 12.0, level = 0.18, fm_from = 4, fm_index = 0.3}, {shape = "sine", semitones = 26.0, level = 0.0}],
				{type = "lowpass", cutoff_hz = 5000.0, q = 0.7}, {attack_s = 0.002, decay_s = 2.2, sustain = 0.0, release_s = 0.35})
			p.env2 = {attack_s = 0.0, decay_s = 0.35, sustain = 0.0, release_s = 0.3, curve = "exp"}
			p.mods = [{source = "env2", dest = "osc1.fm", amount = 0.8}, {source = "velocity", dest = "osc1.fm", amount = 0.5},
				{source = "key", dest = "cutoff", amount = 0.6}]
			p.velocity_sens = 0.75
			p.effects = [{type = "eq", low_db = 2.0, high_db = -2.0}, {type = "chorus", rate_hz = 0.4, depth_ms = 1.5, mix = 0.15}]
		1:   # chromatic percussion: bell-like mallets
			p = AKPatchLib.preset(&"fm_bell")
			p.amp_env = {attack_s = 0.001, decay_s = 1.6, sustain = 0.0, release_s = 0.8, curve = "linear"}
		2:
			p = AKPatchLib.preset(&"organ")
		3:   # guitar: a plucked, darkening saw
			p = _new([{shape = "saw", level = 0.6}, {shape = "pulse", width = 0.25, level = 0.3, cents = 6.0}],
				{type = "ladder", cutoff_hz = 500.0, resonance = 0.25, drive = 1.3}, {attack_s = 0.001, decay_s = 1.2, sustain = 0.0, release_s = 0.25})
			p.effects = [{type = "chorus", rate_hz = 0.8, depth_ms = 1.5, mix = 0.2}]
			p.env2 = {attack_s = 0.0, decay_s = 0.2, sustain = 0.15, release_s = 0.2, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 3.0}, {source = "key", dest = "cutoff", amount = 0.7},
				{source = "velocity", dest = "cutoff", amount = 1.0}]
			p.velocity_sens = 0.6
		4:   # bass: saw and sub, a short filter blip
			p = _new([{shape = "saw", level = 0.55}, {shape = "sine", semitones = -12.0, level = 0.5}],
				{type = "ladder", cutoff_hz = 280.0, resonance = 0.3, drive = 1.5}, {attack_s = 0.003, decay_s = 0.5, sustain = 0.6, release_s = 0.08})
			p.env2 = {attack_s = 0.0, decay_s = 0.12, sustain = 0.0, release_s = 0.1, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 2.0}, {source = "velocity", dest = "cutoff", amount = 0.8}]
			p.velocity_sens = 0.5
		5:
			p = AKPatchLib.preset(&"strings")
		6:   # ensemble: a soft, wide choir on the vowel wavetable
			p = _new([{shape = "table", table = "vowel", position = 0.3, level = 0.6}, {shape = "sine", semitones = 12.0, level = 0.15}],
				{type = "lowpass", cutoff_hz = 2800.0, q = 0.7}, {attack_s = 0.25, decay_s = 0.6, sustain = 0.85, release_s = 0.6})
			p.unison = 5
			p.detune_cents = 22.0
			p.spread = 0.8
			p.effects = [{type = "chorus", rate_hz = 0.35, depth_ms = 4.0, mix = 0.3}]
			p.lfo1 = {shape = "sine", rate_hz = 4.8, delay_s = 0.3}
			p.mods = [{source = "lfo1", dest = "pitch", amount = 0.07}]
			p.velocity_sens = 0.3
		7:
			p = AKPatchLib.preset(&"brass")
		8:   # reed: a nasal pulse with breathy vibrato
			p = _new([{shape = "pulse", width = 0.3, level = 0.6}, {shape = "saw", level = 0.25}, {shape = "noise", level = 0.04}],
				{type = "bandpass", cutoff_hz = 1300.0, q = 0.9}, {attack_s = 0.04, decay_s = 0.3, sustain = 0.8, release_s = 0.1})
			p.lfo1 = {shape = "sine", rate_hz = 5.2, delay_s = 0.3}
			p.mods = [{source = "lfo1", dest = "pitch", amount = 0.15}, {source = "velocity", dest = "cutoff", amount = 0.8},
				{source = "key", dest = "cutoff", amount = 0.8}]
			p.effects = [{type = "saturate", drive_db = 5.0, tone_hz = 5000.0, mix = 0.5}]
		9:   # pipe: sine and breath
			p = _new([{shape = "sine", level = 0.75}, {shape = "triangle", semitones = 12.0, level = 0.08}, {shape = "noise", level = 0.05}],
				{type = "lowpass", cutoff_hz = 3500.0, q = 0.7}, {attack_s = 0.06, decay_s = 0.2, sustain = 0.85, release_s = 0.12})
			p.lfo1 = {shape = "sine", rate_hz = 5.0, delay_s = 0.25}
			p.mods = [{source = "lfo1", dest = "pitch", amount = 0.08}, {source = "lfo1", dest = "amp", amount = 0.05}]
			p.velocity_sens = 0.4
		10:
			p = AKPatchLib.preset(&"saw_lead")
			p.mode = "poly"
			p.glide_s = 0.0
		11:
			p = AKPatchLib.preset(&"wavetable_pad")
		12:  # synth effects: a sweeping, wandering pad through a phaser
			p = _new([{shape = "table", table = "digital", position = 0.4, level = 0.5}, {shape = "square", semitones = 7.0, level = 0.3}],
				{type = "ladder", cutoff_hz = 900.0, resonance = 0.7}, {attack_s = 0.3, decay_s = 1.0, sustain = 0.7, release_s = 0.8})
			p.effects = [{type = "phaser", rate_hz = 0.2, stages = 6, mix = 0.5}]
			p.lfo1 = {shape = "random", rate_hz = 6.0}
			p.lfo2 = {shape = "sine", rate_hz = 0.25}
			p.mods = [{source = "lfo1", dest = "cutoff", amount = 0.8}, {source = "lfo2", dest = "cutoff", amount = 1.2}]
		13:  # ethnic: a buzzy plucked string with a ring-modulated jangle
			p = _new([{shape = "saw", level = 0.6, fm_from = 1, fm_index = 0.3}, {shape = "sine", level = 0.12, semitones = 19.0, ring_from = 1}],
				{type = "bandpass", cutoff_hz = 1200.0, q = 2.0}, {attack_s = 0.001, decay_s = 1.0, sustain = 0.0, release_s = 0.2})
			p.env2 = {attack_s = 0.0, decay_s = 0.3, sustain = 0.0, release_s = 0.2, curve = "exp"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 1.5}, {source = "key", dest = "cutoff", amount = 0.8}]
		14:  # percussive: a short metallic hit
			p = AKPatchLib.preset(&"fm_bell")
			p.oscillators[1].semitones = 12.0 * log(1.41) / log(2.0)
			p.amp_env = {attack_s = 0.001, decay_s = 0.35, sustain = 0.0, release_s = 0.15, curve = "linear"}
		15:  # sound effects: filtered noise with a sweep
			p = _new([{shape = "noise", level = 0.6}, {shape = "saw", level = 0.2}],
				{type = "bandpass", cutoff_hz = 800.0, q = 2.5}, {attack_s = 0.05, decay_s = 0.6, sustain = 0.5, release_s = 0.4})
			p.effects = [{type = "flanger", rate_hz = 0.3, mix = 0.5}]
			p.env2 = {attack_s = 0.3, decay_s = 0.6, sustain = 0.2, release_s = 0.4, curve = "linear"}
			p.mods = [{source = "env2", dest = "cutoff", amount = 2.5}, {source = "key", dest = "cutoff", amount = 1.0}]
		_:
			return null
	p.polyphony = 16
	p.gain_db += float(FAMILY_TRIM_DB.get(family, 0.0))
	p.resource_name = "gm_" + FAMILIES[family]
	p.category = FAMILY_CATEGORY[family]
	return p


## The recipe for a drum lane (see DRUM_LANES).
static func drum_recipe(lane: String) -> AKRecipe:
	var r := AKRecipe.new()
	match lane:
		"kick": r.voice = &"kick"; r.params = {tune_hz = 52.0, punch = 3.0, decay_s = 0.32, click = 0.4, drive = 0.2}
		"snare": r.voice = &"snare"; r.params = {tone_hz = 190.0, noise_hz = 5200.0, noise_decay_s = 0.16}
		"rim": r.voice = &"click"; r.params = {mode = "band", freq_hz = 1700.0, q = 6.0, decay_s = 0.012, body_hz = 400.0, body = 0.4}
		"clap": r.voice = &"clap"; r.params = {}
		"hat": r.voice = &"hat"; r.params = {decay_s = 0.045, tone_hz = 8500.0}
		"open_hat": r.voice = &"hat"; r.params = {decay_s = 0.35, tone_hz = 8000.0}
		"tom_low": r.voice = &"boing"; r.params = {start_hz = 120.0, end_hz = 80.0, drop_s = 0.08, decay_s = 0.25, click = 0.3, sub = 0.2}
		"tom_mid": r.voice = &"boing"; r.params = {start_hz = 170.0, end_hz = 115.0, drop_s = 0.07, decay_s = 0.22, click = 0.3}
		"tom_high": r.voice = &"boing"; r.params = {start_hz = 240.0, end_hz = 160.0, drop_s = 0.06, decay_s = 0.2, click = 0.3}
		"crash": r.voice = &"hat"; r.params = {decay_s = 1.4, tone_hz = 6500.0, metal = 0.75, tune = 0.8}
		"ride": r.voice = &"hat"; r.params = {decay_s = 0.7, tone_hz = 9500.0, metal = 0.85, tune = 1.3}
		"ride_bell": r.voice = &"mallet"; r.params = {freq_hz = 1900.0, material = "metal", decay_s = 0.5, hardness = 0.7}
		"tambourine": r.voice = &"hat"; r.params = {decay_s = 0.12, tone_hz = 11000.0, metal = 0.9, tune = 1.6}
		"cowbell":
			r.voice = &"tone"
			r.params = {wave = "square", freq_hz = 560.0, attack_s = 0.001, decay_s = 0.12, sustain = 0.0, gate_s = 0.1, release_s = 0.04}
			r.layers = [{voice = &"tone", gain_db = -3.0, params = {wave = "square", freq_hz = 845.0, attack_s = 0.001, decay_s = 0.1, sustain = 0.0, gate_s = 0.1, release_s = 0.04}}]
			r.fx = [{type = "bandpass", cutoff_hz = 800.0, q = 1.5}]
		"shaker": r.voice = &"static"; r.params = {length_s = 0.09, hiss = 0.8, color_hz = 7000.0, q = 0.8, crackles_per_s = 0.0, fade_s = 0.04}
		"wood": r.voice = &"mallet"; r.params = {freq_hz = 900.0, material = "wood", decay_s = 0.06, hardness = 0.8}
		"conga": r.voice = &"boing"; r.params = {start_hz = 300.0, end_hz = 220.0, drop_s = 0.03, decay_s = 0.15, click = 0.5}
		_: r.voice = &"click"; r.params = {mode = "band", freq_hz = 2500.0, q = 3.0, decay_s = 0.02}   # perc
	r.gain_db = float(DRUM_TRIM_DB.get(lane, -6.0))
	r.resource_name = "gm_drum_" + lane
	return r


## Drum levels against each other (a kit, not a normalised set).
const DRUM_TRIM_DB := {"kick": -3.0, "snare": -3.0, "rim": -8.0, "clap": 0.0, "hat": -2.0, "open_hat": -4.0, "ride": -3.0,
	"crash": -4.0, "ride_bell": -12.0, "tambourine": 0.0, "cowbell": -14.0, "shaker": -8.0, "wood": -8.0, "conga": -6.0, "perc": -8.0}


## The bank as built here, referring to files under BANK_DIR.
static func make_bank() -> AKBank:
	var b := AKBank.new()
	var fams := []
	for i in 16:
		fams.append(BANK_DIR + "patches/gm_%s.tres" % FAMILIES[i])
	b.families = fams
	var drums := {}
	for lane in DRUM_LANES:
		for note in DRUM_LANES[lane]:
			drums[int(note)] = {lane = lane, recipe = BANK_DIR + "drums/%s.tres" % lane}
	b.drums = drums
	b.drum_default = {lane = "perc", recipe = BANK_DIR + "drums/perc.tres"}
	b.resource_name = "General MIDI starter bank"
	return b


## Load the shipped bank (null if its files are missing).
static func default_bank() -> AKBank:
	return load(DEFAULT_BANK) if ResourceLoader.exists(DEFAULT_BANK) else null


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
