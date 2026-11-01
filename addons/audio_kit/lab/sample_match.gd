# SPDX-License-Identifier: Apache-2.0
@tool
## Matching a recording as a synth patch: an Auxy "Export for Bitwig Studio"
## (.axbw) of an instrument playing the scale MIDI (docs/sample_matching.md)
## becomes two patches.
##
##   var m := AKSampleMatch.new()
##   var res := m.run("res://recordings/stack.axbw")
##   res.full, res.lite                   # AKPatch
##   res.report.full_db, res.report.lite_db, res.report.floor_db
##
## Full: a table oscillator whose key zones (every 3 semitones) hold cycles
## taken from the recording at points through the note, keeping their levels,
## so the waveform, the decay and the level across the keyboard are the
## recording's own. Lite: one of those zones (key 72) for the whole keyboard,
## with three fitted curves for how the sound changes away from it: a low-pass
## following the key and the note's time, a fixed EQ, and a level by key.
##
## The score (`report`) is the harmonic score in dB over every note of the
## file, the level matched once: each harmonic's level through the note and
## the noise between them, against the original. `floor_db` is the original
## against itself (scene 3's two identical passes): what a perfect copy of a
## sound whose voices run free would score.
##
## Needs the native core (AKMatch): the analysis runs thousands of spectra.
## `run` takes a few minutes, mostly the lite fit; call it from a thread and
## watch `progress`.
class_name AKSampleMatch
extends RefCounted

## Called as progress.call(fraction 0..1, text) (from the thread running `run`).
var progress := Callable()
## Set from another thread to stop `run` at the next step.
var cancelled := false
## Frames per zone of the full patch; 0 tries 16 and 24 and keeps 24 when it scores at least 0.5 dB
## better (sounds that move a lot through the note).
var frames := 0
## Semitones between the full patch's zones.
var zone_step := 3
## The key the lite patch is exact at.
var lite_center := 72
## EQs in the lite patch (each a low shelf, a peak and a high shelf).
var lite_eqs := 2

const HOP := 441
# Where the table position sits through the note: W x (1 - e^(-t/TAU)) (env2, detail in the attack) +
# (1 - W) x t/T (env3, even later). Frames sit where it crosses i/(frames - 1).
const POS_W := 0.5
const POS_TAU := 0.08
const POS_T := 1.0
const JOIN_S := 0.2

var _m: Object
var _sr := 44100.0
var _x := {}          # the export: {l, r, mid (raw), clean (high-passed mid), notes, name, scenes}
var _tr := 0.0
var _frames := 16


static func available() -> bool:
	return ClassDB.class_exists(&"AKMatch")


## Everything in one go: {ok, error, name, full, lite (AKPatch), report, renders: {full, lite (AKBuffer)}, original (AKBuffer)}.
func run(path: String) -> Dictionary:
	var out := {ok = false, error = ""}
	if not available():
		out.error = "matching needs the native core (AKMatch)"
		return out
	_m = ClassDB.instantiate(&"AKMatch")
	_step(0.0, "Reading %s" % path.get_file())
	var rd := read_export(path)
	if not rd.ok:
		out.error = rd.error
		return out
	_x = rd
	_sr = float(rd.rate)
	var why := _check_layout()
	if why != "":
		out.error = why
		return out
	_step(0.03, "Finding the pitch")
	_tr = transposition()
	var all := _all_notes()
	var full_spec := {}
	var full_db := 0.0
	var r_full: AKBuffer
	for nf in ([frames] if frames > 0 else [16, 24]):
		_frames = nf
		var spec := full_patch()
		if cancelled:
			return _stopped(out)
		_step(0.25, "Setting the level (%d frames)" % nf)
		spec.gain_db = level_db(spec)
		var r := AKSynth.render_notes(to_patch(spec), all, _length_s(), int(_sr))
		var db := check(r)
		if full_spec.is_empty() or db < full_db - 0.5:
			full_spec = spec
			full_db = db
			r_full = r
	var lite_spec := lite_patch(full_spec)
	if cancelled:
		return _stopped(out)
	_step(0.9, "Checking both against the recording")
	var r_lite := AKSynth.render_notes(to_patch(lite_spec), all, _length_s(), int(_sr))
	var report := {transpose = _tr, stereo = full_spec.oscillators.size() > 1,
		zones = (full_spec.oscillators[0].table.zones as Array).size(), frames = (full_spec.oscillators[0].table.zones[0].frames as Array).size(),
		full_db = full_db, lite_db = check(r_lite), floor_db = floor_db(),
		lite_by_distance = by_distance(r_lite), full_by_distance = by_distance(r_full),
		lite = lite_spec.get("_fit", {})}
	lite_spec.erase("_fit")
	var full := to_patch(full_spec)
	var lite := to_patch(lite_spec)
	full.resource_name = rd.name
	lite.resource_name = rd.name + " Lite"
	var orig := AKBuffer.new(0, int(_sr))
	orig.l = rd.l
	orig.r = rd.r
	_step(1.0, "Done")
	out.merge({ok = true, name = rd.name, full = full, lite = lite, report = report,
		renders = {full = r_full, lite = r_lite}, original = orig, scenes = rd.scenes}, true)
	return out


## A one-line summary of a run's report.
static func summary(report: Dictionary) -> String:
	return "Full %.1f dB, lite %.1f dB (the original against itself: %.1f dB). %s, %d zones of %d frames, transposed %+d." % [
		report.full_db, report.lite_db, report.floor_db, "Stereo" if report.stereo else "Mono", report.zones, report.frames, int(report.transpose)]


func _stopped(out: Dictionary) -> Dictionary:
	out.error = "stopped"
	return out


func _step(f: float, text: String) -> void:
	if progress.is_valid():
		progress.call(f, text)


# ------------------------------------------------------------------ reading

## The export as plain data: {ok, error, name, rate, l, r (PackedFloat32Array), mid, clean,
## notes: [{t, len, note, vel}] (seconds, velocity 0..1), scenes: [start_s, ...]}.
static func read_export(path: String) -> Dictionary:
	var out := {ok = false, error = ""}
	var model := AKAuxy.read(path)
	if not model.ok:
		out.error = model.error
		return out
	var ci := -1
	for i in model.channels.size():
		if model.channels[i].kind == "instrument" and model.stems.has(i):
			ci = i
			break
	if ci < 0:
		out.error = "%s has no instrument channel with a stem" % path.get_file()
		return out
	var zip := ZIPReader.new()
	zip.open(path)
	var wav := _read_wav(zip.read_file(String(model.stems[ci])))
	zip.close()
	if wav.error != "":
		out.error = "stem: %s" % wav.error
		return out
	var spb := 60.0 / float(model.bpm)
	var notes := []
	var scenes := []
	var at := 0.0
	for sc: Dictionary in model.scenes:
		scenes.append(at * spb)
		var beats := float(sc.bars) * AKAuxy.BEATS_PER_BAR
		for key: String in sc.loops:
			var lp: Dictionary = model.loops[key]
			if int(lp.channel) != ci:
				continue
			# A loop shorter than its scene repeats to fill it.
			var lb := float(AKAuxy.loop_bars(lp) * AKAuxy.BEATS_PER_BAR)
			var r := 0.0
			while r < beats - 1e-6:
				for n: Array in lp.notes:
					if r + float(n[0]) < beats - 1e-6:
						notes.append({t = (at + r + float(n[0])) * spb, len = float(n[1]) * spb, note = int(n[2]), vel = float(n[3])})
				r += lb
		at += beats
	var end_s := at * spb
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	var mid := PackedFloat32Array()
	mid.resize(wav.l.size())
	for i in mid.size():
		mid[i] = 0.5 * (wav.l[i] + wav.r[i])
	var m: Object = ClassDB.instantiate(&"AKMatch")
	var name := String(model.channels[ci].label)
	out.merge({ok = true, name = name if name != "" else path.get_file().get_basename(), rate = wav.rate,
		l = wav.l, r = wav.r, mid = mid, clean = m.highpass(mid, float(wav.rate), 15.0), notes = notes, scenes = scenes, end_s = end_s}, true)
	return out


## A WAV's two channels (a mono file twice): {l, r, rate, error}. PCM 16, 24 or 32 bit, or float.
static func _read_wav(b: PackedByteArray) -> Dictionary:
	var out := {l = PackedFloat32Array(), r = PackedFloat32Array(), rate = 0, error = ""}
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		out.error = "not a WAV file"
		return out
	var pos := 12
	var fmt := 0
	var ch := 0
	var bits := 0
	var data_at := -1
	var data_len := 0
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		if id == "fmt ":
			fmt = b.decode_u16(pos + 8)
			ch = b.decode_u16(pos + 10)
			out.rate = b.decode_u32(pos + 12)
			bits = b.decode_u16(pos + 22)
			if fmt == 0xFFFE and size >= 26:
				fmt = b.decode_u16(pos + 32)
		elif id == "data":
			data_at = pos + 8
			data_len = mini(size, b.size() - data_at)
		pos += 8 + size + (size & 1)
	if data_at < 0 or ch < 1 or not (bits in [16, 24, 32]) or not (fmt in [1, 3]):
		out.error = "unsupported WAV (format %d, %d bits)" % [fmt, bits]
		return out
	var bps := bits / 8
	var n := data_len / (bps * ch)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	var c2 := 1 if ch > 1 else 0
	for i in n:
		var a := data_at + i * bps * ch
		if bits == 16:
			l[i] = b.decode_s16(a) / 32768.0
			r[i] = b.decode_s16(a + c2 * 2) / 32768.0
		elif bits == 24:
			l[i] = (((b[a + 2] << 24) | (b[a + 1] << 16) | (b[a] << 8)) << 32 >> 40) / 8388608.0
			var q := a + c2 * 3
			r[i] = (((b[q + 2] << 24) | (b[q + 1] << 16) | (b[q] << 8)) << 32 >> 40) / 8388608.0
		elif fmt == 3:
			l[i] = b.decode_float(a)
			r[i] = b.decode_float(a + c2 * 4)
		else:
			l[i] = b.decode_s32(a) / 2147483648.0
			r[i] = b.decode_s32(a + c2 * 4) / 2147483648.0
	out.l = l
	out.r = r
	return out


## The scale MIDI's parts, by scene: the chromatic run, the 1 s holds, the velocity pair.
func _check_layout() -> String:
	if _x.scenes.size() < 3:
		return "expected the scale MIDI's three scenes, found %d (docs/sample_matching.md)" % _x.scenes.size()
	if _run().size() < 24:
		return "scene 1 should be a chromatic run of short notes; found %d notes" % _run().size()
	if _holds().size() < 3:
		return "scene 2 should start with 1 s holds; found %d" % _holds().size()
	if _velocity_pair().size() < 2:
		return "scene 3 should hold a note at two velocities"
	return ""


func _run() -> Array:
	return _x.notes.filter(func(n: Dictionary) -> bool: return n.t < _x.scenes[1])


func _holds() -> Array:
	var s1: float = _x.scenes[1]
	var h: Array = _x.notes.filter(func(n: Dictionary) -> bool: return n.t >= s1 and n.t < s1 + 12.0 and n.len >= 0.9)
	h.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.note < b.note)
	return h


func _velocity_pair() -> Array:
	var s2: float = _x.scenes[2]
	var v: Array = _x.notes.filter(func(n: Dictionary) -> bool: return n.t >= s2 and n.len >= 0.9)
	return v.slice(0, 2) if v.size() >= 2 and v[0].vel != v[1].vel else []


func _length_s() -> float:
	return float(_x.l.size()) / _sr


func _all_notes() -> Array:
	return _x.notes.map(func(n: Dictionary) -> Dictionary: return {time_s = n.t, note = n.note, velocity = n.vel, length_s = n.len})


static func _f(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


# ------------------------------------------------------------------ analysis

## The octave the sound plays at against its MIDI: the lowest offset whose
## fundamental is within 30 dB of the strongest peak on most of the run.
func transposition() -> float:
	var votes := {}
	var run := _run()
	var nfft := 1 << 17
	for i in range(0, run.size(), 5):
		var n: Dictionary = run[i]
		var a := int((n.t + 0.03) * _sr)
		var S: PackedFloat64Array = _m.spectrum(_x.clean, a, int((n.t + 0.24) * _sr) - a, nfft)
		var mx := 0.0
		for v in S:
			mx = maxf(mx, v)
		for off in [-36, -24, -12, 0, 12]:
			var f0 := _f(n.note + off)
			if f0 < 15.0 or f0 > _sr / 2.0:
				continue
			var top := 0.0
			for k in range(ceili(f0 * 0.95 * nfft / _sr), ceili(f0 * 1.05 * nfft / _sr)):
				if k < S.size():
					top = maxf(top, S[k])
			if not votes.has(off):
				votes[off] = []
			votes[off].append(_db(top) - _db(mx))
	var offs := votes.keys()
	offs.sort()
	for off: int in offs:
		var ok := 0
		for v: float in votes[off]:
			if v > -30.0:
				ok += 1
		if float(ok) / votes[off].size() > 0.8:
			return float(off)
	return 0.0


static func _db(v: float) -> float:
	return 20.0 * log(maxf(v, 1e-9)) / log(10.0)


## Where frame i of `count` sits in time through the note.
static func frame_times(count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in count:
		var target := float(i) / maxf(count - 1, 1)
		# Position rises steadily, so bisect for the time it reaches the target.
		var lo := 0.0
		var hi := POS_T
		for _it in 50:
			var mid := 0.5 * (lo + hi)
			if _pos(mid) < target:
				lo = mid
			else:
				hi = mid
		out.append(minf(0.5 * (lo + hi), 0.97) if i == count - 1 else 0.5 * (lo + hi))
	return out


static func _pos(t: float) -> float:
	return POS_W * (1.0 - exp(-t / POS_TAU)) + (1.0 - POS_W) * minf(t / POS_T, 1.0)


## The fundamental of a note near its nominal pitch fg: the peak of the first five harmonics together.
func _refine(start: int, n: int, fg: float) -> float:
	var nfft := 1
	while nfft < 8 * n:
		nfft <<= 1
	var X: PackedFloat64Array = _m.spectrum(_x.clean, start, n, nfft)
	var df := _sr / nfft
	var best := fg
	var bs := -1.0
	for i in 241:
		var c := fg * (0.985 + 0.03 * i / 240.0)
		var s := 0.0
		for k in range(1, 6):
			var p := c * k / df
			var j := int(p)
			if j + 1 < X.size():
				s += X[j] + (X[j + 1] - X[j]) * (p - j)
		if s > bs:
			bs = s
			best = c
	return best


## The complex amplitudes of harmonics 1..K around time t of a note starting at sample a (a window of
## two periods, at least 6 ms), phases measured from the note's start: [re, im, ...].
func _cycle(sig: PackedFloat32Array, a: int, f0: float, t: float, K: int) -> PackedFloat64Array:
	var W := int(maxf(2.0 * _sr / f0, 0.006 * _sr))
	var a0 := maxi(int(t * _sr) - W / 2, 0)
	var fr := PackedFloat64Array()
	for k in range(1, K + 1):
		fr.append(k * f0)
	return _m.dft(sig, a + a0, W, fr, _sr, a0 / _sr)


## A held or run note's frames at times ts, per channel, each turned so the mid channel's fundamental
## has phase 0 (the frames line up through the note, and left and right keep their relation).
func _measure(n: Dictionary, ts: PackedFloat64Array, chans: Array) -> Dictionary:
	var a := int(n.t * _sr)
	var fg := _f(n.note + _tr)
	var s0 := a + int(0.03 * _sr)
	var f0 := _refine(s0, a + int(minf(n.len, 0.9) * _sr) - s0, fg)
	var K := int(minf(511.0, 18000.0 / f0))
	var out := []
	for _c in chans:
		out.append([])
	for t in ts:
		var tt := maxf(t, 1.0 / f0)
		var fund := _cycle(_x.clean, a, f0, tt, 1)
		var ang := atan2(fund[1], fund[0])
		for c in chans.size():
			var A := _cycle(chans[c], a, f0, tt, K)
			# Turn harmonic k by -k x the fundamental's phase.
			for k in K:
				var th := -(k + 1) * ang
				var re := A[2 * k]
				var im := A[2 * k + 1]
				A[2 * k] = re * cos(th) - im * sin(th)
				A[2 * k + 1] = re * sin(th) + im * cos(th)
			out[c].append(A)
	return {f0 = f0, fg = fg, frames = out}


static func _energy(A: PackedFloat64Array) -> float:
	var e := 0.0
	for v in A:
		e += v * v
	return e


## A frame for the table: amplitudes (to 80 dB below the loudest) and sine phases in cycles.
static func _frame(A: PackedFloat64Array) -> Dictionary:
	var K := A.size() / 2
	var mx := 0.0
	for k in K:
		mx = maxf(mx, Vector2(A[2 * k], A[2 * k + 1]).length())
	var amps := []
	var phs := []
	var last := 0
	for k in K:
		var v := Vector2(A[2 * k], A[2 * k + 1])
		var keep := v.length() > mx * 1e-4
		amps.append(_sig(v.length()) if keep else 0.0)
		# a cos(theta + phi) = a sin(theta + phi + pi/2), in cycles.
		phs.append(snappedf(fposmod((atan2(v.y, v.x) + PI * 0.5) / TAU, 1.0), 0.0001))
		if keep:
			last = k + 1
	return {harmonics = amps.slice(0, last), phases = phs.slice(0, last)}


static func _sig(v: float) -> float:
	if v == 0.0:
		return 0.0
	var e := floori(log(absf(v)) / log(10.0)) - 3
	return snappedf(v, pow(10.0, e))


## The full patch as a spec: the zoned table (a table per side for wide sounds), the measured tuning,
## release and velocity curve.
func full_patch() -> Dictionary:
	var holds := _holds()
	var run := {}
	for n: Dictionary in _run():
		run[n.note] = n
	var times := frame_times(_frames)
	var join := PackedFloat64Array()
	for t in times:
		if t <= JOIN_S:
			join.append(t)
	# Wide sounds (left/right correlation under 0.95 on the held notes) get a table per side.
	var cor := 0.0
	for h: Dictionary in holds:
		var a := int((h.t + 0.05) * _sr)
		var b := int((h.t + 0.95) * _sr)
		var ll := 0.0
		var rr := 0.0
		var lr := 0.0
		for i in range(a, mini(b, _x.l.size())):
			ll += _x.l[i] * _x.l[i]
			rr += _x.r[i] * _x.r[i]
			lr += _x.l[i] * _x.r[i]
		cor += lr / sqrt(ll * rr + 1e-20)
	var stereo: bool = cor / holds.size() < 0.95
	var chans := [_x.clean]
	if stereo:
		chans = [_m.highpass(_centred(_x.l), _sr, 15.0), _m.highpass(_centred(_x.r), _sr, 15.0)]
	var H := {}
	var cents := []
	for i in holds.size():
		_step(0.03 + 0.1 * i / holds.size(), "Measuring held note %d of %d (%d frames)" % [i + 1, holds.size(), _frames])
		var h: Dictionary = holds[i]
		H[h.note] = _measure(h, times, chans)
		cents.append(1200.0 * log(H[h.note].f0 / H[h.note].fg) / log(2.0))
	var keys := {}
	for k: int in run:
		if posmod(k - int(holds[0].note), zone_step) == 0:
			keys[k] = true
	for k: int in H:
		keys[k] = true
	var klist := keys.keys()
	klist.sort()
	var zones := []
	for _c in chans:
		zones.append([])
	for zi in klist.size():
		if cancelled:
			return {}
		var k: int = klist[zi]
		_step(0.13 + 0.12 * zi / klist.size(), "Measuring zone %d of %d (%d frames)" % [zi + 1, klist.size(), _frames])
		var F: Array
		if H.has(k):
			F = H[k].frames
		else:
			# A run note gives the frames up to JOIN_S; the rest come from the nearest held note, scaled to
			# meet it, with the run note's phases.
			F = _measure(run[k], join, chans).frames
			var hk: int = H.keys()[0]
			for hn: int in H:
				if absi(hn - k) < absi(hk - k):
					hk = hn
			var G: Array = H[hk].frames
			var j: int = F[0].size() - 1
			var ef := 0.0
			var eg := 0.0
			for c in chans.size():
				ef += _energy(F[c][j])
				eg += _energy(G[c][j])
			var g := sqrt(ef / maxf(eg, 1e-30))
			for c in chans.size():
				var last: PackedFloat64Array = F[c][j]
				var K := last.size() / 2
				for i in range(F[c].size(), times.size()):
					var gi: PackedFloat64Array = G[c][i]
					var A := PackedFloat64Array()
					A.resize(2 * K)
					for q in K:
						var mag := Vector2(gi[2 * q], gi[2 * q + 1]).length() * g if 2 * q + 1 < gi.size() else 0.0
						var ph := atan2(last[2 * q + 1], last[2 * q])
						A[2 * q] = mag * cos(ph)
						A[2 * q + 1] = mag * sin(ph)
					F[c].append(A)
		for c in chans.size():
			var frs := []
			for A: PackedFloat64Array in F[c]:
				frs.append(_frame(A))
			zones[c].append({key = k, frames = frs})
	cents.sort()
	var det: float = cents[cents.size() / 2] if cents.size() % 2 == 1 else 0.5 * (cents[cents.size() / 2 - 1] + cents[cents.size() / 2])
	var oscs := []
	var pk := []
	for zc: Array in zones:
		pk.append(float(AKWavetables.build({zones = zc, normalize = false, blend = false}).peak))
	for c in zones.size():
		oscs.append({shape = "table", table = {zones = zones[c], normalize = false, blend = false}, semitones = _tr, cents = det,
			position = POS_W, level = (0.7071 if stereo else 1.0) * pk[c] / pk.max(), pan = [-1.0, 1.0][c] if stereo else 0.0})
	return {oscillators = oscs, filter = {type = "off"},
		amp_env = {attack_s = 0.0, decay_s = 0.0, sustain = 1.0, release_s = maxf(_release_s(), 0.002), curve = "exp"},
		env2 = {attack_s = 0.0, decay_s = POS_TAU, sustain = 0.0, release_s = 1000.0, curve = "exp"},
		env3 = {attack_s = POS_T, decay_s = 0.0, sustain = 1.0, release_s = 1000.0},
		mods = [{source = "env2", dest = "osc.position", amount = -POS_W}, {source = "env3", dest = "osc.position", amount = 1.0 - POS_W}],
		velocity_sens = 1.0, velocity_curve = _velocity_curve(), polyphony = 16, mode = "poly", gain_db = 0.0}


static func _centred(x: PackedFloat32Array) -> PackedFloat32Array:
	var s := 0.0
	for v in x:
		s += v
	var mean := s / maxf(x.size(), 1)
	var o := x.duplicate()
	for i in o.size():
		o[i] -= mean
	return o


## The release: the level's time constant after note-off, on the held notes (median).
func _release_s() -> float:
	var rels := []
	for n: Dictionary in _holds():
		var a := int((n.t + n.len) * _sr)
		var lo := a - 2000
		var hi := mini(a + int(0.6 * _sr), _x.clean.size())
		if lo < 220:
			continue
		# A moving RMS over 441 samples (centred).
		var cum := PackedFloat64Array()
		cum.resize(hi - lo + 442)
		cum[0] = 0.0
		for i in range(hi - lo + 441):
			var j := lo - 220 + i
			var v: float = _x.clean[j] if j < _x.clean.size() else 0.0
			cum[i + 1] = cum[i] + v * v
		var rms := func(i: int) -> float: return sqrt(maxf(cum[i + 441] - cum[i], 0.0) / 441.0)
		var e0: float = rms.call(2000)
		if e0 <= 1e-4:
			continue
		for i in range(2000, hi - lo):
			if rms.call(i) < e0 * exp(-1.0):
				rels.append((i - 2000) / _sr)
				break
	if rels.is_empty():
		return 0.05
	rels.sort()
	return rels[rels.size() / 2] if rels.size() % 2 == 1 else 0.5 * (rels[rels.size() / 2 - 1] + rels[rels.size() / 2])


## The velocity curve: 127 against 64, from the levels of the long pair (scene 3).
func _velocity_curve() -> float:
	var vp := _velocity_pair()
	var lv := []
	for n: Dictionary in vp:
		var s := 0.0
		var a := int((n.t + 0.01) * _sr)
		var b := int((n.t + 0.3) * _sr)
		for i in range(a, b):
			s += _x.clean[i] * _x.clean[i]
		lv.append(sqrt(s / (b - a)))
	var hi: float = lv[0] if vp[0].vel > vp[1].vel else lv[1]
	var lo: float = lv[1] if vp[0].vel > vp[1].vel else lv[0]
	var v0 := minf(vp[0].vel, vp[1].vel)
	var v1 := maxf(vp[0].vel, vp[1].vel)
	if hi <= 0.0 or lo <= 0.0:
		return 1.0
	return clampf(log(lo / hi) / log(v0 / v1), 0.25, 4.0)


# ------------------------------------------------------------------ scoring

## Harmonic features of slots [[orig_t, new_t, dur, note]] in a signal (mid), at the original's or the new times.
func _features(sig: PackedFloat32Array, slots: Array, use_new: bool, tr: float) -> Array:
	var out := []
	for s: Array in slots:
		var t0: float = s[1] if use_new else s[0]
		var a := int(t0 * _sr)
		var res: Array = _m.features(sig, a, int((t0 + float(s[2])) * _sr) - a, _f(float(s[3]) + tr), _sr, 40, 12000.0)
		out.append(res)
	return out


static func _mid(b: AKBuffer) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(b.l.size())
	for i in o.size():
		o[i] = 0.5 * (b.l[i] + b.r[i])
	return o


func _load(fa: Array, fb: Array, slots: Array) -> void:
	_m.clear()
	for i in slots.size():
		var a: Array = fa[i]
		var b: Array = fb[i]
		var k := mini(int(a[3]), int(b[3]))
		var note := float(slots[i][3])
		_m.add_slot(note, _cut_k(a[0], int(a[3]), k), a[1], int(a[2]), _cut_k(b[0], int(b[3]), k), b[1], int(b[2]), k,
			maxf(4.0 * _sr / _f(note + _tr), 512.0) / 2.0 / _sr)


static func _cut_k(h: PackedFloat64Array, k: int, to: int) -> PackedFloat64Array:
	if k == to:
		return h
	var o := PackedFloat64Array()
	for i in h.size() / maxi(k, 1):
		o.append_array(h.slice(i * k, i * k + to))
	return o


## Slots for every note from `notes` (up to the next note, at most 0.9 s past its end), at their own times.
func _slots(notes: Array) -> Array:
	var ts := []
	for n: Dictionary in _x.notes:
		ts.append(n.t)
	ts.sort()
	var out := []
	for e: Dictionary in notes:
		var nxt := _length_s()
		for t: float in ts:
			if t > e.t + 1e-3:
				nxt = t
				break
		out.append([e.t, e.t, minf(e.len + 0.9, nxt - e.t - 0.005), e.note])
	return out


## The harmonic score of a render of the whole file against the original, over every note.
func check(render: AKBuffer) -> float:
	var slots := _slots(_x.notes.filter(func(n: Dictionary) -> bool: return n.len >= 0.2))
	_load(_features(_x.mid, slots, false, _tr), _features(_mid(render), slots, true, _tr), slots)
	return float(_m.score(PackedFloat64Array(), 0, -999.0, 0.0)[0])


## Score by distance from the lite patch's centre (run and holds), at the file's one level: {"0-3": dB, ...}.
func by_distance(render: AKBuffer) -> Dictionary:
	var slots := _slots(_scenes12())
	_load(_features(_x.mid, slots, false, _tr), _features(_mid(render), slots, true, _tr), slots)
	var s: PackedFloat64Array = _m.score(PackedFloat64Array(), 0, -999.0, 0.0)
	var per: PackedFloat64Array = _m.slot_scores(s[1], s[2])
	var out := {}
	for g in [[0, 3], [3, 7], [7, 13], [13, 19], [19, 25], [25, 40]]:
		var sum := 0.0
		var n := 0
		for i in slots.size():
			var d := absi(int(slots[i][3]) - lite_center)
			if d >= g[0] and d < g[1]:
				sum += per[i]
				n += 1
		if n:
			out["%d-%d" % g] = sum / n
	return out


func _scenes12() -> Array:
	var s1: float = _x.scenes[1]
	return _x.notes.filter(func(n: Dictionary) -> bool: return n.len >= 0.2 and n.t < s1 + 12.0)


## The original against itself: scene 3's two identical passes.
func floor_db() -> float:
	var s2: float = _x.scenes[2]
	# The loop plays twice in the scene.
	var half := (float(_x.end_s) - s2) / 2.0
	var evs: Array = _x.notes.filter(func(n: Dictionary) -> bool: return n.t >= s2 and n.t < s2 + half - 1e-3 and n.len >= 0.2)
	var a := _slots(evs)
	var b := a.map(func(s: Array) -> Array: return [s[0] + half, s[1] + half, s[2], s[3]])
	_load(_features(_x.mid, a, false, _tr), _features(_x.mid, b, false, _tr), a)
	return float(_m.score(PackedFloat64Array(), 0, -999.0, 0.0)[0])


## gain_db that plays the patch at the recording's level: the energy over the probe notes (the holds,
## the velocity pair, run notes every 6 semitones), each rendered alone.
func level_db(spec: Dictionary) -> float:
	var s1: float = _x.scenes[1]
	var s2: float = _x.scenes[2]
	var evs := _holds().duplicate()
	evs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	evs += _x.notes.filter(func(n: Dictionary) -> bool: return n.t >= s2 and n.len >= 0.9)
	evs += _run().filter(func(n: Dictionary) -> bool: return n.note % 6 == 0)
	var slots := []
	var rn := []
	var t := 0.2
	var ts := []
	for n: Dictionary in _x.notes:
		ts.append(n.t)
	ts.sort()
	for e: Dictionary in evs:
		var nxt := 1e9
		for x: float in ts:
			if x > e.t + 1e-3:
				nxt = x
				break
		var dur := minf(e.len + 0.9, nxt - e.t - 0.005)
		slots.append([e.t, t, dur, e.note])
		rn.append({time_s = t, note = e.note, velocity = e.vel, length_s = e.len})
		t += dur + 0.1
	var p := spec.duplicate()
	p.gain_db = 0.0
	var y := AKSynth.render_notes(to_patch(p), rn, t + 0.2, int(_sr))
	_load(_features(_x.mid, slots, false, _tr), _features(_mid(y), slots, true, _tr), slots)
	return snappedf(float(_m.score(PackedFloat64Array(), 0, -999.0, 0.0)[1]), 0.01)


# ------------------------------------------------------------------ the lite patch

## The lite patch: the zone nearest lite_center for the whole keyboard, with a fitted low-pass (key
## tracking, env2 and env3 on the cutoff, key -> amp), EQs and a level by key. The zone's frames are
## divided by the curves' response at the centre, so the centre note stays exact.
func lite_patch(full: Dictionary) -> Dictionary:
	var p: Dictionary = full.duplicate(true)
	for o: Dictionary in p.oscillators:
		var zs: Array = o.table.zones
		var z: Dictionary = zs[0]
		for zz: Dictionary in zs:
			if absi(int(zz.key) - lite_center) < absi(int(z.key) - lite_center):
				z = zz
		o.table.zones = [z]
	var center := float(lite_center)
	_step(0.3, "Rendering the one-zone version")
	var raw := AKSynth.render_notes(to_patch(p), _all_notes(), _length_s(), int(_sr))
	var slots := _slots(_scenes12())
	_load(_features(_x.mid, slots, false, _tr), _features(_mid(raw), slots, true, _tr), slots)
	var cents := float(p.oscillators[0].cents)
	var semis := _tr + cents / 100.0
	var lo := 999
	var hi := -999
	for s: Array in slots:
		lo = mini(lo, int(s[3]))
		hi = maxi(hi, int(s[3]))
	var kp := PackedFloat64Array()
	var k := floori(lo / 6.0) * 6
	while k < hi + 6:
		kp.append(k)
		k += 6
	_m.setup(center, semis, kp, lite_eqs, _sr)
	var raw_db := float(_m.score(PackedFloat64Array(), 0, -999.0, 0.0)[0])
	var neq := lite_eqs
	var nk := kp.size()
	var base := PackedFloat64Array()
	base.resize(6 + 7 * neq + nk)
	# Stage 1: the low-pass, from several starts.
	var best := {}
	var tries := 0
	for c0 in [300.0, 1000.0, 3000.0, 8000.0]:
		for e0 in [[0.0, 0.0], [2.0, 0.0], [0.0, -1.0]]:
			if cancelled:
				return {}
			_step(0.33 + 0.27 * tries / 12.0, "Fitting the filter (%d of 12)" % (tries + 1))
			tries += 1
			var x0 := PackedFloat64Array([log(c0), 0.3, log(0.707), 0.1, e0[0], e0[1]])
			var r := AKFit.nelder_mead(func(v: PackedFloat64Array) -> float: return _lite_loss(v, base, 1), x0, 600, 1e-3, 1e-3)
			if best.is_empty() or r.fun < best.fun:
				best = r
	var v: PackedFloat64Array = best.x
	for i in 6:
		base[i] = v[i]
	var filt_db: float = best.fun
	# Stage 2: the EQs, on top of the filter.
	var eq_db := filt_db
	if neq > 0:
		_step(0.6, "Fitting the EQ")
		var pe := PackedFloat64Array()
		for i in neq:
			pe.append_array([log([60.0, 120.0][i % 2]), 0.0, log([400.0, 1500.0][i % 2]), 0.0, log(0.7), log([3000.0, 8000.0][i % 2]), 0.0])
		var r := AKFit.powell(func(x: PackedFloat64Array) -> float: return _eq_loss(x, base), pe, 4000, 1e-3, 1e-4, func() -> bool: return cancelled)
		for i in pe.size():
			base[6 + i] = r.x[i]
		eq_db = r.fun
	if cancelled:
		return {}
	# Stage 3: the level by key, for level changes across the keyboard neither curve follows; it starts
	# from each region's level difference.
	_step(0.75, "Fitting the level by key")
	var st := 3 if neq > 0 else 1
	var sc: PackedFloat64Array = _m.score(base, st, -999.0, 0.0)
	var d0: PackedFloat64Array = _m.slot_levels(base, st, sc[1])
	var kd := PackedFloat64Array()
	for kk in kp:
		var near := []
		for i in slots.size():
			if absf(float(slots[i][3]) - kk) <= 3.0:
				near.append(d0[i])
		near.sort()
		kd.append(0.0 if near.is_empty() else (near[near.size() / 2] if near.size() % 2 == 1 else 0.5 * (near[near.size() / 2 - 1] + near[near.size() / 2])))
	var rk := AKFit.powell(func(x: PackedFloat64Array) -> float: return _kl_loss(x, base, st), kd, 3000, 1e-2, 1e-4, func() -> bool: return cancelled)
	var kl_db: float = rk.fun
	var at_c := AKFit.interp(center, kp, rk.x)
	var key_levels := []
	for i in nk:
		key_levels.append([int(kp[i]), snappedf(rk.x[i] - at_c, 0.01)])
	# Divide the zone's frames by the filter and EQ at the centre (complex, so the centre keeps its
	# waveform too), and keep the level the division changes: the engine scales the table by its peak.
	var fc := exp(v[0])
	var q := exp(v[2])
	var a := v[3]
	var kc := (center - 60.0) / 12.0
	var f0c := _f(center + semis)
	var times := frame_times((p.oscillators[0].table.zones[0].frames as Array).size())
	var eqs := _eq_dicts(base.slice(6, 6 + 7 * neq), neq)
	for o: Dictionary in p.oscillators:
		var z: Dictionary = o.table.zones[0]
		var p0 := float(AKWavetables.build(o.table).peak)
		for j in (z.frames as Array).size():
			var fr: Dictionary = z.frames[j]
			var cut := clampf(fc * pow(2.0, v[1] * (center - 60.0) / 12.0 + v[4] * exp(-times[j] / 0.08) + v[5] * minf(times[j], 1.0)), 20.0, 20000.0)
			var hs: Array = fr.harmonics
			var ps: Array = fr.phases
			for i in hs.size():
				var f := (i + 1) * f0c
				# 1 / (s^2 + s/q + 1), s = j f / fc.
				var s := f / cut
				var hc := Vector2(1.0 - s * s, s / q)
				hc = Vector2(hc.x, -hc.y) / hc.length_squared()
				for e: Dictionary in eqs:
					hc = _cmul(hc, AKFit.eq_response(e, f, _sr))
				var mag := maxf(hc.length(), pow(10.0, -24.0 / 20.0))
				hs[i] = _sig(float(hs[i]) / mag)
				ps[i] = snappedf(fposmod(float(ps[i]) - hc.angle() / TAU, 1.0), 0.0001)
		o.level = float(o.level) * float(AKWavetables.build(o.table).peak) / p0 / maxf(1.0 + a * kc, 1e-3)
	p.filter = {type = "lowpass", cutoff_hz = fc, q = q, slope_db = 12.0}
	p.mods = (p.mods as Array) + [{source = "key", dest = "cutoff", amount = v[1]}, {source = "env2", dest = "cutoff", amount = v[4]},
		{source = "env3", dest = "cutoff", amount = v[5]}]
	if absf(a) > 0.01:
		p.mods.append({source = "key", dest = "amp", amount = a})
	p.effects = eqs + (p.get("effects", []) as Array)
	p.key_levels = key_levels
	_step(0.85, "Setting the lite patch's level")
	p.gain_db = level_db(p)
	p._fit = {one_zone_db = raw_db, filter_db = filt_db, eq_db = eq_db, key_levels_db = kl_db}
	return p


static func _cmul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)


func _lite_loss(v: PackedFloat64Array, base: PackedFloat64Array, stages: int) -> float:
	if not (v[3] > -0.25 and v[3] < 0.6 and v[1] > -1.0 and v[1] < 1.2 and v[0] > log(40.0) and v[0] < log(18000.0)
			and v[2] > log(0.3) and v[2] < log(3.0) and absf(v[4]) < 9.0 and absf(v[5]) < 9.0):
		return 99.0
	var p := base.duplicate()
	for i in 6:
		p[i] = v[i]
	return float(_m.score(p, stages, -999.0, 0.0)[0])


func _eq_loss(x: PackedFloat64Array, base: PackedFloat64Array) -> float:
	for i in x.size() / 7:
		for j in [0, 2, 5]:
			if not (x[i * 7 + j] > log(20.0) and x[i * 7 + j] < log(18000.0)):
				return 99.0
		for j in [1, 3, 6]:
			if absf(x[i * 7 + j]) > 24.0:
				return 99.0
		if not (x[i * 7 + 4] > log(0.2) and x[i * 7 + 4] < log(4.0)):
			return 99.0
	var p := base.duplicate()
	for i in x.size():
		p[6 + i] = x[i]
	return float(_m.score(p, 3, -999.0, 0.0)[0])


func _kl_loss(x: PackedFloat64Array, base: PackedFloat64Array, stages: int) -> float:
	for v in x:
		if absf(v) > 40.0:
			return 99.0
	var p := base.duplicate()
	var at := p.size() - x.size()
	for i in x.size():
		p[at + i] = x[i]
	return float(_m.score(p, stages | 4, -999.0, 0.0)[0])


static func _eq_dicts(pe: PackedFloat64Array, neq: int) -> Array:
	var out := []
	for i in neq:
		out.append({type = "eq", low_hz = exp(pe[i * 7]), low_db = pe[i * 7 + 1], mid_hz = exp(pe[i * 7 + 2]), mid_db = pe[i * 7 + 3],
			mid_q = exp(pe[i * 7 + 4]), high_hz = exp(pe[i * 7 + 5]), high_db = pe[i * 7 + 6]})
	return out


# ------------------------------------------------------------------ patches

## An AKPatch from a spec dictionary (the keys of AKPatch).
static func to_patch(spec: Dictionary) -> AKPatch:
	var p := AKPatch.new()
	for k: String in spec:
		if k.begins_with("_"):
			continue
		var v: Variant = spec[k]
		if k in ["oscillators", "mods", "effects"]:
			var arr: Array[Dictionary] = []
			for d: Dictionary in v:
				arr.append(d)
			p.set(k, arr)
		else:
			p.set(k, v)
	return p


# ------------------------------------------------------------------ the scale MIDI

const PPQ := 480
const SCALE_FILES := ["scale_1_run.mid", "scale_2_holds.mid", "scale_3_velocity.mid"]


## The scale MIDI's three loops, one per scene at 60 BPM: {beats, notes: [[tick, length ticks, key, velocity]]}
## at 480 ticks a beat. 1: a chromatic run from 102 down to 43, a quarter beat each, half a beat apart.
## 2: 1-beat holds on 96, 84, 72, 60 and 48, the same notes repeated four times fast, an octave
## arpeggio. 3: 84 at velocity 127 and then 64 at four lengths, then fast repeats (16 beats, so it plays
## twice in its 8-bar scene).
static func scale_loops() -> Array:
	var run := []
	for i in 60:
		run.append([960 + 240 * i, 120, 102 - i, 127])
	var holds := []
	for i in 5:
		holds.append([480 + 960 * i, 480, 96 - 12 * i, 127])
	for i in 5:
		for j in 4:
			holds.append([5760 + 960 * i + 120 * j, 120, 96 - 12 * i, 127])
	var arp := [48, 48, 55, 55, 60, 60, 67, 67, 72, 72, 79, 79, 84, 84, 91, 91, 96, 96]
	for i in arp.size():
		holds.append([10560 + 120 * i, 120, arp[i], 127])
	var vel := []
	for e in [[0, 120], [120, 120], [240, 120], [360, 120], [600, 240], [960, 360], [1440, 480]]:
		vel.append([e[0], e[1], 84, 127])
	for e in [[2160, 120], [2280, 120], [2520, 240], [2880, 360], [3360, 480]]:
		vel.append([e[0], e[1], 84, 64])
	for t in [4020, 4260, 4500, 4680, 4860, 5040, 5220, 5400, 5580, 5700, 5820, 5940, 6060, 6180, 6300, 6360, 6420, 6480, 6540, 6600, 6660, 6720]:
		vel.append([t, 60, 84, 127])
	for e in [[6840, 120], [7020, 180], [7260, 240]]:
		vel.append([e[0], e[1], 84, 127])
	return [{beats = 32, notes = run}, {beats = 32, notes = holds}, {beats = 16, notes = vel}]


## A scale loop as a Standard MIDI File (format 0, 60 BPM, the end of track at the loop's length).
static func scale_midi(loop: int) -> PackedByteArray:
	var lp: Dictionary = scale_loops()[loop]
	var ev := []
	for n: Array in lp.notes:
		ev.append([n[0], 1, n[2], n[3]])
		ev.append([n[0] + n[1], 0, n[2], 0])
	# Note-offs before note-ons at the same tick.
	ev.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var trk := PackedByteArray([0x00, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40])   # 1,000,000 us a beat
	var last := 0
	for e: Array in ev:
		trk.append_array(_vlq(e[0] - last))
		last = e[0]
		trk.append_array([0x90 if e[1] == 1 else 0x80, e[2], e[3] if e[1] == 1 else 64])
	trk.append_array(_vlq(int(lp.beats) * PPQ - last))
	trk.append_array([0xFF, 0x2F, 0x00])
	var out := "MThd".to_ascii_buffer()
	out.append_array([0, 0, 0, 6, 0, 0, 0, 1, PPQ >> 8, PPQ & 0xFF])
	out.append_array("MTrk".to_ascii_buffer())
	out.append_array([(trk.size() >> 24) & 0xFF, (trk.size() >> 16) & 0xFF, (trk.size() >> 8) & 0xFF, trk.size() & 0xFF])
	out.append_array(trk)
	return out


## Write the three loops into a folder (scale_1_run.mid, ...); returns their paths.
static func save_scale_midi(dir: String) -> Array:
	DirAccess.make_dir_recursive_absolute(dir)
	var out := []
	for i in 3:
		var path := dir.path_join(SCALE_FILES[i])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return []
		f.store_buffer(scale_midi(i))
		f.close()
		out.append(path)
	return out


static func _vlq(v: int) -> PackedByteArray:
	var bytes := [v & 0x7F]
	v >>= 7
	while v > 0:
		bytes.push_front((v & 0x7F) | 0x80)
		v >>= 7
	return PackedByteArray(bytes)
