# SPDX-License-Identifier: Apache-2.0
## DX7 voice -> AKPatch, by direct parameter conversion (docs/plans/synth-expansion-phase2.md).
##
##   var Dx7 := preload("res://tools/patch_convert/dx7.gd")
##   var patch: AKPatch = Dx7.convert(sidecar.content.dx7.params)
##   var report: Dictionary = Dx7.check(patch, sidecar, folder)   # SNR per note against render_msfa_v100.wav
##
## The patch: six sine operators (oscillator N = operator N) with msfa's
## frequencies (dx7_freq), the algorithm's FM graph and feedback, each on its
## own dx7 envelope (env2, env3, env4 .. env7), the pitch envelope in env8, and
## the DX7 LFO in lfo1. Carriers have level 1; the output is scaled as msfa's
## (dx7render keeps carrier sums >> 13: gain 1/8). The reference is msfa's FM
## engine (Dexed "Modern", Apache-2.0), rendered by tools/patch_convert/render_msfa.py.
extends RefCounted

const VERSION := 1
## What a modulator's output (envelope x sine, gain 1 at level 99) does to its
## target's phase in msfa: Q24 bus value 2 x out, 2^24 = a cycle, so 4 pi radians.
const INDEX := 4.0 * PI
const GAIN_DB := -18.061799739838872   # 20 log10(1/8)
## Oscillator N's envelope slot (1-based: amp_env, env2, env3, envelopes ...).
const OP_ENV := [2, 3, 4, 5, 6, 7]
const PITCH_ENV := 8


## A DX7 voice's named parameters (the prep tool's content.dx7.params) as a patch.
static func convert(params: Dictionary) -> AKPatch:
	var p := AKPatch.new()
	var alg := AKPatchLib.dx7_algorithm(int(params.algorithm))
	var shift := int(params.get("transpose", 24)) - 24
	var fb := int(params.get("feedback", 0))
	var ops := {}
	for op: Dictionary in params.operators:
		ops[int(op.operator)] = op
	var oscs: Array[Dictionary] = []
	var envs := []
	for n in range(1, 7):
		var op: Dictionary = ops[n]
		var fm := []
		for m: int in alg.mods[n]:
			fm.append({from = m, index = INDEX})
		var o := {shape = "sine", level = 1.0 if n in alg.carriers else 0.0, level_env = OP_ENV[n - 1],
			dx7_freq = {mode = int(op.osc_mode), coarse = int(op.freq_coarse), fine = int(op.freq_fine), detune = int(op.detune)}}
		if shift != 0:
			o.semitones = float(shift)
		if not fm.is_empty():
			o.fm = fm
		if n == int(alg.feedback) and fb > 0:
			# msfa: (y[n-1] + y[n-2]) >> (fb_shift + 1), fb_shift = 8 - feedback.
			o.feedback = INDEX / pow(2.0, 8 - fb)
		oscs.append(o)
		envs.append({mode = "dx7", rates = [op.eg_rate_1, op.eg_rate_2, op.eg_rate_3, op.eg_rate_4],
			levels = [op.eg_level_1, op.eg_level_2, op.eg_level_3, op.eg_level_4], output_level = int(op.output_level),
			rate_scaling = int(op.kbd_rate_scaling), velocity_sens = int(op.key_velocity_sensitivity),
			amp_mod_sens = int(op.amp_mod_sensitivity), key_offset = shift,
			key_scaling = {break_point = int(op.kbd_break_point), left_depth = int(op.kbd_left_depth), right_depth = int(op.kbd_right_depth),
				left_curve = int(op.kbd_left_curve), right_curve = int(op.kbd_right_curve)}})
	p.oscillators = oscs
	p.amp_env = {stages = [{time_s = 0.0, level = 1.0}], sustain = -1}
	p.env2 = envs[0]
	p.env3 = envs[1]
	var more: Array[Dictionary] = []
	for e: Dictionary in envs.slice(2):
		more.append(e)
	var pe: Dictionary = params.pitch_eg
	more.append({mode = "dx7_pitch", rates = pe.rates, levels = pe.levels})
	p.envelopes = more
	var l: Dictionary = params.lfo
	p.lfo1 = {mode = "dx7", speed = int(l.speed), delay = int(l.delay), wave = int(l.wave), sync = int(l.key_sync) != 0,
		pitch_mod_depth = int(l.pitch_mod_depth), pitch_mod_sens = int(l.pitch_mod_sensitivity), amp_mod_depth = int(l.amp_mod_depth)}
	p.mods = [{source = "env%d" % PITCH_ENV, dest = "pitch", amount = 12.0}, {source = "lfo1", dest = "pitch", amount = 12.0}]
	p.filter = {type = "off"}
	p.velocity_sens = 0.0
	p.gain_db = GAIN_DB
	p.polyphony = 16
	p.resource_name = String(params.get("name", "")).strip_edges()
	return p


## Things in a voice the reference can't pin down (dx7render's uninitialised LFO phase).
static func caveats(params: Dictionary) -> Array:
	var out := []
	var l: Dictionary = params.lfo
	var moves := int(l.pitch_mod_depth) > 0 and int(l.pitch_mod_sensitivity) > 0
	var amps := false
	for op: Dictionary in params.operators:
		amps = amps or (int(l.amp_mod_depth) > 0 and int(op.amp_mod_sensitivity) > 0)
	if int(l.key_sync) == 0 and (moves or amps):
		out.append("LFO not key-synced: dx7render starts it from uninitialised memory, so its phase is unknown")
	if int(l.wave) == 5 and (moves or amps):
		out.append("sample-and-hold LFO: dx7render's random state starts uninitialised")
	if int(params.get("feedback", 0)) == 7:
		out.append("feedback 7 can be chaotic: dx7render's feedback buffer starts uninitialised, and float and msfa's integers drift apart")
	return out


## Renders the patch in the reference's layout and measures it against
## render_msfa_v<vel>.wav: SNR per note over its hold and release.
static func check(patch: AKPatch, sidecar: Dictionary, folder: String) -> Dictionary:
	var st: Dictionary = sidecar.content.render
	var sr := int(st.sample_rate)
	var vel := int((st.velocities as Array)[0])
	var ref := _read_wav16(folder.path_join("render_msfa_v%03d.wav" % vel))
	var notes := []
	if ref.is_empty():
		return {error = "no render_msfa_v%03d.wav" % vel}
	var c := patch.compile()
	var hold := roundi(float(st.hold_s) * sr)
	var n := roundi((float(st.hold_s) + float(st.release_s)) * sr)
	var per := roundi((float(st.hold_s) + float(st.release_s) + float(st.gap_s)) * sr)
	var snrs := []
	for i in (st.notes as Array).size():
		var key := float(st.notes[i])
		var buf := AKSynth.render_events(c, [[0, AKSynth.E_ON, key, vel / 127.0], [hold, AKSynth.E_OFF, key, 0.0]], n, sr)
		var s := 0.0
		var e := 0.0
		var base := i * per
		for k in n:
			if base + k >= ref.size():
				break
			var r: float = ref[base + k]
			var d: float = r - buf.l[k]
			s += r * r
			e += d * d
		var snr := 10.0 * log(maxf(s, 1e-30) / maxf(e, 1e-30)) / log(10.0)
		snrs.append(snr)
		notes.append({note = int(key), snr_db = snapped(snr, 0.01), ref_rms_db = snapped(10.0 * log(maxf(s / n, 1e-30)) / log(10.0), 0.01)})
	var sorted := snrs.duplicate()
	sorted.sort()
	return {converter = "patch_convert/dx7.gd %d" % VERSION, engine = AKSynthCore.VERSION, reference = "render_msfa_v%03d.wav" % vel,
		notes = notes, snr_min_db = snapped(sorted[0], 0.01), snr_median_db = snapped(sorted[sorted.size() / 2], 0.01),
		caveats = caveats(sidecar.content.dx7.params)}


## A mono 16-bit PCM WAV's samples as floats (-1..1); empty if it can't be read.
static func _read_wav16(path: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	f.seek(12)
	while f.get_position() + 8 <= f.get_length():
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		if id == "data":
			var raw := f.get_buffer(size)
			out.resize(size / 2)
			for i in out.size():
				out[i] = float(raw.decode_s16(2 * i)) / 32768.0
			return out
		f.seek(f.get_position() + size + (size & 1))
	return out
