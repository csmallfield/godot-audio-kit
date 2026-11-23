# SPDX-License-Identifier: Apache-2.0
## Surge XT patch -> AKPatch, by direct parameter conversion through Surge XT 1.3.4's own formulas
## (its source: SurgeVoice, QuadFilterChain, the oscillators, ADSRModulationSource,
## LFOModulationSource; sst-filters), checked against Surge XT's renders of single settings.
##
##   var Surge := preload("res://tools/patch_convert/surge.gd")
##   var patch: AKPatch = Surge.convert(sidecar.content.surge)   # with patch_xml added (see below)
##   var notes: Array = Surge.caveats(sidecar.content.surge)
##
## It reads the patch as Surge XT itself saved it after loading (`patch_xml`: surge_patch.xml beside
## the reference render, current revision, old revisions migrated), or else the prep tool's
## `params` and `mods`. Wavetables come from the patch chunk (`chunk_b64`).
##
## The patch: the scene that plays (scene A, or B when A is muted or in single mode with B active);
## its three oscillators (classic as a saw, a pulse and the sub square, which is exactly Surge's
## shape morph; sine with its shape modes as one-frame tables; wavetables from the patch's own
## tables; S&H noise as noise; FM2 and FM3 as GAK operators; the others approximated), unison as
## each oscillator's stack, hard sync, the FM routing, ring modulation, the mixer's levels, mutes,
## solos, noise and routes (the oscillators' `filter`), the warm character as a pre-filter; both
## filters (types matched by their measured resonance peaks and levels), the filter configuration
## as filter2 in series or parallel, filter balance as oscillator copies, cutoff, key tracking and
## the filter envelope; the waveshaper as the filter's saturation; the amp and filter envelopes
## (digital and analog); the LFOs (their shapes drawn as custom LFOs, step sequences and MSEGs as
## points, their own envelopes as `via` envelopes, envelope LFOs as envelopes); the modulation
## routings in GAK's units (macros 1-4 as GAK's macros); play mode, polyphony, portamento, bend
## range, velocity; the low cut and the effects GAK has.
extends RefCounted

const VERSION := 1
const LN2 := 0.6931471805599453
const LN10 := 2.302585092994046
## GAK's level against Surge's (dB), from the library's median level error.
const CAL_DB := 0.0
## Surge's Init Saw (a classic saw at level 1, scene volume 1, master 0 dB) against a GAK saw at
## level 1 and 0 dB (measured at middle C: -16.9 dB rms in Surge's left channel, -4.8 dB in GAK).
const BASE_DB := -12.11
## The velocity the references play at (100 / 127).
const VEL_REF := 100.0 / 127.0
## The references start each note 0.1 s into the song: free-running LFOs are that far on.
const PREROLL_S := 0.1
## Surge's sine FM index (radians) at an FM depth of 0 dB: 32 pi (SineOscillator: 32 pi d^3, d linear).
const FM_SINE := 100.53096
## FM2's modulator index at amount 1: 8 pi d^3 (FM2Oscillator calcmd); FM3's: 32 pi d^3.
const FM2_K := 25.132741
const FM3_K := 100.53096
## Sine oscillators in the legacy FM behavior add d m to their phase every sample at 96 kHz:
## linear FM of d 96000 / 2 pi Hz per unit.
const FM_LEGACY_HZ := 15278.875
## Classic FM is linear in frequency (f (1 + d m), d the FM depth linear): as exponential FM, this
## many semitones per unit of d m (12 / ln 2, its slope at m = 0).
const FM_CLASSIC_ST := 17.312340
## Surge's oscillator signals are this much of GAK's per unit (measured through the waveshaper: a
## classic saw at level 1 is +-0.5 inside Surge, its sine +-1).
const OSC_SCALE := 0.5
## The patch's "character" (warm) on the classic, sine, modern, string, twist and alias oscillators:
## a one-pole low-pass, (1 - 2 x 5000 / 48000)^2 run at the 96 kHz oscillator rate, -3 dB at 7.27 kHz.
const WARM_HZ := 7268.0
## Surge's mixer noise against GAK's white noise (measured).
const NOISE_LEVEL := 1.29
## Surge's S&H noise oscillator against GAK's white noise (measured).
const SH_LEVEL := 1.0
## Surge's sine and wavetable oscillators against GAK's saw scale (measured: Surge's sine plays
## 6.1 dB over its saw, GAK's sine 4.8 dB under its saw at the same rms ratio).
const SINE_LEVEL := 2.016
const WT_LEVEL := 2.0
## Wavetables: at most this many frames, each at most this many samples.
const WT_FRAMES := 32
const WT_SAMPLES := 1024
## The standard state-variable filter's coefficient is capped at 2 sin(pi 0.11) (2x oversampled):
## its cutoff stops at 0.11 of 96 kHz.
const SVF_MAX_HZ := 10560.0
## GAK's release power-curve amounts closest to Surge's digital release, phase^n, for n = 1..4.
const REL_AMOUNT := [0.0, -2.054, -3.480, -4.686]
## An exponential stage's length in time constants (and its power-curve amount).
const EXP_TC := 7.0

## Resonance tables: Surge's resonance, and per filter type its measured response at the cutoff
## over the passband (dB) and the passband's level (dB) for white noise at full level, cutoff
## 1357 Hz (tools: a DawDreamer render of Surge's mixer noise through each filter, against none).
const RES_X := [0.0, 0.2, 0.4, 0.6, 0.8, 0.9, 0.95]
const F_SVF12 := [[-5.35, -0.13, 3.52, 8.94, 17.53, 23.47, 25.8], [-0.43, -3.1, -4.53, -5.86, -7.36, -8.24, -8.63]]
const F_SVF24 := [[-11.27, -1.19, 6.24, 15.25, 23.86, 26.5, 27.28], [-0.5, -3.03, -4.09, -5.78, -7.73, -8.71, -8.88]]
const F_DRV12 := [[-5.62, -1.9, 3.15, 9.36, 16.5, 18.83, 20.39], [-0.43, -0.32, -0.93, -1.54, -3.67, -4.38, -5.69]]
const F_CLN12 := [[-12.27, -9.24, -5.17, 1.27, 10.28, 16.13, 17.49], [-1.24, -1.08, -0.4, -1.02, -1.36, -1.98, -2.18]]
const F_DRV24 := [[-10.96, -7.05, -2.24, 4.33, 15.2, 22.22, 26.1], [-1.28, -1.13, -1.84, -3.42, -6.87, -9.24, -10.57]]
const F_CLN24 := [[-25.26, -23.23, -18.46, -13.6, -4.55, 3.06, 8.24], [-2.58, -1.7, -2.0, -2.16, -3.28, -3.96, -4.79]]
const F_LADDER := [[-11.99, -3.84, 2.28, 8.34, 17.54, 22.09, 25.77], [-0.09, -4.47, -6.43, -6.16, -5.76, -4.38, -4.45]]
const F_VINTAGE := [[-11.26, -3.74, 1.82, 8.72, 20.16, 34.15, 41.94], [-5.7, -10.88, -14.13, -16.4, -18.01, -19.13, -19.87]]
const F_HUOV := [[-11.62, -4.5, 1.38, 6.29, 14.0, 20.0, 24.0], [-0.48, -5.48, -8.82, -10.4, -12.0, -13.0, -13.5]]
const F_OBXD12 := [[-5.97, -3.48, -1.24, 2.4, 8.38, 13.21, 18.53], [-2.49, -2.91, -2.86, -2.7, -2.58, -2.28, -2.47]]
const F_OBXD24 := [[-2.55, 3.34, 8.07, 13.3, 18.98, 23.04, 25.25], [-4.63, -6.88, -7.44, -8.17, -8.82, -9.21, -8.78]]
const F_K35 := [[-5.01, -3.95, -1.4, 2.55, 7.87, 12.22, 16.77], [-0.54, -0.23, -0.37, -0.7, -0.33, 0.26, -0.19]]
const F_DIODE := [[-7.65, 2.59, 10.28, 17.18, 23.48, 28.68, 30.57], [-10.78, -12.3, -13.33, -13.81, -14.25, -14.92, -14.37]]
## GAK's ladder, measured the same way: response at the cutoff and passband level by resonance.
const G_LADDER_R := [0.0, 0.2, 0.4, 0.6, 0.8, 0.9, 1.0, 1.1, 1.2]
const G_LADDER_FC := [-11.81, -5.20, 0.38, 6.14, 13.69, 19.07, 25.46, 32.2, 39.0]
const G_LADDER_LO := [-0.33, -2.12, -3.07, -3.64, -4.03, -4.18, -4.34, -4.58, -4.8]
## The diode ladder's peak sits this far under its cutoff (measured at 1357 Hz).
const DIODE_HZ := 0.62

## Menus (SurgeStorage.h, ModulationSource.h, sst-filters' FilterConfiguration.h).
const OSC_NAMES := ["classic", "sine", "wavetable", "s&h noise", "audio input", "fm3", "fm2", "window",
	"modern", "string", "twist", "alias"]
const FILTER_NAMES := ["off", "lp 12", "lp 24", "lp legacy ladder", "hp 12", "hp 24", "bp 12", "notch 12",
	"comb +", "sample & hold", "lp vintage ladder", "lp ob-xd 12", "lp ob-xd 24", "lp k35", "hp k35",
	"lp diode ladder", "lp cutoff warp", "hp cutoff warp", "notch cutoff warp", "bp cutoff warp", "hp ob-xd 12",
	"notch ob-xd 12", "bp ob-xd 12", "bp 24", "notch 24", "comb -", "allpass", "allpass cutoff warp",
	"lp resonance warp", "hp resonance warp", "notch resonance warp", "bp resonance warp",
	"allpass resonance warp", "tri-pole"]
const CONFIG_NAMES := ["serial 1", "serial 2", "serial 3", "dual 1", "dual 2", "stereo", "ring", "wide"]
const FX_NAMES := ["off", "delay", "reverb 1", "phaser", "rotary speaker", "distortion", "eq",
	"frequency shifter", "conditioner", "chorus", "vocoder", "reverb 2", "flanger", "ring modulator",
	"airwindows", "neuron", "graphic eq", "resonator", "chow", "exciter", "ensemble", "combulator", "nimbus",
	"tape", "treemonster", "waveshaper", "mid-side tool", "spring reverb", "bonsai", "audio input"]
const SOURCE_NAMES := ["original", "velocity", "keytrack", "poly aftertouch", "aftertouch", "pitchbend",
	"modwheel", "macro1", "macro2", "macro3", "macro4", "macro5", "macro6", "macro7", "macro8", "amp eg",
	"filter eg", "lfo1", "lfo2", "lfo3", "lfo4", "lfo5", "lfo6", "slfo1", "slfo2", "slfo3", "slfo4", "slfo5",
	"slfo6", "timbre", "release velocity", "random bipolar", "random unipolar", "alternate bipolar",
	"alternate unipolar", "breath", "expression", "sustain", "lowest key", "highest key", "latest key"]
## FX slots in the order Surge runs them: A's inserts, then the sends, then the global ones (B's
## inserts belong to scene B).
const FX_A := [0, 1, 8, 9]
const FX_SEND := [4, 5, 12, 13]
const FX_GLOBAL := [6, 7, 14, 15]
## Surge's delay feedback is an amplitude parameter (x^3; measured: 0.5 repeats 18 dB down).
## Reverb 1's wet signal against GAK's Freeverb at the same decay (measured: 7 dB louder while a
## note holds, 14 dB in the tail; reverb 2 matched as it is). The chorus at mix m against GAK's
## (measured: GAK's 3.3 dB quieter at 0.5).
const REV1_WET := 4.0
const CHORUS_DB := 3.3
## The waveshaper: Surge's signal is 0.5 per GAK unit (measured: tanh(drive x) at drives 0, 12 and
## 24 dB against a dry saw); GAK's c (1 - e^-|u|) with ceiling 2 x 1.18 follows Surge's
## 2 tanh(g x / 2) within 1 dB over drives 0-24 dB and levels 0.3-1.5, and 2.5 put Surge's own
## renders of a saw at drives 0, 12 and 24 dB within 0.5 dB on average. The hard type (clipping at
## 2) needs 2.7 (measured at 12 dB).
const WS_CEIL := 2.5
const WS_HARD_CEIL := 2.7


# --- reading the patch -----------------------------------------------------------------

## The patch as {p: {name: {v, a (attributes), m (routings: {source, depth, muted, index, scene})}},
## seq: {"scene/lfo": {steps, loop_start, loop_end, trigmask}}, macros: [{v, bipolar}], xml: bool}.
static func parse(content: Dictionary) -> Dictionary:
	if content.has("_parsed"):
		return content._parsed
	var p := {}
	var seq := {}
	var msegs := {}
	var macros: Array = []
	var xml := String(content.get("patch_xml", ""))
	var have_xml := false
	if not xml.is_empty():
		var xp := XMLParser.new()
		if xp.open_buffer(xml.to_utf8_buffer()) == OK:
			have_xml = true
			var section := ""
			var last := ""
			while xp.read() == OK:
				var t := xp.get_node_type()
				if t == XMLParser.NODE_ELEMENT:
					var nm := xp.get_node_name()
					if nm in ["parameters", "stepsequences", "customcontroller", "msegs"]:
						if not xp.is_empty():
							section = nm
						continue
					var a := {}
					for i in xp.get_attribute_count():
						a[xp.get_attribute_name(i)] = xp.get_attribute_value(i)
					match section:
						"parameters":
							if nm == "modrouting":
								if p.has(last):
									p[last].m.append({source = int(a.get("source", "0")), depth = float(a.get("depth", "0")),
										muted = int(a.get("muted", "0")), index = int(a.get("source_index", "0")),
										scene = int(a.get("source_scene", "0"))})
							elif a.has("value"):
								p[nm] = {v = float(a.value), a = a, m = []}
								last = nm
						"stepsequences":
							if nm == "sequence":
								var steps: Array = []
								for i in 16:
									steps.append(float(a.get("s%d" % i, "0")))
								seq["%s/%s" % [a.get("scene", "0"), a.get("i", "0")]] = {steps = steps,
									loop_start = int(a.get("loop_start", "0")), loop_end = int(a.get("loop_end", "15")),
									trigmask = int(a.get("trigmask", "0"))}
						"msegs":
							if nm == "mseg":
								last = "%s/%s" % [a.get("scene", "0"), a.get("i", "0")]
								msegs[last] = {edit = int(a.get("editMode", "0")), loop = int(a.get("loopMode", "1")), segs = []}
							elif nm == "segment" and msegs.has(last):
								msegs[last].segs.append([float(a.get("duration", "0")), float(a.get("v0", "0")), float(a.get("nv1", "0"))])
						"customcontroller":
							if nm == "entry":
								macros.append({v = float(a.get("v", "0")), bipolar = int(a.get("bipolar", "0"))})
				elif t == XMLParser.NODE_ELEMENT_END:
					if xp.get_node_name() == section:
						section = ""
	if not have_xml:
		var src: Dictionary = content.get("params", {})
		for k: String in src:
			if src[k] is float or src[k] is int:
				p[k] = {v = float(src[k]), a = {}, m = []}
		for r: Variant in content.get("mods", []):
			if r is Dictionary and p.has(String(r.get("dest", ""))):
				p[r.dest].m.append({source = int(r.get("source", 0)), depth = float(r.get("depth", 0.0)),
					muted = int(r.get("muted", 0)), index = int(r.get("source_index", 0)), scene = int(r.get("source_scene", 0))})
		for m: Variant in content.get("macros", []):
			if m is Dictionary:
				macros.append({v = float(m.get("v", 0.0)), bipolar = int(m.get("bipolar", 0))})
	var out := {p = p, seq = seq, msegs = msegs, macros = macros, xml = have_xml}
	content._parsed = out
	return out


static func _v(P: Dictionary, name: String, d := 0.0) -> float:
	return float(P.p[name].v) if P.p.has(name) else d


static func _i(P: Dictionary, name: String, d := 0) -> int:
	return roundi(float(P.p[name].v)) if P.p.has(name) else d


static func _attr(P: Dictionary, name: String, key: String) -> String:
	return String(P.p[name].a.get(key, "")) if P.p.has(name) else ""


static func _fx(P: Dictionary, pre: String, i: int, d := 0.0) -> float:
	return _v(P, pre + str(i), d)


static func _e(E: Dictionary, name: String, d := 0.0) -> float:
	return float(E.get(name, d))


static func _on(P: Dictionary, name: String, key: String) -> bool:
	return _attr(P, name, key) == "1"


## The routings onto a parameter (unmuted).
static func _mods(P: Dictionary, name: String) -> Array:
	var out: Array = []
	if P.p.has(name):
		for r: Dictionary in P.p[name].m:
			if int(r.muted) == 0 and absf(float(r.depth)) > 0.0:
				out.append(r)
	return out


## The wavetables in the patch chunk: {scene * 3 + osc: {n_samples, n_tables, data (float32 array)}}.
static func wavetables(content: Dictionary) -> Dictionary:
	if content.has("_wt"):
		return content._wt
	var out := {}
	var b64 := String(content.get("chunk_b64", ""))
	if not b64.is_empty():
		var raw := Marshalls.base64_to_raw(b64)
		if raw.size() > 32 and raw.slice(0, 4).get_string_from_ascii() == "sub3":
			var pos := 32 + raw.decode_u32(4)
			for k in 6:
				var sz := raw.decode_u32(8 + 4 * k)
				if sz == 0:
					continue
				# The header's tag is zeroed in patch chunks ("vawt" in .wt files).
				if pos + 12 <= raw.size():
					var ns := raw.decode_u32(pos + 4)
					var nt := raw.decode_u16(pos + 8)
					var fl := raw.decode_u16(pos + 10)
					var data := PackedFloat32Array()
					var d0 := pos + 12
					if fl & 4:
						var sc := 1.0 / (32768.0 if fl & 8 else 16384.0)
						data.resize(ns * nt)
						for i in ns * nt:
							if d0 + 2 * i + 2 <= raw.size():
								data[i] = raw.decode_s16(d0 + 2 * i) * sc
					elif d0 + 4 * ns * nt <= raw.size():
						data = raw.slice(d0, d0 + 4 * ns * nt).to_float32_array()
					if ns > 0 and nt > 0 and data.size() == ns * nt:
						out[k] = {n_samples = ns, n_tables = nt, data = data, sample = (fl & 1) != 0}
				pos += sz
	content._wt = out
	return out


## A Surge wavetable as a GAK table spec: up to WT_FRAMES frames picked evenly, each halved (pairs
## averaged) down to WT_SAMPLES samples.
## With `only` >= 0, that frame alone. The result's "peak" is the frames' largest sample.
static func _wt_spec(wt: Dictionary, only := -1) -> Dictionary:
	var ns: int = wt.n_samples
	var nt: int = wt.n_tables
	var data: PackedFloat32Array = wt.data
	var m := mini(nt, WT_FRAMES) if only < 0 else 1
	var frames: Array = []
	var peak := 0.0
	for k in m:
		var j := 0 if m == 1 else roundi(float(k) * (nt - 1) / (m - 1))
		if only >= 0:
			j = clampi(only, 0, nt - 1)
		var s := data.slice(j * ns, (j + 1) * ns)
		while s.size() > WT_SAMPLES and s.size() % 2 == 0:
			var h := PackedFloat32Array()
			h.resize(s.size() / 2)
			for i in h.size():
				h[i] = 0.5 * (s[2 * i] + s[2 * i + 1])
			s = h
		var arr: Array = []
		for x in s:
			arr.append(snappedf(x, 0.00001))
			peak = maxf(peak, absf(x))
		frames.append({samples = arr})
	return {frames = frames, normalize = false, peak = peak}


## Whether a destination (scene prefix stripped; globals as "g:name") gets matrix rows.
static func _dynamic_dest(P: Dictionary, s: String, short: String) -> bool:
	if short in ["pitch", "filter1_cutoff", "filter2_cutoff", "filter1_resonance", "filter2_resonance",
			"filter1_envmod", "filter2_envmod", "filter1_keytrack", "filter2_keytrack", "volume", "vca_level", "pan",
			"fm_depth", "g:volume"]:
		return true
	if RegEx.create_from_string("^(level_(o[123]|noise|ring12|ring23)|osc[123]_pitch|lfo\\d+_rate)$").search(short):
		return true
	var m := RegEx.create_from_string("^osc([123])_param(\\d)$").search(short)
	if m:
		var typ := _i(P, s + "osc%s_type" % m.get_string(1))
		var pn := m.get_string(2).to_int()
		return (typ == 0 and pn in [0, 1, 3, 4]) or ((typ == 2 or typ == 7) and pn == 0)
	return false


## The FM index for Surge's FM depth (linear) d: kind 0 phase modulation (sine-like carriers,
## radians), 1 the legacy sine's linear FM (Hz), 2 classic and wavetable carriers (semitones).
static func _fm_index(kind: int, d: float) -> float:
	match kind:
		1:
			return FM_LEGACY_HZ * d
		2:
			return FM_CLASSIC_ST * d
	return FM_SINE * d * d * d


# --- sine shapes -----------------------------------------------------------------------

## The sine oscillator's shape mode m at phase x (SineOscillator valueFromSinAndCosForMode).
static func sine_mode(m: int, x: float) -> float:
	var s := sin(TAU * x)
	var c := cos(TAU * x)
	var sw := 1.0 if s >= 0.0 else -1.0
	var s2 := 2.0 * s * c
	var c2 := 1.0 - 2.0 * s * s
	var q := 1
	if s <= 0.0:
		q = 3 if c <= 0.0 else 4
	elif c <= 0.0:
		q = 2
	match m:
		0:
			return s
		1:
			return sw + (-1.0 if s * c >= 0.0 else 1.0) * c
		2:
			return s if s >= 0.0 else 0.0
		3:
			if s < 0.0:
				return 0.0
			return 1.0 + c * (1.0 if c <= 0.0 else -1.0)
		4:
			return s2 if s >= 0.0 else 0.0
		5:
			if s < 0.0:
				return 0.0
			return (1.0 if s2 >= 0.0 else -1.0) + (-1.0 if s2 * c2 >= 0.0 else 1.0) * c2
		6:
			return absf(s2) if s >= 0.0 else 0.0
		7:
			return absf(sine_mode(5, x))
		8:
			return 2.0 * (s if s >= 0.0 else 0.0) - 1.0
		9:
			return s if s * c <= 0.0 else 0.0
		10:
			return s if s * c >= 0.0 else 0.0
		11:
			return 2.0 * sine_mode(3, x) - 1.0
		12:
			return s2 * (1.0 if c >= 0.0 else -1.0)
		13:
			return (s2 * (-1.0 if s <= 0.0 else 1.0)) if s2 >= 0.0 else 0.0
		14:
			return absf(c2) if s >= 0.0 else 0.0
		15:
			if c < 0.0:
				return 0.0
			return 1.0 - s if s >= 0.0 else -1.0 - s
		16:
			if c < 0.0:
				return 0.0
			return 1.0 - s if s >= 0.0 else c - 1.0
		17:
			return sw - s
		18:
			return c if c <= 0.0 else sw * s2
		19:
			if s < 0.0:
				return s
			return s2 if c >= 0.0 else -2.0 * s2 * c2
		20:
			return s if s * c >= 0.0 else sw
		21:
			return sw if s * c >= 0.0 else s
		22:
			return s if c >= 0.0 else 0.0
		23:
			return s if c <= 0.0 else 0.0
		24:
			return 1.0 - s if s >= 0.0 else s
		25:
			return s2 / q if s >= 0.0 else 0.0
		26:
			return 0.0 if s <= 0.0 and c <= 0.0 else s
		27:
			return s2 / q
	return s


# --- small helpers ---------------------------------------------------------------------

static func _db(x: float) -> float:
	return 20.0 * log(maxf(absf(x), 1e-9)) / LN10


static func _lin(db: float) -> float:
	return pow(10.0, db / 20.0)


## Surge's amplitude parameters: x^3 (amp_to_linear).
static func _cube(x: float) -> float:
	x = maxf(x, 0.0)
	return x * x * x


static func _interp(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
	var n := xs.size()
	return ys[n - 1] + (ys[n - 1] - ys[n - 2]) / (xs[n - 1] - xs[n - 2]) * (x - xs[n - 1])


## The inverse of a rising table.
static func _inv(xs: Array, ys: Array, y: float) -> float:
	return _interp(ys, xs, y)


static func _hz(semis: float) -> float:
	return 440.0 * pow(2.0, semis / 12.0)


## Which scene plays the reference notes: [scene index, caveat or ""].
static func scene_of(P: Dictionary) -> Array:
	var mode := _i(P, "scenemode")
	var active := _i(P, "scene_active")
	var muted_a := _on(P, "a_volume", "deactivated")
	var muted_b := _on(P, "b_volume", "deactivated")
	match mode:
		1:
			var split := _i(P, "splitkey", 60)
			var below := 0
			for n in [36, 48, 60, 72, 84]:
				if n < split:
					below += 1
			return [0 if below >= 3 else 1, "key split: scene %s only (Surge plays the other above or below key %d)" % ["A" if below >= 3 else "B", split]]
		2:
			if muted_a and not muted_b:
				if _audio_in(P, "b_") and _scene_sounds(P, "a_"):
					return [0, "scene B processes muted scene A through its audio input: scene A converted"]
				return [1, ""]
			if not muted_b and _scene_sounds(P, "b_"):
				return [0, "dual scenes: scene B not converted"]
			return [0, ""]
		3:
			return [0, ""]
	return [active, ""]


## Whether a scene has an audible audio input oscillator.
static func _audio_in(P: Dictionary, s: String) -> bool:
	for o in 3:
		if _i(P, s + "osc%d_type" % (o + 1)) == 4 and _i(P, s + "mute_o%d" % (o + 1)) == 0 and _v(P, s + "level_o%d" % (o + 1)) > 0.0:
			return true
	return false


## Whether a scene has an audible source at all.
static func _scene_sounds(P: Dictionary, s: String) -> bool:
	var solo := false
	for k in ["o1", "o2", "o3", "ring12", "ring23", "noise"]:
		solo = solo or _i(P, s + "solo_" + k) != 0
	for k in ["o1", "o2", "o3", "ring12", "ring23", "noise"]:
		if solo and _i(P, s + "solo_" + k) == 0:
			continue
		if _i(P, s + "mute_" + k) == 0 and (_v(P, s + "level_" + k) > 0.0 or not _mods(P, s + "level_" + k).is_empty()):
			if k.begins_with("o") and _i(P, s + "osc%s_type" % k.substr(1)) == 4:
				continue
			return true
	return false


# --- envelopes -------------------------------------------------------------------------

## Surge's ADSR (prefix "a_env1_") as a GAK stages envelope.
static func adsr(P: Dictionary, pre: String) -> Dictionary:
	var a := _v(P, pre + "attack", -8.0)
	var d := _v(P, pre + "decay", -2.0)
	var s := clampf(_v(P, pre + "sustain", 1.0), 0.0, 1.0)
	var r := _v(P, pre + "release", -5.0)
	var stages: Array = []
	if _i(P, pre + "mode") == 1:
		# Analog: a capacitor charging toward 1.5 V until it passes 1, then discharging toward S^2,
		# then toward 0; per block (32 samples) by 2^(2 - log2(sr / 32) - x): a time constant of
		# 2^x / 4 seconds.
		var ta := 0.25 * pow(2.0, a)
		var att := 0.0 if a <= -7.99 else ta * log(3.0)
		stages.append({time_s = att, level = 1.0, curve = "power", amount = -log(3.0)})
		var s2 := s * s
		if s2 < 0.999:
			stages.append({time_s = EXP_TC * 0.25 * pow(2.0, d), level = s2, curve = "power", amount = -EXP_TC})
		var sus := stages.size() - 1
		stages.append({time_s = EXP_TC * 0.25 * pow(2.0, r), level = 0.0, curve = "power", amount = -EXP_TC})
		return {stages = stages, sustain = sus}
	# Digital: each stage a phase running 0..1 in 2^x seconds (envelope_rate_linear).
	var ash := _i(P, pre + "attack_shape", 1)
	var dsh := _i(P, pre + "decay_shape", 1)
	var rsh := _i(P, pre + "release_shape", 2)
	if a <= -7.99:
		stages.append({time_s = 0.0, level = 1.0})
	else:
		var ta := pow(2.0, a)
		var n := 1 if ash == 1 else 4
		for k in n:
			var x := float(k + 1) / n
			var y := x if ash == 1 else (sqrt(x) if ash == 0 else x * x)
			stages.append({time_s = ta / n, level = y})
	# Decay: the phase moves toward S in the domain of y^(1/n) (n = 1, 2, 3 for shapes 0, 1, 2):
	# (1 - t / T)^n from 1, stopped at S.
	var nd := clampi(dsh + 1, 1, 3)
	if s < 0.999:
		var td := pow(2.0, d)
		var k1 := 1.0 - pow(s, 1.0 / nd)
		var m := 1 if nd == 1 else 6
		for k in m:
			var u := float(k + 1) / m
			stages.append({time_s = td * k1 / m, level = pow(1.0 - u * k1, nd)})
	var sus := stages.size() - 1
	# Release: the level at key-off times phase^n, phase falling 1 -> 0 in 2^r seconds.
	var nr := clampi(rsh + 1, 1, 4)
	var rel := {time_s = pow(2.0, r), level = 0.0}
	if nr > 1:
		rel.curve = "power"
		rel.amount = REL_AMOUNT[nr - 1]
	stages.append(rel)
	return {stages = stages, sustain = sus}


## An LFO's own envelope (delay, attack, hold, decay, sustain, release; all linear) as a GAK
## stages envelope, or {} when it stays at 1 through a note.
static func lfo_env(P: Dictionary, pre: String, force := false) -> Dictionary:
	var dl := _v(P, pre + "delay", -8.0)
	var dl_off := _on(P, pre + "delay", "deactivated") or dl <= -7.99
	var a := _v(P, pre + "attack", -8.0)
	var h := _v(P, pre + "hold", -8.0)
	var d := _v(P, pre + "decay", 0.0)
	var s := clampf(_v(P, pre + "sustain", 1.0), 0.0, 1.0)
	var r := _v(P, pre + "release", 5.0)
	var trivial := dl_off and a <= -7.99 and h <= -7.99 and s >= 0.999
	if trivial and r >= 3.0 and not force:
		return {}
	var stages: Array = []
	stages.append({time_s = 0.0 if a <= -7.99 else pow(2.0, a), level = 1.0})
	var env := {stages = stages, start = 0.0}
	if not dl_off:
		env.delay_s = pow(2.0, dl)
	if h > -7.99:
		env.hold_s = pow(2.0, h)
	stages.append({time_s = pow(2.0, d), level = s})
	env.sustain = stages.size() - 1
	stages.append({time_s = pow(2.0, r), level = 0.0})
	return env


# --- LFO waveforms ---------------------------------------------------------------------

## Surge's bend1 (the default deform) on x.
static func _bend1(x: float, df: float) -> float:
	var a := 0.5 * clampf(df, -3.0, 3.0)
	x = x - a * x * x + a
	x = x - a * x * x + a
	return x


static func _bend2(x: float, df: float) -> float:
	return x + 4.5 * df * sin(x * TAU) / TAU


## LFO shape s (0 sine, 1 triangle, 2 square, 3 ramp) at phase x, with deform df and its type.
## Measured (an LFO on pitch): the sine and triangle start at 0 rising, the ramp at 1 falling, the
## square high for its first half.
static func lfo_wave(s: int, x: float, df: float, dtype: int) -> float:
	if s == 1:
		x += 0.25
	x -= floorf(x)
	var y := 0.0
	match s:
		0:
			y = sin(TAU * x)
		1:
			y = -1.0 + 4.0 * (1.0 - x if x > 0.5 else x)
		2:
			return -1.0 if x > 0.5 + 0.5 * df else 1.0
		3:
			y = 1.0 - 2.0 * x
	if absf(df) < 1e-6:
		return y
	match dtype:
		1:
			var v := _bend2(y, df)
			if df < -1.0 / 4.5:
				v /= 1.0 - (df + 1.0 / 4.5) / 1.6
			return v
		2:
			return (_bend2(y + 0.25, df) - 0.25 - df / TAU) / (1.0 + 0.5 * absf(df)) - 0.06 * df
	return _bend1(y, df)


# --- filters ---------------------------------------------------------------------------

## Surge filter unit (type, subtype, cutoff in semitones from A4, resonance) as a GAK filter:
## {f (dict), gain_db, comb (dict, or empty), note (caveat or "")}.
static func filter_of(t: int, st: int, cut: float, reso: float) -> Dictionary:
	var hz := clampf(_hz(cut), 10.0, 22000.0)
	var r := clampf(reso, 0.0, 1.0)
	var out := {f = {}, gain_db = 0.0, comb = {}, note = ""}
	var svf := func(kind: String, tab: Array, slope: float) -> void:
		var fc := _interp(RES_X, tab[0], r)
		var q := pow(10.0, fc / (20.0 if slope == 12.0 else 40.0))
		out.f = {type = kind, cutoff_hz = minf(hz, SVF_MAX_HZ), q = clampf(q, 0.1, 40.0)}
		if slope == 24.0:
			out.f.slope_db = 24.0
		out.gain_db = _interp(RES_X, tab[1], r)
	var ladder := func(tab: Array, poles: float, hz_k: float) -> void:
		var fc := _interp(RES_X, tab[0], r)
		var gr := clampf(_inv(G_LADDER_R, G_LADDER_FC, fc), 0.0, 1.2)
		out.f = {type = "ladder", cutoff_hz = clampf(hz * hz_k, 10.0, 20000.0), resonance = gr}
		if poles < 4.0:
			out.f.poles = poles
		out.gain_db = _interp(RES_X, tab[1], r) - _interp(G_LADDER_R, G_LADDER_LO, gr)
	var kind := ""
	match t:
		1, 4, 6, 7, 24, 23, 16, 17, 18, 19, 28, 29, 30, 31:
			# 12 dB state-variable families (and the warp filters, approximated by them).
			if t in [1, 16, 28]:
				kind = "lowpass"
			elif t in [4, 17, 29]:
				kind = "highpass"
			elif t in [6, 19, 31, 23]:
				kind = "bandpass"
			else:
				kind = "notch"
			var tab: Array = F_SVF12
			var slope := 12.0
			if t == 23 or t == 24:
				tab = F_SVF24
				slope = 24.0
			if t <= 7 or t == 23 or t == 24:
				if st == 1 or st == 3:
					tab = F_DRV12 if slope == 12.0 else F_DRV24
				elif st == 2:
					tab = F_CLN12 if slope == 12.0 else F_CLN24
			else:
				out.note = "filter %s as a plain state-variable filter" % FILTER_NAMES[t]
			svf.call(kind, tab, slope)
		2, 5:
			var tab: Array = F_SVF24
			if st == 1 or st == 3:
				tab = F_DRV24
			elif st == 2:
				tab = F_CLN24
			svf.call("lowpass" if t == 2 else "highpass", tab, 24.0)
		3:
			ladder.call(F_LADDER, float(clampi(st, 0, 3) + 1), 1.0)
		10:
			ladder.call(F_VINTAGE if st < 2 else F_HUOV, 4.0, 1.0)
		12:
			# OB-Xd 4-pole: its subtypes are the slopes (6 .. 24 dB).
			ladder.call(F_OBXD24, float(clampi(st, 0, 3) + 1), 1.0)
		11, 20, 21, 22:
			svf.call({11: "lowpass", 20: "highpass", 21: "notch", 22: "bandpass"}[t], F_OBXD12, 12.0)
		13, 14:
			svf.call("lowpass" if t == 13 else "highpass", F_K35, 12.0)
			if st > 0:
				out.note = "K35 saturation not converted"
		15:
			ladder.call(F_DIODE, float(clampi(st, 0, 3) + 1), DIODE_HZ)
			out.note = "diode ladder as GAK's ladder"
		8, 25:
			# Comb: a delay of one period of the cutoff, fed back by the resonance.
			out.comb = {hz = hz, feedback = clampf((r if t == 8 else -r) * 0.95, -0.99, 0.99), wet = st}
		33:
			ladder.call(F_LADDER, 4.0, 1.0)
			out.note = "tri-pole as a ladder"
		_:
			out.note = "filter %s not converted" % FILTER_NAMES[clampi(t, 0, FILTER_NAMES.size() - 1)]
	return out


# --- conversion ------------------------------------------------------------------------

## A Surge XT patch (the prep tool's content.surge, with patch_xml) as a patch.
static func convert(content: Dictionary) -> AKPatch:
	return _convert(content, [])


static func _convert(content: Dictionary, notes: Array) -> AKPatch:
	var P := parse(content)
	var sc: Array = scene_of(P)
	var sn: int = sc[0]
	if String(sc[1]) != "":
		notes.append(sc[1])
	var s := "a_" if sn == 0 else "b_"
	var out := AKPatch.new()
	var mods: Array[Dictionary] = []
	var gain_db := BASE_DB + CAL_DB

	# --- sources: Surge's modulation sources as GAK matrix sources ------------------------
	var lfo_slots: Array = []      # GAK LFO dicts, lfo1.. in order
	var env_slots: Array = []      # GAK envelope dicts for env3..env8
	var lfo_map := {}              # Surge LFO index -> {src, via, k, offset} or {static}
	var macros: Array = P.macros
	var gak_macros := [0.0, 0.0, 0.0, 0.0]
	var shift := 12.0 * _i(P, s + "octave") + _v(P, s + "pitch") * (12.0 if _on(P, s + "pitch", "extend_range") else 1.0)
	var root := float(_i(P, s + "ktrkroot", 60))

	var E0 := {}    # static values from the routings of non-LFO sources (filled below)
	var add_env := func(env: Dictionary) -> String:
		if env_slots.size() >= 6:
			return ""
		env_slots.append(env)
		return "env%d" % (env_slots.size() + 2)
	var add_lfo := func(l: Dictionary) -> String:
		if lfo_slots.size() >= 8:
			return ""
		lfo_slots.append(l)
		return "lfo%d" % lfo_slots.size()

	# One Surge LFO (0..5 voice, 6..11 scene) as a source descriptor.
	var lfo_src := func(k: int, index: int) -> Dictionary:
		var key := "%d/%d" % [k, index]
		if lfo_map.has(key):
			return lfo_map[key]
		var pre := s + "lfo%d_" % k
		var shape := _i(P, pre + "shape")
		var mag := clampf(_e(E0, pre + "magnitude", _v(P, pre + "magnitude", 1.0)), -3.0, 3.0)
		if _on(P, pre + "magnitude", "extend_range"):
			mag = 2.0 * mag - 1.0
		var uni := _i(P, pre + "unipolar") != 0
		var rate := pow(2.0, _e(E0, pre + "rate", _v(P, pre + "rate")))
		var frozen := _on(P, pre + "rate", "deactivated")
		var trig := _i(P, pre + "trigmode", 1)
		var ph0 := _e(E0, pre + "phase", _v(P, pre + "phase"))
		if trig == 0 and not frozen:
			ph0 += PREROLL_S * rate
		elif trig == 2:
			notes.append("lfo%d random phase taken as its phase" % (k + 1))
		var df := _e(E0, pre + "deform", _v(P, pre + "deform"))
		var dtype := int(_attr(P, pre + "deform", "deform_type").to_int())
		var d := {src = "", via = "", k = 1.0, offset = 0.0}
		var envd := lfo_env(P, pre)
		if index == 2 or shape == 6:
			# The envelope itself (an envelope-type LFO, or another LFO's envelope output).
			var e2 := lfo_env(P, pre, true)
			var en: String = add_env.call(e2)
			if en == "":
				d.offset = 0.0
				notes.append("too many envelopes: lfo%d's dropped" % (k + 1))
			else:
				d.src = en
				d.k = mag if index != 2 else 1.0
			lfo_map[key] = d
			return d
		if shape == 9:
			notes.append("lfo%d formula not converted" % (k + 1))
			lfo_map[key] = d
			return d
		var l := {free = false}
		var pts: Array = []
		var n := 128
		match shape:
			0, 1, 2, 3:
				var sh: int = [0, 1, 2, 3][shape]
				for i in n:
					var y := lfo_wave(sh, ph0 + float(i) / n, df, dtype)
					pts.append(0.5 + 0.5 * y if uni else y)
				if frozen:
					d.offset = float(pts[0]) * mag
					lfo_map[key] = d
					return d
				l.shape = "custom"
				l.interp = "step" if shape == 2 else "linear"
				l.points = pts
				l.rate_hz = rate
			4, 5:
				l.shape = "smooth" if shape == 4 else "random"
				l.rate_hz = rate
				if uni:
					d.offset = 0.5 * mag
					d.k = 0.5
				notes.append("lfo%d %s: random, not repeatable" % [k + 1, "noise" if shape == 4 else "S&H"])
			8:
				# MSEG: its segments as straight lines (curve types not followed); in envelope mode the
				# phase runs over the whole length (at least 1; once, when one-shot), in LFO mode one cycle
				# is the whole drawing.
				var ms: Dictionary = P.msegs.get("%d/%d" % [sn, k], {})
				var segs: Array = ms.get("segs", [])
				var total := 0.0
				for sg: Array in segs:
					total += maxf(float(sg[0]), 0.0)
				if segs.is_empty() or total <= 0.0:
					notes.append("lfo%d MSEG without segments" % (k + 1))
					lfo_map[key] = d
					return d
				var env_mode := int(ms.get("edit", 0)) == 0
				var span := maxf(total, 1.0) if env_mode else total
				var nn := 128
				for i in nn:
					var tt := span * float(i) / (nn - 1 if env_mode and int(ms.get("loop", 1)) == 1 else nn)
					var acc := 0.0
					var y := float(segs[segs.size() - 1][2])
					for sg: Array in segs:
						var du := maxf(float(sg[0]), 0.0)
						if tt <= acc + du and du > 0.0:
							y = lerpf(float(sg[1]), float(sg[2]), (tt - acc) / du)
							break
						acc += du
					pts.append(0.5 + 0.5 * y if uni else y)
				l.shape = "custom"
				l.interp = "linear"
				l.points = pts
				l.rate_hz = rate / span if env_mode else rate
				if env_mode and int(ms.get("loop", 1)) == 1:
					l.once = true
				notes.append("lfo%d MSEG curves as straight segments" % (k + 1))
			7:
				var sq: Dictionary = P.seq.get("%d/%d" % [sn, k], {})
				var steps: Array = sq.get("steps", [0.0])
				var a0 := clampi(int(sq.get("loop_start", 0)), 0, 15)
				var a1 := clampi(int(sq.get("loop_end", 15)), a0, 15)
				for i in range(a0, a1 + 1):
					var y := float(steps[i])
					pts.append(maxf(y, 0.0) if uni else y)
				if pts.size() < 2:
					pts.append(pts[0] if pts.size() > 0 else 0.0)
				l.shape = "custom"
				l.interp = "step"
				l.points = pts
				l.rate_hz = rate / float(a1 - a0 + 1)
				if int(sq.get("trigmask", 0)) != 0:
					notes.append("step sequencer envelope retriggers not converted")
				if frozen:
					d.offset = float(pts[0]) * mag
					lfo_map[key] = d
					return d
			_:
				lfo_map[key] = d
				return d
		if _on(P, pre + "rate", "temposync"):
			l.rate_sync = 2.0 / maxf(float(l.rate_hz), 1e-4)
			l.erase("rate_hz")
		var ln: String = add_lfo.call(l)
		if ln == "":
			notes.append("too many LFOs: lfo%d dropped" % (k + 1))
			lfo_map[key] = d
			return d
		d.src = ln
		d.k *= mag
		d.lfo = k
		d.mag = mag
		if index == 1:
			d.k = 1.0
		elif absf(mag) < 1e-6 and not _mods(P, pre + "magnitude").is_empty():
			# Magnitude 0, raised by its routings: rows at magnitude 1, turned into rows via those
			# routings' sources below.
			d.k = 1.0
			d.mag0 = true
		if not envd.is_empty() and index == 0:
			var en: String = add_env.call(envd)
			if en != "":
				d.via = en
		lfo_map[key] = d
		return d

	# A routing's source as {src, via, k, offset}: the row is amount k x src (x via), and offset
	# its constant part (added to the parameter).
	var source := func(r: Dictionary) -> Dictionary:
		var id: int = r.source
		var d := {src = "", via = "", k = 1.0, offset = 0.0}
		match id:
			1:
				d.src = "velocity"
			2:
				d.src = "key"
				d.offset = (60.0 + shift - root) / 12.0
			3, 4:
				d.src = "aftertouch"
			5:
				d.src = "bend"
			6:
				d.src = "mod_wheel"
			7, 8, 9, 10, 11, 12, 13, 14:
				var mi := id - 7
				var m: Dictionary = macros[mi] if mi < macros.size() else {v = 0.0, bipolar = 0}
				var v := float(m.v)
				if int(m.bipolar) == 0 and mi < 4:
					d.src = "macro%d" % (mi + 1)
					d.value = v
					gak_macros[mi] = v
				else:
					d.offset = 2.0 * v - 1.0 if int(m.bipolar) != 0 else v
			15:
				d.src = "env1"
			16:
				d.src = "env2"
			17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28:
				return lfo_src.call(id - 17, int(r.index))
			31:
				d.src = "random"
			32:
				d.src = "random"
				d.k = 0.5
				d.offset = 0.5
			_:
				pass
		return d

	# Static values: each parameter plus the constant parts of its routings (first without the
	# LFOs, which read these).
	for name: String in P.p:
		if not (name.begins_with(s) or not (name.begins_with("a_") or name.begins_with("b_"))):
			continue
		var v0 := float(P.p[name].v)
		var sup0 := _dynamic_dest(P, s, name.substr(2) if name.begins_with(s) else "g:" + name)
		for r: Dictionary in _mods(P, name):
			if int(r.source) >= 17 and int(r.source) <= 28:
				continue
			var d0: Dictionary = source.call(r)
			v0 += float(r.depth) * float(d0.offset)
			if not sup0 and d0.has("value"):
				v0 += float(r.depth) * float(d0.value)
			elif not sup0 and String(d0.src) == "velocity":
				v0 += float(r.depth) * VEL_REF
		E0[name] = v0
	var E := {}
	var dyn := {}    # name -> [[source dict, depth], ...]
	for name: String in P.p:
		if not (name.begins_with(s) or not (name.begins_with("a_") or name.begins_with("b_"))):
			continue
		var v := float(P.p[name].v)
		var sup := _dynamic_dest(P, s, name.substr(2) if name.begins_with(s) else "g:" + name)
		for r: Dictionary in _mods(P, name):
			var d: Dictionary = source.call(r)
			v += float(r.depth) * float(d.offset)
			if d.has("value") and not sup:
				# A macro onto a destination without matrix rows: its value, folded in.
				v += float(r.depth) * float(d.value)
				continue
			if String(d.src) == "velocity" and not sup:
				# Velocity there: taken at the references' velocity.
				v += float(r.depth) * VEL_REF
				notes.append("velocity to %s taken at velocity 100" % (name.substr(2) if name.begins_with(s) else name))
				continue
			if d.src != "":
				if not dyn.has(name):
					dyn[name] = []
				dyn[name].append([d, float(r.depth)])
		E[name] = v

	# --- oscillators ----------------------------------------------------------------------
	var solo := false
	for k in ["o1", "o2", "o3", "ring12", "ring23", "noise"]:
		solo = solo or _i(P, s + "solo_" + k) != 0
	var plays := func(k: String) -> bool:
		if solo and _i(P, s + "solo_" + k) == 0:
			return false
		return _i(P, s + "mute_" + k) == 0
	var fm_mode := _i(P, s + "fm_switch")
	var fm_lin := _lin(_e(E, s + "fm_depth", -24.0))
	var is_mod := [false, fm_mode != 0, fm_mode >= 2]
	var ring12: bool = plays.call("ring12") and _e(E, s + "level_ring12") > 0.0
	var ring23: bool = plays.call("ring23") and _e(E, s + "level_ring23") > 0.0
	var oscs: Array[Dictionary] = []
	var parts := [[], [], []]      # per Surge osc: [[gak index (1-based), weight], ...]
	var pitched := [[], [], []]    # per Surge osc: gak indexes its pitch rows move
	var info := [{}, {}, {}]
	var wts := wavetables(content)
	var cfg := _i(P, s + "fb_config", 0)
	var parallel := cfg in [3, 4, 5, 6]
	var f1t := _i(P, s + "filter1_type")
	var f2t := _i(P, s + "filter2_type")
	var f1_on := f1t != 0 and not _on(P, s + "filter1_type", "deactivated")
	var f2_on := f2t != 0 and not _on(P, s + "filter2_type", "deactivated") and cfg != 2
	if f2t != 0 and cfg == 2:
		notes.append("serial 3: filter 2 sits in the feedback path only; not converted")
	var route_of := func(k: String) -> String:
		var rv := _i(P, s + "route_" + k, 1)
		if not parallel and rv == 1:
			rv = 0
		if rv == 2:
			return "2" if f2_on else "none"
		if rv == 0 and parallel:
			return "1" if f1_on else "none"
		return "both"
	for i in 3:
		var o := i + 1
		var pre := s + "osc%d_" % o
		var audible: bool = plays.call("o%d" % o) and (_e(E, s + "level_o%d" % o) > 0.0 or dyn.has(s + "level_o%d" % o))
		var needed: bool = audible or is_mod[i] or ((ring12 and i < 2) or (ring23 and i > 0))
		if not needed:
			continue
		var typ := _i(P, pre + "type")
		var semis := _e(E, pre + "pitch") * (12.0 if _on(P, pre + "pitch", "extend_range") else 1.0) + shift + 12.0 * _i(P, pre + "octave")
		var keytrack := _i(P, pre + "keytrack", 1) != 0
		var lvl := _cube(_e(E, s + "level_o%d" % o)) if audible else 0.0
		var base := {semitones = semis}
		if not keytrack:
			base = {fixed_hz = 261.6256 * pow(2.0, semis / 12.0)}
			notes.append("osc%d without key tracking: fixed at its middle-C pitch" % o)
		var route: String = route_of.call("o%d" % o)
		var voices := clampi(_i(P, pre + "param6", 1), 1, 16)
		var det := _e(E, pre + "param5") * (12.0 if _on(P, pre + "param5", "extend_range") else 1.0)
		var stack := {}
		var add := func(d: Dictionary, w: float) -> int:
			var od := base.duplicate()
			od.merge(d, true)
			od.level = lvl * w
			if route != "both":
				od.filter = route
			oscs.append(od)
			var idx := oscs.size()
			parts[i].append([idx, w])
			pitched[i].append(idx)
			return idx
		info[i] = {type = typ}
		match typ:
			0:
				# Classic: (1 - sub) ((1 + shape) saw + shape pulse(width 1)) + sub square(width 2) an
				# octave down: Surge's two impulse trains summed (saw(x) + shape saw(x - w), measured:
				# shape -1 is a pulse, +1 two saws half a cycle apart), as aligned GAK saw and pulse.
				var wf := clampf(_e(E, pre + "param0"), -1.0, 1.0)
				var w1 := clampf(_e(E, pre + "param1", 0.5), 0.0, 1.0)
				var w2 := clampf(_e(E, pre + "param2", 0.5), 0.0, 1.0)
				var sub := clampf(_e(E, pre + "param3"), 0.0, 1.0)
				var sync := _e(E, pre + "param4")
				if voices > 1:
					stack = {stack = voices, stack_cents = 100.0 * det}
				var master := 0
				var sync_d := {}
				if sync > 0.0 or dyn.has(pre + "param4"):
					oscs.append(base.duplicate().merged({shape = "saw", level = 0.0}, true))
					master = oscs.size()
					pitched[i].append(master)
					sync_d = {semitones = semis + maxf(sync, 0.0), sync_to = master}
					if not keytrack:
						sync_d = {fixed_hz = 261.6256 * pow(2.0, (semis + maxf(sync, 0.0)) / 12.0), sync_to = master}
				var saw_i: int = add.call({shape = "saw"}.merged(stack).merged(sync_d, true), (1.0 - sub) * (1.0 + wf))
				info[i].saw = saw_i
				if absf(wf) > 1e-4 or dyn.has(pre + "param0") or dyn.has(pre + "param1"):
					var pi_: int = add.call({shape = "pulse", width = clampf(w1, 0.01, 0.99), phase_with = saw_i}.merged(stack).merged(sync_d, true), (1.0 - sub) * wf)
					info[i].pulse = pi_
				if sub > 1e-4 or dyn.has(pre + "param3"):
					var sd := {shape = "pulse", width = clampf(w2, 0.01, 0.99), semitones = semis - 12.0}
					if not keytrack:
						sd = {shape = "pulse", width = clampf(w2, 0.01, 0.99), fixed_hz = 261.6256 * pow(2.0, (semis - 12.0) / 12.0)}
					info[i].sub = add.call(sd.merged(stack), sub)
				info[i].sub_w = sub
				info[i].wf = wf
			1:
				var mode := _i(P, pre + "param0")
				if voices > 1:
					stack = {stack = voices, stack_cents = 100.0 * det}
				var sd := {shape = "sine"}.merged(stack)
				var fb := _e(E, pre + "param1") * (4.0 if _on(P, pre + "param1", "extend_range") else 1.0)
				if fb > 0.0:
					sd.feedback = fb
				elif fb < 0.0:
					notes.append("osc%d negative sine feedback not converted" % o)
				if mode != 0 and mode <= 27:
					# The shape as a one-frame table (GAK scales it to a peak of 1; Surge's level is its peak).
					var smp: Array = []
					var pk := 0.0
					for k2 in 512:
						var y := sine_mode(mode, k2 / 512.0)
						smp.append(snappedf(y, 0.00001))
						pk = maxf(pk, absf(y))
					sd.shape = "table"
					sd.table = {frames = [{samples = smp}], normalize = false}
					if sd.has("feedback"):
						sd.erase("feedback")
						notes.append("osc%d sine feedback with a shape not converted" % o)
					add.call(sd, SINE_LEVEL * pk)
				else:
					add.call(sd, SINE_LEVEL)
			2, 7:
				if voices > 1:
					stack = {stack = voices, stack_cents = 100.0 * det}
				var wt: Dictionary = wts.get(sn * 3 + i, {})
				if wt.is_empty() or bool(wt.sample):
					notes.append("osc%d %s without a table: a saw" % [o, OSC_NAMES[typ]])
					add.call({shape = "saw"}.merged(stack), 1.0)
				else:
					# Morph: without extend (the default) Surge plays frame floor(morph n) alone, no
					# interpolation; extended, it interpolates across frames 0 .. n - 1.
					var pos := clampf(_e(E, pre + "param0"), 0.0, 1.0)
					var nt: int = wt.n_tables
					var spec := {}
					if _on(P, pre + "param0", "extend_range"):
						spec = _wt_spec(wt)
					elif dyn.has(pre + "param0"):
						spec = _wt_spec(wt)
						pos = float(clampi(int(pos * nt * 0.99999), 0, nt - 1)) / maxf(nt - 1, 1)
					else:
						spec = _wt_spec(wt, clampi(int(pos * nt * 0.99999), 0, nt - 1))
						pos = 0.0
					# GAK scales a table to a peak of 1: Surge's level is its own peak.
					var pk := float(spec.peak)
					spec.erase("peak")
					info[i].table = add.call({shape = "table", table = spec, position = pos}.merged(stack), WT_LEVEL * maxf(pk, 1e-3))
					if typ == 7:
						notes.append("osc%d window oscillator as its wavetable" % o)
					else:
						for k2 in [1, 2, 3, 4]:
							if absf(_e(E, pre + "param%d" % k2)) > 0.01:
								notes.append("osc%d wavetable skew, saturate and formant not converted" % o)
								break
			3:
				add.call({shape = "noise"}, SH_LEVEL)
				notes.append("osc%d S&H noise as white noise" % o)
			5, 6:
				# FM3 / FM2: a sine carrier phase-modulated by sines at its ratios.
				var car: int = add.call({shape = "sine"}, SINE_LEVEL)
				var fm_l: Array = []
				var mk := func(d: Dictionary) -> int:
					var od := base.duplicate()
					od.merge(d, true)
					od.level = 0.0
					oscs.append(od)
					pitched[i].append(oscs.size())
					return oscs.size()
				if typ == 6:
					for m in 2:
						var amt := _e(E, pre + "param%d" % (2 * m))
						var ratio := float(_i(P, pre + "param%d" % (2 * m + 1), 1))
						if amt > 0.0:
							fm_l.append({from = mk.call({shape = "sine", ratio = maxf(ratio, 0.01)}), index = FM2_K * amt * amt * amt})
					if absf(_e(E, pre + "param4")) > 0.01:
						notes.append("osc%d FM2 modulator offset not converted" % o)
					var fb := _e(E, pre + "param6") * (4.0 if _on(P, pre + "param6", "extend_range") else 1.0)
					if fb > 0.0:
						oscs[car - 1].feedback = fb
				else:
					for m in 2:
						var amt := _e(E, pre + "param%d" % (2 * m))
						var rv := _e(E, pre + "param%d" % (2 * m + 1), 1.0)
						if _on(P, pre + "param%d" % (2 * m + 1), "extend_range"):
							rv = (rv - 16.0) * 31.0 / 16.0 + 1.0 if rv > 16.0 else -((16.0 - rv) * 31.0 / 16.0 + 1.0)
						if rv < 0.0:
							rv = -1.0 / rv
						if amt > 0.0:
							var md := {shape = "sine", ratio = maxf(rv, 0.001)}
							if _on(P, pre + "param%d" % (2 * m + 1), "absolute"):
								md = {shape = "sine", fixed_hz = _hz(69.0 * ((_e(E, pre + "param%d" % (2 * m + 1)) - 16.0) / 16.0))}
							fm_l.append({from = mk.call(md), index = FM3_K * amt * amt * amt})
					var a3 := _e(E, pre + "param4")
					if a3 > 0.0:
						var od := {shape = "sine", fixed_hz = 261.6256 * pow(2.0, _e(E, pre + "param5") / 12.0), level = 0.0}
						oscs.append(od)
						fm_l.append({from = oscs.size(), index = FM3_K * a3 * a3 * a3})
					var fb := _e(E, pre + "param6") * (4.0 if _on(P, pre + "param6", "extend_range") else 1.0)
					if fb > 0.0:
						oscs[car - 1].feedback = fb
				if not fm_l.is_empty():
					oscs[car - 1].fm = fm_l
				info[i].car = car
			8:
				# Modern: saw, pulse and triangle mixed by bipolar levels.
				if voices > 1:
					stack = {stack = voices, stack_cents = 100.0 * det}
				var sm := _e(E, pre + "param0")
				var pm := _e(E, pre + "param1")
				var tm := _e(E, pre + "param2")
				var first := 0
				if absf(sm) > 1e-3:
					first = add.call({shape = "saw"}.merged(stack), sm)
				if absf(pm) > 1e-3:
					var d := {shape = "pulse", width = clampf(_e(E, pre + "param3", 0.5), 0.01, 0.99)}.merged(stack)
					if first > 0:
						d.phase_with = first
					add.call(d, pm)
				if absf(tm) > 1e-3:
					add.call({shape = "triangle"}.merged(stack), tm)
				if parts[i].is_empty():
					add.call({shape = "saw"}, 0.0)
				notes.append("osc%d modern oscillator approximated" % o)
			4:
				notes.append("osc%d audio input: silent" % o)
				add.call({shape = "sine"}, 0.0)
			_:
				if voices > 1 and typ == 11:
					stack = {stack = voices, stack_cents = 100.0 * det}
				add.call({shape = "saw" if typ != 10 else "sine"}.merged(stack), 1.0)
				notes.append("osc%d %s approximated as a %s" % [o, OSC_NAMES[clampi(typ, 0, 11)], "sine" if typ == 10 else "saw"])

	# FM routing: 2 > 1, 3 > 2 > 1, 2 and 3 > 1.
	var fm_rows: Array = []    # [carrier, kind, weight] for the FM depth's rows
	if fm_mode != 0:
		var pairs: Array = []
		match fm_mode:
			1:
				pairs = [[0, 1]]
			2:
				pairs = [[0, 1], [1, 2]]
			3:
				pairs = [[0, 1], [0, 2]]
		for pr: Array in pairs:
			var c: int = pr[0]
			var m: int = pr[1]
			if parts[c].is_empty() or parts[m].is_empty():
				continue
			var ctype := int(info[c].get("type", 0))
			var sine_like := ctype in [1, 5, 6]
			var legacy := ctype == 1 and _i(P, s + "osc%d_param2" % (c + 1), 1) == 0
			var fmk := 1 if legacy else (0 if sine_like else 2)
			for cp: Array in parts[c]:
				var od: Dictionary = oscs[cp[0] - 1]
				var lst: Array = od.get("fm", [])
				for mp: Array in parts[m]:
					# What Surge's carrier hears is the modulator's own signal, at Surge's internal scale:
					# half of GAK's per unit (a classic saw is 0.5, the sine 1), times the part's share.
					var w := float(mp[1])
					if absf(w) < 1e-6:
						w = 1.0
					w *= OSC_SCALE
					var idx := _fm_index(fmk, fm_lin) * w
					# The first modulator as fm_from, so the matrix's oscN.fm moves it (the FM depth's rows).
					if not od.has("fm_from"):
						od.fm_from = mp[0]
						od.fm_index = idx
						fm_rows.append([cp[0], fmk, w])
					else:
						lst.append({from = mp[0], index = idx})
				if not lst.is_empty():
					od.fm = lst
				if legacy:
					od.fm_mode = "linear"
				elif not sine_like:
					od.fm_mode = "pitch"
			if not sine_like:
				notes.append("FM into a %s oscillator: linear FM as exponential" % OSC_NAMES[ctype])

	# Ring modulation: a copy of the first oscillator's main part ringed by the second's.
	var ring_add := func(a: int, b: int, k: String) -> void:
		if parts[a].is_empty() or parts[b].is_empty():
			return
		var od: Dictionary = (oscs[parts[a][0][0] - 1] as Dictionary).duplicate(true)
		# Surge multiplies the two raw signals (at its internal scale, OSC_SCALE of GAK's per unit).
		var fa := absf(float(parts[a][0][1]))
		var fb := absf(float(parts[b][0][1]))
		od.level = _cube(_e(E, s + "level_" + k)) * OSC_SCALE * (fa if fa > 0.05 else 1.0) * (fb if fb > 0.05 else 1.0)
		od.ring_from = parts[b][0][0]
		od.erase("fm")
		od.erase("phase_with")
		var rt: String = route_of.call(k)
		od.erase("filter")
		if rt != "both":
			od.filter = rt
		oscs.append(od)
		info.append({ring = k})
		if parts[a].size() > 1 or parts[b].size() > 1:
			notes.append("ring modulation of composite oscillators: their main parts only")
		if _attr(P, s + "level_" + k, "deform_type") not in ["", "0"]:
			notes.append("ring modulation mode not converted")
	var ring_idx := {}
	if ring12:
		ring_add.call(0, 1, "ring12")
		ring_idx["ring12"] = oscs.size()
	if ring23:
		ring_add.call(1, 2, "ring23")
		ring_idx["ring23"] = oscs.size()
	# The oscillators that play only to modulate: level 0.
	for i in 3:
		var o := i + 1
		var audible: bool = plays.call("o%d" % o) and (_e(E, s + "level_o%d" % o) > 0.0 or dyn.has(s + "level_o%d" % o))
		if not audible:
			for pp: Array in parts[i]:
				oscs[pp[0] - 1].level = 0.0
	# Noise.
	var noise_idx := 0
	if plays.call("noise") and (_e(E, s + "level_noise") > 0.0 or dyn.has(s + "level_noise")):
		var col := _e(E, s + "noisecol")
		var nd := {shape = "noise", level = _cube(_e(E, s + "level_noise")) * NOISE_LEVEL}
		if col < -0.66:
			nd.color = "red"
		elif col < -0.2:
			nd.color = "pink"
		if col > 0.2:
			notes.append("blue noise as white")
		var rt: String = route_of.call("noise")
		if rt != "both":
			nd.filter = rt
		oscs.append(nd)
		noise_idx = oscs.size()
	if oscs.is_empty():
		oscs.append({shape = "sine", level = 0.0})
	var ws_on := _i(P, s + "ws_type") != 0 and not _on(P, s + "ws_type", "deactivated")
	if not ws_on:
		gain_db += _e(E, s + "level_pfg")

	# --- filter block ---------------------------------------------------------------------
	var c1 := _e(E, s + "filter1_cutoff")
	var c2 := _e(E, s + "filter2_cutoff")
	var kt1 := _e(E, s + "filter1_keytrack")
	var kt2 := _e(E, s + "filter2_keytrack")
	var em1 := _e(E, s + "filter1_envmod")
	var em2 := _e(E, s + "filter2_envmod")
	var off2 := _i(P, s + "f2_cf_is_offset") != 0
	var r1 := _e(E, s + "filter1_resonance")
	var r2 := r1 if _i(P, s + "f2_link_resonance") != 0 else _e(E, s + "filter2_resonance")
	# Cutoffs at middle C: key tracking about the scene's root, with the scene's transpose.
	var cut1 := c1 + kt1 * (60.0 + shift - root)
	var cut2 := c2 + kt2 * (60.0 + shift - root)
	if off2:
		cut2 += cut1
	var ff1 := filter_of(f1t, _i(P, s + "filter1_subtype"), cut1, r1) if f1_on else {f = {}, gain_db = 0.0, comb = {}, note = ""}
	var ff2 := filter_of(f2t, _i(P, s + "filter2_subtype"), cut2, r2) if f2_on else {f = {}, gain_db = 0.0, comb = {}, note = ""}
	for ff: Dictionary in [ff1, ff2]:
		if String(ff.note) != "":
			notes.append(ff.note)
	var comb := {}
	for k in 2:
		var ff: Dictionary = [ff1, ff2][k]
		if not (ff.comb as Dictionary).is_empty():
			var kt := kt1 if k == 0 else kt2
			var hz := float(ff.comb.hz)
			comb = {semitones = 12.0 * log(hz / 261.6256) / LN2, feedback = ff.comb.feedback}
			if absf(kt - 1.0) > 0.05:
				notes.append("comb filter without full key tracking: tuned at middle C")
			if k == 1:
				notes.append("comb filter 2 moved before filter 1")
	var swapped := false
	var fa: Dictionary = ff1.f
	var fb2: Dictionary = ff2.f
	if fa.is_empty() and not fb2.is_empty() and not parallel:
		# Filter 2 alone in series: GAK's filter 1 takes it (the routes stay).
		fa = fb2
		fb2 = {}
		ff1 = ff2
		ff2 = {f = {}, gain_db = 0.0, comb = {}, note = ""}
		for od: Dictionary in oscs:
			if od.get("filter", "") == "2":
				od.erase("filter")
		kt1 = kt2
		em1 = em2
		f1_on = true
		f2_on = false
		off2 = false
		swapped = true
	var have1 := not fa.is_empty()
	var have2 := not fb2.is_empty()
	out.filter = fa if have1 else {type = "off"}
	if have2:
		out.filter2 = fb2
		out.filter_routing = "parallel" if parallel else "series"
	else:
		for od: Dictionary in oscs:
			if od.get("filter", "") == "2":
				od.filter = "none"
			elif od.get("filter", "") in ["1", "both"]:
				od.erase("filter")
	if not comb.is_empty():
		out.comb = comb
	# Character: warm filters the classic-family oscillators (GAK's pre-filter takes every filtered
	# oscillator, so with a wavetable or FM oscillator audible as well it filters those too).
	var charv := _i(P, "character", 1)
	if charv != 1:
		var fam := 0
		var other := 0
		for i in 3:
			var typ := int(info[i].get("type", -1))
			if typ < 0 or parts[i].is_empty() or float(oscs[parts[i][0][0] - 1].get("level", 0.0)) == 0.0:
				continue
			if typ in [0, 1, 8, 9, 10, 11]:
				fam += 1
			else:
				other += 1
		if charv == 0 and fam > 0:
			out.pre_filter = {lowpass_hz = WARM_HZ}
			if other > 0:
				notes.append("warm character also on the wavetable and FM oscillators")
		elif charv == 2 and fam > 0:
			notes.append("bright character not converted")
	# The filters' passband levels: filter 1's on the whole (it carries most patches), filter 2's
	# in series.
	gain_db += float(ff1.gain_db)
	if have2 and not parallel:
		gain_db += float(ff2.gain_db)
	elif have2:
		gain_db += 0.5 * float(ff2.gain_db) - 0.5 * float(ff1.gain_db)
	if parallel:
		# Dual, stereo and ring sum the two filters at half level each (balance 0).
		gain_db += -6.0206
	if cfg == 6:
		notes.append("ring filter configuration as parallel filters")
	if cfg == 5:
		notes.append("stereo filter configuration summed")
	# Filter balance: in parallel each filter's share (0.5 -+ 0.5 b, against 0.5 at 0); in series,
	# above 0, filter 1's output crossfaded with its input (1 - b, b). Both exact as copies of the
	# oscillators on the other path, starting at the same phases.
	var bal := _e(E, s + "f_balance")
	if absf(bal) > 0.01:
		var n0 := oscs.size()
		var through1 := func(od: Dictionary) -> bool:
			return String(od.get("filter", "both")) in ["1", "both"]
		var cnt := 0
		for od: Dictionary in oscs:
			if float(od.get("level", 0.0)) != 0.0 and bool(through1.call(od)):
				cnt += 1
		if n0 + cnt > 16:
			notes.append("filter balance not converted: too many oscillators")
		elif parallel and have2:
			for j in n0:
				var od: Dictionary = oscs[j]
				if float(od.get("level", 0.0)) == 0.0:
					continue
				var f := String(od.get("filter", "both"))
				if f == "1":
					od.level = float(od.level) * (1.0 - bal)
				elif f == "2":
					od.level = float(od.level) * (1.0 + bal)
				elif f == "both":
					var cp := od.duplicate(true)
					cp.filter = "2"
					cp.level = float(od.level) * (1.0 + bal)
					if not cp.has("phase_with") and not cp.has("phase"):
						cp.phase_with = j + 1
					od.filter = "1"
					od.level = float(od.level) * (1.0 - bal)
					oscs.append(cp)
		elif not parallel and bal > 0.0 and have1:
			for j in n0:
				var od: Dictionary = oscs[j]
				if float(od.get("level", 0.0)) == 0.0 or not bool(through1.call(od)):
					continue
				var cp := od.duplicate(true)
				cp.filter = "2" if have2 else "none"
				cp.level = float(od.level) * bal
				if not cp.has("phase_with") and not cp.has("phase"):
					cp.phase_with = j + 1
				od.level = float(od.level) * (1.0 - bal)
				oscs.append(cp)
		elif not parallel and bal < 0.0 and have2:
			notes.append("filter balance toward filter 2's input not converted")
	var fbk := _e(E, s + "feedback")
	if cfg in [1, 2, 3, 4, 5, 6, 7] and absf(fbk) > 0.01:
		notes.append("filter block feedback not converted")
	if have1 or have2:
		if absf(kt1) > 1e-4 and have1:
			mods.append({source = "key", dest = "cutoff", amount = kt1})
		if have2 and (absf(kt2) > 1e-4 or (off2 and absf(kt1) > 1e-4)):
			mods.append({source = "key", dest = "cutoff2", amount = kt2 + (kt1 if off2 else 0.0)})
		if absf(em1) > 1e-4 and have1:
			mods.append({source = "env2", dest = "cutoff", amount = em1 / 12.0})
		if have2 and (absf(em2) > 1e-4 or (off2 and absf(em1) > 1e-4)):
			mods.append({source = "env2", dest = "cutoff2", amount = (em2 + (em1 if off2 else 0.0)) / 12.0})
	# The waveshaper: its soft and hard types as the filter's saturation (Surge's signal at GAK's
	# scale; a drive of 0 dB is a gain of 1).
	var ws := _i(P, s + "ws_type")
	if ws != 0 and not _on(P, s + "ws_type", "deactivated"):
		var drive := _e(E, s + "ws_drive") * (2.0 if _on(P, s + "ws_drive", "extend_range") else 1.0)
		var tgt: Dictionary = out.filter
		if not have1:
			out.filter = {type = "off"}
			tgt = out.filter
		tgt.sat_gain_db = drive + _e(E, s + "level_pfg")
		tgt.sat_ceiling = WS_HARD_CEIL if ws == 2 else WS_CEIL
		if ws not in [1, 2]:
			notes.append("waveshaper type %d as a soft clipper" % ws)
		if have2 and parallel and cfg == 3:
			notes.append("dual 1 waveshaper after the sum: on filter 1 only")

	# --- envelopes ------------------------------------------------------------------------
	out.amp_env = adsr(P, s + "env1_")
	out.env2 = adsr(P, s + "env2_")

	# --- levels, velocity, pan ------------------------------------------------------------
	gain_db += _db(_cube(_e(E, s + "volume", 0.890899)))
	gain_db += _e(E, "volume")
	gain_db += _e(E, s + "vca_level")
	var vs := -_e(E, s + "vca_velsense")
	out.velocity_sens = 0.0
	out.velocity_curve = 1.0
	if vs > 0.01:
		# Surge's level falls vs dB at velocity 0, linear in dB (vs (1 - v)); GAK's is
		# 1 - sens (1 - v^curve): matched at the reference velocity, by the curve with full
		# sensitivity (v^c), or by the sensitivity with a straight curve when vs is small.
		var drop := vs * (1.0 - VEL_REF)
		var c := drop / -_db(VEL_REF)
		if c >= 0.25:
			out.velocity_sens = 1.0
			out.velocity_curve = minf(c, 4.0)
			gain_db += -drop - _db(pow(VEL_REF, out.velocity_curve))
		else:
			out.velocity_sens = (1.0 - _lin(-drop)) / (1.0 - VEL_REF)
	out.pan = clampf(_e(E, s + "pan"), -1.0, 1.0)

	# --- modulation rows ------------------------------------------------------------------
	var row := func(d: Dictionary, dest: String, amount: float) -> void:
		if absf(amount) < 1e-6 or String(d.src) == "":
			return
		var rw := {source = d.src, dest = dest, amount = amount * float(d.k)}
		if String(d.via) != "":
			rw.via = d.via
		mods.append(rw)
	var unsupported := {}
	for name: String in dyn:
		var lst: Array = dyn[name]
		var short := name.substr(2) if name.begins_with(s) else "g:" + name
		for pair: Array in lst:
			var d: Dictionary = pair[0]
			var dep: float = pair[1]
			var bip: bool = String(d.src).begins_with("lfo") or String(d.src) in ["random", "bend"]
			var lvl_row := func(x: float) -> float:
				if bip:
					return 0.5 * (_cube(x + dep) - _cube(x - dep))
				return _cube(x + dep) - _cube(x)
			var m := RegEx.create_from_string("^osc([123])_(pitch|param(\\d))$").search(short)
			if m:
				var i := m.get_string(1).to_int() - 1
				if parts[i].is_empty():
					continue
				var typ := int(info[i].get("type", -1))
				if m.get_string(2) == "pitch":
					var k := 12.0 if _on(P, name, "extend_range") else 1.0
					for gi: int in pitched[i]:
						row.call(d, "osc%d.pitch" % gi, dep * k)
					continue
				var pn := m.get_string(3).to_int()
				var L := _cube(_e(E, s + "level_o%d" % (i + 1)))
				if typ == 0 and pn == 0:
					var sub := float(info[i].get("sub_w", 0.0))
					row.call(d, "osc%d.level" % info[i].saw, dep * L * (1.0 - sub))
					if info[i].has("pulse"):
						row.call(d, "osc%d.level" % info[i].pulse, dep * L * (1.0 - sub))
					continue
				if typ == 0 and pn == 1 and info[i].has("pulse"):
					row.call(d, "osc%d.width" % info[i].pulse, dep)
					continue
				if typ == 0 and pn == 3 and info[i].has("sub"):
					row.call(d, "osc%d.level" % info[i].sub, dep * L)
					continue
				if typ == 0 and pn == 4:
					for pp: Array in parts[i]:
						if oscs[pp[0] - 1].has("sync_to"):
							row.call(d, "osc%d.pitch" % pp[0], dep)
					continue
				if (typ == 2 or typ == 7) and pn == 0 and info[i].has("table"):
					row.call(d, "osc%d.position" % info[i].table, dep)
					continue
				unsupported["osc%d %s param %d" % [i + 1, OSC_NAMES[clampi(typ, 0, 11)], pn + 1]] = true
				continue
			m = RegEx.create_from_string("^level_(o[123]|noise|ring12|ring23)$").search(short)
			if m:
				var k := m.get_string(1)
				var x := _e(E, name)
				if k.begins_with("o"):
					var i := k.substr(1).to_int() - 1
					for pp: Array in parts[i]:
						row.call(d, "osc%d.level" % pp[0], float(lvl_row.call(x)) * float(pp[1]) * (1.0 if not (k == "noise") else NOISE_LEVEL))
				elif k == "noise" and noise_idx > 0:
					row.call(d, "osc%d.level" % noise_idx, float(lvl_row.call(x)) * NOISE_LEVEL)
				elif ring_idx.has(k):
					row.call(d, "osc%d.level" % ring_idx[k], float(lvl_row.call(x)))
				continue
			match short:
				"pitch":
					row.call(d, "pitch", dep * (12.0 if _on(P, name, "extend_range") else 1.0))
				"filter1_cutoff":
					if have1 and not swapped:
						row.call(d, "cutoff", dep / 12.0)
					if (have2 and off2) or (swapped and _i(P, s + "f2_cf_is_offset") != 0):
						row.call(d, "cutoff2" if have2 else "cutoff", dep / 12.0)
					if not comb.is_empty() and f1t in [8, 25]:
						row.call(d, "comb.pitch", dep)
				"filter2_cutoff":
					if have2:
						row.call(d, "cutoff2", dep / 12.0)
					elif swapped:
						row.call(d, "cutoff", dep / 12.0)
				"filter1_resonance", "filter2_resonance":
					var fn := 1 if short == "filter1_resonance" else 2
					var tgt := ""
					if swapped:
						tgt = "q" if fn == 2 else ""
					elif fn == 1 and have1:
						tgt = "q"
					elif fn == 2 and have2:
						tgt = "q2"
					if tgt != "":
						var r0 := r1 if fn == 1 else r2
						var t0 := f1t if fn == 1 else f2t
						var st0 := _i(P, s + "filter%d_subtype" % fn)
						var cc := cut1 if fn == 1 else cut2
						var lo := filter_of(t0, st0, cc, r0 - (absf(dep) if bip else 0.0))
						var hi := filter_of(t0, st0, cc, r0 + absf(dep))
						var qv := func(f: Dictionary) -> float:
							return maxf(float(f.f.get("q", f.f.get("resonance", 0.0))), 0.02)
						var oc := log(float(qv.call(hi)) / float(qv.call(lo))) / LN2 * (0.5 if bip else 1.0)
						row.call(d, tgt, oc * signf(dep))
				"filter1_envmod":
					if have1 and not swapped:
						var rw := {source = "env2", dest = "cutoff", amount = dep / 12.0 * float(d.k), via = d.src}
						mods.append(rw)
				"filter2_envmod":
					if have2 or swapped:
						mods.append({source = "env2", dest = "cutoff2" if have2 else "cutoff", amount = dep / 12.0 * float(d.k), via = d.src})
				"filter1_keytrack":
					# Key tracking times the source: about Surge's root with the scene's transpose (a row
					# via the key, plus the source alone for the constant part).
					if have1 and not swapped:
						mods.append({source = "key", dest = "cutoff", amount = dep * float(d.k), via = d.src})
						row.call(d, "cutoff", dep * (60.0 + shift - root) / 12.0)
				"filter2_keytrack":
					if have2 or swapped:
						mods.append({source = "key", dest = "cutoff2" if have2 else "cutoff", amount = dep * float(d.k), via = d.src})
						row.call(d, "cutoff2" if have2 else "cutoff", dep * (60.0 + shift - root) / 12.0)
				"volume":
					var x := _e(E, name, 0.890899)
					var base := _cube(x)
					if base > 1e-6:
						var hi := _cube(x + dep)
						var lo := _cube(x - dep) if bip else base
						row.call(d, "amp", ((hi - lo) * (0.5 if bip else 1.0)) / base)
				"g:volume":
					row.call(d, "amp", _lin(dep) - 1.0)
				"fm_depth":
					var x := _e(E, name)
					for fr: Array in fm_rows:
						var hi := _fm_index(fr[1], _lin(x + dep))
						var lo := _fm_index(fr[1], _lin(x - dep)) if bip else _fm_index(fr[1], _lin(x))
						row.call(d, "osc%d.fm" % fr[0], (hi - lo) * (0.5 if bip else 1.0) * float(fr[2]))
				"vca_level":
					row.call(d, "amp", _lin(dep) - 1.0)
				"pan":
					row.call(d, "pan", dep)
				_:
					var lm := RegEx.create_from_string("^lfo(\\d+)_rate$").search(short)
					if lm:
						var key := "%d/0" % lm.get_string(1).to_int()
						if lfo_map.has(key) and String(lfo_map[key].src).begins_with("lfo"):
							row.call(d, String(lfo_map[key].src) + ".rate", dep)
						continue
					if not name.begins_with(s):
						if name.begins_with("fx"):
							unsupported["effect parameters"] = true
						continue
					unsupported[short] = true
	# LFO magnitudes moved by routings: each row from that LFO also via the routing's source,
	# scaled by depth / magnitude (or, at magnitude 0, only those).
	var mag_rows: Array[Dictionary] = []
	var drop_rows := {}
	for key: String in lfo_map:
		var ld: Dictionary = lfo_map[key]
		if not ld.has("lfo") or not key.ends_with("/0"):
			continue
		var mname := s + "lfo%d_magnitude" % int(ld.lfo)
		if not dyn.has(mname):
			continue
		unsupported.erase("lfo%d_magnitude" % int(ld.lfo))
		for ri in mods.size():
			var rw: Dictionary = mods[ri]
			if String(rw.source) != String(ld.src) or rw.has("via"):
				continue
			var unit := float(rw.amount) / (1.0 if ld.has("mag0") else float(ld.mag))
			for pair: Array in dyn[mname]:
				var sd: Dictionary = pair[0]
				if String(sd.src) == "" or String(sd.via) != "":
					continue
				mag_rows.append({source = rw.source, via = sd.src, dest = rw.dest, amount = unit * float(pair[1]) * float(sd.k)})
			if ld.has("mag0"):
				drop_rows[ri] = true
	if not drop_rows.is_empty():
		var kept: Array[Dictionary] = []
		for ri in mods.size():
			if not drop_rows.has(ri):
				kept.append(mods[ri])
		mods = kept
	mods.append_array(mag_rows)
	for k: String in unsupported:
		notes.append("modulation of %s not converted" % k)
	if mods.size() > 32:
		notes.append("more than 32 matrix rows: the rest dropped")
		mods.resize(32)

	# --- LFO and envelope slots -----------------------------------------------------------
	if lfo_slots.size() > 0:
		out.lfo1 = lfo_slots[0]
	if lfo_slots.size() > 1:
		out.lfo2 = lfo_slots[1]
	if lfo_slots.size() > 2:
		var extra: Array[Dictionary] = []
		for l: Dictionary in lfo_slots.slice(2):
			extra.append(l)
		out.lfos = extra
	if env_slots.size() > 0:
		out.env3 = env_slots[0]
	if env_slots.size() > 1:
		var extra: Array[Dictionary] = []
		for e: Dictionary in env_slots.slice(1):
			extra.append(e)
		out.envelopes = extra
	out.mods = mods
	out.macros = gak_macros
	out.oscillators = oscs

	# --- playing --------------------------------------------------------------------------
	var pm := _i(P, s + "polymode")
	out.mode = "poly" if pm == 0 or pm == 5 else ("legato" if pm == 2 or pm == 4 else "mono")
	out.polyphony = clampi(_i(P, "polylimit", 16), 1, 32)
	var porta := _v(P, s + "portamento", -8.0)
	out.glide_s = 0.0 if porta <= -7.99 else clampf(pow(2.0, porta) / 3.0, 0.0, 2.0)
	out.bend_range = float(_i(P, s + "pbrange_up", 2))
	if _on(P, s + "pbrange_up", "extend_range"):
		out.bend_range = 0.01 * out.bend_range
	out.tempo_bpm = 120.0
	out.unison = 1
	out.nyquist_clamp = true
	out.sinc_blep = true
	if _e(E, s + "drift") > 0.01:
		notes.append("oscillator drift not converted")

	# --- effects --------------------------------------------------------------------------
	var fx: Array[Dictionary] = []
	var lc := _v(P, s + "lowcut", -72.0)
	if not _on(P, s + "lowcut", "deactivated"):
		var slope := int(_attr(P, s + "lowcut", "deform_type").to_int())
		# Also at its lowest (-72, 6.9 Hz): it takes the DC of pulses out, as in Surge.
		fx.append({type = "filter", mode = "highpass", cutoff_hz = maxf(_hz(lc), 5.0), q = 0.4, slope_db = 12.0 if slope == 0 else 24.0})
		if slope > 1:
			notes.append("low cut steeper than 24 dB")
	var bypass := _i(P, "fx_bypass")
	var disabled := _i(P, "fx_disable")
	if bypass != 3:
		var chain: Array = []
		for k: int in FX_A:
			chain.append([k, 1.0])
		if bypass == 0:
			for j in 4:
				var k: int = FX_SEND[j]
				var lvl := _cube(_v(P, s + "send_fx_%d" % (j + 1))) * _cube(_v(P, "volume_FX%d" % (j + 1), 1.0))
				if lvl > 1e-4:
					chain.append([k, -lvl])
		if bypass != 2:
			for k: int in FX_GLOBAL:
				chain.append([k, 1.0])
		for c: Array in chain:
			var k: int = c[0]
			if disabled & (1 << k):
				continue
			var t := _i(P, "fx%d_type" % (k + 1))
			if t == 0:
				continue
			var e := _effect(P, k + 1, t, float(c[1]), notes)
			if not e.is_empty():
				gain_db += float(e.get("_gain_db", 0.0))
				e.erase("_gain_db")
				fx.append(e)
	out.effects = fx
	out.gain_db = gain_db
	out.resource_name = String(content.get("name", ""))
	return out


## Surge effect in slot n (1-based) of type t as a GAK effect; send < 0 marks a send effect at that
## (positive) level. A "_gain_db" key carries a level change for the dry signal.
static func _effect(P: Dictionary, n: int, t: int, send: float, notes: Array) -> Dictionary:
	var pre := "fx%d_p" % n
	var is_send := send < 0.0
	var wet_of := func(mix: float, wet_k: float) -> Array:
		# An insert's dry/wet crossfade (dry 1 - m, wet m) or a send (dry 1, wet at its level) as
		# GAK's added wet (at most 1) after a gain G on everything: G = dry, mix = wet / dry while
		# the wet is the smaller; beyond that mix 1 and G between the two (their geometric mean).
		var a := 1.0 if is_send else 1.0 - clampf(mix, 0.0, 1.0)
		var b := clampf(mix, 0.0, 1.0) * wet_k * (-send if is_send else 1.0)
		if b <= a:
			return [b / maxf(a, 1e-6), _db(a) if a < 1.0 else 0.0]
		return [1.0, _db(sqrt(maxf(a, 0.05) * b))]
	match t:
		1:
			var tl := pow(2.0, _fx(P, pre, 0, -2.0))
			var tr := tl if _on(P, pre + "1", "deactivated") else pow(2.0, _fx(P, pre, 1, -2.0))
			var fb := clampf(_cube(_fx(P, pre, 2, 0.5)), 0.0, 0.95)
			var w: Array = wet_of.call(_fx(P, pre, 10, 0.3), 1.0)
			var damp := 20000.0 if _on(P, pre + "5", "deactivated") else clampf(_hz(_fx(P, pre, 5, 60.0)), 200.0, 20000.0)
			var e := {type = "delay", time_ms = clampf(minf(tl, tr) * 1000.0, 1.0, 2000.0),
				spread_ms = clampf((tr - tl) * 1000.0, -100.0, 100.0), feedback = fb, damp_hz = damp, mix = w[0],
				mode = "cross" if _fx(P, pre, 3) > 0.5 else "stereo", _gain_db = w[1]}
			if maxf(tl, tr) > 2.0:
				notes.append("delay longer than GAK's 2 s")
			return e
		2, 11:
			# Reverb 1 and 2 as Freeverb, matched in decay time (GAK's RT60 = 0.098 / -log10(0.7 + 0.28 room)).
			var rt60 := pow(2.0, _fx(P, pre, 3 if t == 2 else 2, 1.0))
			var fbr := pow(10.0, -0.098 / maxf(rt60, 0.05))
			var mix := _fx(P, pre, 9 if t == 2 else 9, 0.5)
			var w: Array = wet_of.call(mix, sqrt(minf(1.0, rt60 / 0.6)) * (REV1_WET if t == 2 else 1.0))
			var damp := _fx(P, pre, 4 if t == 2 else 7, 0.2)
			var e := {type = "reverb", room = clampf((fbr - 0.7) / 0.28, 0.0, 1.0), damp = clampf(damp, 0.0, 1.0), width = 1.0,
				mix = w[0], _gain_db = w[1]}
			var pd := _fx(P, pre, 0, -8.0)
			if pd > -7.0:
				e.predelay_ms = clampf(pow(2.0, pd) * 1000.0, 0.0, 500.0)
			notes.append("reverb %d as GAK's Freeverb" % (1 if t == 2 else 2))
			return e
		9:
			var cm := clampf(_fx(P, pre, 6, 1.0), 0.0, 1.0)
			var w: Array = [cm / maxf(1.0 - cm, 1e-3) if not is_send else cm * -send]
			var tm := pow(2.0, _fx(P, pre, 0, -6.0)) * 1000.0
			var e := {type = "chorus", rate_hz = pow(2.0, _fx(P, pre, 1, -2.0)), depth_ms = clampf(tm * _fx(P, pre, 2, 0.3), 0.1, 20.0),
				delay_ms = clampf(tm, 1.0, 40.0), voices = 2, mix = clampf(float(w[0]) / (1.0 + float(w[0])), 0.0, 1.0),
				feedback = clampf(_fx(P, pre, 3), 0.0, 0.9), _gain_db = CHORUS_DB * 2.0 * minf(float(w[0]) / (1.0 + float(w[0])), 0.5)}
			notes.append("chorus approximated")
			return e
		12:
			var e := {type = "flanger", rate_hz = pow(2.0, _fx(P, pre, 2, -2.0)), depth_ms = 2.0 * _fx(P, pre, 3, 0.5), delay_ms = 1.0,
				feedback = clampf(_fx(P, pre, 7, 0.0), 0.0, 0.95), mix = clampf(absf(_fx(P, pre, 10, 0.8)) * 0.5, 0.0, 1.0)}
			if is_send:
				var b := -send * float(e.mix)
				e.mix = b / (1.0 + b)
				e._gain_db = _db(1.0 + b)
			notes.append("flanger approximated")
			return e
		3:
			var e := {type = "phaser", rate_hz = pow(2.0, _fx(P, pre, 3, -2.0)), stages = clampi(roundi(_fx(P, pre, 8, 4.0)), 1, 12),
				center_hz = 800.0 * pow(2.0, 2.0 * _fx(P, pre, 0)), depth = clampf(_fx(P, pre, 4, 0.5), 0.0, 1.0),
				feedback = clampf(_fx(P, pre, 1), -0.95, 0.95), mix = clampf(_fx(P, pre, 6, 0.5), 0.0, 1.0)}
			if is_send:
				var b := -send * float(e.mix)
				e.mix = b / (1.0 + b)
				e._gain_db = _db(1.0 + b)
			notes.append("phaser approximated")
			return e
		6:
			if is_send:
				notes.append("EQ as a send effect not converted")
				return {}
			# The parametric EQ's three bands as GAK's low shelf, peak and high shelf.
			var e := {type = "eq", low_db = 0.0 if _on(P, pre + "0", "deactivated") else _fx(P, pre, 0), low_hz = _hz(_fx(P, pre, 1, -2.5 * 12.0)),
				mid_db = 0.0 if _on(P, pre + "3", "deactivated") else _fx(P, pre, 3), mid_hz = _hz(_fx(P, pre, 4, 0.0)), mid_q = clampf(sqrt(pow(2.0, maxf(_fx(P, pre, 5, 1.0), 0.05))) / (pow(2.0, maxf(_fx(P, pre, 5, 1.0), 0.05)) - 1.0), 0.2, 10.0),
				high_db = 0.0 if _on(P, pre + "6", "deactivated") else _fx(P, pre, 6), high_hz = _hz(_fx(P, pre, 7, 3.0 * 12.0)), _gain_db = _fx(P, pre, 9)}
			if absf(float(e.low_db)) + absf(float(e.high_db)) > 0.5:
				notes.append("EQ bands 1 and 3 as shelves")
			return e
		5:
			# Drive (dB, x5 extended), the shaper, then the output gain; no dry. As a send: its wet at
			# the send level, crossfaded in (dropped when that wet stays 30 dB under the dry).
			var dr := _fx(P, pre, 4) * (5.0 if _on(P, pre + "4", "extend_range") else 1.0)
			var e := {type = "saturate", drive_db = clampf(dr, -24.0, 48.0), tone_hz = 18000.0, mix = 1.0,
				output_db = _fx(P, pre, 10)}
			if is_send:
				if -send * _lin(dr + _fx(P, pre, 10)) < 0.03:
					return {}
				e.mix = -send / (1.0 - send)
				e._gain_db = _db(1.0 - send)
			notes.append("distortion approximated")
			return e
	notes.append("effect %s not converted" % FX_NAMES[clampi(t, 0, FX_NAMES.size() - 1)])
	return {}


## What the conversion only approximates, for this patch.
static func caveats(content: Dictionary) -> Array:
	var notes: Array = []
	_convert(content, notes)
	var seen := {}
	var out: Array = []
	for n: Variant in notes:
		if not seen.has(n):
			seen[n] = true
			out.append(n)
	return out
