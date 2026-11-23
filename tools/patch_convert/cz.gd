# SPDX-License-Identifier: Apache-2.0
# Casio CZ-101 tones (the prep tool's content.cz_tone.params, osp/cz.py) as AKPatches.
#
# The tone data is the CZ's uPD933 chip values almost as they are (docs/plans/synth-expansion-phase4.md):
# each line's waveform word is the chip's waveform register, and its DCA, DCW and DCO steps are the
# chip's rates and levels. They become a `pd` oscillator per sounding line with three `cz`
# envelopes, which the engine runs as MAME's uPD933 does (tests/test_cz.gd holds it to the chip).
#
# What the firmware does with the rest is documented, not known exactly (no CZ ROM is available),
# so these are approximations, listed per tone in caveats():
# - Vibrato: wave from the data; rate, delay and depth in Hz, seconds and cents are guesses from the
#   firmware's 16-bit values (VIB_* below).
# - DCW key follow: the manual says it lowers the DCW level at higher keys; here a matrix row takes
#   the DCW envelope down by KF_DCW x the key follow per octave above middle C (and up below it).
# - DCA key follow (shorter envelopes at higher keys) is left out.
# - Detune: the manual's octave, note and fine (1/60 semitone).
# - Tuning: A = 440 Hz.
extends RefCounted

const VERSION := 1
## Chip wave codes and windows, as AKPatch.PD_WAVES and PD_WINDOWS.
const WAVES := ["saw", "square", "pulse", "silent", "double_sine", "saw_pulse", "resonance", "double_pulse"]
const WINDOWS := ["none", "saw", "triangle", "trapezoid", "pulse", "double_saw"]
## Panel vibrato waves 1-4.
const VIB_WAVES := {1: "triangle", 2: "saw", 3: "saw_down", 4: "square"}
## Guesses: the firmware's vibrato values as an LFO increment, a delay count and a depth, ticking
## at 128 Hz on a 16-bit phase (rate 50 is about 5 Hz), depth 1024 = an octave.
const VIB_TICK_HZ := 128.0
const VIB_CENTS_PER_UNIT := 1200.0 / 1024.0
## Guess: the DCW envelope's share taken off per octave above middle C, per key follow step (0-9).
const KF_DCW := 0.08
## Headroom: one line at full level peaks near -6 dBFS (mono, equal power), two lines together too.
const GAIN_ONE_DB := -3.0
const GAIN_TWO_DB := -9.0


## Envelope slots (1-based: amp_env, env2, env3, envelopes ...) of the first and second sounding
## line: DCA, DCW, DCO.
const SLOTS := [[2, 3, 4], [5, 6, 7]]


static func _env(e: Dictionary, kind: String) -> Dictionary:
	var steps := []
	var endi := int(e.end_step) - 1
	for i in endi + 1:
		var s: Dictionary = e.steps[i]
		steps.append([int(s.rate7), int(s.level7)])
	var sus: Variant = e.get("sustain_step", null)
	return {mode = "cz", kind = kind, steps = steps, end = endi, sustain = int(sus) - 1 if sus != null else -1}


static func _osc(line: Dictionary, slots: Array) -> Dictionary:
	var wf: Dictionary = line.waveform
	var o := {shape = "pd", pd_wave = WAVES[int(wf.wave1.code)], pd_window = WINDOWS[int(wf.window)], level = 1.0,
		level_env = slots[0], shape_env = slots[1], pitch_env = slots[2], filtered = false}
	if wf.get("wave2") is Dictionary:
		o.pd_wave2 = WAVES[int(wf.wave2.code)]
	return o


static func convert(params: Dictionary, name := "") -> AKPatch:
	var p := AKPatch.new()
	var ls := int(params.line_select_raw)
	# Which lines sound (1-based), the second one primed (detuned, and modulated) in 1+1' and 1+2'.
	var lines: Array = {0: [1], 1: [2], 2: [1, 1], 3: [1, 2]}[ls]
	var two := lines.size() == 2
	var oct := int(params.get("octave", 0)) if params.get("octave") != null else 0
	var dt: Dictionary = params.detune
	var detune := float(dt.sign) * (float(dt.octave) * 12.0 + float(dt.note) + float(dt.fine) / 60.0)
	var l1wf: Dictionary = params.lines[0].waveform
	var oscs: Array[Dictionary] = []
	var envs := []
	var mods: Array[Dictionary] = []
	for i in lines.size():
		var line: Dictionary = params.lines[int(lines[i]) - 1]
		var o := _osc(line, SLOTS[i])
		var semis := 12.0 * oct + (detune if i == 1 else 0.0)
		if semis != 0.0:
			o.semitones = semis
		envs.append(_env(line.dca, "dca"))
		envs.append(_env(line.dcw, "dcw"))
		envs.append(_env(line.dco, "dco"))
		var kf := int(line.dcw_key_follow.panel)
		if kf > 0:
			mods.append({source = "env%d" % SLOTS[i][1], via = "key", dest = "osc%d.position" % (2 - i if two else 1),
				amount = -KF_DCW * kf})
		oscs.append(o)
	if two:
		# The primed line first: computed before line 1, its ring reads line 1's sample of this
		# moment, as on the chip (line 2' right after line 1).
		var primed := oscs[1]
		if bool(l1wf.ring):
			primed.ring_from = 2
		elif bool(l1wf.noise):
			primed.pd_noise = true
		oscs = [primed, oscs[0]]
	p.oscillators = oscs
	p.amp_env = {stages = [{time_s = 0.0, level = 1.0}], sustain = -1}
	p.env2 = envs[0]
	p.env3 = envs[1]
	var more: Array[Dictionary] = []
	for e: Dictionary in envs.slice(2):
		more.append(e)
	p.envelopes = more
	var vib: Dictionary = params.vibrato
	var depth_cents := float(vib.depth.value) * VIB_CENTS_PER_UNIT
	if int(vib.depth.panel) > 0 and VIB_WAVES.has(int(vib.wave)):
		var w := String(VIB_WAVES[int(vib.wave)])
		var l := {shape = "saw" if w == "saw_down" else w, rate_hz = float(vib.rate.value) * VIB_TICK_HZ / 65536.0,
			delay_s = float(vib.delay.value) / VIB_TICK_HZ}
		p.lfo1 = l
		mods.append({source = "lfo1", dest = "pitch", amount = (-1.0 if w == "saw_down" else 1.0) * depth_cents / 100.0})
	p.mods = mods
	p.filter = {type = "off"}
	p.velocity_sens = 0.0
	p.gain_db = GAIN_TWO_DB if two else GAIN_ONE_DB
	p.polyphony = 4 if two else 8
	p.resource_name = name
	return p


## What the data or the firmware leaves open for this tone.
static func caveats(params: Dictionary) -> Array:
	var out := []
	if int(params.vibrato.depth.panel) > 0:
		out.append("vibrato rate, delay and depth are guessed (no CZ ROM)")
	var ls := int(params.line_select_raw)
	var used: Array = {0: [1], 1: [2], 2: [1], 3: [1, 2]}[ls]
	for n: int in used:
		var line: Dictionary = params.lines[n - 1]
		if int(line.dca_key_follow.panel) > 0:
			out.append("line %d: DCA key follow %d left out" % [n, int(line.dca_key_follow.panel)])
		if int(line.dcw_key_follow.panel) > 0:
			out.append("line %d: DCW key follow %d approximated" % [n, int(line.dcw_key_follow.panel)])
	for x: String in params.get("issues", []):
		out.append("data: " + x)
	return out
