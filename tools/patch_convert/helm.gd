# SPDX-License-Identifier: Apache-2.0
## Helm patch -> AKPatch, by direct parameter conversion through Helm 0.9.0's own formulas
## (its source: src/common/helm_common.cpp, src/synthesis, mopo).
##
##   var Helm := preload("res://tools/patch_convert/helm.gd")
##   var patch: AKPatch = Helm.convert(sidecar.content.helm)
##   var notes: Array = Helm.caveats(sidecar.content.helm)
##
## `content` is the prep tool's content.helm: {name, params (the .helm file's settings, Helm's
## stored units), modulations [{source, destination, amount}], ...}. Files older than 0.9 are
## upgraded first, as Helm's loader does.
##
## The patch: osc 1 and 2 (wavetables of Helm's waves, each with its unison as a stack, or with
## harmonize as a table of the harmonic series), their cross modulation as two
## hidden sines phase-modulating each other and the oscillators, the sub (shuffle as a wavetable of
## the warped period), noise, the oscillator feedback as the comb, the filter (12 and 24 dB blends
## as the state-variable mix, the shelves), the amp, filter (env2) and mod (env3) envelopes, the two
## mono LFOs (lfo1, lfo2), the poly LFO and the step sequencer (custom LFOs in `lfos`), the
## modulation rows GAK has a destination for (others through their source's mean), the
## arpeggiator, distortion (saturate), delay, reverb, and the formant filter as GAK's `formant` filter
## type (filter 2 behind Helm's filter, or filter 1 when that is off; x/y fitted onto the vowel axis).
extends RefCounted

const VERSION := 4
## Copies per oscillator stack. GAK stacks up to 16, but Helm's 9-15 voice unisons as up to 15
## scored worse than as 8 (61 patches: spectral error worse on 25, better on 10).
const MAX_STACK := 8
## GAK's level against Helm's (dB), from the library's median level error.
const CAL_DB := 0.0
## The reference renders start each note this far into a fresh instance: a free-running LFO is
## that far into its cycle at the note.
const PREROLL_S := 0.1
## The reference renders' tempo, in beats per second (Helm takes the host's 120 bpm).
const BPS := 2.0
## The time constant of Helm's cutoff smoother (3 Hz).
## Rows GAK can't take act through their source's mean over this much of a held note.
const TYPICAL_S := 2.0
const CUTOFF_TAU := 1.0 / (6.0 * PI)
## A voice takes about this long to pick up the smoothed cutoff (measured).
const CUTOFF_LAG := 0.0
const LN10 := 2.302585092994046
## Helm's arpeggiator keeps time at 44.1 kHz whatever the host's rate: at the references' 48 kHz its
## steps come 48/44.1 times as fast (measured: free 2 notes/s steps 0.459 s apart).
const ARP_CLOCK := 44100.0 / 48000.0

## Helm 0.9.0's parameter defaults (helm_common.cpp), for keys a file leaves out.
const DEFAULTS := {amp_attack = 0.109545, amp_decay = 1.5, amp_release = 0.3, amp_sustain = 1.0, arp_frequency = 2.0,
	arp_gate = 0.5, arp_octaves = 1.0, arp_on = 0.0, arp_pattern = 0.0, arp_sync = 1.0, arp_tempo = 9.0,
	beats_per_minute = 2.0, cross_modulation = 0.0, cutoff = 80.0, delay_dry_wet = 0.5, delay_feedback = 0.4,
	delay_frequency = 2.0, delay_on = 0.0, delay_sync = 1.0, delay_tempo = 9.0, distortion_on = 0.0, distortion_type = 0.0,
	distortion_drive = 0.0, distortion_mix = 1.0, fil_attack = 0.0, fil_decay = 1.5, fil_env_depth = 0.0, fil_release = 1.5,
	fil_sustain = 0.5, filter_saturation = 0.0, filter_drive = 0.0, filter_blend = 0.0, filter_type = 6.0, filter_style = 0.0,
	filter_shelf = 0.0, filter_on = 0.0, formant_on = 0.0, formant_x = 0.5, formant_y = 0.5, keytrack = 0.0, legato = 0.0,
	mod_attack = 0.0, mod_decay = 1.5, mod_release = 1.5, mod_sustain = 0.5, mono_lfo_1_amplitude = 1.0,
	mono_lfo_1_frequency = 1.0, mono_lfo_1_retrigger = 2.0, mono_lfo_1_sync = 1.0, mono_lfo_1_tempo = 6.0,
	mono_lfo_1_waveform = 0.0, mono_lfo_2_amplitude = 1.0, mono_lfo_2_frequency = 1.0, mono_lfo_2_retrigger = 2.0,
	mono_lfo_2_sync = 1.0, mono_lfo_2_tempo = 7.0, mono_lfo_2_waveform = 0.0, noise_volume = 0.0, num_steps = 8.0,
	osc_1_transpose = 0.0, osc_1_tune = 0.0, osc_1_unison_detune = 10.0, osc_1_unison_voices = 1.0,
	osc_1_volume = 0.5477225575, osc_1_waveform = 4.0, osc_2_transpose = 0.0, osc_2_tune = 0.0, osc_2_unison_detune = 10.0,
	osc_2_unison_voices = 1.0, osc_2_volume = 0.5477225575, osc_2_waveform = 4.0, osc_feedback_amount = 0.0,
	osc_feedback_transpose = 0.0, osc_feedback_tune = 0.0, pitch_bend_range = 2.0, poly_lfo_amplitude = 1.0,
	poly_lfo_frequency = 1.0, poly_lfo_sync = 1.0, poly_lfo_tempo = 7.0, poly_lfo_waveform = 0.0, polyphony = 4.0,
	portamento = -7.0, portamento_type = 0.0, resonance = 0.5, reverb_damping = 0.5, reverb_dry_wet = 0.5,
	reverb_feedback = 0.9, reverb_on = 0.0, step_frequency = 2.0, step_sequencer_retrigger = 2.0, step_sequencer_sync = 1.0,
	step_sequencer_tempo = 7.0, step_smoothing = 0.0, stutter_frequency = 3.0, stutter_sync = 1.0, stutter_tempo = 8.0,
	stutter_on = 0.0, stutter_resample_frequency = 1.0, stutter_resample_sync = 1.0, stutter_resample_tempo = 6.0,
	stutter_softness = 0.2, sub_shuffle = 0.0, sub_octave = 0.0, sub_volume = 0.0, sub_waveform = 2.0,
	unison_1_harmonize = 0.0, unison_2_harmonize = 0.0, velocity_track = 0.0, volume = 0.7071068}
## Tempo-synced rates: cycles (steps, notes, 1/delay time) per beat, by tempo index (helm_common.h).
const SYNC_RATIO := [1.0 / 128.0, 1.0 / 64.0, 1.0 / 32.0, 1.0 / 16.0, 1.0 / 8.0, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
## The sync switch's rate multiplier: off, straight, dotted, triplet.
const SYNC_MOD := [1.0, 1.0, 2.0 / 3.0, 1.5]
const WAVE_NAMES := ["sine", "triangle", "square", "down saw", "up saw", "3 step", "4 step", "8 step", "3 pyramid",
	"5 pyramid", "9 pyramid"]
## Sources that swing both ways (their mean is 0).
const BIPOLAR := ["mono_lfo_1", "mono_lfo_2", "poly_lfo", "step_sequencer", "random", "pitch_wheel"]


static func _f(p: Dictionary, k: String) -> float:
	return float(p.get(k, DEFAULTS.get(k, 0.0)))


static func _db(x: float) -> float:
	return 20.0 * log(maxf(absf(x), 1e-9)) / LN10


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (clampf(midi, 0.0, 128.0) - 69.0) / 12.0)


static func _ver_le(v: String, than: String) -> bool:
	var a := v.split(".")
	var b := than.split(".")
	for i in maxi(a.size(), b.size()):
		var x := a[i].to_int() if i < a.size() else 0
		var y := b[i].to_int() if i < b.size() else 0
		if x != y:
			return x < y
	return true


# --- the file, as Helm holds it once loaded ---------------------------------------------

## The settings with Helm's loader's upgrades for old files (load_save.cpp) and the defaults filled.
static func params(content: Dictionary) -> Dictionary:
	var src: Dictionary = content.get("params", {})
	var s := src.duplicate()
	var ver := String(content.get("synth_version", "0.9.0"))
	var g := func(k: String) -> float: return float(s.get(k, 0.0))   # the loader reads a missing key as 0
	if _ver_le(ver, "0.5.0") and s.has("osc_mix"):
		s.osc_1_volume = sqrt(1.0 - g.call("osc_mix"))
		s.osc_2_volume = sqrt(g.call("osc_mix"))
	if _ver_le(ver, "0.7.2") and g.call("stutter_on") != 0.0:
		s.stutter_resample_sync = 0.0
		s.stutter_sync = 0.0
	if _ver_le(ver, "0.8.6"):
		var v1: float = g.call("osc_1_volume")
		var v2: float = g.call("osc_2_volume")
		s.osc_1_volume = sqrt(v1 * v1 * sqrt(0.5 / ((g.call("osc_1_unison_voices") + 1.0) / 2.0)))
		s.osc_2_volume = sqrt(v2 * v2 * sqrt(0.5 / ((g.call("osc_2_unison_voices") + 1.0) / 2.0)))
		s.sub_volume = sqrt(0.5) * g.call("sub_volume")
		if _ver_le(ver, "0.5.0"):
			s.sub_octave = 1.0
			s.cutoff = g.call("cutoff") - g.call("keytrack") * 12.0
		var ft: float = g.call("filter_type")
		if ft >= 6.0:
			s.filter_on = 0.0
		elif ft >= 3.0:
			s.filter_shelf = 1.0 if ft >= 5.0 else (2.0 if ft >= 4.0 else 0.0)
			s.filter_on = 1.0
			s.filter_style = 2.0
		else:
			if ft >= 2.0:
				s.filter_blend = 1.0
			elif ft >= 1.0:
				s.filter_blend = 2.0
			s.filter_on = 1.0
			s.filter_style = 0.0
		s.distortion_on = 1.0
		s.distortion_type = 0.0
		s.distortion_mix = 1.0
		if ft >= 6.0:
			s.distortion_drive = g.call("filter_saturation")
		else:
			s.distortion_drive = g.call("filter_saturation") + 12.0
			s.filter_drive = -12.0
		var vol: float = g.call("volume")
		for fx in ["delay", "reverb"]:
			var w: float = g.call(fx + "_dry_wet")
			if g.call(fx + "_on") != 0.0 and w != 0.0 and w != 1.0:
				var r := w / (1.0 - w)
				var nw := 1.0 - 1.0 / (1.0 + r * r)
				s[fx + "_dry_wet"] = nw
				vol *= sqrt(w / sqrt(nw))
		s.volume = vol
		s.beats_per_minute = g.call("beats_per_minute") / 60.0
	for k: String in DEFAULTS:
		if not s.has(k):
			s[k] = DEFAULTS[k]
	return s


## The modulation rows (amount 0 = no connection), upgraded as the loader does.
static func modulations(content: Dictionary) -> Array:
	var ver := String(content.get("synth_version", "0.9.0"))
	var out := []
	for m: Variant in content.get("modulations", []):
		if not (m is Dictionary):
			continue
		var src := String(m.get("source", ""))
		var dst := String(m.get("destination", ""))
		var a := float(m.get("amount", 0.0))
		if a == 0.0:
			continue
		if _ver_le(ver, "0.5.0") and dst == "osc_mix":
			out.append({source = src, destination = "osc_1_volume", amount = -a})
			out.append({source = src, destination = "osc_2_volume", amount = a})
			continue
		if _ver_le(ver, "0.8.6") and dst == "filter_saturation":
			dst = "distortion_drive"
		out.append({source = src, destination = dst, amount = a})
	return out


# --- waveforms ---------------------------------------------------------------------------

## One cycle of Helm's waveform w (0..10), naive, n points (mopo wave.h).
static func wave_cycle(w: int, n := 1024) -> Array:
	var out := []
	out.resize(n)
	for i in n:
		out[i] = wave_at(w, float(i) / n)
	return out


static func wave_at(w: int, t: float) -> float:
	t -= floorf(t)
	match w:
		0:
			return sin(TAU * t)
		1:
			return absf(2.0 - 4.0 * fposmod(t + 0.75, 1.0)) - 1.0
		2:
			return 1.0 if t < 0.5 else -1.0
		3:
			return 1.0 - 2.0 * t
		4:
			return 2.0 * t - 1.0
		5, 6, 7:
			var steps: int = [3, 4, 8][w - 5]
			return 2.0 * floorf(steps * t) / (steps - 1) - 1.0
		8, 9, 10:
			var sq: int = [2, 4, 8][w - 8]
			var ph := 0.75 + t
			var acc := 0.0
			for i in sq:
				acc += 1.0 if fposmod(ph, 1.0) < 0.5 else -1.0
				ph += 1.0 / (2.0 * sq)
			return acc / sq
	return 0.0


## One frame of waveform w for a wavetable: the triangle, square and saws as their Fourier series
## (GAK's own saw and square, polyBLEP, fall 2-3 dB under Helm's tables at 10-13 kHz), the steps and
## pyramids as one naive cycle.
static func wave_frame(w: int) -> Dictionary:
	if w > 4:
		return {samples = wave_cycle(w)}
	var h := []
	var ph := []
	for k in range(1, 512):
		var a := 0.0
		var p := 0.0
		match w:
			0:
				a = 1.0 if k == 1 else 0.0
			1:
				if k % 2 == 1:
					a = 8.0 / (PI * PI * k * k)
					p = 0.0 if (k / 2) % 2 == 0 else 0.5
			2:
				a = 4.0 / (PI * k) if k % 2 == 1 else 0.0
			3:
				a = 2.0 / (PI * k)
			4:
				a = 2.0 / (PI * k)
				p = 0.5
		h.append(snappedf(a, 1e-9))
		ph.append(p)
	return {harmonics = h, phases = ph}


## Harmonic amplitudes of a waveform (index 0 = the fundamental).
static func wave_harmonics(w: int) -> PackedFloat64Array:
	var amps := PackedFloat64Array()
	var phs := PackedFloat64Array()
	AKWavetables._spectrum(wave_frame(w), amps, phs)
	return amps


## A wavetable's level: GAK normalises a frame to peak 1, so the oscillator's level carries its peak.
static func table_peak(spec: Dictionary) -> float:
	return float(AKWavetables.build(spec).get("peak", 1.0))


## Helm's unison offsets in cents for `voices` voices `detune` apart (helm_oscillators.cpp).
static func unison_cents(voices: int, detune: float) -> Array:
	var k := (voices + 1) / 2
	var out := []
	for v in voices:
		var c := detune * float((v + 1) / 2) / float(k)
		out.append(-c if v % 2 == 1 else c)
	return out


## Helm's unison level: 1 / sqrt(voices / 2 + 1).
static func unison_scale(voices: int) -> float:
	return 1.0 / sqrt(float(voices / 2) + 1.0)


## Oscillator n (1 or 2) as a GAK oscillator, and its level factor k (GAK level = volume^2 * k).
static func _osc(p: Dictionary, n: int) -> Dictionary:
	var pre := "osc_%d_" % n
	var w := clampi(roundi(_f(p, pre + "waveform")), 0, 10)
	var voices := clampi(int(_f(p, pre + "unison_voices")), 1, 15)
	var detune := _f(p, pre + "unison_detune")
	var harm := _f(p, "unison_%d_harmonize" % n) != 0.0 and voices > 1
	var semis := _f(p, pre + "transpose")
	var tune := _f(p, pre + "tune")
	var o := {}
	var k := 1.0
	if harm:
		# Harmonize: voice v plays at (v + 1)x the note (its detune shrinks to nothing up there). The voices'
		# harmonics fall on the harmonic series and add in power; one table holds the sum.
		var base := wave_harmonics(w)
		var pw := PackedFloat64Array()
		pw.resize(511)
		pw.fill(0.0)
		for v in voices:
			for h in base.size():
				var at := (h + 1) * (v + 1) - 1
				if at < pw.size():
					pw[at] += base[h] * base[h]
		var hs := []
		var phs := []
		var top := 0
		for i in pw.size():
			if pw[i] > 1e-12:
				top = i
		for i in top + 1:
			hs.append(snappedf(sqrt(pw[i]), 1e-7))
			phs.append(fposmod(i * 0.381966 + i * i * 0.1347, 1.0))
		var spec := {frames = [{harmonics = hs, phases = phs}]}
		o = {shape = "table", table = spec}
		k = unison_scale(voices) * table_peak(spec)
		# The voices' own detune (cents / (v + 1) each): the spread's middle.
		var cs := unison_cents(voices, detune)
		var mid := 0.0
		for v in voices:
			mid += float(cs[v]) / (v + 1)
		tune += mid / voices / 100.0
	else:
		if w == 0:
			o = {shape = "sine"}
		else:
			var spec := {frames = [wave_frame(w)]}
			o = {shape = "table", table = spec}
			k = table_peak(spec)
		if voices > 1:
			var cs := unison_cents(voices, detune)
			var lo: float = cs.min()
			var hi: float = cs.max()
			o.stack = mini(voices, MAX_STACK)
			o.stack_cents = (hi - lo) * 0.5
			tune += (hi + lo) * 0.5 / 100.0
			# GAK's stack keeps its power; Helm's voices add in power at its unison level.
			k *= sqrt(float(voices)) * unison_scale(voices)
	if semis != 0.0:
		o.semitones = semis
	if tune != 0.0:
		o.cents = tune * 100.0
	return {osc = o, k = k}


## The sub oscillator: an octave (two with sub_octave) under the note, ignoring the oscillators'
## transposes. Shuffle squeezes the first of the two cycles in each period and stretches the second;
## as a wavetable of that whole period (frames across shuffle when it is modulated).
static func _sub(p: Dictionary, frames: int) -> Dictionary:
	var w := clampi(roundi(_f(p, "sub_waveform")), 0, 10)
	var down := 12.0 if _f(p, "sub_octave") == 0.0 else 24.0
	var shuffle := clampf(_f(p, "sub_shuffle"), 0.0, 1.0)
	if frames <= 1 and shuffle == 0.0:
		if w == 0:
			return {osc = {shape = "sine", semitones = -down}, k = 1.0}
		var one := {frames = [wave_frame(w)]}
		return {osc = {shape = "table", table = one, semitones = -down}, k = table_peak(one)}
	var fr := []
	var nf := maxi(1, frames)
	for f in nf:
		var sh := shuffle if nf == 1 else float(f) / (nf - 1)
		fr.append({samples = sub_period(w, sh)})
	var spec := {frames = fr, normalize = false}
	var o := {shape = "table", table = spec, semitones = -down - 12.0}
	if nf > 1:
		o.position = shuffle
	return {osc = o, k = table_peak(spec)}


## One base period of the sub (two cycles of w, the first squeezed into s/2 of it).
static func sub_period(w: int, shuffle: float, n := 1024) -> Array:
	var s := clampf(1.0 - shuffle, 0.0, 1.0)
	var out := []
	out.resize(n)
	for i in n:
		var t := float(i) / n
		if t < s * 0.5:
			out[i] = wave_at(w, t / (s * 0.5))
		else:
			out[i] = wave_at(w, (t - s * 0.5) / (1.0 - s * 0.5))
	return out


## The level tanh(drive x) gives the oscillator mix x, against x's own: the mix (the oscillators'
## naive waves at their levels, unison, sub, noise, the comb's boost as a gain) simulated over 4096
## samples of middle C.
static func drive_gain(p: Dictionary, drive: float, fb: float) -> float:
	var comps := []   # [wave, amplitude, frequency ratio, phase]
	var seed := 1
	for n in [1, 2]:
		var pre := "osc_%d_" % n
		var v := _f(p, pre + "volume")
		if v == 0.0:
			continue
		var w := clampi(roundi(_f(p, pre + "waveform")), 0, 10)
		var voices := clampi(int(_f(p, pre + "unison_voices")), 1, 15)
		var harm := _f(p, "unison_%d_harmonize" % n) != 0.0
		var cs := unison_cents(voices, _f(p, pre + "unison_detune"))
		var base := pow(2.0, (_f(p, pre + "transpose") + _f(p, pre + "tune")) / 12.0)
		for i in voices:
			seed = (seed * 1103515245 + 12345) % 2147483648
			var r := (float(i) if harm else 0.0) + pow(2.0, float(cs[i]) / 1200.0)
			comps.append([w, v * v * unison_scale(voices), base * r, 0.0 if i == 0 else float(seed) / 2147483648.0])
	if _f(p, "sub_volume") != 0.0:
		var sv := _f(p, "sub_volume")
		comps.append([clampi(roundi(_f(p, "sub_waveform")), 0, 10), sv * sv, 0.5 if _f(p, "sub_octave") == 0.0 else 0.25, 0.0])
	var nv := _f(p, "noise_volume")
	var boost := 1.0 / sqrt(maxf(0.02, 1.0 - fb * fb))
	var f0 := _hz(60.0) / 48000.0
	var s_in := 0.0
	var s_out := 0.0
	var rng := 12345
	for t in 4096:
		var x := 0.0
		for c: Array in comps:
			x += float(c[1]) * wave_at(int(c[0]), float(c[3]) + f0 * float(c[2]) * t)
		if nv != 0.0:
			rng = (rng * 1103515245 + 12345) % 2147483648
			x += nv * nv * (float(rng) / 1073741824.0 - 1.0)
		x *= boost
		s_in += x * x
		var y := tanh(drive * x)
		s_out += y * y
	if s_in <= 0.0:
		return drive
	return sqrt(s_out / s_in)


# --- LFOs --------------------------------------------------------------------------------

## A Helm LFO (pre: "mono_lfo_1_", "mono_lfo_2_" or "poly_lfo_") as a GAK LFO: {lfo, scale (its
## amplitude and sign), hz}.
static func _lfo(p: Dictionary, pre: String, poly: bool) -> Dictionary:
	var w := clampi(int(_f(p, pre + "waveform")), 0, 12)
	var sync := clampi(int(_f(p, pre + "sync")), 0, 3)
	var l := {}
	var hz := 0.0
	if sync == 0:
		hz = pow(2.0, _f(p, pre + "frequency"))
		l.rate_hz = hz
	else:
		var beats: float = 1.0 / (SYNC_RATIO[clampi(int(_f(p, pre + "tempo")), 0, 11)] * SYNC_MOD[sync])
		l.rate_sync = beats
		hz = BPS / beats
	var scale := _f(p, pre + "amplitude")
	var ph := 0.0
	match w:
		0:
			l.shape = "sine"
		1:
			l.shape = "triangle"
			ph = 0.25   # Helm's triangle starts at 0, rising; GAK's at -1
		2:
			l.shape = "square"
		3:
			l.shape = "saw"
			scale = -scale
		4:
			l.shape = "saw"
		11:
			l.shape = "random"
		12:
			l.shape = "smooth"
		_:
			l.shape = "custom"
			l.interp = "step"
			var n: int = [3, 4, 8, 4, 8, 16][w - 5]
			var pts := []
			for i in n:
				pts.append(wave_at(w, (i + 0.5) / n))
			l.points = pts
	var retrig := 1 if poly else int(_f(p, pre + "retrigger"))
	if retrig == 1:
		l.free = false
	else:
		# Free (or following the host's playhead, which starts with the render): running since the
		# instance started.
		l.free = true
		ph += PREROLL_S * hz
	if ph != 0.0:
		l.phase = fposmod(ph, 1.0)
	return {lfo = l, scale = scale, hz = hz}


## The step sequencer as a custom LFO (one cycle = num_steps steps), its smoothing (a one-pole
## with a half-life in seconds) worked out into the points.
static func _steps(p: Dictionary) -> Dictionary:
	var n := clampi(int(_f(p, "num_steps")), 1, 32)
	var sync := clampi(int(_f(p, "step_sequencer_sync")), 0, 3)
	var rate := 0.0   # steps per second
	if sync == 0:
		rate = pow(2.0, _f(p, "step_frequency"))
	else:
		rate = SYNC_RATIO[clampi(int(_f(p, "step_sequencer_tempo")), 0, 11)] * SYNC_MOD[sync] * BPS
	var vals := []
	for i in n:
		vals.append(clampf(_f(p, "step_seq_%02d" % i), -1.0, 1.0))
	var l := {shape = "custom", free = true}
	var half := _f(p, "step_smoothing")
	if half <= 0.0:
		l.points = vals
		l.interp = "step"
	else:
		var m := clampi(n * maxi(1, 256 / n), n, 256)
		var per_step := m / n
		var dt := 1.0 / (rate * per_step)
		var k := pow(0.5, dt / half)
		var y: float = vals[n - 1]
		var pts := []
		for cyc in 4:
			for j in m:
				var raw: float = vals[j / per_step]
				y = raw + (y - raw) * k
				if cyc == 3:
					pts.append(y)
		l.points = pts
		l.interp = "linear"
	var hz := rate / n
	if sync == 0:
		l.rate_hz = hz
	else:
		l.rate_sync = BPS / hz
	l.phase = fposmod(PREROLL_S * hz, 1.0)
	return {lfo = l, scale = 1.0, hz = hz}


# --- conversion ------------------------------------------------------------------------

## A source's typical value while a note holds (for destinations GAK can't modulate).
static func _typical(p: Dictionary, src: String) -> float:
	match src:
		"amp_envelope":
			return env_mean(p, "amp")
		"fil_envelope":
			return env_mean(p, "fil")
		"mod_envelope":
			return env_mean(p, "mod")
		"velocity", "aftertouch":
			return 100.0 / 127.0
		"note":
			return 60.0 / 127.0
		"step_sequencer":
			var n := clampi(int(_f(p, "num_steps")), 1, 32)
			var s := 0.0
			for i in n:
				s += _f(p, "step_seq_%02d" % i)
			return s / n
	return 0.0


## An envelope's mean level over the first TYPICAL_S of a held note.
static func env_mean(p: Dictionary, pre: String) -> float:
	var a := _f(p, pre + "_attack")
	a *= a
	var d := _f(p, pre + "_decay")
	var tau := maxf(1e-4, d * d / log(256.0))
	var sus := clampf(_f(p, pre + "_sustain"), 0.0, 1.0)
	var acc := 0.0
	var n := 200
	for i in n:
		var t := (i + 0.5) / n * TYPICAL_S
		acc += t / a if t < a else sus + (1.0 - sus) * exp(-(t - a) / tau)
	return acc / n


## Helm's modulation destinations GAK has rows for.
const SUPPORTED := ["cutoff", "resonance", "osc_1_transpose", "osc_1_tune", "osc_2_transpose", "osc_2_tune",
	"osc_1_volume", "osc_2_volume", "sub_volume", "noise_volume", "cross_modulation", "mono_lfo_1_frequency",
	"mono_lfo_2_frequency", "poly_lfo_frequency", "step_frequency", "sub_shuffle", "osc_feedback_amount",
	"osc_feedback_transpose", "osc_feedback_tune", "formant_x", "formant_y"]
const SOURCES := ["amp_envelope", "fil_envelope", "mod_envelope", "poly_lfo", "mono_lfo_1", "mono_lfo_2",
	"step_sequencer", "velocity", "aftertouch", "note", "random", "mod_wheel", "pitch_wheel"]


## Whether a row can be a GAK matrix row (its source and destination both exist there).
static func _row_ok(p: Dictionary, m: Dictionary) -> bool:
	var d := String(m.destination)
	if not (String(m.source) in SOURCES) or not (d in SUPPORTED):
		return false
	if m.has("via") and not (String(m.via) in SOURCES):
		return false
	match d:
		"resonance":
			return _f(p, "filter_on") != 0.0 and int(_f(p, "filter_style")) != 2
		"mono_lfo_1_frequency":
			return int(_f(p, "mono_lfo_1_sync")) == 0
		"mono_lfo_2_frequency":
			return int(_f(p, "mono_lfo_2_sync")) == 0
		"poly_lfo_frequency":
			return int(_f(p, "poly_lfo_sync")) == 0
		"step_frequency":
			return int(_f(p, "step_sequencer_sync")) == 0
		"formant_x", "formant_y":
			return _f(p, "formant_on") != 0.0
	return true


## Rows that act through others, worked out into rows GAK can take. A row may carry `via` (a second
## Helm source it is multiplied by, GAK's `via`) and `unit` (its LFO source taken without its
## amplitude); the rows they replace are marked `handled`.
## - a source moving the filter envelope's depth: the envelope via that source, on the cutoff (exact);
## - a source moving an LFO's amplitude (itself too): that LFO via the source, on whatever the LFO
##   moves (exact);
## - a source moving the filter envelope's sustain moves whatever that envelope moves, by that much
##   (to first order: exact once the envelope has reached its sustain).
static func _derived(p: Dictionary, rows: Array) -> Array:
	var out := []
	for m: Dictionary in rows:
		out.append(m.duplicate())
	for m: Dictionary in rows:
		var src := String(m.source)
		var dst := String(m.destination)
		var a := float(m.amount)
		if not (src in SOURCES):
			continue
		if dst == "fil_sustain":
			out.append({source = src, destination = "cutoff", amount = a * _f(p, "fil_env_depth")})
			for r: Dictionary in rows:
				if String(r.source) == "fil_envelope" and String(r.destination) != "fil_sustain":
					out.append({source = src, destination = r.destination, amount = a * float(r.amount)})
		elif dst == "fil_env_depth":
			out.append({source = "fil_envelope", via = src, destination = "cutoff", amount = a})
			_mark(out, m)
		elif dst.ends_with("_amplitude") and dst.trim_suffix("_amplitude") in ["mono_lfo_1", "mono_lfo_2", "poly_lfo"]:
			var lfo := dst.trim_suffix("_amplitude")
			for r: Dictionary in rows:
				if String(r.source) == lfo and not String(r.destination).ends_with("_amplitude"):
					out.append({source = lfo, via = src, unit = true, destination = r.destination, amount = float(r.amount) * a})
			_mark(out, m)
	return out


static func _mark(rows: Array, m: Dictionary) -> void:
	for r: Dictionary in rows:
		if r.source == m.source and r.destination == m.destination and r.amount == m.amount and not r.has("via"):
			r.handled = true
			return


## A Helm source as GAK's: [name, scale, offset] (Helm's value = scale x GAK's + offset). `unit`: an
## LFO without its amplitude (its sign only).
static func _gak_src(src: String, lfo_src: Dictionary, unit: bool) -> Array:
	match src:
		"amp_envelope": return ["env1", 1.0, 0.0]
		"fil_envelope": return ["env2", 1.0, 0.0]
		"mod_envelope": return ["env3", 1.0, 0.0]
		"velocity", "aftertouch": return ["velocity", 1.0, 0.0]
		"note": return ["key", 12.0 / 127.0, 60.0 / 127.0]
		"random": return ["random", 1.0, 0.0]
		"mod_wheel": return ["mod_wheel", 1.0, 0.0]
		"pitch_wheel": return ["bend", 1.0, 0.0]
	var l: Dictionary = lfo_src[src]
	return [l.name, float(l.sign) if unit else float(l.scale), 0.0]


static func _lfo_sign(p: Dictionary, pre: String) -> float:
	return -1.0 if int(_f(p, pre + "waveform")) == 3 else 1.0


## A Helm patch (the prep tool's content.helm) as a patch.
static func convert(content: Dictionary) -> AKPatch:
	var p := params(content)
	var mods_in := modulations(content)
	var stored_cutoff := _f(p, "cutoff")
	var out := AKPatch.new()

	# Rows GAK can't take act through their source's typical value; the note source's offset (it
	# runs 0..1 over MIDI 0..127, GAK's key source 0 at middle C) moves the base too.
	mods_in = _derived(p, mods_in)
	var rows := []
	var blend_swing := 0.0   # the blend's swing from LFO-like rows, as one amplitude
	for m: Dictionary in mods_in:
		if String(m.destination) == "filter_blend" and String(m.source) in BIPOLAR:
			var amp := float(m.amount) * (_f(p, String(m.source) + "_amplitude") if String(m.source).ends_with("lfo") or String(m.source).begins_with("mono_lfo") else 1.0)
			blend_swing = sqrt(blend_swing * blend_swing + amp * amp)
			continue
		if m.get("handled", false):
			continue
		if _row_ok(p, m):
			rows.append(m)
			if String(m.source) == "note" and not m.has("via"):
				p[m.destination] = _f(p, m.destination) + float(m.amount) * 60.0 / 127.0
		else:
			p[m.destination] = _f(p, m.destination) + float(m.amount) * _typical(p, String(m.source))
	var modded := {}
	for m: Dictionary in rows:
		modded[String(m.destination)] = true

	# Oscillators: osc 1, osc 2, sub, noise, then the cross modulation's sines.
	var oscs: Array[Dictionary] = []
	var index := {}   # role -> 1-based oscillator number
	var kf := {}      # volume parameter -> [oscillator number, level factor]
	for n in [1, 2]:
		var vk := "osc_%d_volume" % n
		if _f(p, vk) == 0.0 and not modded.has(vk):
			continue
		var r := _osc(p, n)
		var o: Dictionary = r.osc
		var v := _f(p, vk)
		o.level = v * v * float(r.k)
		oscs.append(o)
		index["osc%d" % n] = oscs.size()
		kf[vk] = [oscs.size(), float(r.k)]
	if _f(p, "sub_volume") != 0.0 or modded.has("sub_volume"):
		var r := _sub(p, 9 if modded.has("sub_shuffle") else 1)
		var o: Dictionary = r.osc
		var v := _f(p, "sub_volume")
		o.level = v * v * float(r.k)
		oscs.append(o)
		index.sub = oscs.size()
		kf.sub_volume = [oscs.size(), float(r.k)]
	if _f(p, "noise_volume") != 0.0 or modded.has("noise_volume"):
		var v := _f(p, "noise_volume")
		oscs.append({shape = "noise", level = v * v})
		index.noise = oscs.size()
		kf.noise_volume = [oscs.size(), 1.0]
	var cm := _f(p, "cross_modulation")
	if cm != 0.0 or modded.has("cross_modulation"):
		# Each oscillator's phase moves by pi * cm * sin(the other's phase), the sines themselves
		# moved the same way by each other (helm_oscillators.cpp): two silent sines at the
		# oscillators' pitches, modulating each other and the oscillators.
		var idx := PI * cm
		for n in [1, 2]:
			var sh := {shape = "sine", level = 0.0}
			var pre := "osc_%d_" % n
			if _f(p, pre + "transpose") != 0.0:
				sh.semitones = _f(p, pre + "transpose")
			if _f(p, pre + "tune") != 0.0:
				sh.cents = _f(p, pre + "tune") * 100.0
			oscs.append(sh)
			index["sh%d" % n] = oscs.size()
		oscs[index.sh1 - 1].fm_from = index.sh2
		oscs[index.sh1 - 1].fm_index = idx
		oscs[index.sh2 - 1].fm_from = index.sh1
		oscs[index.sh2 - 1].fm_index = idx
		if index.has("osc1"):
			oscs[index.osc1 - 1].fm_from = index.sh2
			oscs[index.osc1 - 1].fm_index = idx
		if index.has("osc2"):
			oscs[index.osc2 - 1].fm_from = index.sh1
			oscs[index.osc2 - 1].fm_index = idx
	if oscs.is_empty():
		oscs.append({shape = "sine", level = 0.0})
	out.oscillators = oscs

	# Oscillator feedback: a comb tuned to the note.
	var fb := _f(p, "osc_feedback_amount")
	if fb != 0.0 or modded.has("osc_feedback_amount") or modded.has("osc_feedback_transpose") or modded.has("osc_feedback_tune"):
		out.comb = {semitones = _f(p, "osc_feedback_transpose"), cents = _f(p, "osc_feedback_tune") * 100.0,
			feedback = clampf(fb, -0.99, 0.99)}

	# Filter. Helm's cutoff is a MIDI note, key tracked about MIDI 64 (GAK's key source is 0 at 60).
	var pre_gain := 0.0   # dB, before the distortion
	var style := int(_f(p, "filter_style"))
	var on := _f(p, "filter_on") != 0.0
	var res := clampf(_f(p, "resonance"), 0.0, 1.0)
	var mods: Array[Dictionary] = []
	if on:
		var track := _f(p, "keytrack")
		var cut := _hz(_f(p, "cutoff") + track * (60.0 - 64.0))
		if style == 2:
			out.filter = {type = ["lowshelf", "bandshelf", "highshelf"][clampi(int(_f(p, "filter_shelf")), 0, 2)],
				cutoff_hz = cut, q = 1.0, gain_db = -24.0 + 48.0 * res}
		else:
			var q := clampf(pow(2.0, 5.0 * res - 1.0), 0.1, 16.0)
			# The blend's weights (an equal-power LP > BP > HP crossfade); an LFO sweeping it gives
			# its weights' mean power over a sine's swing.
			var wts := [0.0, 0.0, 0.0]
			var steps := 64 if blend_swing != 0.0 else 1
			for i in steps:
				var b := clampf(_f(p, "filter_blend") + blend_swing * sin(TAU * i / steps), 0.0, 2.0)
				wts[0] += clampf(1.0 - b, 0.0, 1.0) / steps
				wts[1] += clampf(1.0 - absf(b - 1.0), 0.0, 1.0) / steps
				wts[2] += clampf(b - 1.0, 0.0, 1.0) / steps
			out.filter = {type = "mix", cutoff_hz = cut, q = sqrt(q) if style == 1 else q,
				low = sqrt(wts[0]), band = sqrt(wts[1]), high = sqrt(wts[2]), slope_db = 24.0 if style == 1 else 12.0}
		if track != 0.0:
			mods.append({source = "key", dest = "cutoff", amount = track})
		# Helm smooths its cutoff (a 3 Hz one-pole) from the default, 80, once a patch loads: a note
		# soon after still hears the rest of that glide. env4 runs it from the note on.
		var left := (80.0 - stored_cutoff) * exp(-(PREROLL_S - CUTOFF_LAG) / CUTOFF_TAU)
		if absf(left) > 0.5:
			out.envelopes = [{attack_s = CUTOFF_LAG, decay_s = CUTOFF_TAU, sustain = 0.0, release_s = CUTOFF_TAU, curve = "exp"}]
			mods.append({source = "env4", dest = "cutoff", amount = left / 12.0})
		# The drive: tanh(drive x) ahead of the filter, taken as the gain it has on the mix.
		pre_gain += _db(drive_gain(p, pow(10.0, _f(p, "filter_drive") / 20.0), fb))
	else:
		out.filter = {type = "off"}

	# The formant filter: per voice, after Helm's filter (and its stutter), before the amp
	# (helm_voice_handler.cpp): GAK's formant type in filter 2 behind the filter, or in filter 1 when
	# Helm's filter is off. Helm's band-passes peak at their gains (kGainedBandPass), GAK's at unity
	# (the first formant at 0 dB): the first formant's gain and the overall gain go into the gain.
	var vowel_dest := ""
	var fslope := [0.0, 0.0]
	if _f(p, "formant_on") != 0.0:
		var ff := formant_fit(_f(p, "formant_x"), _f(p, "formant_y"))
		var fd := {type = "formant", vowel = float(ff.vowel), formant_set = "tenor", formant_q = float(ff.formant_q)}
		if float(ff.formant_shift) != 0.0:
			fd.formant_shift = float(ff.formant_shift)
		if on:
			out.filter2 = fd
			vowel_dest = "vowel2"
		else:
			out.filter = fd
			vowel_dest = "vowel"
		pre_gain += float(ff.gain_db)
		if modded.has("formant_x") or modded.has("formant_y"):
			fslope = formant_slope(_f(p, "formant_x"), _f(p, "formant_y"))

	# Envelopes: attack linear, decay and release reach 1/256 of the way in their time.
	out.amp_env = _env(p, "amp")
	out.env2 = _env(p, "fil")
	out.env3 = _env(p, "mod")
	var depth := _f(p, "fil_env_depth")
	if on and depth != 0.0:
		mods.append({source = "env2", dest = "cutoff", amount = depth / 12.0})

	# LFOs: lfo1, lfo2 the mono ones; the poly LFO and the step sequencer in `lfos` when used.
	var used := {}
	for m: Dictionary in rows:
		used[String(m.source)] = true
		used[String(m.get("via", ""))] = true
	var lfo_src := {}   # Helm source -> {name, scale}
	var l1 := _lfo(p, "mono_lfo_1_", false)
	var l2 := _lfo(p, "mono_lfo_2_", false)
	out.lfo1 = l1.lfo
	out.lfo2 = l2.lfo
	lfo_src.mono_lfo_1 = {name = "lfo1", scale = l1.scale, sign = _lfo_sign(p, "mono_lfo_1_")}
	lfo_src.mono_lfo_2 = {name = "lfo2", scale = l2.scale, sign = _lfo_sign(p, "mono_lfo_2_")}
	var extra: Array[Dictionary] = []
	if used.has("poly_lfo"):
		var lp := _lfo(p, "poly_lfo_", true)
		extra.append(lp.lfo)
		lfo_src.poly_lfo = {name = "lfo%d" % (extra.size() + 2), scale = lp.scale, sign = _lfo_sign(p, "poly_lfo_")}
	if used.has("step_sequencer"):
		var ls := _steps(p)
		extra.append(ls.lfo)
		lfo_src.step_sequencer = {name = "lfo%d" % (extra.size() + 2), scale = 1.0, sign = 1.0}
	out.lfos = extra

	# Modulation rows: each row's terms (a note source's offset splits a product in two), then its
	# destination in GAK's units.
	var vols := {}   # volume parameter -> [[gak source, amount]] (Helm squares the sum)
	for m: Dictionary in rows:
		var dst := String(m.destination)
		var s1 := _gak_src(String(m.source), lfo_src, bool(m.get("unit", false)))
		var terms := []   # [source, via, amount]
		var a := float(m.amount)
		if m.has("via"):
			var s2 := _gak_src(String(m.via), lfo_src, false)
			terms.append([s1[0], s2[0], a * float(s1[1]) * float(s2[1])])
			if float(s2[2]) != 0.0:
				terms.append([s1[0], "", a * float(s1[1]) * float(s2[2])])
			if float(s1[2]) != 0.0:
				terms.append([s2[0], "", a * float(s1[2]) * float(s2[1])])
		else:
			terms.append([s1[0], "", a * float(s1[1])])
		for t: Array in terms:
			var gs: String = t[0]
			var gv: String = t[1]
			var amt: float = t[2]
			var add := func(dest: String, x: float) -> void:
				var row := {source = gs, dest = dest, amount = x}
				if gv != "":
					row.via = gv
				mods.append(row)
			match dst:
				"cutoff":
					if on:
						add.call("cutoff", amt / 12.0)
				"resonance":
					add.call("q", amt * (2.5 if style == 1 else 5.0))
				"osc_1_transpose", "osc_1_tune", "osc_2_transpose", "osc_2_tune":
					var n := dst.substr(4, 1)
					for role in ["osc" + n, "sh" + n]:
						if index.has(role):
							add.call("osc%d.pitch" % index[role], amt)
				"osc_1_volume", "osc_2_volume", "sub_volume", "noise_volume":
					if kf.has(dst):
						if gv == "":
							if not vols.has(dst):
								vols[dst] = []
							vols[dst].append([gs, amt])
						else:
							# A product on a squared volume: its slope only.
							add.call("osc%d.level" % int(kf[dst][0]), float(kf[dst][1]) * 2.0 * _f(p, dst) * amt)
				"cross_modulation":
					for role in ["osc1", "osc2", "sh1", "sh2"]:
						if index.has(role):
							add.call("osc%d.fm" % index[role], PI * amt)
				"osc_feedback_amount":
					add.call("comb.feedback", amt)
				"osc_feedback_transpose", "osc_feedback_tune":
					add.call("comb.pitch", amt)
				"mono_lfo_1_frequency":
					add.call("lfo1.rate", amt)
				"mono_lfo_2_frequency":
					add.call("lfo2.rate", amt)
				"poly_lfo_frequency":
					if lfo_src.has("poly_lfo"):
						add.call(String(lfo_src.poly_lfo.name) + ".rate", amt)
				"step_frequency":
					if lfo_src.has("step_sequencer"):
						add.call(String(lfo_src.step_sequencer.name) + ".rate", amt)
				"sub_shuffle":
					if index.has("sub"):
						add.call("osc%d.position" % index.sub, amt)
				"formant_x", "formant_y":
					var dv := float(fslope[0 if dst == "formant_x" else 1])
					if vowel_dest != "" and not is_nan(dv) and dv != 0.0:
						add.call(vowel_dest, amt * dv)
	# Volumes: gain = k (v + sum a_i s_i)^2 = k v^2 + 2 k v a_i s_i + k a_i a_j s_i s_j, the products as
	# rows with `via`: exact.
	for dst: String in vols:
		var v := _f(p, dst)
		var j: int = kf[dst][0]
		var k: float = kf[dst][1]
		var ts: Array = vols[dst]
		for i in ts.size():
			mods.append({source = ts[i][0], dest = "osc%d.level" % j, amount = k * 2.0 * v * float(ts[i][1])})
			for i2 in range(i, ts.size()):
				mods.append({source = ts[i][0], via = ts[i2][0], dest = "osc%d.level" % j,
					amount = k * float(ts[i][1]) * float(ts[i2][1]) * (1.0 if i2 == i else 2.0)})
	if mods.size() > AKPatch.MAX_MODS:
		mods.resize(AKPatch.MAX_MODS)
	out.oscillators = oscs
	out.mods = mods

	# Playing.
	var poly := clampi(int(_f(p, "polyphony")), 1, 32)
	out.polyphony = poly
	if poly == 1:
		out.mode = "legato" if _f(p, "legato") != 0.0 else "mono"
		out.retrigger_from_zero = true   # Helm restarts every envelope from zero
	else:
		out.mode = "poly"
	out.bend_range = _f(p, "pitch_bend_range")
	if int(_f(p, "portamento_type")) == 2:
		# Helm glides (0.4 + 0.07 d^2) / T semitones a second; a time constant matched at an octave.
		out.glide_s = 1.14 * pow(2.0, _f(p, "portamento"))
	var vt := clampf(_f(p, "velocity_track"), -1.0, 1.0)
	if vt >= 0.0:
		out.velocity_sens = vt
	else:
		# Louder for softer notes: (1 - vt) (1 + vt / (1 - vt) velocity).
		out.velocity_sens = 0.0
		mods.append({source = "velocity", dest = "amp", amount = vt / (1.0 - vt)})
		pre_gain += _db(1.0 - vt)
		out.mods = mods
	out.tempo_bpm = BPS * 60.0

	# Arpeggiator.
	if _f(p, "arp_on") != 0.0:
		var sync := clampi(int(_f(p, "arp_sync")), 0, 3)
		var f: float = pow(2.0, _f(p, "arp_frequency")) if sync == 0 else \
			SYNC_RATIO[clampi(int(_f(p, "arp_tempo")), 0, 11)] * SYNC_MOD[sync] * BPS
		var min_gate: float = 0.03 * f
		out.arp = {mode = ["up", "down", "updown", "up", "random"][clampi(int(_f(p, "arp_pattern")), 0, 4)],
			octaves = clampi(int(_f(p, "arp_octaves")), 1, 4), rate = BPS / f * ARP_CLOCK,
			gate = clampf(lerpf(min_gate, 1.0, _f(p, "arp_gate")), 0.01, 1.0)}

	# Effects: distortion, delay, reverb; Helm's volume after them.
	var fx: Array[Dictionary] = []
	var post_gain := _db(_f(p, "volume") * _f(p, "volume"))
	var sat := {}
	if _f(p, "distortion_on") != 0.0:
		var dd := _f(p, "distortion_drive")
		var g := pow(10.0, dd / 20.0)
		sat = {type = "saturate", drive_db = dd, tone_hz = 20000.0, asymmetry = 0.0,
			mix = clampf(_f(p, "distortion_mix"), 0.0, 1.0), output_db = _db(tanh(g))}
		fx.append(sat)
	if _f(p, "delay_on") != 0.0:
		var sync := clampi(int(_f(p, "delay_sync")), 0, 3)
		var t: float = 1.0 / pow(2.0, _f(p, "delay_frequency")) if sync == 0 else \
			1.0 / (SYNC_RATIO[clampi(int(_f(p, "delay_tempo")), 0, 11)] * SYNC_MOD[sync] * BPS)
		var w := clampf(_f(p, "delay_dry_wet"), 0.0, 1.0)
		# Helm: sqrt(1 - w) dry + sqrt(w) wet; GAK adds the wet at `mix` to the dry.
		var dry := sqrt(1.0 - w)
		var wet := sqrt(w)
		var mix := 1.0
		if dry >= wet:
			mix = wet / dry
			post_gain += _db(dry)
		else:
			# The dry too loud, the wet too quiet: between the two (fitted on the library's levels).
			post_gain += _db(sqrt(wet * sqrt((dry * dry + wet * wet) * 0.5)))
		fx.append({type = "delay", time_ms = clampf(t * 1000.0, 1.0, 2000.0), feedback = clampf(_f(p, "delay_feedback"), -0.95, 0.95),
			damp_hz = 20000.0, mix = mix, mode = "stereo"})
	if _f(p, "reverb_on") != 0.0:
		var w := clampf(_f(p, "reverb_dry_wet"), 0.0, 1.0)
		var dry := sqrt(1.0 - w)
		var wet := sqrt(w) * 0.5   # GAK's reverb takes left + right, Helm's the mono signal
		var mix := 1.0
		if dry >= wet:
			mix = wet / dry
			post_gain += _db(dry)
		else:
			post_gain += _db(sqrt((dry * dry + wet * wet) * 0.5))   # the dry too loud, the wet too quiet: their power
		fx.append({type = "reverb", room = clampf((_f(p, "reverb_feedback") - 0.7) / 0.28, 0.0, 1.0),
			damp = clampf(_f(p, "reverb_damping") / 0.4, 0.0, 2.5), width = 1.0, mix = mix})
	out.effects = fx
	# Gains after the distortion go into its output; without one, everything is linear.
	if not sat.is_empty():
		sat.output_db = float(sat.output_db) + post_gain
		out.gain_db = pre_gain + CAL_DB
	else:
		out.gain_db = pre_gain + post_gain + CAL_DB
	out.resource_name = String(content.get("name", ""))
	return out


## Helm's formant filter's vowels (helm_voice_handler.cpp): per formant [gain dB, Q, MIDI note], and
## the overall gain in dB. Corners of its x/y square: A (0, 0), O (1, 0), I (0, 1), E (1, 1).
const VOWELS := {
	a = [[24.0, 10.0, 75.7552], [18.0, 12.0, 84.5455], [17.0, 16.0, 100.0850], [16.0, 16.0, 101.6457], -4.0],
	o = [[24.0, 11.0, 67.3500], [14.0, 12.0, 79.3500], [12.0, 16.0, 99.7552], [12.0, 16.0, 101.0382], -4.0],
	i = [[24.0, 13.0, 61.7826], [9.0, 12.0, 94.0496], [6.0, 16.0, 101.0382], [4.0, 16.0, 103.6184], -2.0],
	e = [[24.0, 10.0, 67.3500], [10.0, 12.0, 92.3995], [12.0, 16.0, 99.7552], [10.0, 16.0, 103.3500], -2.0]}
## Helm's vowels are the Csound formant table's tenor a, o, i, e (frequencies exactly, levels relative to
## the first formant exactly, its own Qs), which is GAK's `formant` filter's `tenor` set: its corners are
## GAK's vowels a (0), o (0.75), i (0.5), e (0.25). Helm interpolates the square bilinearly (MIDI notes,
## so in log frequency); GAK's vowel is one axis (a e i o u, in Hz), so a point inside the square is
## fitted: the vowel and formant_shift whose first four formants sit nearest Helm's (in semitones,
## weighted by each formant's level), formant_q the level-weighted ratio of the Qs. Exact at the corners;
## the i-e edge to within a few cents.
const FORMANT_SET := 1   # tenor, in AKSynthCore.FORMANTS
## Grid steps of the vowel search.
const FORMANT_STEPS := 400
## Weight of formant_shift (semitones squared) against the fit's error, so a plain vowel wins a near tie.
const FORMANT_SHIFT_COST := 0.05


## Helm's formant filter at (x, y): [gain dB, Q, MIDI note] per formant, and the overall gain (dB).
static func helm_formants(x: float, y: float) -> Dictionary:
	x = clampf(x, 0.0, 1.0)
	y = clampf(y, 0.0, 1.0)
	var lerp4 := func(a: float, o: float, i: float, e: float) -> float:
		return lerpf(lerpf(a, o, x), lerpf(i, e, x), y)
	var bands := []
	for k in 4:
		var v := []
		for j in 3:
			v.append(lerp4.call(VOWELS.a[k][j], VOWELS.o[k][j], VOWELS.i[k][j], VOWELS.e[k][j]))
		bands.append(v)
	return {bands = bands, overall = lerp4.call(VOWELS.a[4], VOWELS.o[4], VOWELS.i[4], VOWELS.e[4])}


## GAK's formant filter's table (tenor) at `vowel`: [Hz, bandwidth Hz, dB] for its first four formants,
## read as the engine reads it (straight lines between the vowels).
static func gak_formants(vowel: float) -> Array:
	var base := FORMANT_SET * 75
	var p4 := clampf(vowel, 0.0, 1.0) * 4.0
	var vi := mini(3, floori(p4))
	var w := p4 - float(vi)
	var t := AKSynthCore.FORMANTS
	var out := []
	for i in 4:
		var a0 := base + vi * 15 + i * 3
		var b0 := a0 + 15
		out.append([lerpf(t[a0], t[b0], w), lerpf(t[a0 + 1], t[b0 + 1], w), lerpf(t[a0 + 2], t[b0 + 2], w)])
	return out


## Helm's formant filter at (x, y) as GAK's: {vowel, formant_shift, formant_q, gain_db (Helm's first
## formant's level plus its overall gain: GAK's formants are unity at their peaks, the first at 0 dB),
## err (the fit's level-weighted RMS error, semitones)}.
static func formant_fit(x: float, y: float) -> Dictionary:
	var h := helm_formants(x, y)
	var w := []
	var wsum := 0.0
	for b: Array in h.bands:
		w.append(pow(10.0, float(b[0]) / 40.0))
		wsum += float(w[-1])
	var best := {cost = INF}
	for s in FORMANT_STEPS + 1:
		var v := float(s) / FORMANT_STEPS
		var g := gak_formants(v)
		var r := []
		var mean := 0.0
		for i in 4:
			r.append(float(h.bands[i][2]) - (69.0 + 12.0 * log(float(g[i][0]) / 440.0) / log(2.0)))
			mean += float(w[i]) * float(r[i]) / wsum
		var err := 0.0
		for i in 4:
			err += float(w[i]) * pow(float(r[i]) - mean, 2.0) / wsum
		var cost := err + FORMANT_SHIFT_COST * mean * mean
		if cost < float(best.cost) - 1e-9:
			best = {cost = cost, vowel = v, shift = mean, err = sqrt(err), g = g}
	var lq := 0.0
	for i in 4:
		var gq := float(best.g[i][0]) / maxf(1.0, float(best.g[i][1]))
		lq += float(w[i]) * log(float(h.bands[i][1]) / gq) / wsum
	return {vowel = best.vowel, formant_shift = snappedf(float(best.shift), 1e-4), formant_q = snappedf(exp(lq), 1e-4),
		gain_db = float(h.bands[0][0]) + float(h.overall), err = best.err}


## How GAK's vowel moves with Helm's x and y at (x, y) (central differences of the fit, one-sided at the
## edges): [d vowel / dx, d vowel / dy], for rows to formant_x / formant_y. A step where the fit jumps
## to another part of the vowel axis (a slope steeper than 1; smooth stretches stay under 0.6) gives NAN:
## no line fits there.
static func formant_slope(x: float, y: float) -> Array:
	const H := 0.05
	var out := []
	for axis in 2:
		var lo := [x, y]
		var hi := [x, y]
		lo[axis] = maxf(0.0, float(lo[axis]) - H)
		hi[axis] = minf(1.0, float(hi[axis]) + H)
		var d := float(hi[axis]) - float(lo[axis])
		var dv := float(formant_fit(hi[0], hi[1]).vowel) - float(formant_fit(lo[0], lo[1]).vowel)
		out.append(NAN if d <= 0.0 or absf(dv) > d else dv / d)
	return out


## An envelope: times are the stored value squared (seconds); the decay and release are
## exponential, reaching 1/256 of the way in that time (a time constant of t / ln 256).
static func _env(p: Dictionary, pre: String) -> Dictionary:
	var a := _f(p, pre + "_attack")
	var d := _f(p, pre + "_decay")
	var r := _f(p, pre + "_release")
	return {attack_s = a * a, decay_s = maxf(1e-4, d * d / log(256.0)), sustain = clampf(_f(p, pre + "_sustain"), 0.0, 1.0),
		release_s = maxf(1e-4, r * r / log(256.0)), curve = "exp"}


## A fit worse than this (level-weighted RMS, semitones) is listed in the caveats.
const FORMANT_CAVEAT_ST := 0.25


## The formant x and y convert() fits: stored values, a note row's offset and rows GAK can't take at
## their source's mean, as convert() folds them in.
static func _formant_xy(p: Dictionary, mods: Array) -> Array:
	var q := p.duplicate()
	for m: Dictionary in _derived(p, mods):
		var d := String(m.destination)
		if not (d in ["formant_x", "formant_y"]) or m.get("handled", false):
			continue
		if _row_ok(q, m):
			if String(m.source) == "note" and not m.has("via"):
				q[d] = _f(q, d) + float(m.amount) * 60.0 / 127.0
		else:
			q[d] = _f(q, d) + float(m.amount) * _typical(q, String(m.source))
	return [_f(q, "formant_x"), _f(q, "formant_y")]


## What the conversion only approximates, for this patch.
static func caveats(content: Dictionary) -> Array:
	var p := params(content)
	var out := []
	var dropped := {}
	var approx := {}
	var vol := {}
	var mods := modulations(content)
	var lfo_used := {}
	for m: Dictionary in mods:
		lfo_used[String(m.source)] = true
	for m: Dictionary in mods:
		var src := String(m.source)
		var dst := String(m.destination)
		var name := "%s > %s" % [src, dst]
		var amp_of := dst.trim_suffix("_amplitude") if dst.ends_with("_amplitude") else ""
		if dst == "fil_env_depth" and src in SOURCES:
			continue
		if amp_of in ["mono_lfo_1", "mono_lfo_2", "poly_lfo"] and src in SOURCES:
			# Exact as products (via) on the LFO's rows; one on volumes keeps only its slope.
			for r: Dictionary in mods:
				if String(r.source) == amp_of and String(r.destination).ends_with("_volume"):
					vol["%s > %s (through %s)" % [src, r.destination, amp_of]] = true
			continue
		if (dst == "fil_sustain" and src in SOURCES) or (dst == "filter_blend" and src in BIPOLAR):
			approx[name] = true
		elif not _row_ok(p, m):
			dropped[name] = true
	if not dropped.is_empty():
		out.append("modulation not converted (taken at its source's mean): " + ", ".join(dropped.keys()))
	if not approx.is_empty():
		out.append("modulation approximated to first order: " + ", ".join(approx.keys()))
	if not vol.is_empty():
		out.append("volume modulation by a product linearised (Helm squares it): " + ", ".join(vol.keys()))
	if _f(p, "formant_on") != 0.0:
		# The x/y as the conversion sees them (rows GAK can't take folded in at their means).
		var fxy := _formant_xy(p, mods)
		var ff := formant_fit(fxy[0], fxy[1])
		if float(ff.err) > FORMANT_CAVEAT_ST:
			out.append("formant filter: Helm's x/y square fitted onto GAK's vowel axis (%.2f semitones off)" % float(ff.err))
		var fsl := formant_slope(fxy[0], fxy[1])
		for m: Dictionary in mods:
			var d := String(m.destination)
			if d in ["formant_x", "formant_y"] and _row_ok(p, m):
				if is_nan(float(fsl[0 if d == "formant_x" else 1])):
					out.append("formant %s modulation not converted (the vowel fit jumps there)" % d.trim_prefix("formant_"))
				else:
					out.append("formant %s modulation as a straight line on GAK's vowel axis" % d.trim_prefix("formant_"))
	if _f(p, "stutter_on") != 0.0:
		out.append("stutter not converted")
	if _f(p, "filter_on") != 0.0 and _f(p, "filter_drive") > 0.0:
		out.append("filter drive approximated by a gain (no saturation)")
	if _f(p, "distortion_on") != 0.0 and int(_f(p, "distortion_type")) != 0:
		out.append("distortion type %s approximated by soft clipping" % ["", "hard clip", "linear fold", "sine fold"][clampi(int(_f(p, "distortion_type")), 0, 3)])
	if _f(p, "delay_on") != 0.0 and _f(p, "delay_dry_wet") > 0.5:
		out.append("delay mix above half: dry level too high")
	if _f(p, "reverb_on") != 0.0 and _f(p, "reverb_dry_wet") > 0.8:
		out.append("reverb mix above 0.8: dry level too high")
	if _f(p, "reverb_on") != 0.0 and _f(p, "reverb_feedback") > 0.98:
		out.append("reverb feedback above 0.98 held there")
	if absf(_f(p, "osc_feedback_amount")) > 0.99:
		out.append("oscillator feedback held at 0.99")
	if int(_f(p, "portamento_type")) == 1:
		out.append("auto portamento not converted")
	for n in [1, 2]:
		if int(_f(p, "osc_%d_unison_voices" % n)) > 8 and _f(p, "unison_%d_harmonize" % n) == 0.0:
			out.append("osc %d unison: %d voices as 8" % [n, int(_f(p, "osc_%d_unison_voices" % n))])
		if _f(p, "unison_%d_harmonize" % n) != 0.0 and int(_f(p, "osc_%d_unison_voices" % n)) > 1:
			out.append("osc %d harmonize as a wavetable (no beating)" % n)
	if _f(p, "arp_on") != 0.0 and int(_f(p, "arp_pattern")) == 3:
		out.append("arp as played taken as up")
	return out
