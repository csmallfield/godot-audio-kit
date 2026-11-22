# SPDX-License-Identifier: Apache-2.0
## TAL-NoiseMaker program -> AKPatch, by direct parameter conversion through the open port's
## formulas (DISTRHO-Ports tal-noisemaker), checked against TAL-NoiseMaker 5.0.6's own renders.
##
##   var Tal := preload("res://tools/patch_convert/tal.gd")
##   var patch: AKPatch = Tal.convert(sidecar.content.tal)
##   var notes: Array = Tal.caveats(sidecar.content.tal)
##
## The patch: osc1, osc2 and the sub (osc3, two octaves down, the sync master) with their
## waveforms, tunes, levels, pulse width, ring modulation (a copy of osc2 ringed by osc1) and FM
## (osc2's frequency moved by a sine at osc1's pitch: a phase-modulation index plus the carrier's
## shift); the filter (the ladder for TAL's 4-pole types, its pole mixes for HP, BP and notch, the
## state-variable filter for the SV types); the amp and filter envelopes and the free AD envelope
## as stages envelopes on TAL's own curves (the filter ones in octaves, as TAL adds them to the
## cutoff before squaring it); both LFOs, the drawn envelope as a custom LFO; the bitcrusher's
## level; the master high-pass, delay, chorus and reverb as effects.
extends RefCounted

const VERSION := 1
const LN2 := 0.6931471805599453
const LN10 := 2.302585092994046
## GAK's level against TAL's (dB), from the library's median level error.
const CAL_DB := 0.27
## TAL's ADSR level offset (its decay and release aim this far below 0), at 48 kHz.
const ENV_S := 0.0037
## TAL 5.0.6's attack runs this much slower at 48 kHz than the port's 44.1 kHz formula.
const ATTACK_SCALE := 1.045
## The cutoff's floor and ceiling in TAL's units before squaring.
const C_MIN := 0.021
const C_MAX := 1.0
## The velocity the references play at (100 / 127): velocity terms TAL multiplies into the
## filter envelope are taken at it.
const VEL_REF := 100.0 / 127.0
## TAL's noise against GAK's uniform noise (measured: 3.9 dB under a full-scale uniform noise).
const NOISE_LEVEL := 0.64
## A quiet noise that starts a self-oscillating ladder, as the noise in TAL's does.
const EXCITE := 0.001
## The frequency the delay's loop filters are matched at.
const DELAY_HZ := 500.0
## The drawn envelope's speed at 48 kHz against its nominal one.
const ED_SR_RATIO := 48000.0 / 44100.0

## Combo sizes (AudioUtils.h).
const N_FILTER := 12
const N_OSC1 := 3
const N_OSC2 := 5

## Defaults for missing attributes (TalCore.cpp).
const DEFAULTS := {volume = 0.5, filtertype = 0.0, cutoff = 1.0, resonance = 0.0, osc1volume = 0.8, osc2volume = 0.0,
	osc3volume = 0.8, osc1waveform = 0.0, osc2waveform = 0.0, oscsync = 0.0, oscmastertune = 0.5, osc1tune = 0.25,
	osc2tune = 0.5, osc1finetune = 0.5, osc2finetune = 0.5, keyfollow = 0.0, filtercontour = 0.5, filterattack = 0.0,
	filterdecay = 0.0, filtersustain = 1.0, filterrelease = 0.0, ampattack = 0.0, ampdecay = 0.0, ampsustain = 1.0,
	amprelease = 0.0, voices = 0.0, portamentomode = 0.0, portamento = 0.0, lfo1waveform = 0.0, lfo2waveform = 0.0,
	lfo1rate = 0.0, lfo2rate = 0.0, lfo1amount = 0.5, lfo2amount = 0.5, lfo1destination = 0.0, lfo2destination = 0.0,
	lfo1phase = 0.0, lfo2phase = 0.0, osc1pw = 0.5, osc2fm = 0.0, osc1phase = 0.5, osc2phase = 0.0, transpose = 0.5,
	freeadattack = 0.0, freeaddecay = 0.0, freeadamount = 0.0, freeaddestination = 0.0, lfo1sync = 0.0,
	lfo1keytrigger = 0.0, lfo2sync = 0.0, lfo2keytrigger = 0.0, velocityvolume = 0.0, velocitycontour = 0.0,
	velocitycutoff = 0.0, pitchwheelcutoff = 0.0, pitchwheelpitch = 0.0, highpass = 0.0, detune = 0.0,
	vintagenoise = 0.0, filterdrive = 0.0, ringmodulation = 0.0, chorus1enable = 0.0, chorus2enable = 0.0,
	reverbwet = 0.0, reverbdecay = 0.5, reverbpredelay = 0.0, reverbhighcut = 1.0, reverblowcut = 0.1,
	oscbitcrusher = 1.0, delaywet = 0.0, delaytime = 0.5, delaysync = 0.0, delayfactorl = 0.0, delayfactorr = 0.0,
	delayhighshelf = 0.0, delaylowshelf = 0.0, delayfeedback = 0.5, envelopeeditordest1 = 0.0,
	envelopeeditorspeed = 0.0, envelopeeditoramount = 0.0, envelopeoneshot = 0.0, envelopefixtempo = 0.0}
## TAL-NoiseMaker 5.0.6 reads these attributes by these names (case-sensitive; measured): a
## program saved with the open port's names (velocitycutoff, lfo1phase, lfo2phase,
## envelopeoneshot, delayfactorr), as the factory bank is, plays them at 0.
const NAMES_506 := {velocityfilter = "velocitycutoff", lfo1Phase = "lfo1phase", lfo2Phase = "lfo2phase",
	envelopeOneShot = "envelopeoneshot", delayfactorR = "delayfactorr"}
const RENAMED := ["velocitycutoff", "lfo1phase", "lfo2phase", "envelopeoneshot", "delayfactorr"]

## LFO sync: cycles per beat for int(v * 17 + 0.001) (AudioUtils.h): 1/16 .. 2/1, triplets, dotted.
const LFO_SYNC := [4.0, 2.0, 1.0, 0.5, 0.25, 0.125, 6.0, 3.0, 1.5, 0.75, 0.375, 0.1875,
	5.3333, 2.6667, 1.3333, 0.6667, 0.3333, 0.1667]
## Delay sync: seconds at 120 bpm for int(v * 17) (4 T / bpm, AudioUtils.h; 5.0.6 keeps the port's
## values, twice the note's length for straight notes: measured).
const DELAY_SYNC := [0.25, 0.5, 1.0, 2.0, 4.0, 4.0, 0.375, 0.75, 1.5, 3.0, 4.0, 4.0,
	0.16667, 0.33333, 0.66667, 1.33333, 2.66667, 4.0]

## Measured cutoff: TAL's frequency over 22050 c^2, by that frequency, for LP24 (and the others).
const CUT_HZ := [120.0, 338.0, 757.0, 1504.0, 2773.0, 4862.0, 8236.0, 13603.0, 22050.0]
const CUT_LP24 := [1.469, 1.406, 1.400, 1.390, 1.380, 1.356, 1.292, 1.20, 1.10]
const CUT_REST := [1.077, 1.007, 0.998, 0.993, 0.985, 0.960, 0.910, 0.80, 0.60]
## Measured resonance: GAK ladder resonance giving TAL's peak, by TAL's resonance.
const RES_X := [0.0, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 1.0]
const RES_LP24 := [0.0, 0.35, 0.555, 0.775, 0.88, 0.98, 1.05, 1.12]
const RES_LP12 := [0.0, 0.32, 0.53, 0.735, 0.835, 0.94, 1.0, 1.1]
## The SV types' q by resonance (TAL's damping is resonance^24: nothing below 0.6).
const SVQ_X := [0.0, 0.6, 0.65, 0.7, 0.8, 0.9, 1.0]
const SVQ := [0.5, 0.55, 1.0, 2.9, 5.0, 6.3, 7.0]


# --- helpers ---------------------------------------------------------------------------

## The program's attributes, lower-cased, aliases resolved, defaults filled and old versions
## brought up to 1.7 (TalCore.cpp's setStateInformation).
static func params(content: Dictionary) -> Dictionary:
	var src: Dictionary = content.get("params", content)
	# The attributes as the program holds them (names exactly as written), when it's there.
	var xml := String(content.get("program_xml", ""))
	if not xml.is_empty():
		var head := xml.get_slice("<splinePoints", 0)
		var re := RegEx.create_from_string(' ([A-Za-z0-9_]+)="([^"]*)"')
		var attrs := {}
		for m in re.search_all(head):
			if m.get_string(2).is_valid_float():
				attrs[m.get_string(1)] = m.get_string(2).to_float()
		if not attrs.is_empty():
			src = attrs
	var p := DEFAULTS.duplicate()
	for k: String in src:
		if not (src[k] is float or src[k] is int):
			continue
		if NAMES_506.has(k):
			p[NAMES_506[k]] = float(src[k])
		elif p.has(k) and not k in RENAMED:
			p[k] = float(src[k])
	var ver := float(String(content.get("xml_version", "1.7")))
	if ver < 1.1:
		var w1: float = p.osc1waveform
		p.osc1waveform = 0.0 if w1 < 0.5 - 0.001 else 0.5
		var w2: float = p.osc2waveform
		p.osc2waveform = 0.0 if w2 < 1.0 / 3.0 - 0.001 else (0.25 if w2 < 2.0 / 3.0 - 0.001 else 0.5)
	if ver < 1.6:
		for pair in [["voices", 6], ["portamentomode", 3], ["lfo1destination", 8], ["lfo2destination", 8],
				["freeaddestination", 6], ["filtertype", 10], ["osc1waveform", 3], ["osc2waveform", 5],
				["envelopeeditordest1", 8], ["envelopeeditorspeed", 6]]:
			var n: int = pair[1]
			var v: float = p[pair[0]]
			if v >= 1.0:
				p[pair[0]] = (v - 1.0) / (n - 1)
	if ver < 1.7:
		var idx := floori(float(p.filtertype) * 9.0 + 1.5)
		p.filtertype = (idx - 1) / 11.0
	return p


static func combo(v: float, n: int) -> int:
	return clampi(floori(v * (n - 1) + 1.5), 1, n)


static func log_vol(v: float, m := 1.0) -> float:
	return (pow(20.0, v * m) - 1.0) / 19.0


static func log_filt(v: float) -> float:
	return (pow(8.0, v) - 1.0) / 7.0


static func cen3(v: float) -> float:
	var x := 2.0 * (v - 0.5)
	return x * x * x


static func _db(x: float) -> float:
	return 20.0 * log(maxf(x, 1e-6)) / LN10


static func _interp(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[ys.size() - 1]


## A tune knob: trunc(48 v - 24) semitones (snapped where float32 storage sits on an edge).
static func tune_semis(v: float) -> float:
	var x := 48.0 * v - 24.0
	if absf(x - roundf(x)) < 1e-4:
		x = roundf(x)
	return float(int(x))


## The filter type 1..12.
static func ftype(p: Dictionary) -> int:
	return combo(p.filtertype, N_FILTER)


## TAL's cutoff in Hz for c (its units before squaring), by type.
static func cut_hz(t: int, c: float) -> float:
	# TAL squares the sum and clamps after: a negative sum opens the filter again (measured).
	c = clampf(absf(c), C_MIN, C_MAX)
	var f := 22050.0 * c * c
	var table: Array = CUT_LP24 if t == 1 or t == 11 else CUT_REST
	return f * _interp(CUT_HZ, table, f)


## Octaves between two cutoffs in TAL's units.
static func cut_oct(t: int, c: float, c0: float) -> float:
	return log(cut_hz(t, c) / cut_hz(t, c0)) / LN2


# --- envelopes -------------------------------------------------------------------------

## The attack: [seconds to full level, its curve's amount] (an exponential approach to 1.04 + A/2).
static func attack(a: float) -> Array:
	var srf := 0.004
	var k := (0.0003 * srf + srf * pow(1.0 - a * 0.5, 24.0) * 7.0) * srf * 200.0
	var tgt := 1.04 + 0.5 * a
	var b := log(tgt / (tgt - 1.0))
	var tau := 1.0 / (-log(1.0 - minf(k, 0.99)) * 44100.0)
	return [tau * b * ATTACK_SCALE, -b]


## Decay and release time constants (s).
static func decay_tau(d: float) -> float:
	var srf := 0.004
	var k := 0.0003 * srf + srf * pow(1.0 - d * 0.5, 23.0) * 7.0
	return 1.0 / (-log(1.0 - minf(k, 0.99)) * 44100.0)


static func release_tau(r: float) -> float:
	var srf := 0.004
	var k := (0.0003 * srf + srf * pow(1.0 - r * 0.5, 22.0) * 2.0) * 8.0
	return 1.0 / (-log(1.0 - minf(k, 0.99)) * 44100.0)


## TAL's ADSR as GAK stages, each of TAL's segments split in `subs` parts whose levels go through
## `f` (identity when null): [stages, index of the sustain stage]. Each part keeps TAL's
## exponential shape (a power curve), so with f null and one part the stages are exact.
static func adsr_stages(a: float, d: float, s: float, r: float, f: Callable, subs: int, instant_attack := false) -> Dictionary:
	var stages: Array = []
	var at: Array = attack(a)
	var a_t: float = 0.0 if instant_attack else at[0]
	_segment(stages, 0.0, 1.0, a_t, at[1], f, maxi(1, subs - 1) if subs > 1 else 1)
	var dl := 0.0
	var da := 0.0
	if s < 1.0:
		var dt := decay_tau(d)
		da = -log((1.0 + ENV_S) / (maxf(s, 0.0) + ENV_S))
		dl = -da * dt
	_segment(stages, 1.0, s, dl, da, f, subs)
	var sus := stages.size() - 1
	var rt := release_tau(r)
	# From full level: the curve is relative, so a release from any level keeps TAL's time constant.
	var ra := -log((1.0 + ENV_S) / ENV_S)
	_segment(stages, s, 0.0, -ra * rt, ra, f, subs)
	return {stages = stages, sustain = sus}


static func _segment(out: Array, y0: float, y1: float, time: float, amount: float, f: Callable, subs: int) -> void:
	for k in subs:
		var x1 := float(k + 1) / subs
		var prog := x1 if absf(amount) < 1e-6 else (exp(amount * x1) - 1.0) / (exp(amount) - 1.0)
		var y := y0 + (y1 - y0) * prog
		var lv := y if f.is_null() else float(f.call(y))
		var st := {time_s = time / subs, level = lv}
		var am := clampf(amount / subs, -40.0, 40.0)
		if absf(am) > 1e-4:
			st.curve = "power"
			st.amount = am
		out.append(st)


## Scales a stages list's levels by 1 / k.
static func _scale_levels(stages: Array, k: float) -> void:
	for st: Dictionary in stages:
		st.level = st.level / k


## TAL's ADSR level at tm seconds into a held note.
static func adsr_at(tm: float, a: float, d: float, s: float, instant: bool) -> float:
	var at: Array = attack(a)
	var ta: float = 0.0 if instant else at[0]
	var b: float = -at[1]
	if tm < ta:
		return (1.0 - exp(-b * tm / ta)) / (1.0 - exp(-b))
	if s >= 1.0:
		return 1.0
	return maxf((1.0 + ENV_S) * exp(-(tm - ta) / decay_tau(d)) - ENV_S, s)


## The filter envelope plus the free AD, through TAL's cutoff curve, as one stages envelope in
## octaves (normalized; {env, span}), sampled at times spaced geometrically.
static func _filter_sum_stages(p: Dictionary, t: int, c60: float, ccl: float, contour: float, fsus: float, ad: float) -> Dictionary:
	var fi := float(p.filterattack) == 0.0
	var ai := float(p.freeadattack) == 0.0
	var end_f: float = (0.0 if fi else float(attack(p.filterattack)[0])) + 6.0 * decay_tau(p.filterdecay)
	var end_a: float = (0.0 if ai else float(attack(p.freeadattack)[0])) + 6.0 * decay_tau(p.freeaddecay)
	var t_end := clampf(maxf(end_f, end_a), 0.01, 20.0)
	var n := 20
	var times: Array = [0.0]
	for i in n:
		times.append(0.001 * pow(t_end / 0.001, float(i) / (n - 1)))
	var lv: Array = []
	for tm: float in times:
		var c := c60 + contour * adsr_at(tm, p.filterattack, p.filterdecay, fsus, fi) + ad * adsr_at(tm, p.freeadattack, p.freeaddecay, 0.0, ai)
		lv.append(cut_oct(t, c, ccl))
	var rt := release_tau(p.filterrelease)
	var rel: Array = []
	var rtimes: Array = []
	for i in 8:
		var tm := 0.001 * pow(6.0 * rt / 0.001, float(i) / 7.0)
		rtimes.append(tm)
		var y := maxf((fsus + ENV_S) * exp(-tm / rt) - ENV_S, 0.0)
		rel.append(cut_oct(t, c60 + contour * y, ccl))
	var span := 0.0
	for y: float in lv + rel:
		span = maxf(span, absf(y))
	if span < 1e-3:
		return {}
	var stages: Array = []
	for i in range(1, times.size()):
		stages.append({time_s = times[i] - times[i - 1], level = lv[i] / span})
	var sus := stages.size() - 1
	var prev := 0.0
	for i in rel.size():
		stages.append({time_s = rtimes[i] - prev, level = rel[i] / span})
		prev = rtimes[i]
	stages.append({time_s = 0.0, level = 0.0})
	return {env = {stages = stages, sustain = sus, start = lv[0] / span}, span = span}


# --- the drawn envelope ----------------------------------------------------------------

## The drawn curve at x (0..1): Bezier y between the two points around it, t linear in x.
static func curve_at(pts: Array, x: float) -> float:
	if pts.size() < 2:
		return 0.5
	var i := 0
	while i + 2 < pts.size() and float(pts[i + 1].centerPointX) < x:
		i += 1
	var a: Dictionary = pts[i]
	var b: Dictionary = pts[i + 1]
	var x0 := float(a.centerPointX)
	var x1 := float(b.centerPointX)
	var t := 0.0 if x1 - x0 <= 1e-9 else clampf((x - x0) / (x1 - x0), 0.0, 1.0)
	var u := 1.0 - t
	var y := u * u * u * float(a.centerPointY) + 3.0 * u * u * t * float(a.get("controlPointRightY", a.centerPointY)) \
		+ 3.0 * u * t * t * float(b.get("controlPointLeftY", b.centerPointY)) + t * t * t * float(b.centerPointY)
	return clampf(y, 0.0, 1.0)


static func curve_points(content: Dictionary) -> Array:
	var pts: Array = []
	for pt: Variant in content.get("curve", []):
		if pt is Dictionary and pt.has("centerPointX"):
			pts.append(pt)
	if pts.size() < 2:
		pts = [{centerPointX = 0.0, centerPointY = 0.5}, {centerPointX = 1.0, centerPointY = 0.5}]
	pts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.centerPointX) < float(b.centerPointX))
	return pts


# --- LFOs ------------------------------------------------------------------------------

static func lfo_wave(p: Dictionary, k: int) -> int:
	return clampi(int(float(p["lfo%dwaveform" % k]) * 5.000001), 0, 5)


## Cycles per second.
static func lfo_rate(p: Dictionary, k: int) -> float:
	if float(p["lfo%dsync" % k]) > 0.0:
		return 2.0 * LFO_SYNC[clampi(int(float(p["lfo%drate" % k]) * 17.0 + 0.001), 0, 17)]
	return (exp(0.2 + float(p["lfo%drate" % k]) * 3.0 * log(20.0)) - 1.0) / 19.0 * 256.0 / 255.0


## Where the LFO starts, in cycles: its phase on key trigger; synced to the host otherwise
## (the references start each note 0.1 s into the song); else 0.
static func lfo_phase(p: Dictionary, k: int) -> float:
	var ph := 0.0
	if float(p["lfo%dkeytrigger" % k]) > 0.0:
		ph = float(p["lfo%dphase" % k])
	elif float(p["lfo%dsync" % k]) > 0.0:
		ph = float(p["lfo%dphase" % k]) + 0.1 * lfo_rate(p, k)
	return ph - floorf(ph)


## TAL's LFO waveform at phase x (cycles).
static func tal_wave(w: int, x: float) -> float:
	x -= floorf(x)
	match w:
		0:
			return sin(TAU * x)
		1:
			return 4.0 * x if x < 0.25 else (2.0 - 4.0 * x if x < 0.75 else 4.0 * x - 4.0)
		2:
			return 2.0 * x - 1.0
		3:
			return 1.0 if x < 0.5 else -1.0
	return 0.0


## The GAK LFO for TAL LFO k.
static func lfo_dict(p: Dictionary, k: int) -> Dictionary:
	var w := lfo_wave(p, k)
	var ph := lfo_phase(p, k)
	var l := {rate_hz = lfo_rate(p, k), free = false}
	match w:
		0:
			l.shape = "sine"
		1:
			l.shape = "triangle"
			ph += 0.25
		2:
			l.shape = "saw"
		3:
			l.shape = "square"
		4:
			l.shape = "random"
		_:
			l.shape = "random"
			l.rate_hz = 1000.0
	ph -= floorf(ph)
	if ph != 0.0:
		l.phase = ph
	return l


# --- conversion ------------------------------------------------------------------------

## A TAL-NoiseMaker program (the prep tool's content.tal) as a patch.
static func convert(content: Dictionary) -> AKPatch:
	var p := params(content)
	var out := AKPatch.new()
	var mods: Array[Dictionary] = []
	var gain_db := _db(log_vol(p.volume, 2.0)) - 6.0206 + CAL_DB

	# --- oscillators: osc1, osc2, [ring copy of osc2], sub, [FM sine], [vintage noise]
	var base := 2.0 * (float(p.oscmastertune) - 0.5)
	base += [-12.0, 0.0, 12.0, 24.0][clampi(int(float(p.transpose) * 3.00001), 0, 3)]
	var s1 := base + tune_semis(p.osc1tune) + 2.0 * (float(p.osc1finetune) - 0.5)
	var s2 := base + tune_semis(p.osc2tune) + 2.0 * (float(p.osc2finetune) - 0.5)
	var w1 := combo(p.osc1waveform, N_OSC1)
	var w2 := combo(p.osc2waveform, N_OSC2)
	var l1 := log_vol(p.osc1volume)
	var l2 := log_vol(p.osc2volume)
	var l3 := log_vol(p.osc3volume)
	var ring := clampf(float(p.ringmodulation), 0.0, 1.0)
	var fm0 := log_vol(p.osc2fm)
	var sync := float(p.oscsync) > 0.0
	var ed_dest := combo(p.envelopeeditordest1, 8)
	var ed_amt := float(p.envelopeeditoramount) * float(p.envelopeeditoramount)
	var ed_on := ed_amt > 0.0 and ed_dest > 1
	var ad_dest := combo(p.freeaddestination, 6)
	var ad_amt := cen3(p.freeadamount)
	var ad_on := absf(ad_amt) > 1e-6 and ad_dest > 1
	var lfo_dest := [0, combo(p.lfo1destination, 8), combo(p.lfo2destination, 8)]
	var lfo_amt := [0.0, cen3(p.lfo1amount), cen3(p.lfo2amount)]
	var lfo_on := [false, absf(lfo_amt[1]) > 1e-6 and lfo_dest[1] > 1, absf(lfo_amt[2]) > 1e-6 and lfo_dest[2] > 1]
	var fm_mod: bool = (lfo_on[1] and lfo_dest[1] == 6) or (ad_on and ad_dest == 6) or (ed_on and ed_dest == 6)
	var need_ring := ring > 0.0 or (ed_on and ed_dest == 7)
	var need_fm: bool = (fm0 > 0.0 or fm_mod) and w2 != 5
	# osc2's frequency ratio to osc1's: FM shifts osc2 by 10 fm f1 on average.
	var r12 := pow(2.0, (s1 - s2) / 12.0)
	var shift := func(fm: float) -> float: return 12.0 * log(1.0 + 10.0 * fm * r12) / LN2 if need_fm else 0.0

	# Polarity: TAL's mixer subtracts osc1 and osc2 from the sub, its pulses and square sit low
	# for the first part of a cycle (GAK's high), its sine is -cos. GAK's levels carry the signs.
	var sig1 := -1.0 if w1 == 2 else 1.0
	var sig2 := -1.0 if w2 == 2 else 1.0
	var a1 := l1 * (2.0 * NOISE_LEVEL if w1 == 3 else 1.0)
	var a2 := l2 * (2.0 * NOISE_LEVEL if w2 == 5 else 1.0)
	var oscs: Array[Dictionary] = []
	var o1 := {shape = ["saw", "pulse", "noise"][w1 - 1], level = -(1.0 - ring) * a1 * sig1}
	if w1 == 2:
		o1.width = clampf(float(p.osc1pw), 0.01, 0.99)
	var o2 := {shape = ["saw", "square", "triangle", "sine", "noise"][w2 - 1], level = -(1.0 - ring) * a2 * sig2}
	o1.semitones = s1
	o2.semitones = s2 + float(shift.call(fm0))
	oscs.append(o1)
	oscs.append(o2)
	var i_ring := -1
	if need_ring:
		var oc := o2.duplicate()
		oc.level = 4.0 * ring * a1 * a2 * sig1 * sig2
		oc.ring_from = 1
		oscs.append(oc)
		i_ring = oscs.size()
	var sub := {shape = "square", level = -l3, semitones = base - 24.0}
	oscs.append(sub)
	var i_sub := oscs.size()
	if sync:
		for o in [o1, o2]:
			if o.shape != "sine" and o.shape != "noise":
				o.sync_to = i_sub
		if i_ring > 0 and oscs[i_ring - 1].shape != "sine" and oscs[i_ring - 1].shape != "noise":
			oscs[i_ring - 1].sync_to = i_sub
	# TAL starts osc1 and osc2 at their phase knobs (osc1 half a cycle on, by default) against the sub
	# at 0; GAK's oscillators all start at 0, so they're offset by phase modulation from a held "DC"
	# oscillator (a square far below 1 Hz). Under sync TAL restarts them with the sub.
	var ph1 := float(p.osc1phase)
	var ph2 := float(p.osc2phase) - (0.25 if w2 == 4 else 0.0)
	ph2 -= floorf(ph2)
	var need_ph1 := not sync and w1 != 3 and absf(ph1) > 1e-3
	var need_ph2 := not sync and w2 != 5 and absf(ph2) > 1e-3 and not ((fm0 > 0.0 or fm_mod))
	if need_ph1 or need_ph2:
		oscs.append({shape = "square", level = 0.0, semitones = -300.0})
		var i_dc := oscs.size()
		if need_ph1:
			o1.fm_from = i_dc
			o1.fm_index = TAU * ph1
		if need_ph2:
			for j in [2, i_ring]:
				if j > 0:
					oscs[j - 1].fm_from = i_dc
					oscs[j - 1].fm_index = TAU * ph2
	var i_fm := -1
	if need_fm:
		oscs.append({shape = "sine", level = 0.0, semitones = s1})
		i_fm = oscs.size()
		for j in [2, i_ring]:
			if j > 0:
				oscs[j - 1].fm_from = i_fm
				oscs[j - 1].fm_index = 10.0 * fm0
	if float(p.vintagenoise) > 0.0:
		oscs.append({shape = "noise", level = 0.08 * float(p.vintagenoise)})
	elif float(p.resonance) >= 0.9 and combo(p.filtertype, N_FILTER) <= 7:
		# TAL's ladder has a little noise inside: a self-oscillating filter sings with no input.
		oscs.append({shape = "noise", level = EXCITE})
	out.oscillators = oscs
	var osc1_pitch := [1] + ([i_fm] if i_fm > 0 else [])
	var osc2_pitch := [2] + ([i_ring] if i_ring > 0 else [])
	var fm_targets := [2] + ([i_ring] if i_ring > 0 else [])

	# --- filter
	var t := ftype(p)
	var kf := float(p.keyfollow) * float(p.keyfollow)
	var c0 := log_filt(p.cutoff) + log_filt(p.velocitycutoff) * VEL_REF
	var c60 := c0 + kf * (60.0 - 72.0) / 512.0
	var ccl := clampf(absf(c60), C_MIN, C_MAX)
	var cutoff := cut_hz(t, ccl)
	var rv := clampf(float(p.resonance), 0.0, 1.0)
	var drive := float(p.filterdrive) * 10.0
	match t:
		1, 2, 3, 4, 11:
			var poles: float = [4.0, 3.0, 2.0, 1.0][t - 1] if t <= 4 else 4.0
			var res := _interp(RES_X, RES_LP24, rv) if t == 1 else _interp(RES_X, RES_LP12, rv)
			if t == 2:
				res = 0.5 * (res + _interp(RES_X, RES_LP24, rv))
			if t == 11:
				res = rv
			out.filter = {type = "ladder", cutoff_hz = cutoff, resonance = res, drive = 1.0 + drive, poles = poles}
			gain_db += _res_comp(rv, res)
		5, 6, 7:
			# The ladder's pole mixes (TAL's HP, BP and notch taps), each with its own resonance and level
			# measured against TAL: the HP's passband doesn't rise with resonance, the BP is driven by 4.
			var res := minf(1.1, _interp(RES_X, RES_LP12, rv) + (0.0 if t == 6 else 0.06))
			var mix: Array = [[1.0, -2.0, 1.0, 0.0, 0.0], [0.0, 0.0, 2.0, -4.0, 2.0], [1.0, -2.0, 4.0, -4.0, 0.0]][t - 5]
			out.filter = {type = "ladder", cutoff_hz = cutoff, resonance = res, drive = 1.0 + drive, pole_mix = mix}
			if t == 5:
				gain_db += -2.2 - _db(1.0 + 2.0 * res)
			elif t == 6:
				gain_db += 11.6 - 1.6 * minf(1.0, rv / 0.3)
		8, 9, 10:
			out.filter = {type = ["lowpass", "highpass", "bandpass"][t - 8], cutoff_hz = cutoff, q = _interp(SVQ_X, SVQ, rv),
				slope_db = 24.0}
		_:
			out.filter = {type = "off"}
			gain_db += _db(3.0)
	if drive > 0.0:
		gain_db += _db((1.0 + drive) / (1.0 + drive * 0.5))
	var filt := t != 12
	# key follow: a straight line in octaves through TAL's curve at the reference notes
	if filt and kf > 0.0:
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var sxy := 0.0
		for n in [36.0, 48.0, 60.0, 72.0, 84.0]:
			var x: float = (n - 60.0) / 12.0
			var y := cut_oct(t, c0 + kf * (n - 72.0) / 512.0, ccl)
			sx += x
			sy += y
			sxx += x * x
			sxy += x * y
		var slope := (5.0 * sxy - sx * sy) / (5.0 * sxx - sx * sx)
		mods.append({source = "key", dest = "cutoff", amount = slope})
	# velocity to cutoff: linear in octaves around the reference velocity
	if filt and float(p.velocitycutoff) > 0.0:
		var kv := log_filt(p.velocitycutoff)
		var oct := cut_oct(t, c60, c60 - kv * 0.2) / 0.2
		mods.append({source = "velocity", dest = "cutoff", amount = oct})
		out.filter.cutoff_hz = cutoff * pow(2.0, -oct * VEL_REF)
	# filter envelope (env2), in octaves
	var contour := cen3(p.filtercontour) + log_filt(p.velocitycontour) * VEL_REF
	var fsus := log_vol(p.filtersustain)
	var c_ref := c60 + contour * fsus
	var ad_filter := ad_on and ad_dest == 2 and filt
	if ad_filter:
		# The filter envelope and the free AD both add to the cutoff before it's squared: one
		# envelope through TAL's curve of their sum, sampled in time.
		var sim := _filter_sum_stages(p, t, c60, ccl, contour, fsus, ad_amt)
		if not sim.is_empty():
			out.env2 = sim.env
			mods.append({source = "env2", dest = "cutoff", amount = sim.span})
	elif filt and absf(contour) > 1e-5:
		var f := func(e: float) -> float: return cut_oct(t, c60 + contour * e, ccl)
		var span := 0.0
		for i in 21:
			span = maxf(span, absf(float(f.call(i / 20.0))))
		if span > 1e-3:
			var sc := adsr_stages(p.filterattack, p.filterdecay, fsus, p.filterrelease, f, 4, float(p.filterattack) == 0.0)
			_scale_levels(sc.stages, span)
			out.env2 = {stages = sc.stages, sustain = sc.sustain}
			mods.append({source = "env2", dest = "cutoff", amount = span})

	# --- amp envelope
	var amp := adsr_stages(p.ampattack, p.ampdecay, clampf(float(p.ampsustain), 0.0, 1.0), p.amprelease, Callable(), 1)
	out.amp_env = {stages = amp.stages, sustain = amp.sustain}

	# --- free AD envelope (env4)
	if ad_on and not ad_filter:
		var at: Array = attack(p.freeadattack)
		var dt := decay_tau(p.freeaddecay)
		var da := -log((1.0 + ENV_S) / ENV_S)
		var ff := Callable()
		var amount := 0.0
		var span := 1.0
		if ad_dest == 2 and filt:
			ff = func(e: float) -> float: return cut_oct(t, c_ref + ad_amt * e, c_ref)
			span = 0.0
			for i in 21:
				span = maxf(span, absf(float(ff.call(i / 20.0))))
			amount = span
		var st: Array = []
		_segment(st, 0.0, 1.0, 0.0 if float(p.freeadattack) == 0.0 else at[0], at[1], ff, 3 if ff.is_valid() else 1)
		_segment(st, 1.0, 0.0, -da * dt, da, ff, 4 if ff.is_valid() else 1)
		var sus := st.size() - 1
		var rt := release_tau(1.0)
		st.append({time_s = rt * 5.6, level = 0.0, curve = "power", amount = -5.6})
		if span > 1e-3:
			_scale_levels(st, span)
		out.envelopes = [{stages = st, sustain = sus}]
		match ad_dest:
			2:
				if filt and span > 1e-3:
					mods.append({source = "env4", dest = "cutoff", amount = amount})
			3:
				for j in osc1_pitch:
					mods.append({source = "env4", dest = "osc%d.pitch" % j, amount = 48.0 * ad_amt})
			4:
				for j in osc2_pitch:
					mods.append({source = "env4", dest = "osc%d.pitch" % j, amount = 48.0 * ad_amt})
			5:
				if w1 == 2:
					mods.append({source = "env4", dest = "osc1.width", amount = absf(ad_amt)})
			6:
				if need_fm:
					for j in fm_targets:
						mods.append({source = "env4", dest = "osc%d.fm" % j, amount = 10.0 * absf(ad_amt)})
						mods.append({source = "env4", dest = "osc%d.pitch" % j,
							amount = float(shift.call(fm0 + absf(ad_amt))) - float(shift.call(fm0))})

	# --- LFOs
	for k in [1, 2]:
		var l := lfo_dict(p, k)
		if k == 1:
			out.lfo1 = l
		else:
			out.lfo2 = l
		if not lfo_on[k]:
			continue
		var a: float = lfo_amt[k]
		var src := "lfo%d" % k
		var w := lfo_wave(p, k)
		if w == 5:
			# TAL's noise LFO is white noise smoothed to almost nothing (about 0.09 rms): taken as 0, so
			# a unipolar destination gets half the amount, held.
			var dn: int = lfo_dest[k]
			if dn == 2 and filt:
				var cr0 := c_ref
				out.filter.cutoff_hz = float(out.filter.cutoff_hz) * pow(2.0, cut_oct(t, cr0 + a * 0.5, cr0))
			elif k == 1 and dn == 5 and w1 == 2:
				o1.width = clampf(float(o1.width) + absf(a) * 0.5, 0.01, 0.99)
			elif k == 1 and dn == 6 and need_fm:
				for j in fm_targets:
					oscs[j - 1].fm_index = float(oscs[j - 1].fm_index) + 5.0 * absf(a)
					oscs[j - 1].semitones = float(oscs[j - 1].semitones) + float(shift.call(fm0 + absf(a) * 0.5)) - float(shift.call(fm0))
			elif k == 2 and dn == 6:
				gain_db += _db(1.0 - a * 0.5)
			continue
		var d: int = lfo_dest[k]
		if d == 2 and filt:
			var cr := c_ref
			if w <= 3:
				# A custom shape through TAL's curve: unipolar, added before the square.
				var pts: Array = []
				var span := 0.0
				var ph := lfo_phase(p, k)
				for i in 128:
					var y := cut_oct(t, cr + 0.5 * (1.0 + tal_wave(w, ph + i / 128.0)) * a, cr)
					pts.append(y)
					span = maxf(span, absf(y))
				if span > 1e-3:
					for i in pts.size():
						pts[i] = pts[i] / span
					l.shape = "custom"
					l.points = pts
					l.interp = "linear"
					l.erase("phase")
					mods.append({source = src, dest = "cutoff", amount = span})
			else:
				var hi := cut_oct(t, cr + a, cr)
				mods.append({source = src, dest = "cutoff", amount = hi * 0.5})
				out.filter.cutoff_hz = float(out.filter.cutoff_hz) * pow(2.0, hi * 0.5)
		elif d == 3 or d == 4 or d == 8:
			var targets: Array = osc1_pitch if d == 3 else (osc2_pitch if d == 4 else osc1_pitch + osc2_pitch)
			for j in targets:
				mods.append({source = src, dest = "osc%d.pitch" % j, amount = 48.0 * a})
		elif k == 1 and d == 5:
			if w1 == 2:
				mods.append({source = src, dest = "osc1.width", amount = absf(a) * 0.5})
				o1.width = clampf(float(o1.width) + absf(a) * 0.5, 0.01, 0.99)
		elif k == 1 and d == 6:
			if need_fm:
				var h := absf(a) * 0.5
				var sh := (float(shift.call(fm0 + absf(a))) - float(shift.call(fm0))) * 0.5
				for j in fm_targets:
					mods.append({source = src, dest = "osc%d.fm" % j, amount = 10.0 * h})
					mods.append({source = src, dest = "osc%d.pitch" % j, amount = sh})
					oscs[j - 1].fm_index = float(oscs[j - 1].fm_index) + 10.0 * h
					oscs[j - 1].semitones = float(oscs[j - 1].semitones) + sh
		elif d == 7:
			if a > 0.0:
				var oct := log(1.0 + 100.0 * a * a * a) / LN2
				var other: int = 3 - k
				mods.append({source = src, dest = "lfo%d.rate" % other, amount = oct * 0.5})
				var ol: Dictionary = out.lfo1 if other == 1 else out.lfo2
				if ol.has("rate_hz"):
					ol.rate_hz = float(ol.rate_hz) * pow(2.0, oct * 0.5)
		elif k == 2 and d == 6:
			gain_db += _db(1.0 - a * 0.5)
			mods.append({source = src, dest = "amp", amount = -(a * 0.5) / (1.0 - a * 0.5)})
		elif k == 2 and d == 5:
			gain_db += _db(1.0 - absf(a) * 0.5)
			mods.append({source = src, dest = "pan", amount = absf(a) * 0.5})

	# --- the drawn envelope (lfo3)
	if ed_on:
		var pts_src := curve_points(content)
		var once := float(p.envelopeoneshot) > 0.0
		var n := 256
		var es: Array = []
		for i in n:
			es.append(curve_at(pts_src, float(i) / (n - 1 if once else n)))
		var speed := pow(2.0, combo(p.envelopeeditorspeed, 6) - 1)
		var l3d := {shape = "custom", interp = "linear", once = once, free = false}
		# 16 / speed beats a cycle (4/4), but 5.0.6 runs it 48000 / 44100 times faster at 48 kHz (measured).
		if float(p.envelopefixtempo) > 0.0:
			l3d.rate_hz = speed / 8.0 * ED_SR_RATIO
		else:
			l3d.rate_sync = 16.0 / speed / ED_SR_RATIO
		var pts: Array = []
		match ed_dest:
			2:
				if filt:
					var cr := c_ref
					var span := 0.0
					for e: float in es:
						var y := cut_oct(t, cr + ed_amt * e, cr)
						pts.append(y)
						span = maxf(span, absf(y))
					if span > 1e-3:
						for i in pts.size():
							pts[i] = pts[i] / span
						mods.append({source = "lfo3", dest = "cutoff", amount = span})
			3, 4, 5:
				for e: float in es:
					pts.append(2.0 * e - 1.0)
				var targets: Array = osc1_pitch if ed_dest == 3 else (osc2_pitch if ed_dest == 4 else osc1_pitch + osc2_pitch)
				for j in targets:
					mods.append({source = "lfo3", dest = "osc%d.pitch" % j, amount = 24.0 * ed_amt})
			6:
				pts = es.duplicate()
				if need_fm:
					for j in fm_targets:
						mods.append({source = "lfo3", dest = "osc%d.fm" % j, amount = 10.0 * ed_amt})
						mods.append({source = "lfo3", dest = "osc%d.pitch" % j,
							amount = float(shift.call(fm0 + ed_amt)) - float(shift.call(fm0))})
			7:
				pts = es.duplicate()
				mods.append({source = "lfo3", dest = "osc1.level", amount = a1 * sig1 * ed_amt})
				mods.append({source = "lfo3", dest = "osc2.level", amount = a2 * sig2 * ed_amt})
				if i_ring > 0:
					mods.append({source = "lfo3", dest = "osc%d.level" % i_ring, amount = 4.0 * a1 * a2 * sig1 * sig2 * ed_amt})
			8:
				for e: float in es:
					pts.append(e - 1.0)
				mods.append({source = "lfo3", dest = "amp", amount = 1.0})
				gain_db += _db(ed_amt * 0.5)
		if not pts.is_empty():
			l3d.points = pts
			out.lfos = [l3d]
	out.mods = mods
	out.oscillators = oscs

	# --- playing
	var nv := combo(p.voices, 6)
	var pm := combo(p.portamentomode, 3)
	out.mode = "poly" if nv > 1 else ("legato" if pm == 2 else "mono")
	out.polyphony = maxi(1, nv)
	if pm > 1 and float(p.portamento) > 0.0:
		var pr := float(p.portamento)
		var rate := 44100.0 * 10000.0 * (pow(0.11 - 0.1 * pr, 6.0) + 1e-8)
		out.glide_s = clampf(4.0 / rate, 0.0, 2.0)
	out.bend_range = 12.0 * float(p.pitchwheelpitch)
	if filt and float(p.pitchwheelcutoff) > 0.0:
		var pw := float(p.pitchwheelcutoff)
		mods.append({source = "bend", dest = "cutoff", amount = 0.5 * (cut_oct(t, c_ref + pw, c_ref) - cut_oct(t, c_ref - pw, c_ref))})
		out.mods = mods
	out.velocity_sens = clampf(float(p.velocityvolume), 0.0, 1.0)
	out.velocity_curve = 1.0
	if float(p.detune) > 0.0:
		out.slop = {pitch_cents = 15.0 * float(p.detune) * float(p.detune)}
	out.tempo_bpm = 120.0
	out.unison = 1

	# --- effects: bitcrusher, master high-pass, delay, chorus, reverb
	var fx: Array[Dictionary] = []
	var bc := float(p.oscbitcrusher)
	if bc < 1.0:
		var q := floorf(1.0 + pow(bc, 8.0) * 65535.0)
		if q < 4000.0:
			# TAL truncates osc1 + osc2 (and the ring) to q steps before the filter, which GAK can't:
			# their level is set to what the truncation leaves (simulated on the raw waveforms at
			# middle C). A crush effect after the voices for the steps made the match worse.
			var kq := _crush_gain(w1, w2, a1 * (1.0 - ring), a2 * (1.0 - ring), s1, s2, float(o1.get("width", 0.5)), q)
			for j in [1, 2] + ([i_ring] if i_ring > 0 else []):
				oscs[j - 1].level = float(oscs[j - 1].level) * kq
	if true:
		# Always there: at 0 it still takes out everything under 7.6 Hz (a sub two octaves under a low
		# note droops through it).
		var rr := 0.999 - 0.4 * log_vol(p.highpass)
		fx.append({type = "filter", mode = "highpass", cutoff_hz = -log(rr) * 48000.0 / TAU, slope_db = 6.0})
	if float(p.delaywet) > 0.0:
		var secs := 0.0
		if float(p.delaysync) > 0.0:
			secs = DELAY_SYNC[clampi(int(float(p.delaytime) * 17.0), 0, 17)]
		else:
			secs = 4.0 * (0.01 + 0.99 * log_vol(p.delaytime))
		var tl := secs * (0.5 if float(p.delayfactorl) > 0.0 else 1.0)
		var tr := secs * (0.5 if float(p.delayfactorr) > 0.0 else 1.0)
		var fb := 1.0 + pow(2.0 * float(p.delayfeedback) - 1.0, 3.0)
		var lpc := log_vol(1.0 - float(p.delayhighshelf)) * 0.38
		var kfcr := 1.8730 * lpc * lpc * lpc + 0.4955 * lpc * lpc - 0.6490 * lpc + 0.9988
		var g := 1.0 - exp(-PI * kfcr * lpc)
		var damp := 20000.0 if g >= 0.999 else -log(1.0 - g) * 44100.0 / TAU
		# TAL filters every pass through its loop, the first echo too, with a low-pass and a high-pass
		# (149 Hz and up); GAK's delay low-passes the repeats only and has no high-pass. Both are
		# taken at DELAY_HZ: the first echo's level loses both, each repeat the high-pass.
		var hp_r := 0.999 - 0.4 * (0.05 + 0.95 * float(p.delaylowshelf))
		var hp_hz := -log(hp_r) * 48000.0 / TAU
		var x := DELAY_HZ / hp_hz
		var g_hp := x / sqrt(1.0 + x * x)
		var g_lp := 1.0 / sqrt(1.0 + pow(DELAY_HZ / maxf(damp, 1.0), 2.0))
		fx.append({type = "delay", time_ms = minf(tl, tr) * 1000.0, spread_ms = clampf((tr - tl) * 1000.0, -100.0, 100.0),
			feedback = clampf(fb * g_hp, 0.0, 0.95), damp_hz = clampf(damp, 100.0, 20000.0),
			mix = clampf(float(p.delaywet) * g_hp * g_lp, 0.0, 1.0), mode = "stereo"})
	var ch1 := float(p.chorus1enable) > 0.0
	var ch2 := float(p.chorus2enable) > 0.0
	if ch1 or ch2:
		var wet := 1.4 * (2.0 if ch1 and ch2 else 1.0)
		var m := wet / (1.0 + wet)
		var rate := 0.5 if not ch2 else (0.83 if not ch1 else 0.665)
		fx.append({type = "chorus", rate_hz = rate, depth_ms = 4.2, delay_ms = 0.7, voices = 2 if ch1 and ch2 else 1,
			mix = m, spread = 2.0, feedback = 0.0})
		gain_db += _db(1.0 + wet)
	if float(p.reverbwet) > 0.0:
		var dv := clampf(float(p.reverbdecay), 0.0, 1.0)
		var rt60 := _interp([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
			[0.03, 0.08, 0.25, 0.5, 0.8, 1.3, 2.2, 3.7, 6.0, 11.0, 30.0], dv)
		# GAK's reverb (measured): RT60 = 0.098 / -log10(0.7 + 0.28 room).
		var fbr := pow(10.0, -0.098 / rt60)
		fx.append({type = "reverb", room = clampf((fbr - 0.7) / 0.28, 0.0, 1.0), damp = 0.1,
			width = 1.0, mix = clampf(log_vol(p.reverbwet) * sqrt(minf(1.0, rt60 / 0.6)), 0.0, 1.0)})  # shorter than GAK's: less energy
	out.effects = fx
	out.gain_db = gain_db
	out.resource_name = String(content.get("name", ""))
	return out


## The level TAL's bitcrusher leaves osc1 + osc2 at (their rms after truncation to q steps over
## their rms before), from the raw waveforms at middle C.
static func _crush_gain(w1: int, w2: int, l1: float, l2: float, s1: float, s2: float, pw: float, q: float) -> float:
	var f1 := 261.63 * pow(2.0, s1 / 12.0) / 48000.0
	var f2 := 261.63 * pow(2.0, s2 / 12.0) / 48000.0
	var e0 := 0.0
	var e1 := 0.0
	var seed := 12345
	for i in 9600:
		var x := 0.0
		for k in 2:
			var w := w1 if k == 0 else w2 + 10
			var ph := fmod(float(i) * (f1 if k == 0 else f2) + (0.5 if k == 0 else 0.0), 1.0)
			var l := l1 if k == 0 else l2
			var y := 0.0
			match w:
				1, 11:
					y = ph - 0.5
				2:
					y = -0.5 if ph < pw else 0.5
				12:
					y = -0.5 if ph < 0.5 else 0.5
				13:
					y = (ph * 2.0 if ph < 0.5 else 2.0 - ph * 2.0) - 0.5
				14:
					y = -0.5 * cos(TAU * ph)
				_:
					seed = (seed * 16807) % 2147483647
					y = (float(seed) / 2147483647.0 * 2.0 - 1.0) * NOISE_LEVEL
			x -= y * l
		var c := float(int(x * q)) / q
		e0 += x * x
		e1 += c * c
	return sqrt(e1 / maxf(e0, 1e-12)) if e0 > 0.0 else 1.0


## The level a resonant ladder loses in TAL against GAK's, in dB.
static func _res_comp(r: float, res: float) -> float:
	var tal := -(1.25 * minf(1.0, r / 0.25) + 1.0 * maxf(0.0, r - 0.3))
	var gak := _db((1.0 + 2.0 * res) / (1.0 + 4.0 * res))
	return tal - gak


## What the conversion only approximates, for this program.
static func caveats(content: Dictionary) -> Array:
	var p := params(content)
	var out := []
	var t := ftype(p)
	var filt := t != 12
	var lfo_dest := [0, combo(p.lfo1destination, 8), combo(p.lfo2destination, 8)]
	var lfo_on := [false, absf(cen3(p.lfo1amount)) > 1e-6 and lfo_dest[1] > 1, absf(cen3(p.lfo2amount)) > 1e-6 and lfo_dest[2] > 1]
	var ad_dest := combo(p.freeaddestination, 6)
	var ad_on := absf(cen3(p.freeadamount)) > 1e-6 and ad_dest > 1
	var ed_dest := combo(p.envelopeeditordest1, 8)
	var ed_on := float(p.envelopeeditoramount) > 0.0 and ed_dest > 1
	var pm := combo(p.portamentomode, 3)
	if pm == 3 and float(p.portamento) > 0.0:
		out.append("portamento on: TAL's first note glides up from F#2; not converted")
	if pm > 1 and float(p.portamento) > 0.0:
		out.append("glide: TAL's is linear in semitones, GAK's a time constant")
	if filt and float(p.keyfollow) > 0.0:
		out.append("filter key follow: a straight line in octaves through TAL's curve")
	if filt and ((lfo_on[1] and lfo_dest[1] == 2) or (lfo_on[2] and lfo_dest[2] == 2) or (ed_on and ed_dest == 2)):
		out.append("cutoff modulation: each source taken through TAL's curve on its own")
	if filt and ad_on and ad_dest == 2:
		out.append("free AD and filter envelope summed through TAL's curve at middle C")
	if filt and (float(p.velocitycutoff) > 0.0 or float(p.velocitycontour) > 0.0):
		out.append("velocity to cutoff and contour: matched around velocity 100")
	if float(p.filterdrive) > 0.0 and t >= 8:
		out.append("filter drive on a state-variable type: level only")
	if float(p.resonance) >= 0.9 and t <= 7:
		out.append("self-oscillating filter, started by a quiet noise")
	if t >= 8 and t <= 10 and float(p.resonance) > 0.6:
		out.append("state-variable resonance: two equal stages")
	if float(p.oscbitcrusher) < 1.0 and floorf(1.0 + pow(float(p.oscbitcrusher), 8.0) * 65535.0) < 4000.0:
		out.append("bitcrusher: only the level it leaves")
	if float(p.vintagenoise) > 0.0:
		out.append("vintage noise as quiet white noise")
	if float(p.detune) > 0.0:
		out.append("detune: fixed per voice slot, not new on each note")
	var fm_mod: bool = (lfo_on[1] and lfo_dest[1] == 6) or (ad_on and ad_dest == 6) or (ed_on and ed_dest == 6)
	if fm_mod and combo(p.osc2waveform, N_OSC2) != 5:
		out.append("modulated FM: the carrier's shift linear in semitones")
	for k in [1, 2]:
		if lfo_on[k] and lfo_wave(p, k) == 5:
			out.append("lfo%d noise taken as its mean" % k)
		if lfo_on[k] and lfo_dest[k] == 7:
			out.append("lfo%d to the other LFO's rate: linear in octaves" % k)
	if lfo_on[2] and lfo_dest[2] == 5:
		out.append("lfo2 to pan: GAK's equal-power pan")
	if float(p.chorus1enable) > 0.0 or float(p.chorus2enable) > 0.0:
		out.append("chorus: TAL low-passes its wet signal, GAK doesn't")
	if float(p.delaywet) > 0.0:
		out.append("delay: TAL filters every pass (the first echo too); matched at 500 Hz")
		var secs := 0.0
		if float(p.delaysync) > 0.0:
			secs = DELAY_SYNC[clampi(int(float(p.delaytime) * 17.0), 0, 17)]
		else:
			secs = 4.0 * (0.01 + 0.99 * log_vol(p.delaytime))
		if secs > 2.0:
			out.append("delay longer than GAK's 2 s")
		if (float(p.delayfactorl) > 0.0) != (float(p.delayfactorr) > 0.0) and secs * 0.5 > 0.1:
			out.append("delay: left and right times more than 100 ms apart")
		if 1.0 + pow(2.0 * float(p.delayfeedback) - 1.0, 3.0) > 0.95:
			out.append("delay feedback above 0.95 (TAL limits its runaway)")
	if float(p.reverbwet) > 0.0:
		if float(p.reverbpredelay) > 0.0:
			out.append("reverb predelay not converted")
		if float(p.reverbhighcut) > 0.05 or float(p.reverblowcut) < 0.95:
			out.append("reverb input filters not converted")
		if float(p.reverbdecay) < 0.35:
			out.append("reverb shorter than GAK's shortest: its level scaled")
	if float(p.pitchwheelcutoff) > 0.0 and filt:
		out.append("pitch wheel to cutoff: linear in octaves")
	if t == 11 or t == 12:
		out.append("filter type %d: approximated" % t)
	return out
