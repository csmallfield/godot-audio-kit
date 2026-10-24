# SPDX-License-Identifier: Apache-2.0
@tool
## MIDI files into songs.
##
##   var song := AKMidi.import_file("res://music/minuet.mid")     # an AKSong
##   ResourceSaver.save(song, "res://music/minuet_song.tres")       # editable text
##   AKMidi.summary(song)                                            # lanes, notes, length
##
## In the editor, .mid files import as AKSongs (the import dock has the
## options below), so a .mid can go straight into a cue bridge or the dock.
##
## What becomes what:
##   - tempo and time-signature changes -> the song's AKTempoMap (exact,
##     including changes in the middle of a bar)
##   - each track and channel -> a lane playing the bank's patch for its
##     program (the first program change before its first note; programs
##     that change mid-track split the lane)
##   - channel 10 -> one lane per kind of drum (kick, snare, hat ...)
##   - notes -> freely timed lane `events` [[beat, length, midi, velocity]];
##     overlapping notes on one key close first-in, first-out; the sustain
##     pedal (CC 64) holds notes until it lifts
##   - CC 7 (volume) and CC 10 (pan) at the start of a lane -> its gain and
##     pan; CC 91 (reverb) -> its send
##   - marker meta events -> sections (else one section, "song")
## Not carried over: pitch bend, modulation and aftertouch inside songs
## (songs render note by note; live MIDI input does use them).
##
## Options: bank (AKBank or path; default the shipped GM bank), quantize
## (steps per beat to snap note starts to, 0 = off), velocity_curve (1 =
## linear; below 1 lifts quiet notes), min_length_beats (shortest note),
## reverb_send (when the file sets none), sections (false: ignore markers).
class_name AKMidi
extends RefCounted

const DEFAULTS := {bank = "", quantize = 0, velocity_curve = 1.0, min_length_beats = 0.0625, reverb_send = 0.12, sections = true}


static func import_file(path: String, options := {}) -> AKSong:
	var m := AKMidiFile.load_file(path)
	if m.error != "" and m.tracks.is_empty():
		push_error("AKMidi: %s: %s" % [path, m.error])
		return null
	if m.error != "":
		push_warning("AKMidi: %s: %s (imported what was readable)" % [path, m.error])
	var song := to_song(m, options)
	if song:
		song.resource_name = path.get_file().get_basename()
	return song


## The song for a parsed file.
static func to_song(m: AKMidiFile, options := {}) -> AKSong:
	var o := DEFAULTS.duplicate()
	o.merge(options, true)
	var bank: AKBank = o.bank if o.bank is AKBank else null
	if bank == null:
		var bp := String(o.bank) if String(o.bank) != "" else AKGeneralMidi.DEFAULT_BANK
		bank = load(bp) if ResourceLoader.exists(bp) else AKGeneralMidi.make_bank()
	var ppq := float(m.ppq)

	# ---- tempo map: tempo and meter changes in beats (quarter notes)
	var tempos := m.tempo_list()
	var meters := [[0, 4, 4]]
	var markers := []
	for t in m.tracks:
		for e in t.events:
			if e.type == "time_sig":
				meters.append([int(e.tick), int(e.num), int(e.den)])
			elif e.type == "marker" and String(e.text).strip_edges() != "":
				markers.append([int(e.tick), String(e.text).strip_edges()])
	meters.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var meter_at := {}
	for x in meters:
		meter_at[int(x[0])] = x
	meters = meter_at.values()
	meters.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var tm := AKTempoMap.new()
	var first: Array = meters[0]
	tm.beats_per_bar = maxi(1, roundi(_bpb(first)))
	tm.bpm = 60e6 / float(tempos[0][1])
	var changes: Array[Dictionary] = []
	var ticks := {}
	for x in tempos:
		ticks[int(x[0])] = true
	for x in meters:
		ticks[int(x[0])] = true
	var keys := ticks.keys()
	keys.sort()
	if not is_equal_approx(_bpb(first), float(tm.beats_per_bar)):
		changes.append({bar = 0.0, beats_per_bar = _bpb(first)})   # a fractional meter from the start (5/8)
	for tk in keys:
		if tk == 0:
			continue
		var bar := _bar_at(float(tk) / ppq, meters, ppq)
		var c := {bar = snappedf(bar, 1e-9)}
		var tp := _value_at(tempos, tk)
		c["bpm"] = 60e6 / float(tp[1])
		var bpb := _bpb(_value_at(meters, tk))
		c["beats_per_bar"] = roundi(bpb) if is_equal_approx(bpb, roundf(bpb)) else bpb
		changes.append(c)
	tm.changes = changes

	# ---- notes per lane
	var lanes := {}        # lane key -> {name, patch/recipe, events, gain_db, pan, send, order}
	var order := 0
	var total_beats := 0.0
	for ti in m.tracks.size():
		var tr: Dictionary = m.tracks[ti]
		var program := {}   # ch -> program
		var vol := {}
		var pan := {}
		var rev := {}
		var pedal := {}     # ch -> down
		var held := {}      # "ch:key" -> [[start_tick, vel], ...] (FIFO)
		var pedal_held := {} # ch -> [[lane_key, start, vel, key]] waiting for the pedal
		var notes := []     # [lane_key, start_tick, end_tick, key, vel]
		for e: Dictionary in tr.events:
			var ch := int(e.get("ch", 0))
			match String(e.type):
				"program":
					program[ch] = int(e.program)
				"cc":
					match int(e.num):
						7: vol[ch] = int(e.value)
						10: pan[ch] = int(e.value)
						91: rev[ch] = int(e.value)
						64:
							var down := int(e.value) >= 64
							if not down and pedal.get(ch, false):
								for w: Array in pedal_held.get(ch, []):
									notes.append([w[0], w[1], int(e.tick), w[3], w[2]])
								pedal_held[ch] = []
							pedal[ch] = down
						120, 123:
							for hk in held.keys():
								if String(hk).begins_with("%d:" % ch):
									for st: Array in held[hk]:
										notes.append([st[2], st[0], int(e.tick), int(String(hk).get_slice(":", 1)), st[1]])
									held.erase(hk)
				"note_on":
					var lk := _lane_key(ti, ch, int(program.get(ch, 0)), int(e.key), tr, bank)
					if not lanes.has(lk.key):
						for other: Dictionary in lanes.values():
							if other.name == lk.name:
								lk.name = "%s_p%d" % [lk.name, int(program.get(ch, 0))]
								break
						lanes[lk.key] = {name = lk.name, ref = lk.ref, drum = lk.drum, events = [], order = order,
							gain_db = _vol_db(int(vol.get(ch, 100))), pan = (float(pan.get(ch, 64)) - 64.0) / 63.0,
							send = float(rev[ch]) / 127.0 * 0.5 if rev.has(ch) else float(o.reverb_send)}
						order += 1
					var hk := "%d:%d" % [ch, int(e.key)]
					if not held.has(hk):
						held[hk] = []
					held[hk].append([int(e.tick), int(e.vel), lk.key])
				"note_off":
					var hk := "%d:%d" % [ch, int(e.key)]
					if held.has(hk) and not held[hk].is_empty():
						var st: Array = held[hk].pop_front()
						if pedal.get(ch, false):
							if not pedal_held.has(ch):
								pedal_held[ch] = []
							pedal_held[ch].append([st[2], st[0], st[1], int(e.key)])
						else:
							notes.append([st[2], st[0], int(e.tick), int(e.key), st[1]])
		# Anything still sounding ends with the track.
		var end_tick := int(tr.events.back().tick) if not tr.events.is_empty() else 0
		for hk in held:
			for st: Array in held[hk]:
				notes.append([st[2], st[0], end_tick, int(String(hk).get_slice(":", 1)), st[1]])
		for ch in pedal_held:
			for w: Array in pedal_held[ch]:
				notes.append([w[0], w[1], end_tick, w[3], w[2]])
		for n: Array in notes:
			var L: Dictionary = lanes[n[0]]
			var b0 := float(n[1]) / ppq
			if int(o.quantize) > 0:
				b0 = roundf(b0 * int(o.quantize)) / int(o.quantize)
			var length := maxf(float(o.min_length_beats), float(int(n[2]) - int(n[1])) / ppq)
			var vel := pow(float(n[4]) / 127.0, float(o.velocity_curve))
			L.events.append([snappedf(b0, 1e-6), snappedf(length, 1e-6), -1 if L.drum else int(n[3]), snappedf(vel, 1e-4)])
			total_beats = maxf(total_beats, b0 + length)

	# ---- sections: split at markers
	var bounds := [[0.0, "song"]]
	if bool(o.sections) and not markers.is_empty():
		markers.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		bounds = []
		if int(markers[0][0]) > 0:
			bounds.append([0.0, "intro"])
		for mk in markers:
			bounds.append([float(mk[0]) / ppq, _unique(String(mk[1]), bounds)])
	var song_beats := maxf(total_beats, 1.0)
	var sections: Array[Dictionary] = []
	var lane_list := lanes.values()
	lane_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.order < b.order)
	for i in bounds.size():
		var b0: float = bounds[i][0]
		var b1: float = bounds[i + 1][0] if i + 1 < bounds.size() else _round_up_to_bar(song_beats, tm)
		if b1 <= b0:
			continue
		var pat := AKPattern.new()
		pat.steps_per_beat = 4
		pat.steps = maxi(1, ceili((b1 - b0) * 4.0))
		var pl: Array[Dictionary] = []
		for L: Dictionary in lane_list:
			var evs := []
			for ev: Array in L.events:
				if float(ev[0]) >= b0 - 1e-9 and float(ev[0]) < b1 - 1e-9:
					evs.append([snappedf(float(ev[0]) - b0, 1e-6), ev[1], ev[2], ev[3]])
			if evs.is_empty():
				continue
			evs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[2] < b[2])
			var lane := {name = L.name, events = evs, gain_db = snappedf(float(L.gain_db), 0.01), pan = snappedf(float(L.pan), 0.01),
				send = snappedf(float(L.send), 0.01)}
			if L.drum:
				lane["recipe"] = L.ref
			else:
				lane["patch"] = L.ref
			pl.append(lane)
		pat.lanes = pl
		var bar0 := tm_bar(tm, b0)
		var bar1 := tm_bar(tm, b1)
		sections.append({name = bounds[i][1], bars = snappedf(bar1 - bar0, 1e-9), patterns = [pat]})
	var song := AKSong.new()
	song.tempo = tm
	song.sections = sections
	song.reverb = {room = 0.45, damp = 0.5, width = 1.0, quality = &"full", return_db = 0.0}
	return song


## A one-line description: "3 lanes (piano, bass, drums.kick), 412 notes, 2 sections, 63.2 s".
static func summary(song: AKSong) -> String:
	var names := []
	var count := 0
	for s in song.sections:
		for p in s.get("patterns", []):
			for l in p.lanes:
				if not names.has(l.name):
					names.append(l.name)
				count += l.get("events", []).size()
	return "%d lanes (%s), %d notes, %d sections, %.1f s" % [names.size(), ", ".join(names), count, song.sections.size(), song.length_s()]


## Bars from bar 0 to `beat` on a tempo map (inverse of beats_at_bar).
static func tm_bar(tm: AKTempoMap, beat: float) -> float:
	var segs := tm.segments()
	var start := 0.0
	for i in segs.size():
		var s: Dictionary = segs[i]
		var seg_beats: float = (float(segs[i + 1].bar) - float(s.bar)) * float(s.bpb) if i + 1 < segs.size() else INF
		if beat < start + seg_beats or i == segs.size() - 1:
			return float(s.bar) + (beat - start) / float(s.bpb)
		start += seg_beats
	return 0.0


# ------------------------------------------------------------------ inside

## Which lane a note goes to: {key, name, ref, drum}.
static func _lane_key(ti: int, ch: int, program: int, key: int, tr: Dictionary, bank: AKBank) -> Dictionary:
	if ch == 9:
		var d := bank.drum_for(key)
		var lane := String(d.get("lane", "perc"))
		return {key = "drums." + lane, name = "drums." + lane, ref = d.get("recipe"), drum = true}
	var base := String(tr.get("name", "")).strip_edges().to_snake_case().replace(" ", "_")
	if base == "":
		base = AKGeneralMidi.program_name(program).to_snake_case().replace(" ", "_").replace("(", "").replace(")", "")
	var name := "%s_%d" % [base, ti] + ("" if ch == 0 else "_ch%d" % (ch + 1))
	return {key = "%d:%d:%d" % [ti, ch, program], name = name, ref = bank.patch_ref_for(program), drum = false}


static func _bpb(meter: Array) -> float:
	return float(meter[1]) * 4.0 / float(meter[2])


static func _value_at(list: Array, tick: int) -> Array:
	var v: Array = list[0]
	for x in list:
		if int(x[0]) <= tick:
			v = x
	return v


## The (fractional) bar at `beat`, walking meter changes.
static func _bar_at(beat: float, meters: Array, ppq: float) -> float:
	var bar := 0.0
	var at := 0.0
	for i in meters.size():
		var bpb := _bpb(meters[i])
		var next := float(meters[i + 1][0]) / ppq if i + 1 < meters.size() else INF
		if beat <= next:
			return bar + (beat - at) / bpb
		bar += (next - at) / bpb
		at = next
	return bar


static func _round_up_to_bar(beats: float, tm: AKTempoMap) -> float:
	var bar := ceilf(tm_bar(tm, beats) - 1e-6)
	return tm.beats_at_bar(bar)


static func _vol_db(v: int) -> float:
	# MIDI volume is roughly 40·log10(v/127) dB (the GM recommendation).
	return 40.0 * log(maxf(1.0, float(v)) / 127.0) / log(10.0) if v < 127 else 0.0


static func _unique(name: String, bounds: Array) -> String:
	var n := name
	var i := 2
	var taken := bounds.map(func(b: Array) -> String: return String(b[1]))
	while taken.has(n):
		n = "%s %d" % [name, i]
		i += 1
	return n
