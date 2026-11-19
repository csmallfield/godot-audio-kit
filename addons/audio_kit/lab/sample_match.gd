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
## Two detuned layers (sample-playback synths often stack two copies of a wave a few cents apart, so each
## harmonic beats at k x the detune): 0 tries the patch with and without them when they're found and
## keeps the better, 1 always uses them when found, -1 never looks.
var layers := 0
## A vibrato (a pitch wobble at one rate on every note, from 2.5 to 12 Hz, as an LFO on pitch, free-running
## when it runs on through the file): 0 uses it when found unless it costs the full patch over 0.3 dB, 1
## always uses it when found, -1 never looks.
var vibrato := 0
## How long the table keeps sweeping through the note (s); 0 picks it: 1 s for an Auxy export (its holds
## are 1 s), the held notes' length for a plain WAV (1 to 8 s), so a slow sweep or swell isn't frozen.
var sweep_s := 0.0
## EQs in the lite patch (each a low shelf, a peak and a high shelf).
var lite_eqs := 2

const HOP := 441
# Where the table position sits through the note: W x (1 - e^(-t/TAU)) (env2, detail in the attack) +
# (1 - W) x t/T (env3, even later; T is the sweep, `sweep_s`). Frames sit where it crosses i/(frames - 1).
const POS_W := 0.5
const POS_TAU := 0.08
const POS_T := 1.0
const JOIN_S := 0.2

var _m: Object
var _sr := 44100.0
var _x := {}          # the export: {l, r, mid (raw), clean (high-passed mid), notes, name, scenes}
var _tr := 0.0
var _frames := 16
var _pos_t := POS_T
var _lay := {}         # the layers in use (find_layers), or {} for one voice
var _vib := {}         # the vibrato in use (find_vibrato), or {}


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
	return _match(read_export(path))


## A plain WAV instead of an export: separate held notes with silence between them (a sampled
## multisample: one patch, a few notes), found from the audio. `first_note` is the first note's MIDI
## key and `step` the semitones from each note to the next. There is no velocity pair or repeated
## pass, so the velocity curve stays linear and `report.floor_db` is NAN. Set `lite_center` to one
## of the notes first (by default the middle one is used when 72 isn't among them). `hold_s` > 0 gives
## every note that length instead of finding its key-up (for a pad whose own decay looks like a release).
func run_wav(path: String, first_note: int, step: int, hold_s := 0.0) -> Dictionary:
	var out := {ok = false, error = ""}
	if not available():
		out.error = "matching needs the native core (AKMatch)"
		return out
	_m = ClassDB.instantiate(&"AKMatch")
	_step(0.0, "Reading %s" % path.get_file())
	return _match(read_wav_notes(path, first_note, step, 0.8, hold_s))


func _match(rd: Dictionary) -> Dictionary:
	var out := {ok = false, error = ""}
	if not rd.ok:
		out.error = rd.error
		return out
	_x = rd
	_sr = float(rd.rate)
	var why := _check_layout()
	if why != "":
		out.error = why
		return out
	if _plain() and not _holds().any(func(n: Dictionary) -> bool: return n.note == lite_center):
		var hs := _holds()
		lite_center = int(hs[hs.size() / 2].note)
	_pos_t = sweep_s if sweep_s > 0.0 else _auto_sweep()
	if _m.has_method(&"set_env3_s"):
		_m.set_env3_s(_pos_t)
	elif _pos_t != POS_T:
		_pos_t = POS_T  # an older native core scores env3 over 1 s only
	_step(0.03, "Finding the pitch")
	_tr = transposition()
	var all := _all_notes()
	var found := {}
	if layers >= 0:
		_step(0.03, "Looking for detuned layers")
		found = find_layers()
	var lay_opts := [{}]
	if not found.is_empty():
		lay_opts = [found] if layers > 0 else [{}, found]
	var full_spec := {}
	var full_db := 0.0
	var r_full: AKBuffer
	var used := {}
	for nf in ([frames] if frames > 0 else [16, 24]):
		for lay: Dictionary in lay_opts:
			_frames = nf
			_lay = lay
			var spec := full_patch()
			if cancelled:
				return _stopped(out)
			_step(0.25, "Setting the level (%d frames%s)" % [nf, ", two layers" if not lay.is_empty() else ""])
			spec.gain_db = level_db(spec)
			var r := AKSynth.render_notes(to_patch(spec), all, _length_s(), int(_sr))
			var db := check(r)
			if full_spec.is_empty() or db < full_db - 0.5:
				full_spec = spec
				full_db = db
				r_full = r
				used = lay
	_lay = used
	var vib := {}
	if vibrato >= 0:
		_step(0.6, "Looking for a vibrato")
		vib = find_vibrato()
	_vib = {}
	if not vib.is_empty():
		var spec := _with_vibrato(full_spec, vib)
		var r := AKSynth.render_notes(to_patch(spec), all, _length_s(), int(_sr))
		var db := check(r)
		if vibrato > 0 or db <= full_db + 0.3:
			full_spec = spec
			full_db = db
			r_full = r
			_vib = vib
	var lite_spec := lite_patch(full_spec)
	if cancelled:
		return _stopped(out)
	_step(0.9, "Checking both against the recording")
	var r_lite := AKSynth.render_notes(to_patch(lite_spec), all, _length_s(), int(_sr))
	var report := {transpose = _tr, stereo = (full_spec.oscillators as Array).any(func(o: Dictionary) -> bool: return float(o.get("pan", 0.0)) != 0.0),
		zones = (full_spec.oscillators[0].table.zones as Array).size(), frames = (full_spec.oscillators[0].table.zones[0].frames as Array).size(),
		full_db = full_db, lite_db = check(r_lite), floor_db = floor_db(),
		lite_by_distance = by_distance(r_lite), full_by_distance = by_distance(r_full),
		layers = used, layers_found = found, vibrato = _vib, vibrato_found = vib,
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
	var fl := "n/a" if is_nan(float(report.floor_db)) else "%.1f dB" % report.floor_db
	return "Full %.1f dB, lite %.1f dB (the original against itself: %s). %s, %d zones of %d frames, transposed %+d." % [
		report.full_db, report.lite_db, fl, "Stereo" if report.stereo else "Mono", report.zones, report.frames, int(report.transpose)]


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


## A plain WAV as the same data as `read_export`, its notes found from the audio, keyed first_note,
## first_note + step, ... in order, with no scenes. A note starts where the level climbs past 25 dB
## under the file's loudest (and 30 dB over its floor) and ends at the key-up: the first sharp drop
## (12 dB inside 50 ms) at least 0.2 s in, or where the level starts to fall at least 3x as fast as it
## was (a smooth release). A sound that only fades (no key-up) ends where it gets back within 10 dB of
## the floor. `hold_s` > 0 sets every note's length instead.
static func read_wav_notes(path: String, first_note: int, step: int, velocity := 0.8, hold_s := 0.0) -> Dictionary:
	var out := {ok = false, error = ""}
	if not FileAccess.file_exists(path):
		out.error = "no file at %s" % path
		return out
	var wav := _read_wav(FileAccess.get_file_as_bytes(path))
	if wav.error != "":
		out.error = wav.error
		return out
	var sr := float(wav.rate)
	var mid := PackedFloat32Array()
	mid.resize(wav.l.size())
	for i in mid.size():
		mid[i] = 0.5 * (wav.l[i] + wav.r[i])
	var m: Object = ClassDB.instantiate(&"AKMatch")
	var clean: PackedFloat32Array = m.highpass(mid, sr, 15.0)
	# The level every 10 ms, of the raw signal less its DC (the zero-phase high-pass rings ahead of an
	# attack, which would put each note's start early).
	var dc := 0.0
	for v in mid:
		dc += v
	dc /= maxf(mid.size(), 1)
	var hop := int(sr / 100.0)
	var db := PackedFloat64Array()
	for a in range(0, mid.size() - hop, hop):
		var s := 0.0
		for i in range(a, a + hop):
			s += (mid[i] - dc) * (mid[i] - dc)
		db.append(_db(sqrt(s / hop)))
	var sorted := db.duplicate()
	sorted.sort()
	if sorted.is_empty():
		out.error = "%s is empty" % path.get_file()
		return out
	var floor_lv: float = sorted[sorted.size() / 10]
	var peak: float = sorted[sorted.size() - 1]
	# A note crosses 25 dB under the file's loudest (release tails and their bumps stay under it).
	var thr := maxf(floor_lv + 30.0, peak - 25.0)
	var notes := []
	var i := 0
	var prev_off := -1
	while i < db.size():
		if not (db[i] > thr and (i == 0 or db[i - 1] <= thr)):
			i += 1
			continue
		# Back up to where the rise starts (a slow attack too, up to 2 s, not into the last note).
		var on := i
		while on > maxi(maxi(i - 200, prev_off + 1), 0) and db[on - 1] < db[on] + 1.0 and db[on - 1] > floor_lv + 20.0:
			on -= 1
		# The key-up: a sharp drop anywhere in the note first, else a smooth one, else the fade's end.
		var end := db.size() - 5
		for j in range(on + 20, db.size() - 5):
			if db[j] < floor_lv + 10.0:
				end = j
				break
		var off := -1
		for j in range(on + 20, end):
			# A key-up stays down: the next 150 ms average 10 dB under the level before it (a tremolo dip
			# comes back).
			var after := 0.0
			var na := 0
			for q in range(j + 5, mini(j + 20, db.size())):
				after += db[q]
				na += 1
			if db[j + 5] < db[j] - 12.0 and after / maxi(na, 1) < db[j] - 10.0:
				# The steepest 10 ms inside the drop.
				var best := j
				for q in range(j, j + 5):
					if db[q] - db[q + 1] > db[best] - db[best + 1]:
						best = q
				off = best
				break
		# A smooth key-up (a release with no sudden drop): over the next 100 ms the level falls at least
		# 4 dB and 3x as fast as over the 300 ms before (a decaying note keeps its pace), and over the next
		# 0.5 s it never comes back within 3 dB nor climbs 3 dB over where the fall got to (a swell's dip does).
		if off < 0:
			for j in range(on + 30, mini(end, db.size() - 60)):
				var fall := db[j] - db[j + 10]
				var before := (db[j - 30] - db[j]) / 3.0
				if fall < 4.0 or fall < 3.0 * maxf(before, 0.7):
					continue
				var back := -INF
				for q in range(j + 10, j + 60):
					back = maxf(back, db[q])
				if back < db[j] - 3.0 and back < db[j + 10] + 3.0:
					# Forward to where the fall starts: the last frame within 1 dB of this one.
					var k := j
					while k < j + 10 and db[k + 1] > db[j] - 1.0:
						k += 1
					off = k
					break
		if off < 0:
			off = end
		if hold_s > 0.0:
			off = mini(on + roundi(hold_s * 100.0), db.size() - 1)
		notes.append({t = on * hop / sr, len = (off - on) * hop / sr, note = first_note + step * notes.size(), vel = velocity})
		# The next note can start once this one has stayed 6 dB under the threshold for 0.3 s (so a bump in
		# its release tail isn't a note).
		prev_off = off
		i = off + 1
		var quiet := 0
		while i < db.size() and quiet < 30:
			quiet = quiet + 1 if db[i] < thr - 6.0 else 0
			i += 1
	if notes.is_empty():
		out.error = "%s: no notes found (nothing rises 30 dB over the floor)" % path.get_file()
		return out
	out.merge({ok = true, name = path.get_file().get_basename(), rate = wav.rate, l = wav.l, r = wav.r, mid = mid,
		clean = clean, notes = notes, scenes = [], end_s = mid.size() / sr}, true)
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
	if _plain():
		if _holds().is_empty():
			return "no note is held for 1 s or more (%d notes found)" % _x.notes.size()
		return ""
	if _x.scenes.size() < 3:
		return "expected the scale MIDI's three scenes, found %d (docs/sample_matching.md)" % _x.scenes.size()
	if _run().size() < 24:
		return "scene 1 should be a chromatic run of short notes; found %d notes" % _run().size()
	if _holds().size() < 3:
		return "scene 2 should start with 1 s holds; found %d" % _holds().size()
	if _velocity_pair().size() < 2:
		return "scene 3 should hold a note at two velocities"
	return ""


## A plain WAV (run_wav): every note is held, there are no scenes.
func _plain() -> bool:
	return (_x.scenes as Array).is_empty()


func _run() -> Array:
	if _plain():
		return _x.notes
	return _x.notes.filter(func(n: Dictionary) -> bool: return n.t < _x.scenes[1])


func _holds() -> Array:
	if _plain():
		var ph: Array = _x.notes.filter(func(n: Dictionary) -> bool: return n.len >= 0.9)
		ph.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.note < b.note)
		return ph
	var s1: float = _x.scenes[1]
	var h: Array = _x.notes.filter(func(n: Dictionary) -> bool: return n.t >= s1 and n.t < s1 + 12.0 and n.len >= 0.9)
	h.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.note < b.note)
	return h


func _velocity_pair() -> Array:
	if _plain():
		return []
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
	for i in range(0, run.size(), 5 if run.size() > 15 else 1):
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
## `t_end` is the sweep's length (`sweep_s`); the last frame sits 3% before it.
static func frame_times(count: int, t_end := POS_T) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in count:
		var target := float(i) / maxf(count - 1, 1)
		# Position rises steadily, so bisect for the time it reaches the target.
		var lo := 0.0
		var hi := t_end
		for _it in 50:
			var mid := 0.5 * (lo + hi)
			if _pos(mid, t_end) < target:
				lo = mid
			else:
				hi = mid
		out.append(minf(0.5 * (lo + hi), 0.97 * t_end) if i == count - 1 else 0.5 * (lo + hi))
	return out


static func _pos(t: float, t_end := POS_T) -> float:
	return POS_W * (1.0 - exp(-t / POS_TAU)) + (1.0 - POS_W) * minf(t / t_end, 1.0)


## The sweep for this recording: 1 s for an export; for a plain WAV the median held note, less 50 ms
## (so the last frame is before the key-up), 1 to 8 s.
func _auto_sweep() -> float:
	if not _plain():
		return POS_T
	var ls := []
	for n: Dictionary in _holds():
		ls.append(float(n.len))
	ls.sort()
	return clampf(float(ls[ls.size() / 2]) - 0.05, POS_T, 8.0) if not ls.is_empty() else POS_T


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


## Two detuned layers, from the held notes: {cents (between them), score (the share of the harmonics'
## movement the beating explains), notes: {key: {r, phase, centre}}}, or {} when the sound isn't layered
## that way. Each harmonic's power through the held part, every 10 ms, is fitted with a slow line plus a
## beat at k x the detune; the detune is the one (1 to 40 cents) that explains the most, the same on most
## notes. Then per note, each harmonic as the two layers' complex amplitudes (least squares): r is the
## sharp layer's level against the flat one, phase its start against the flat one's (harmonic k turned by
## k x phase cycles), centre the ratio of the layers' middle pitch to the measured one.
func find_layers() -> Dictionary:
	var notes := []
	for h: Dictionary in _holds():
		var a := int(h.t * _sr)
		var fg := _f(h.note + _tr)
		var s0 := a + int(0.03 * _sr)
		var f0 := _refine(s0, a + int(minf(h.len, 0.9) * _sr) - s0, fg)
		var K := int(minf(16.0, 18000.0 / f0))
		var ts := PackedFloat64Array()
		var t := 0.3
		while t < float(h.len) - 0.05:
			ts.append(t)
			t += 0.01
		if ts.size() < 60:
			continue
		var P := []   # [k] -> power through the note
		var C := []   # [k] -> complex values (re, im) through the note
		for k in K:
			P.append(PackedFloat64Array())
			C.append(PackedFloat64Array())
		for tt in ts:
			var A := _cycle(_x.clean, a, f0, tt, K)
			for k in K:
				P[k].append(A[2 * k] * A[2 * k] + A[2 * k + 1] * A[2 * k + 1])
				C[k].append(A[2 * k])
				C[k].append(A[2 * k + 1])
		notes.append({note = int(h.note), f0 = f0, ts = ts, P = P, C = C, K = K})
	if notes.is_empty():
		return {}
	var best := []
	for nd: Dictionary in notes:
		var top := [0.0, 0.0]
		var c := 1.0
		while c <= 40.0:
			var sc: float = _beat_fit(nd, c).score
			if sc > top[0]:
				top = [sc, c]
			c += 0.25
		var c2: float = top[1] - 0.25
		var hi: float = top[1] + 0.25
		while c2 <= hi:
			var sc2: float = _beat_fit(nd, c2).score
			if sc2 > top[0]:
				top = [sc2, c2]
			c2 += 0.02
		best.append(top)
	var cs := []
	for b: Array in best:
		cs.append(b[1])
	cs.sort()
	var cm: float = cs[cs.size() / 2]
	var ok := 0
	for b: Array in best:
		if b[0] >= 0.5 and absf(b[1] - cm) <= 0.15 * cm:
			ok += 1
	if ok * 2 <= best.size() or cm <= 0.0:
		return {}
	var score := 0.0
	var per := {}
	for nd: Dictionary in notes:
		score += float(_beat_fit(nd, cm).score) / notes.size()
		per[nd.note] = _layer_note(nd, cm)
		# Two layers within 20 dB of each other, or it isn't this.
		if float(per[nd.note].r) < 0.1 or float(per[nd.note].r) > 10.0:
			return {}
	return {cents = snappedf(cm, 0.01), score = snappedf(score, 0.01), notes = per}


## One note's two layers at `cents` apart: {r, phase, centre}. The middle pitch is searched within 3/4
## of the layers' spacing of the measured one (which leans to the louder layer); at each, every harmonic
## that beats at least 1.5 times is solved for the two layers' complex amplitudes, and the middle that
## explains the most is kept.
func _layer_note(nd: Dictionary, cents: float) -> Dictionary:
	var f0: float = nd.f0
	var df := f0 * (pow(2.0, cents / 2400.0) - pow(2.0, -cents / 2400.0))
	var ts: PackedFloat64Array = nd.ts
	var T := ts[ts.size() - 1] - ts[0]
	var top := {}
	var te := -1.0
	for ei in 31:
		var eps := df * (ei - 15) / 20.0
		var res := []
		var energy := 0.0
		for k in int(nd.K):
			var kk := float(k + 1)
			var nu := kk * df
			if nu * T < 1.5 or nu > 15.0:
				continue
			var y: PackedFloat64Array = nd.C[k]
			# u = e^(i 2 pi (k eps - nu/2) t), v = e^(i 2 pi (k eps + nu/2) t); solve [N S; S* N] [al; be] = [u*H; v*H].
			var N := float(ts.size())
			var sre := 0.0
			var sim := 0.0
			var cure := 0.0
			var cuim := 0.0
			var cvre := 0.0
			var cvim := 0.0
			for i in ts.size():
				var tt := ts[i]
				var pu := TAU * (kk * eps - 0.5 * nu) * tt
				var pv := TAU * (kk * eps + 0.5 * nu) * tt
				var hre := y[2 * i]
				var him := y[2 * i + 1]
				# conj(u) v = e^(i 2 pi nu t)
				sre += cos(TAU * nu * tt)
				sim += sin(TAU * nu * tt)
				# conj(u) H
				cure += hre * cos(pu) + him * sin(pu)
				cuim += him * cos(pu) - hre * sin(pu)
				cvre += hre * cos(pv) + him * sin(pv)
				cvim += him * cos(pv) - hre * sin(pv)
			var det := N * N - (sre * sre + sim * sim)
			if det <= 1e-9:
				continue
			# al = (N cu - S cv) / det, be = (N cv - conj(S) cu) / det
			var are := (N * cure - (sre * cvre - sim * cvim)) / det
			var aim := (N * cuim - (sre * cvim + sim * cvre)) / det
			var bre := (N * cvre - (sre * cure + sim * cuim)) / det
			var bim := (N * cvim - (sre * cuim - sim * cure)) / det
			var al := Vector2(are, aim)
			var be := Vector2(bre, bim)
			# What the pair explains: projection energy, al* cu + be* cv (real part).
			energy += are * cure + aim * cuim + bre * cvre + bim * cvim
			res.append([al.length() * be.length(), be.length() / maxf(al.length(), 1e-30), be.angle() - al.angle(), kk])
		if res.size() > 0 and energy > te:
			te = energy
			top = {eps = eps, res = res}
	if top.is_empty():
		return {r = 1.0, phase = 0.0, centre = 1.0}
	var res2: Array = top.res
	var ph := 0.0
	var pbest := -INF
	for i in 1000:
		var phi := i / 1000.0
		var v := 0.0
		for e: Array in res2:
			v += e[0] * cos(e[2] - TAU * e[3] * phi)
		if v > pbest:
			pbest = v
			ph = phi
	var rs := res2.duplicate()
	rs.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
	var wsum := 0.0
	for e: Array in rs:
		wsum += e[0]
	var acc := 0.0
	var r := 1.0
	for e: Array in rs:
		acc += e[0]
		if acc >= 0.5 * wsum:
			r = e[1]
			break
	return {r = snappedf(r, 0.001), phase = snappedf(ph, 0.001), centre = (f0 + float(top.eps)) / f0}


## One note's harmonics' power fitted with a slow line plus a beat at k x the detune of `cents`:
## {score (beat variance explained, weighted by each harmonic's beat), harm: [[weight 2ab, b/a, beat
## phase, k], ...]}. Only harmonics that beat at least 1.5 times through the held part (and under 15 Hz).
func _beat_fit(nd: Dictionary, cents: float) -> Dictionary:
	var f0: float = nd.f0
	var df := f0 * (pow(2.0, cents / 1200.0) - 1.0)
	var ts: PackedFloat64Array = nd.ts
	var T := ts[ts.size() - 1] - ts[0]
	var num := 0.0
	var den := 0.0
	var harm := []
	for k in int(nd.K):
		var nu := (k + 1) * df
		if nu * T < 1.5 or nu > 15.0:
			continue
		var y: PackedFloat64Array = nd.P[k]
		# Least squares on [1, t, cos, sin]: the normal equations, 4 x 4.
		var M := []
		for _i in 4:
			M.append([0.0, 0.0, 0.0, 0.0, 0.0])
		for i in ts.size():
			var tt := ts[i] - ts[0]
			var w := TAU * nu * ts[i]
			var row := [1.0, tt, cos(w), sin(w)]
			for p in 4:
				for q in 4:
					M[p][q] += row[p] * row[q]
				M[p][4] += row[p] * y[i]
		var x := _solve4(M)
		if x.is_empty():
			continue
		var tot := 0.0
		var res := 0.0
		var lin := 0.0
		for i in ts.size():
			var tt := ts[i] - ts[0]
			var w := TAU * nu * ts[i]
			var slow: float = x[0] + x[1] * tt
			var fit: float = slow + x[2] * cos(w) + x[3] * sin(w)
			tot += pow(y[i] - slow, 2.0)
			res += pow(y[i] - fit, 2.0)
			lin += slow
		lin /= ts.size()
		var amp := sqrt(x[2] * x[2] + x[3] * x[3])   # 2ab
		if lin <= 0.0 or tot <= 0.0:
			continue
		num += amp * (1.0 - res / tot)
		den += amp
		# a^2 + b^2 = lin, 2ab = amp.
		var q := sqrt(maxf(lin * lin - amp * amp, 0.0))
		var a2 := 0.5 * (lin + q)
		var b2 := 0.5 * (lin - q)
		harm.append([amp, sqrt(b2 / maxf(a2, 1e-30)), atan2(-x[3], x[2]), k + 1])
	return {score = num / den if den > 0.0 else 0.0, harm = harm}


static func _solve4(M: Array) -> Array:
	var A := M.duplicate(true)
	for c in 4:
		var piv := c
		for r in range(c + 1, 4):
			if absf(A[r][c]) > absf(A[piv][c]):
				piv = r
		if absf(A[piv][c]) < 1e-30:
			return []
		var tmp: Array = A[c]
		A[c] = A[piv]
		A[piv] = tmp
		for r in 4:
			if r != c:
				var f: float = A[r][c] / A[c][c]
				for q in range(c, 5):
					A[r][q] -= f * A[c][q]
	return [A[0][4] / A[0][0], A[1][4] / A[1][1], A[2][4] / A[2][2], A[3][4] / A[3][3]]


## As _measure, for a sound of two detuned layers (_lay): the frames of the flat layer alone. At each frame
## time each harmonic is solved over a window of half a beat either side (least squares): the measured
## value against the two layers' sum, the flat one at -cents/2 from the note's middle pitch, the sharp one
## at +cents/2 with the note's level and start phase. The analysis window's response to each layer's
## offset is the same (Hann, symmetric), so it scales both alike.
func _measure_layered(n: Dictionary, ts: PackedFloat64Array, chans: Array) -> Dictionary:
	var a := int(n.t * _sr)
	var fg := _f(n.note + _tr)
	var s0 := a + int(0.03 * _sr)
	var ln := _lay_note(int(n.note))
	var f0 := _refine(s0, a + int(minf(n.len, 0.9) * _sr) - s0, fg) * float(ln.centre)
	var K := int(minf(511.0, 18000.0 / f0))
	var lc := float(_lay.cents)
	var r := float(ln.r)
	var phi := float(ln.phase)
	var df := f0 * (pow(2.0, lc / 2400.0) - pow(2.0, -lc / 2400.0))
	var Wn := maxf(2.0 / f0, 0.006)
	var end_t := float(n.len) + 0.05
	# Dense measurements every 5 ms over the note, per channel: [c][i] -> (re, im per harmonic).
	var dt := 0.005
	var dts := PackedFloat64Array()
	var t := 1.0 / f0
	while t < end_t:
		dts.append(t)
		t += dt
	var D := []
	for c in chans.size():
		var rows := []
		for tt in dts:
			rows.append(_cycle(chans[c], a, f0, tt, K))
		D.append(rows)
	var out := []
	for _c in chans:
		out.append([])
	for tj in ts:
		var tc := clampf(tj, dts[0], dts[dts.size() - 1])
		for c in chans.size():
			var V := PackedFloat64Array()
			V.resize(2 * K)
			for k in K:
				var kk := float(k + 1)
				var nu := kk * df
				var hw := clampf(0.5 / maxf(nu, 1e-6), 0.02, 0.4)
				# The window's response to an offset of nu / 2 (Hann: sinc / (1 - x^2)).
				var xw := 0.5 * nu * Wn
				var wr := 1.0
				if absf(xw - 1.0) < 1e-6:
					wr = 0.5
				elif xw > 1e-9:
					wr = sin(PI * xw) / (PI * xw) / (1.0 - xw * xw)
				var nre := 0.0
				var nim := 0.0
				var gg := 0.0
				var i0 := maxi(0, int((tc - hw - dts[0]) / dt))
				var i1 := mini(dts.size() - 1, int((tc + hw - dts[0]) / dt))
				for i in range(i0, i1 + 1):
					var ti := dts[i]
					# G = e^(-i pi nu t) + r e^(i (2 pi k phi + pi nu t)), times the window's response.
					var g1 := -PI * nu * ti
					var g2 := TAU * kk * phi + PI * nu * ti
					var gre := wr * (cos(g1) + r * cos(g2))
					var gim := wr * (sin(g1) + r * sin(g2))
					var hre: float = D[c][i][2 * k]
					var him: float = D[c][i][2 * k + 1]
					# H x conj(G)
					nre += hre * gre + him * gim
					nim += him * gre - hre * gim
					gg += gre * gre + gim * gim
				if gg > 1e-20:
					V[2 * k] = nre / gg
					V[2 * k + 1] = nim / gg
			out[c].append(V)
	# Turn each frame so the first channel's fundamental has phase 0, as _measure does; the sharp layer's
	# table is made from these frames, so the two keep their relation.
	for j in ts.size():
		var ang := atan2(out[0][j][1], out[0][j][0])
		for c in chans.size():
			var A: PackedFloat64Array = out[c][j]
			for k in K:
				var th := -(k + 1) * ang
				var re := A[2 * k]
				var im := A[2 * k + 1]
				A[2 * k] = re * cos(th) - im * sin(th)
				A[2 * k + 1] = re * sin(th) + im * cos(th)
			out[c][j] = A
	return {f0 = f0, fg = fg, frames = out}


## The second layer's zones: each zone's frames times its level against the first and turned by its start
## phase (harmonic k by k x phase cycles), from the nearest held note's fit.
func _layer_zones(zs: Array) -> Array:
	var out := []
	for z: Dictionary in zs:
		var ln := _lay_note(int(z.key))
		var r := float(ln.r)
		var ph := float(ln.phase)
		var frs := []
		for fr: Dictionary in z.frames:
			var hs := []
			var ps := []
			for i in (fr.harmonics as Array).size():
				hs.append(_sig(float(fr.harmonics[i]) * r))
				ps.append(snappedf(fposmod(float(fr.phases[i]) + (i + 1) * ph, 1.0), 0.0001))
			frs.append({harmonics = hs, phases = ps})
		out.append({key = z.key, frames = frs})
	return out


## The layer fit of the held note nearest `key`: {r, phase, centre}.
func _lay_note(key: int) -> Dictionary:
	var best := {}
	var bd := 1 << 30
	for nk: int in _lay.notes:
		if absi(nk - key) < bd:
			bd = absi(nk - key)
			best = _lay.notes[nk]
	return best


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
	var times := frame_times(_frames, _pos_t)
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
		H[h.note] = _measure(h, times, chans) if _lay.is_empty() else _measure_layered(h, times, chans)
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
			F = (_measure(run[k], join, chans) if _lay.is_empty() else _measure_layered(run[k], join, chans)).frames
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
		var o := {shape = "table", table = {zones = zones[c], normalize = false, blend = false}, semitones = _tr, cents = det,
			position = POS_W, level = (0.7071 if stereo else 1.0) * pk[c] / pk.max(), pan = [-1.0, 1.0][c] if stereo else 0.0}
		if _lay.is_empty():
			oscs.append(o)
		else:
			# The two layers: the flat one plays the table; the sharp one a copy whose zones carry their own
			# level and start phase (they change across the keyboard, from one root sample to the next).
			var lc := float(_lay.cents)
			var b := o.duplicate()
			o.cents = det - lc / 2.0
			b.cents = det + lc / 2.0
			b.table = {zones = _layer_zones(zones[c]), normalize = false, blend = false}
			b.level = float(o.level) * float(AKWavetables.build(b.table).peak) / float(AKWavetables.build(o.table).peak)
			oscs.append(o)
			oscs.append(b)
	return {oscillators = oscs, filter = {type = "off"},
		amp_env = _release_env(),
		env2 = {attack_s = 0.0, decay_s = POS_TAU, sustain = 0.0, release_s = 1000.0, curve = "exp"},
		env3 = {attack_s = _pos_t, decay_s = 0.0, sustain = 1.0, release_s = 1000.0},
		mods = [{source = "env2", dest = "osc.position", amount = -POS_W}, {source = "env3", dest = "osc.position", amount = 1.0 - POS_W}],
		velocity_sens = 1.0, velocity_curve = _velocity_curve(), polyphony = 16, mode = "poly", gain_db = 0.0}


## The spec with a vibrato (find_vibrato): LFO 1, a sine at its rate and phase (free-running or from each
## note-on), on pitch by its depth.
static func _with_vibrato(spec: Dictionary, vib: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	out.lfo1 = {shape = "sine", rate_hz = vib.rate_hz, phase = vib.phase, free = vib.free, delay_s = 0.0}
	out.mods = (out.mods as Array) + [{source = "lfo1", dest = "pitch", amount = snappedf(float(vib.cents) / 100.0, 0.0001)}]
	return out


## A vibrato: a pitch wobble at one rate on every held note, {rate_hz, cents (its depth either way), phase
## (cycles, where the engine's sine LFO starts), free (true: it runs on through the file, as a hardware LFO
## does, rather than starting again at each note-on), x (how far it stands above the rest of the scan)},
## or {} when there's none. Each held note's pitch every 5 ms through the held part (from its harmonics'
## phase steps, by their level), less a slow curve; then each rate from 2.5 to 12 Hz is fitted over all
## the notes at once, in file time and in time from each note-on. Taken when the best stands 6 times above
## the scan's median, is at least 1 cent deep and
## isn't at either end of the scan. Detuned layers beat at rates that follow the note, so
## they don't line up across notes the way an LFO does.
func find_vibrato() -> Dictionary:
	var dt := 0.005
	var curves := []   # [note-on (s), first time from note-on (s), cents every dt]
	for h: Dictionary in _holds():
		if float(h.len) < 0.8:
			continue
		var a := int(h.t * _sr)
		var fg := _f(h.note + _tr)
		var s0 := a + int(0.03 * _sr)
		var f0 := _refine(s0, a + int(minf(h.len, 0.9) * _sr) - s0, fg)
		var K := clampi(int(4000.0 / f0), 1, 16)
		var cs := PackedFloat64Array()
		var prev := PackedFloat64Array()
		var t := 0.3
		while t < float(h.len) - 0.05:
			var A := _cycle(_x.clean, a, f0, t, K)
			if not prev.is_empty():
				var num := 0.0
				var den := 0.0
				for k in K:
					# This frame against the last: the harmonic's phase step, as a pitch.
					var re := A[2 * k] * prev[2 * k] + A[2 * k + 1] * prev[2 * k + 1]
					var im := A[2 * k + 1] * prev[2 * k] - A[2 * k] * prev[2 * k + 1]
					var w := sqrt(re * re + im * im)
					num += w * atan2(im, re) / (TAU * (k + 1) * f0 * dt)
					den += w
				cs.append(clampf(1731.234 * num / den, -50.0, 50.0) if den > 0.0 else 0.0)
			prev = A
			t += dt
		if cs.size() < 100:
			continue
		curves.append([float(h.t), 0.3 + dt / 2.0, _less_curve(cs)])
	if curves.size() < 2:
		return {}
	var best := {}
	for free in [true, false]:
		var amps := PackedFloat64Array()
		var f := 2.5
		var top := [0.0, 0.0]
		while f <= 12.0:
			var v: Vector3 = _wobble(curves, f, dt, free)
			amps.append(v.x)
			if v.x > top[0]:
				top = [v.x, f]
			f += 0.01
		var fine := [0.0, 0.0, 0.0]
		var g: float = top[1] - 0.01
		while g <= top[1] + 0.01:
			var v: Vector3 = _wobble(curves, g, dt, free)
			if v.x > fine[0]:
				fine = [v.x, g, v.y]
			g += 0.0005
		var sorted := amps.duplicate()
		sorted.sort()
		var x: float = fine[0] / maxf(sorted[sorted.size() / 2], 1e-9)
		if best.is_empty() or fine[0] > float(best.cents):
			best = {rate_hz = snappedf(fine[1], 0.0001), cents = snappedf(fine[0], 0.01),
				phase = snappedf(fposmod(fine[2] / TAU + 0.25, 1.0), 0.001), free = free, x = snappedf(x, 0.1)}
	# A best rate at either end of the scan is the slope of something outside it (slow beating), not a peak.
	if best.is_empty() or float(best.x) < 6.0 or float(best.cents) < 1.0 or float(best.rate_hz) < 2.55 or float(best.rate_hz) > 11.95:
		return {}
	return best


## The notes' pitch curves (find_vibrato) fitted at rate f in one go: Vector3(depth in cents, phase
## (radians) of v ~ depth x cos(2 pi f t + phase), 0); t in file time when `free`, else from each note-on.
static func _wobble(curves: Array, f: float, dt: float, free: bool) -> Vector3:
	var zr := 0.0
	var zi := 0.0
	var n := 0
	var sr := cos(TAU * f * dt)
	var si := -sin(TAU * f * dt)
	for c: Array in curves:
		var t0: float = float(c[1]) + (float(c[0]) if free else 0.0)
		var er := cos(TAU * f * t0)
		var ei := -sin(TAU * f * t0)
		var v: PackedFloat64Array = c[2]
		for i in v.size():
			zr += v[i] * er
			zi += v[i] * ei
			var nr := er * sr - ei * si
			ei = er * si + ei * sr
			er = nr
		n += v.size()
	return Vector3(2.0 * sqrt(zr * zr + zi * zi) / maxf(n, 1), atan2(zi, zr), 0.0)


## The values less their best straight-and-curved line (least squares on 1, i, i^2).
static func _less_curve(v: PackedFloat64Array) -> PackedFloat64Array:
	var n := v.size()
	var M := []
	for _i in 3:
		M.append([0.0, 0.0, 0.0, 0.0])
	for i in n:
		var u := float(i) / n
		var row := [1.0, u, u * u]
		for p in 3:
			for q in 3:
				M[p][q] += row[p] * row[q]
			M[p][3] += row[p] * v[i]
	# Gauss-Jordan, 3 x 3.
	for c in 3:
		var piv := c
		for r in range(c + 1, 3):
			if absf(M[r][c]) > absf(M[piv][c]):
				piv = r
		var tmp: Array = M[c]
		M[c] = M[piv]
		M[piv] = tmp
		if absf(M[c][c]) < 1e-30:
			return v
		for r in 3:
			if r != c:
				var fr: float = M[r][c] / M[c][c]
				for q in range(c, 4):
					M[r][q] -= fr * M[c][q]
	var co := [M[0][3] / M[0][0], M[1][3] / M[1][1], M[2][3] / M[2][2]]
	var out := v.duplicate()
	for i in n:
		var u := float(i) / n
		out[i] -= co[0] + co[1] * u + co[2] * u * u
	return out


static func _centred(x: PackedFloat32Array) -> PackedFloat32Array:
	var s := 0.0
	for v in x:
		s += v
	var mean := s / maxf(x.size(), 1)
	var o := x.duplicate()
	for i in o.size():
		o[i] -= mean
	return o


## The amp envelope: full while held, then the release fitted after the held notes' key-ups. One time
## constant, or two stages (a fast drop to a knee, then a slower tail) when two fit the level clearly
## better, as on sample-playback synths whose release drops at once and then trails off.
func _release_env() -> Dictionary:
	var env := {attack_s = 0.0, decay_s = 0.0, sustain = 1.0, release_s = maxf(_release_s(), 0.002), curve = "exp"}
	var two := _release_two(float(env.release_s))
	if not two.is_empty():
		env.release_knee = two.knee
		env.release2_s = two.r2
	return env


## A second release stage: {knee, r2} (medians over the held notes), or {} when one stage fits nearly as
## well. The level after each key-up, every 10 ms for up to 1.5 s (to the next note), in dB from the
## level at key-up; the first stage keeps the time constant r1. Only levels 6 dB over the floor count.
func _release_two(r1: float) -> Dictionary:
	var hop := int(_sr / 100.0)
	var all := PackedFloat64Array()
	for a in range(0, _x.clean.size() - hop, hop * 7):
		var e := 0.0
		for i in range(a, a + hop):
			e += _x.clean[i] * _x.clean[i]
		all.append(_db(sqrt(e / hop)))
	all.sort()
	var floor_lv: float = all[all.size() / 10] if all.size() > 0 else -120.0
	var ts := []
	for n: Dictionary in _x.notes:
		ts.append(float(n.t))
	ts.sort()
	var knees := []
	var r2s := []
	var wins := 0
	var holds := _holds()
	for n: Dictionary in holds:
		var off := float(n.t) + float(n.len)
		var end := minf(off + 1.5, _length_s())
		for t: float in ts:
			if t > off:
				end = minf(end, t - 0.01)
				break
		var lv := func(t0: float) -> float:
			var a := int(t0 * _sr)
			var e := 0.0
			for i in range(a, mini(a + hop, _x.clean.size())):
				e += _x.clean[i] * _x.clean[i]
			return _db(sqrt(e / hop))
		var l0: float = lv.call(off - 0.012)
		if l0 < floor_lv + 30.0:
			continue
		var tt := PackedFloat64Array()
		var yy := PackedFloat64Array()
		var t := off
		while t < end:
			var v: float = lv.call(t) - l0
			if v + l0 > floor_lv + 6.0:
				tt.append(t - off)
				yy.append(v)
			t += 0.01
		if tt.size() < 10:
			continue
		var fl := floor_lv - l0
		var err := func(knee_db: float, r2: float) -> float:
			var tk := -knee_db * r1 / 8.686
			var s := 0.0
			for i in tt.size():
				var m := -8.686 * tt[i] / r1 if tt[i] < tk else knee_db - 8.686 * (tt[i] - tk) / r2
				s += pow(maxf(m, fl) - yy[i], 2.0)
			return s / tt.size()
		var one: float = err.call(-200.0, 1.0)
		var best := [one, 0.0, 0.0]
		var kd := -6.0
		while kd >= -50.0:
			var r2 := 0.02
			while r2 <= 4.0:
				var e2: float = err.call(kd, r2)
				if e2 < best[0]:
					best = [e2, kd, r2]
				r2 *= 1.25
			kd -= 2.0
		# Two stages when they cut the error by more than half and the tail is slower than the drop.
		if best[2] > 0.0 and best[0] < 0.5 * one and best[2] > 2.0 * r1:
			wins += 1
			knees.append(pow(10.0, best[1] / 20.0))
			r2s.append(best[2])
	if wins * 2 <= holds.size() or knees.is_empty():
		return {}
	knees.sort()
	r2s.sort()
	return {knee = snappedf(knees[knees.size() / 2], 0.0001), r2 = snappedf(r2s[r2s.size() / 2], 0.001)}


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
	if vp.size() < 2:
		return 1.0
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
	if _plain():
		return _x.notes.filter(func(n: Dictionary) -> bool: return n.len >= 0.2)
	var s1: float = _x.scenes[1]
	return _x.notes.filter(func(n: Dictionary) -> bool: return n.len >= 0.2 and n.t < s1 + 12.0)


## The original against itself: scene 3's two identical passes.
func floor_db() -> float:
	if _plain():
		return NAN
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
	var evs := _holds().duplicate()
	evs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	if not _plain():
		var s2: float = _x.scenes[2]
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
	var times := frame_times((p.oscillators[0].table.zones[0].frames as Array).size(), _pos_t)
	var eqs := _eq_dicts(base.slice(6, 6 + 7 * neq), neq)
	for o: Dictionary in p.oscillators:
		var z: Dictionary = o.table.zones[0]
		var p0 := float(AKWavetables.build(o.table).peak)
		for j in (z.frames as Array).size():
			var fr: Dictionary = z.frames[j]
			var cut := clampf(fc * pow(2.0, v[1] * (center - 60.0) / 12.0 + v[4] * exp(-times[j] / 0.08) + v[5] * minf(times[j] / _pos_t, 1.0)), 20.0, 20000.0)
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
