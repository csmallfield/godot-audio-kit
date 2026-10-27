# SPDX-License-Identifier: Apache-2.0
@tool
## Imports an Auxy project, from Auxy's "Export for Bitwig Studio" bundle
## (.axbw), as loops, drum kits and an AKArrangement.
##
##   var res := AKAuxy.import_file("/path/to/Song-bitwig.axbw", "res://audio/")
##   if res.ok:
##       var arr: AKArrangement = res.arrangement     # saved at res.path
##
## Why that export: it is Auxy's own model, not a translation. The bundle is
## a zip holding `manifest.json` (title, bpm, scale, channels with their
## preset names, colours and kind "instrument" or "drums", and the song as a
## list of scenes), one standard MIDI file per loop (`loop_<channel>_<slot>.mid`,
## its end-of-track marking the loop's length) and a rendered stem per
## channel (`stem_<channel>.wav`). Checked against the rendered stems, its
## scenes match the audio bar for bar, where Auxy's Ableton, Studio One and
## MIDI exports each get a few bars wrong around scenes that start mid-loop.
##
## The manifest's song is a list of scenes played one after another:
##   {loop_locations = ["3_0", "5_2"], number_of_bars = 3, start_offset = 1}
## Every listed loop plays for `number_of_bars`, starting `start_offset` bars
## into itself and repeating; a loop restarts at each scene (a two-bar loop
## in five one-bar scenes plays its first bar five times).
##
## What it makes (all under `save_dir`, named after the song):
##   - a loop per Auxy loop (`loops/<song>_<track>_<n>.tres`, flat so the
##     loop browser lists them), the whole bank, used or not. Instrument
##     channels become synth loops on a preset patch picked from the preset
##     name and the notes' register (pass `patches` to choose); drum channels
##     become percussive loops on a kit made for the channel.
##   - a kit per drum channel (`kits/<song>_<track>.tres`): Auxy's drum
##     notes count up from 36, so row = note - 36, and piece n is a copy of
##     the base kit's piece n (kick, snare, clap, closed hat ...). Auxy
##     doesn't say which sound a pad is: swap sounds in this kit once and
##     every loop follows.
##   - the arrangement (`arrangements/<song>.tres`): a track per channel that
##     has loops, Auxy's song on the timeline (a clip per stretch where a
##     loop plays on in phase, a marker wherever the set of loops changes)
##     and a scene per distinct set of loops, to launch from a game.
##   - the stems of channels the song uses (`stems/<song>/<track>.wav`),
##     listed in the arrangement's metadata `auxy`. Reference only: the
##     sequencer plays the loops, not the stems.
##
## Auxy doesn't export dynamics (every velocity is 127), mixer settings or
## its sounds; the stems are the only record of how it sounded.
class_name AKAuxy
extends RefCounted

const FORMAT_VERSIONS := ["0.1"]
## Auxy's first drum pad.
const DRUM_BASE_NOTE := 36
const BEATS_PER_BAR := 4

## Preset patches by words in an Auxy preset name, first match wins.
const PATCH_WORDS := [
	[["sub"], "sub_bass"],
	[["acid", "303"], "acid_bass"],
	[["wobble"], "wobble_bass"],
	[["bass", "basset", "808"], "wavetable_bass"],
	[["string", "viola", "violin", "cello"], "strings"],
	[["pad", "ghost", "choir", "air", "atmos"], "wavetable_pad"],
	[["vocal", "vox", "chop", "voice"], "vowel_pad"],
	[["bell", "chime", "glass"], "fm_bell"],
	[["piano", "keys", "rhodes", "ep"], "fm_epiano"],
	[["organ"], "organ"],
	[["brass", "horn"], "brass"],
	[["lead", "saw"], "saw_lead"],
	[["pluck", "harp", "micro", "arp"], "pluck"],
]


# ------------------------------------------------------------------ reading

## The bundle as plain data:
##   {ok, error, warnings, title, bpm, scale, creator, format_version,
##    channels: [{label, kind, color}],
##    loops: {"<c>_<s>": {channel, slot, beats, notes: [[beat, length_beats, key, velocity 0..1]]}},
##    scenes: [{loops: ["<c>_<s>", ...], bars, start_offset}],
##    stems: {channel: entry name in the zip}}
static func read(path: String) -> Dictionary:
	var out := {ok = false, error = "", warnings = [], title = "", bpm = 120.0, scale = "", creator = "", format_version = "",
		channels = [], loops = {}, scenes = [], stems = {}}
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		out.error = "can't open %s as a zip (is it an Auxy \"Export for Bitwig Studio\" .axbw?)" % path
		return out
	var files := zip.get_files()
	if not files.has("manifest.json"):
		zip.close()
		out.error = "%s has no manifest.json: not an Auxy Bitwig export" % path.get_file()
		return out
	var man: Variant = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not man is Dictionary:
		zip.close()
		out.error = "manifest.json isn't a JSON object"
		return out
	out.title = String(man.get("title", path.get_file().get_basename()))
	out.bpm = float(man.get("bpm", 120.0))
	out.scale = String(man.get("scale", ""))
	out.creator = String(man.get("creator", ""))
	out.format_version = str(man.get("format_version", ""))
	if not FORMAT_VERSIONS.has(out.format_version):
		out.warnings.append("manifest format_version %s is newer than this importer knows (%s); importing anyway" % [out.format_version, ", ".join(FORMAT_VERSIONS)])
	for c: Variant in man.get("channels", []):
		var cd: Dictionary = c if c is Dictionary else {}
		var hex := String(cd.get("color", "#808080"))
		out.channels.append({label = String(cd.get("label", "")), kind = String(cd.get("kind", "instrument")),
			color = Color.html(hex) if Color.html_is_valid(hex) else Color(0.5, 0.5, 0.5)})
	for f: String in files:
		var m := RegEx.create_from_string("^loop_(\\d+)_(\\d+)\\.mid$").search(f)
		if m:
			var key := "%s_%s" % [m.get_string(1), m.get_string(2)]
			var lp := _read_loop(zip.read_file(f))
			if lp.has("error"):
				out.warnings.append("%s: %s" % [f, lp.error])
			lp.erase("error")
			lp["channel"] = int(m.get_string(1))
			lp["slot"] = int(m.get_string(2))
			out.loops[key] = lp
			continue
		var s := RegEx.create_from_string("^stem_(\\d+)\\.wav$").search(f)
		if s:
			out.stems[int(s.get_string(1))] = f
	zip.close()
	for sc: Variant in man.get("scenes", []):
		var sd: Dictionary = sc if sc is Dictionary else {}
		var keys := []
		for k: Variant in sd.get("loop_locations", []):
			if out.loops.has(String(k)):
				keys.append(String(k))
			else:
				out.warnings.append("a scene lists loop %s, which isn't in the bundle" % k)
		out.scenes.append({loops = keys, bars = int(sd.get("number_of_bars", 0)), start_offset = int(sd.get("start_offset", 0))})
	out.ok = true
	return out


## A loop's notes and length from its MIDI file: beats are quarter notes.
static func _read_loop(bytes: PackedByteArray) -> Dictionary:
	var m := AKMidiFile.from_bytes(bytes)
	var out := {beats = 0.0, notes = []}
	if m.error != "":
		out["error"] = m.error
	var end_tick := 0
	for t: Dictionary in m.tracks:
		var open := {}
		for e: Dictionary in t.events:
			end_tick = maxi(end_tick, int(e.tick))
			match String(e.type):
				"note_on":
					var k := Vector2i(int(e.ch), int(e.key))
					if not open.has(k):
						open[k] = []
					open[k].append([int(e.tick), int(e.vel)])
				"note_off":
					var k := Vector2i(int(e.ch), int(e.key))
					if open.has(k) and not (open[k] as Array).is_empty():
						var on: Array = open[k].pop_front()
						out.notes.append([float(on[0]) / m.ppq, float(int(e.tick) - int(on[0])) / m.ppq, int(e.key), float(on[1]) / 127.0])
	out.notes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[2] < b[2]))
	out.beats = float(end_tick) / m.ppq
	if out.beats <= 0.0 and not out.notes.is_empty():
		var last: Array = out.notes.back()
		out.beats = float(last[0]) + float(last[1])
	return out


## A loop's length in whole bars (at least one).
static func loop_bars(lp: Dictionary) -> int:
	return maxi(1, ceili(float(lp.get("beats", 0.0)) / BEATS_PER_BAR - 1e-6))


## What each channel plays in each bar of the song: {channel: [[loop key, bar into the loop] or null per bar]}.
## The scenes expanded exactly as Auxy plays them; the answer the arrangement's timeline must give.
static func bar_map(model: Dictionary) -> Dictionary:
	var total := 0
	for sc: Dictionary in model.scenes:
		total += int(sc.bars)
	var out := {}
	for ci in model.channels.size():
		var row := []
		row.resize(total)
		out[ci] = row
	var bar := 0
	for sc: Dictionary in model.scenes:
		for k: String in sc.loops:
			var lp: Dictionary = model.loops[k]
			var L := loop_bars(lp)
			var ci := int(lp.channel)
			if not out.has(ci):
				var row := []
				row.resize(total)
				out[ci] = row
			for b in int(sc.bars):
				out[ci][bar + b] = [k, (int(sc.start_offset) + b) % L]
		bar += int(sc.bars)
	return out


# ------------------------------------------------------------------ importing

## Read `path` and write loops, kits, stems and an arrangement under
## `save_dir` (as the Sequencer's). Options:
##   kit       base kit for drum channels (a shipped kit name or an AKKit path; default "punch")
##   patches   {channel index or Auxy label: preset name or AKPatch path}, overriding the guess
##   stems     copy the used channels' stems (default true)
##   name      file name stem (default: the song title)
## Returns {ok, error, warnings, arrangement, path, loops: [paths], kits: [paths], stems: {track: path}, model,
## track_of: {channel: track name}, loop_paths: {"<c>_<s>": path}}.
static func import_file(path: String, save_dir := "res://audio/", options := {}) -> Dictionary:
	var model := read(path)
	var res := {ok = false, error = model.error, warnings = model.warnings.duplicate(), arrangement = null, path = "",
		loops = [], kits = [], stems = {}, model = model, track_of = {}, loop_paths = {}}
	if not model.ok:
		return res
	var dir := save_dir if save_dir.ends_with("/") else save_dir + "/"
	var base := String(options.get("name", "")).strip_edges()
	if base == "":
		base = slug(String(model.title))
	if base == "":
		base = "auxy"
	var arr := to_arrangement(model, options, res.warnings)
	arr.resource_name = base

	# Kits and loops are saved first so the arrangement refers to them by path.
	DirAccess.make_dir_recursive_absolute(dir + "loops")
	DirAccess.make_dir_recursive_absolute(dir + "kits")
	DirAccess.make_dir_recursive_absolute(dir + "arrangements")
	var built: Dictionary = arr.get_meta(&"auxy_build")
	arr.remove_meta(&"auxy_build")
	var saved_kits := {}
	for ci: int in built.kits:
		var kit: AKKit = built.kits[ci]
		var kp := dir + "kits/%s_%s.tres" % [base, slug(String(built.track_of[ci]))]
		if ResourceSaver.save(kit, kp) != OK:
			res.error = "couldn't save %s" % kp
			return res
		kit.take_over_path(kp)
		saved_kits[ci] = kp
		res.kits.append(kp)
	var loop_path := {}
	for key: String in built.loops:
		var l: AKLoop = built.loops[key]
		var lp := dir + "loops/%s.tres" % l.resource_name
		if ResourceSaver.save(l, lp) != OK:
			res.error = "couldn't save %s" % lp
			return res
		l.take_over_path(lp)
		loop_path[key] = lp
		res.loops.append(lp)
	res.loop_paths = loop_path
	res.track_of = built.track_of
	# Point scenes and clips at the saved files.
	for s: Dictionary in arr.scenes:
		var clips: Dictionary = s.clips
		for t: Variant in clips.keys():
			clips[t] = loop_path[String(clips[t])]
	for c: Dictionary in arr.timeline:
		c["loop"] = loop_path[String(c.loop)]

	var meta: Dictionary = arr.get_meta(&"auxy")
	if bool(options.get("stems", true)):
		var zip := ZIPReader.new()
		if zip.open(path) == OK:
			var used := {}
			for c: Dictionary in arr.timeline:
				used[String(c.track)] = true
			for ci: int in model.stems:
				if not built.track_of.has(ci) or not used.has(String(built.track_of[ci])):
					continue   # a channel the song doesn't play: its stem is silence
				var tn := String(built.track_of[ci])
				var sp := dir + "stems/%s/%s.wav" % [base, slug(tn)]
				DirAccess.make_dir_recursive_absolute(sp.get_base_dir())
				var f := FileAccess.open(sp, FileAccess.WRITE)
				if f == null:
					res.warnings.append("couldn't write %s" % sp)
					continue
				f.store_buffer(zip.read_file(String(model.stems[ci])))
				f.close()
				res.stems[tn] = sp
			zip.close()
		meta["stems"] = res.stems.duplicate()
	arr.set_meta(&"auxy", meta)

	var ap := dir + "arrangements/%s.tres" % base
	if ResourceSaver.save(arr, ap) != OK:
		res.error = "couldn't save %s" % ap
		return res
	arr.take_over_path(ap)
	AK.refresh_editor_files()
	res.arrangement = arr
	res.path = ap
	res.ok = true
	return res


## The model as an arrangement whose scenes and clips name loops by key
## ("<c>_<s>"); the loops and kits it needs are in its meta `auxy_build`
## ({loops: {key: AKLoop}, kits: {channel: AKKit}, track_of: {channel: track name}}).
## import_file saves them and swaps the keys for paths.
static func to_arrangement(model: Dictionary, options := {}, warnings: Array = []) -> AKArrangement:
	var arr := AKArrangement.new()
	arr.tempo = AKTempoMap.make(float(model.bpm), BEATS_PER_BAR)
	var base := String(options.get("name", ""))
	if base == "":
		base = slug(String(model.title))

	# Tracks: one per channel with loops, named after Auxy's preset (made unique).
	var has_loops := {}
	for key: String in model.loops:
		has_loops[int(model.loops[key].channel)] = true
	var track_of := {}
	var used_names := {}
	for ci in model.channels.size():
		var ch: Dictionary = model.channels[ci]
		if not has_loops.has(ci):
			warnings.append("channel %d (%s) has no loops: left out" % [ci + 1, ch.label])
			continue
		var tn := String(ch.label).strip_edges()
		if tn == "":
			tn = "drums" if ch.kind == "drums" else "track %d" % (ci + 1)
		var unique := tn
		var n := 2
		while used_names.has(unique):
			unique = "%s %d" % [tn, n]
			n += 1
		used_names[unique] = true
		track_of[ci] = unique
		arr.tracks.append({name = unique, color = ch.color})

	# Instruments: a kit per drum channel, a patch per instrument channel.
	var kits := {}
	var patch_of := {}
	for ci: int in track_of:
		var ch: Dictionary = model.channels[ci]
		var keys := _channel_loops(model, ci)
		if ch.kind == "drums":
			var top := 0
			for key: String in keys:
				for nt: Array in model.loops[key].notes:
					top = maxi(top, int(nt[2]) - DRUM_BASE_NOTE)
			var kit := _kit_for(options.get("kit", "punch"), top + 1)
			kit.resource_name = "%s %s" % [base, track_of[ci]]
			kits[ci] = kit
		else:
			patch_of[ci] = _patch_for(model, ci, keys, options.get("patches", {}), warnings)

	# Loops, numbered per track in Auxy's slot order.
	var loops := {}
	for ci: int in track_of:
		var nth := 0
		for key: String in _channel_loops(model, ci):
			nth += 1
			var lp: Dictionary = model.loops[key]
			var l := AKLoop.new()
			l.bars = loop_bars(lp)
			l.beats_per_bar = BEATS_PER_BAR
			l.resource_name = "%s_%s_%d" % [base, slug(String(track_of[ci])), nth]
			if model.channels[ci].kind == "drums":
				l.kind = "percussive"
				l.instrument = kits[ci]
				l.category = "beat"
			else:
				l.kind = "synth"
				l.instrument = patch_of[ci]
				l.category = String((patch_of[ci] as AKPatch).category) if patch_of[ci] is AKPatch else ""
			for nt: Array in lp.notes:
				var row := int(nt[2]) - DRUM_BASE_NOTE if l.kind == "percussive" else int(nt[2])
				if row < 0:
					warnings.append("%s: drum note %d is below the first pad (%d): dropped" % [l.resource_name, nt[2], DRUM_BASE_NOTE])
					continue
				l.notes.append([roundi(float(nt[0]) * AKLoop.TICKS_PER_BEAT), maxi(1, roundi(float(nt[1]) * AKLoop.TICKS_PER_BEAT)), row, snappedf(float(nt[3]), 0.001)])
			loops[key] = l

	# Scenes: one per distinct set of loops, in the order the song first plays them.
	var scene_of := {}
	for sc: Dictionary in model.scenes:
		var sig := _signature(sc.loops)
		if sig == "" or scene_of.has(sig):
			continue
		var clips := {}
		for key: String in sc.loops:
			clips[track_of[int(model.loops[key].channel)]] = key
		scene_of[sig] = "scene %d" % (arr.scenes.size() + 1)
		arr.scenes.append({name = scene_of[sig], bars = 0.0, clips = clips})

	# Timeline: Auxy's scenes in order. A clip carries on while the same loop
	# keeps playing in phase; a loop that restarts (a new scene that starts it
	# from the top) starts a new clip.
	var open := {}   # track -> the clip being extended
	var bar := 0
	var last_sig := "\u0001"
	var marker_names := {}
	for sc: Dictionary in model.scenes:
		var sig := _signature(sc.loops)
		if sig != last_sig:
			var mn := String(scene_of.get(sig, "silence"))
			var k := 2
			var unique := mn
			while marker_names.has(unique):
				unique = "%s (%d)" % [mn, k]
				k += 1
			marker_names[unique] = true
			arr.markers.append({name = unique, bar = float(bar)})
			last_sig = sig
		var playing := {}
		for key: String in sc.loops:
			var lp: Dictionary = model.loops[key]
			var tn := String(track_of[int(lp.channel)])
			var L := loop_bars(lp)
			var phase := int(sc.start_offset) % L
			playing[tn] = true
			var c: Variant = open.get(tn)
			if c != null and String(c.loop) == key and int(float(c.bar) + float(c.bars)) == bar \
					and (int(c.offset_bars) + int(c.bars)) % L == phase:
				c.bars = float(c.bars) + float(sc.bars)
			else:
				var clip := {track = tn, loop = key, bar = float(bar), bars = float(sc.bars), offset_bars = float(phase)}
				arr.timeline.append(clip)
				open[tn] = clip
		for tn: Variant in open.keys():
			if not playing.has(tn):
				open.erase(tn)
		bar += int(sc.bars)
	arr.length_bars = float(bar)

	arr.set_meta(&"auxy", {title = model.title, scale = model.scale, creator = model.creator, bpm = model.bpm,
		format_version = model.format_version, channels = model.channels.map(func(c: Dictionary) -> Dictionary: return {label = c.label, kind = c.kind})})
	arr.set_meta(&"auxy_build", {loops = loops, kits = kits, track_of = track_of})
	return arr


## A file-name-safe lower-case name: "Hexedex - Not So Bad" -> "hexedex_not_so_bad".
static func slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


static func _channel_loops(model: Dictionary, ci: int) -> Array:
	var keys := []
	for key: String in model.loops:
		if int(model.loops[key].channel) == ci:
			keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(model.loops[a].slot) < int(model.loops[b].slot))
	return keys


static func _signature(keys: Array) -> String:
	var s := keys.duplicate()
	s.sort()
	return ",".join(s)


## A kit of `pieces` pieces, piece n a copy of the base kit's piece n (wrapping, renamed to stay unique).
static func _kit_for(base: Variant, pieces: int) -> AKKit:
	var src: AKKit = null
	if base is AKKit:
		src = base
	elif String(base).begins_with("res://") and ResourceLoader.exists(String(base)):
		src = load(String(base)) as AKKit
	else:
		src = AKLibrary.kit(String(base))
	if src == null:
		src = AKLibrary.kit("punch")
	var kit := AKKit.new()
	kit.category = "auxy"
	var names := {}
	for i in maxi(1, pieces):
		var p: Dictionary = src.pieces[i % src.pieces.size()].duplicate(true)
		var nm := String(p.get("name", "pad"))
		var unique := nm
		var n := 2
		while names.has(unique):
			unique = "%s_%d" % [nm, n]
			n += 1
		names[unique] = true
		p["name"] = unique
		kit.pieces.append(p)
	return kit


## The patch for an instrument channel: `choices` by channel index or label,
## else a preset by words in Auxy's preset name, else by the notes' register.
static func _patch_for(model: Dictionary, ci: int, keys: Array, choices: Dictionary, warnings: Array) -> AKPatch:
	var label := String(model.channels[ci].label)
	var pick: Variant = choices.get(ci, choices.get(label, null))
	if pick is AKPatch:
		return pick
	var name := ""
	if pick != null:
		name = String(pick)
	else:
		var low := label.to_lower()
		for rule: Array in PATCH_WORDS:
			for w: String in rule[0]:
				if low.contains(w):
					name = rule[1]
					break
			if name != "":
				break
		if name == "":
			var keys_played := []
			for key: String in keys:
				for nt: Array in model.loops[key].notes:
					keys_played.append(int(nt[2]))
			keys_played.sort()
			var mid := int(keys_played[keys_played.size() / 2]) if not keys_played.is_empty() else 60
			name = "wavetable_bass" if mid < 48 else ("pluck" if mid < 76 else "fm_bell")
	var path := name if name.begins_with("res://") else AKPatchLib.PRESET_DIR + name + ".tres"
	var p: AKPatch = load(path) as AKPatch if ResourceLoader.exists(path) else null
	if p == null:
		warnings.append("no patch %s for %s: using pluck" % [name, label])
		p = load(AKPatchLib.PRESET_DIR + "pluck.tres")
	return p
