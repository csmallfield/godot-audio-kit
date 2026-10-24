# SPDX-License-Identifier: Apache-2.0
@tool
## A Standard MIDI File (.mid) read into plain data.
##
##   var m := AKMidiFile.load_file("res://music/song.mid")
##   m.format, m.ppq, m.tracks[0].name, m.tracks[0].events[0]   # {tick, type, ...}
##
## Reads formats 0, 1 and 2, running status, note-on with velocity 0 as
## note-off, SysEx (skipped), meta events (tempo, time signature, track
## name, marker, end of track) and SMPTE time division (turned into ticks of
## a 120 bpm quarter note, so the rest of the kit sees ordinary ticks).
## Malformed files give `error` text and whatever parsed before the fault.
##
## Event types and their keys (ticks are absolute, per track):
##   note_on {ch, key, vel}  note_off {ch, key, vel}  cc {ch, num, value}
##   program {ch, program}  bend {ch, value -8192..8191}  pressure {ch, value}
##   poly_pressure {ch, key, value}  tempo {us_per_quarter}
##   time_sig {num, den}  key_sig {sf, minor}  name {text}  marker {text}
##   text {text}  end {}
class_name AKMidiFile
extends RefCounted

var format := 1
## Ticks per quarter note.
var ppq := 480
## [{name, events: [{tick, type, ...}]}]
var tracks: Array = []
## Empty when the file read cleanly.
var error := ""


static func load_file(path: String) -> AKMidiFile:
	var bytes := FileAccess.get_file_as_bytes(path)
	var m := AKMidiFile.new()
	if bytes.is_empty():
		m.error = "can't read %s" % path
		return m
	m.parse(bytes)
	return m


static func from_bytes(bytes: PackedByteArray) -> AKMidiFile:
	var m := AKMidiFile.new()
	m.parse(bytes)
	return m


func parse(b: PackedByteArray) -> void:
	tracks = []
	error = ""
	var pos := 0
	if b.size() < 14 or b.slice(0, 4).get_string_from_ascii() != "MThd":
		# RIFF-wrapped MIDI (RMID): find the MThd inside.
		var at := _find(b, "MThd")
		if at < 0:
			error = "not a MIDI file (no MThd header)"
			return
		pos = at
	var hlen := _u32(b, pos + 4)
	format = _u16(b, pos + 8)
	var ntracks := _u16(b, pos + 10)
	var div := _u16(b, pos + 12)
	if div & 0x8000:
		# SMPTE: frames per second x ticks per frame = ticks per second;
		# treated as a 120 bpm quarter (0.5 s), the tempo maps stay right.
		var fps := 256 - (div >> 8)
		if fps == 29:
			fps = 30
		var tpf := div & 0xFF
		ppq = maxi(1, roundi(fps * tpf * 0.5))
		_smpte = true
	else:
		ppq = maxi(1, div)
	pos += 8 + hlen
	for t in ntracks:
		# Skip unknown chunks between tracks.
		while pos + 8 <= b.size() and b.slice(pos, pos + 4).get_string_from_ascii() != "MTrk":
			pos += 8 + _u32(b, pos + 4)
		if pos + 8 > b.size():
			error = "expected %d tracks, found %d" % [ntracks, tracks.size()]
			return
		var length := _u32(b, pos + 4)
		var start := pos + 8
		var end := mini(b.size(), start + length)
		if start + length > b.size():
			error = "track %d is cut short" % t
		tracks.append(_track(b, start, end))
		pos = start + length
	if _smpte and not tracks.is_empty():
		tracks[0].events.push_front({tick = 0, type = "tempo", us_per_quarter = 500000})


var _smpte := false


func _track(b: PackedByteArray, start: int, end: int) -> Dictionary:
	var events := []
	var name := ""
	var tick := 0
	var pos := start
	var status := 0
	while pos < end:
		var dv := _vlq(b, pos)
		pos = dv[1]
		tick += dv[0]
		if pos >= end:
			break
		var c := b[pos]
		if c & 0x80:
			pos += 1
			if c < 0xF0:
				status = c
		elif status == 0:
			error = "data byte without a status at byte %d" % pos
			break
		else:
			c = status   # running status: this byte is data
		if c == 0xFF:
			if pos + 1 > end:
				break
			var mtype := b[pos]
			var lv := _vlq(b, pos + 1)
			var dstart: int = lv[1]
			var dlen: int = lv[0]
			pos = dstart + dlen
			var data := b.slice(dstart, mini(end, dstart + dlen))
			match mtype:
				0x51:
					if data.size() >= 3:
						events.append({tick = tick, type = "tempo", us_per_quarter = (data[0] << 16) | (data[1] << 8) | data[2]})
				0x58:
					if data.size() >= 2:
						events.append({tick = tick, type = "time_sig", num = data[0], den = 1 << data[1]})
				0x59:
					if data.size() >= 2:
						events.append({tick = tick, type = "key_sig", sf = data[0] - 256 if data[0] > 127 else data[0], minor = data[1] == 1})
				0x03:
					name = _text(data)
					events.append({tick = tick, type = "name", text = name})
				0x06:
					events.append({tick = tick, type = "marker", text = _text(data)})
				0x01:
					events.append({tick = tick, type = "text", text = _text(data)})
				0x2F:
					events.append({tick = tick, type = "end"})
					break
			# Meta and SysEx cancel running status in the spec; many files
			# rely on it surviving meta events, so keep it (both work).
			continue
		if c == 0xF0 or c == 0xF7:
			var sl := _vlq(b, pos)
			pos = sl[1] + sl[0]
			continue
		if c >= 0xF1:
			# System common/real-time bytes don't belong in files; skip them.
			pos += {0xF1: 1, 0xF2: 2, 0xF3: 1}.get(c, 0)
			continue
		var hi := c & 0xF0
		var ch := c & 0x0F
		var n := 1 if (hi == 0xC0 or hi == 0xD0) else 2
		if pos + n > end:
			error = "event cut short at byte %d" % pos
			break
		var d1 := b[pos] & 0x7F
		var d2 := b[pos + 1] & 0x7F if n == 2 else 0
		pos += n
		match hi:
			0x90:
				if d2 == 0:
					events.append({tick = tick, type = "note_off", ch = ch, key = d1, vel = 64})
				else:
					events.append({tick = tick, type = "note_on", ch = ch, key = d1, vel = d2})
			0x80:
				events.append({tick = tick, type = "note_off", ch = ch, key = d1, vel = d2})
			0xA0:
				events.append({tick = tick, type = "poly_pressure", ch = ch, key = d1, value = d2})
			0xB0:
				events.append({tick = tick, type = "cc", ch = ch, num = d1, value = d2})
			0xC0:
				events.append({tick = tick, type = "program", ch = ch, program = d1})
			0xD0:
				events.append({tick = tick, type = "pressure", ch = ch, value = d1})
			0xE0:
				events.append({tick = tick, type = "bend", ch = ch, value = ((d2 << 7) | d1) - 8192})
	return {name = name, events = events}


## Seconds at each tick, from the tempo events of every track (format 0/1
## share one tempo map): a callable-free helper that returns the sorted
## tempo list [[tick, us_per_quarter], ...] starting at tick 0.
func tempo_list() -> Array:
	var out := [[0, 500000]]
	var all := []
	for t in tracks:
		for e in t.events:
			if e.type == "tempo":
				all.append([int(e.tick), int(e.us_per_quarter)])
	all.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for x in all:
		if int(x[0]) == int(out.back()[0]):
			out.back()[1] = x[1]
		else:
			out.append(x)
	return out


## Seconds at `tick` under tempo_list() `tl`.
func tick_to_seconds(tick: int, tl: Array = []) -> float:
	if tl.is_empty():
		tl = tempo_list()
	var s := 0.0
	for i in tl.size():
		var t0 := int(tl[i][0])
		var t1 := int(tl[i + 1][0]) if i + 1 < tl.size() else 1 << 62
		if tick <= t0:
			break
		s += float(mini(tick, t1) - t0) / ppq * float(tl[i][1]) / 1e6
	return s


static func _text(d: PackedByteArray) -> String:
	var s := d.get_string_from_utf8()
	return s if s != "" or d.is_empty() else d.get_string_from_ascii()


static func _u16(b: PackedByteArray, at: int) -> int:
	return (b[at] << 8) | b[at + 1] if at + 1 < b.size() else 0


static func _u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3] if at + 3 < b.size() else 0


## [value, next position]; at most 4 bytes.
static func _vlq(b: PackedByteArray, at: int) -> Array:
	var v := 0
	var p := at
	for i in 4:
		if p >= b.size():
			break
		var c := b[p]
		p += 1
		v = (v << 7) | (c & 0x7F)
		if not (c & 0x80):
			break
	return [v, p]


static func _find(b: PackedByteArray, tag: String) -> int:
	var t := tag.to_ascii_buffer()
	for i in range(0, b.size() - 4):
		if b[i] == t[0] and b[i + 1] == t[1] and b[i + 2] == t[2] and b[i + 3] == t[3]:
			return i
	return -1
