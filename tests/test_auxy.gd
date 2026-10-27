# SPDX-License-Identifier: Apache-2.0
# Auxy import (AKAuxy): an "Export for Bitwig Studio" bundle read into data
# and written as loops, kits, stems and an arrangement whose timeline plays
# what Auxy plays, bar for bar. Checked against tests/auxy/fixture.json, an
# answer key written by tools/auxy_fixture/make_fixture.py independently of
# the importer. Set AUXY_FILE to a real .axbw to check one more (its scenes
# against the arrangement; skipped otherwise).
extends RefCounted

const FIXTURE := "res://tests/auxy/fixture.axbw"
const KEY := "res://tests/auxy/fixture.json"
const OUT := "user://test_auxy/"


func _key() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(KEY))


## The import with library kits (drum_samples off): what most checks are about.
func _import(dir := OUT, options := {drum_samples = false}) -> Dictionary:
	AKArrangement.clear_cache()
	return AKAuxy.import_file(ProjectSettings.globalize_path(FIXTURE), dir, options)


## Pitch of mono samples by rising zero crossings (Hz), over the first `seconds`.
static func _pitch(d: PackedFloat32Array, rate: int, seconds := 0.06) -> float:
	var n := mini(d.size(), roundi(seconds * rate))
	var first := -1.0
	var last := -1.0
	var count := 0
	for i in range(1, n):
		if d[i - 1] < 0.0 and d[i] >= 0.0:
			var x := float(i - 1) + (-d[i - 1]) / (d[i] - d[i - 1])
			if first < 0.0:
				first = x
			last = x
			count += 1
	return float(count - 1) * rate / (last - first) if count > 1 else 0.0


## Power at `hz` over the first `seconds` (Goertzel).
static func _goertzel(d: PackedFloat32Array, rate: int, hz: float, seconds: float) -> float:
	var n := mini(d.size(), roundi(seconds * rate))
	var c := 2.0 * cos(TAU * hz / rate)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var s0 := d[i] + c * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - c * s1 * s2


## 10 ms loudness envelope in dB.
static func _envelope(d: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var k := roundi(0.01 * rate)
	var out := PackedFloat32Array()
	for f in d.size() / k:
		var s := 0.0
		for i in range(f * k, (f + 1) * k):
			s += d[i] * d[i]
		out.append(10.0 * log(s / k + 1e-10) / log(10.0))
	return out


## Checks a set of cuts against an answer key's: hit, length, level, pitch, tail warnings.
static func _check_cuts(pads: Array, want: Dictionary, kit: AKKit, warnings: Array) -> String:
	if pads.size() != want.size():
		return "%d pads cut, want %d" % [pads.size(), want.size()]
	for p: Dictionary in pads:
		var w: Dictionary = want[str(int(p.note) - 36)]
		if absf(float(p.start_s) - float(w.start_s)) > 1e-3 or absf(float(p.length_s) - float(w.length_s)) > 2e-3 \
				or absf(float(p.peak_db) - float(w.peak_db)) > 0.05:
			return "pad %d: hit %.3f s, %.4f s long, peak %.2f dB; want %.3f, %.4f, %.2f" % [int(p.note) - 35, p.start_s, p.length_s,
				p.peak_db, w.start_s, w.length_s, w.peak_db]
		# The pad's own pitch carries the most energy at the hit (another pad's tail may ring under it).
		var s: AKSample = load(kit.pieces[int(p.note) - 36].sound)
		var loudest := 0.0
		var power := 0.0
		for f: float in [80.0, 200.0, 500.0, 1200.0, 2500.0]:
			var q := _goertzel(s.data, s.data_rate, f, 0.04)
			if q > power:
				power = q
				loudest = f
		if loudest != float(w.hz):
			return "pad %d sample is loudest at %.0f Hz, want %.0f" % [int(p.note) - 35, loudest, w.hz]
		var warned := warnings.any(func(x: String) -> bool: return x.contains("pad %d (" % (int(p.note) - 35)) and x.contains("tail is cut"))
		if warned != bool(w.tail_cut):
			return "pad %d: tail-cut warning %s, want %s (%s)" % [int(p.note) - 35, warned, w.tail_cut, warnings]
	return ""


## A bar's cell as text, numbers as ints (JSON reads the answer key's numbers as floats).
static func _cell(v: Variant) -> String:
	return "-" if v == null else "%s@%d" % [v[0], int(v[1])]


## What the arrangement's timeline plays per track and bar: [loop, bar into the loop] or null.
static func _timeline_bars(arr: AKArrangement, total: int) -> Dictionary:
	var out := {}
	for t in arr.track_names():
		var row := []
		row.resize(total)
		out[t] = row
	for ci in arr.timeline.size():
		var c: Dictionary = arr.timeline[ci]
		var l := AKArrangement.loop_of(c.loop)
		for sp: Array in arr.clip_spans(ci):
			for b in range(int(sp[0]), int(sp[1])):
				if b < total:
					out[String(c.track)][b] = [l, (int(c.get("offset_bars", 0.0)) + b - int(c.bar)) % l.bars]
	return out


## The answer key's loop key for each imported loop, matched by notes.
static func _keys_by_loop(res: Dictionary, key: Dictionary) -> Dictionary:
	var out := {}
	for p: String in res.loops:
		var l: AKLoop = load(p)
		for k: String in key.loops:
			if JSON.stringify(l.sorted_notes()) == JSON.stringify(key.loops[k].notes.map(func(n: Array) -> Array:
					return [int(n[0]), int(n[1]), int(n[2]), snappedf(float(n[3]), 1e-6)])):
				out[l] = k
	return out


func test_read_bundle() -> String:
	var m := AKAuxy.read(ProjectSettings.globalize_path(FIXTURE))
	if not m.ok:
		return "read failed: %s" % m.error
	var k := _key()
	if not is_equal_approx(float(m.bpm), float(k.bpm)) or m.title != "Fixture - Test Song" or m.scale != "C Minor":
		return "header: %s %s %s" % [m.bpm, m.title, m.scale]
	if m.channels.size() != 5 or m.channels[0].kind != "drums" or not m.channels[0].color.is_equal_approx(Color.html("#0270D6")):
		return "channels: %s" % [m.channels]
	if m.loops.size() != k.loops.size() or m.scenes.size() != 9 or m.stems.size() != 5:
		return "counts: %d loops, %d scenes, %d stems" % [m.loops.size(), m.scenes.size(), m.stems.size()]
	if not m.warnings.is_empty():
		return "warnings: %s" % [m.warnings]
	for kk: String in k.loops:
		var lp: Dictionary = m.loops[kk]
		if AKAuxy.loop_bars(lp) != int(k.loops[kk].bars):
			return "loop %s: %d bars, want %d" % [kk, AKAuxy.loop_bars(lp), k.loops[kk].bars]
		if lp.notes.size() != k.loops[kk].notes.size():
			return "loop %s: %d notes, want %d" % [kk, lp.notes.size(), k.loops[kk].notes.size()]
	var fill: Array = m.loops["0_1"].notes.filter(func(n: Array) -> bool: return int(n[2]) == 39)
	if fill.size() != 3 or absf(float(fill[0][3]) - 100.0 / 127.0) > 1e-6:
		return "velocity 100 read as %s" % [fill]
	var s4: Dictionary = m.scenes[4]
	if s4.bars != 3 or s4.start_offset != 1 or s4.loops != ["0_1", "1_0", "2_0"]:
		return "scene 5: %s" % [s4]
	return ""


## The scenes expanded as Auxy plays them: what every later check stands on.
func test_bar_map_matches_answer_key() -> String:
	var m := AKAuxy.read(ProjectSettings.globalize_path(FIXTURE))
	var k := _key()
	var bm := AKAuxy.bar_map(m)
	for c: String in k.track_of:
		var want: Array = k.bars[k.track_of[c]]
		var got: Array = bm[int(c)]
		if got.size() != int(k.total_bars):
			return "channel %s: %d bars" % [c, got.size()]
		for b in want.size():
			if _cell(got[b]) != _cell(want[b]):
				return "channel %s bar %d: %s, want %s" % [c, b + 1, got[b], want[b]]
	return ""


func test_import_writes_loops_kits_and_arrangement() -> String:
	var res := _import()
	if not res.ok:
		return "import failed: %s" % res.error
	var k := _key()
	var arr: AKArrangement = ResourceLoader.load(res.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if arr == null:
		return "arrangement didn't reload from %s" % res.path
	if arr.track_names() != k.tracks:
		return "tracks %s, want %s" % [arr.track_names(), k.tracks]
	if not (arr.tracks[0].color as Color).is_equal_approx(Color.html("#0270D6")):
		return "track colour %s" % arr.tracks[0].color
	if not is_equal_approx(arr.tempo.bpm, float(k.bpm)) or int(arr.length_bars) != int(k.total_bars):
		return "tempo %s, length %s" % [arr.tempo.bpm, arr.length_bars]
	if res.warnings.size() != 1 or not String(res.warnings[0]).contains("Empty One"):
		return "warnings %s (want only the empty channel's)" % [res.warnings]
	if res.loops.size() != k.loops.size() or res.kits.size() != 1:
		return "%d loops, %d kits" % [res.loops.size(), res.kits.size()]
	for p: String in res.loops:
		if not p.get_file().begins_with("fixture_test_song_") or p.get_base_dir() != OUT + "loops":
			return "loop file %s isn't flat in loops/ with the song's prefix" % p
	# Every loop note for note, at the right length and kind, on the right instrument.
	var by := _keys_by_loop(res, k)
	if by.size() != k.loops.size():
		return "only %d of %d loops match the answer key's notes" % [by.size(), k.loops.size()]
	var kit: AKKit = load(res.kits[0])
	if kit.pieces.size() != int(k.kit_pieces) or kit.piece_name(0) != "kick" or kit.piece_name(1) != "snare":
		return "kit pieces %s" % [kit.pieces.map(func(p: Dictionary) -> String: return p.name)]
	for l: AKLoop in by:
		var kk: String = by[l]
		if l.bars != int(k.loops[kk].bars):
			return "loop %s: %d bars" % [kk, l.bars]
		var drums := kk.begins_with("0_")
		if drums != (l.kind == "percussive"):
			return "loop %s kind %s" % [kk, l.kind]
		if drums and l.instrument.resource_path != res.kits[0]:
			return "loop %s plays %s, not the saved kit" % [kk, l.instrument.resource_path]
	# Patches guessed from the preset names.
	for t: String in k.patches:
		var clip := arr.timeline.filter(func(c: Dictionary) -> bool: return c.track == t)
		if clip.is_empty():
			return "no clips on %s" % t
		var l := AKArrangement.loop_of(clip[0].loop)
		if l.instrument.resource_path.get_file().get_basename() != k.patches[t]:
			return "%s plays %s, want %s" % [t, l.instrument.resource_path, k.patches[t]]
	return ""


## The gate: the arrangement's timeline plays what Auxy plays, every track, every bar.
func test_timeline_plays_what_auxy_plays() -> String:
	var res := _import()
	if not res.ok:
		return "import failed: %s" % res.error
	var k := _key()
	var arr: AKArrangement = ResourceLoader.load(res.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var by := _keys_by_loop(res, k)
	var tb := _timeline_bars(arr, int(k.total_bars))
	for t: String in k.bars:
		for b in int(k.total_bars):
			var want: Variant = k.bars[t][b]
			var got: Variant = tb[t][b]
			var g: Variant = null if got == null else [by[got[0]], got[1]]
			if _cell(g) != _cell(want):
				return "%s bar %d: %s, want %s" % [t, b + 1, g, want]
	var mb := arr.markers.map(func(m: Dictionary) -> int: return int(m.bar))
	if mb != k.markers.map(func(x: float) -> int: return int(x)):
		return "markers at %s, want %s" % [mb, k.markers]
	if not arr.markers.any(func(m: Dictionary) -> bool: return m.name == "silence"):
		return "the empty scene has no marker"
	# Merging: a clip runs on while its loop plays on in phase. The one-bar 0_0
	# runs through scenes 1-4 as one clip. The two-bar 1_0 ends scene 2 back
	# at its start, so scene 3 (from the top) carries on; scene 4 restarts it
	# a bar early (a new clip), and scene 5's start_offset 1 then lines up again.
	var kit_clips := arr.timeline.filter(func(c: Dictionary) -> bool: return c.track == "Kit Alpha")
	var bass_clips := arr.timeline.filter(func(c: Dictionary) -> bool: return c.track == "Fat Basset")
	var spans := func(cs: Array) -> String: return " ".join(cs.map(func(c: Dictionary) -> String:
		return "%d+%d@%d" % [int(c.bar), int(c.bars), int(c.offset_bars)]))
	if spans.call(kit_clips) != "0+8@0 8+7@1 18+2@0":
		return "Kit Alpha clips %s" % spans.call(kit_clips)
	if spans.call(bass_clips) != "2+5@0 7+8@0 15+2@0":
		return "Fat Basset clips %s" % spans.call(bass_clips)
	# Compiled, the timeline sounds every note it should.
	var song := arr.to_song("timeline")
	if song.sections.size() != k.markers.size():
		return "%d sections, want %d" % [song.sections.size(), k.markers.size()]
	var n := song.events().size()
	if n != int(k.notes_played):
		return "%d notes play, want %d" % [n, k.notes_played]
	return ""


func test_scenes_and_stems() -> String:
	var res := _import()
	if not res.ok:
		return "import failed: %s" % res.error
	var k := _key()
	var arr: AKArrangement = ResourceLoader.load(res.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var by := _keys_by_loop(res, k)
	if arr.scenes.size() != k.scenes.size():
		return "%d scenes, want %d" % [arr.scenes.size(), k.scenes.size()]
	for si in arr.scenes.size():
		var keys := []
		for t in arr.scenes[si].clips:
			keys.append(by[AKArrangement.loop_of(arr.scenes[si].clips[t])])
		keys.sort()
		if ",".join(keys) != k.scenes[si]:
			return "scene %d plays %s, want %s" % [si + 1, keys, k.scenes[si]]
	var stems: Array = res.stems.keys()
	stems.sort()
	if stems != k.stems:
		return "stems for %s, want %s (the empty channel's left out)" % [stems, k.stems]
	var meta: Dictionary = arr.get_meta(&"auxy", {})
	if (meta.get("stems", {}) as Dictionary).size() != stems.size() or meta.get("scale") != "C Minor":
		return "metadata %s" % [meta]
	# Each stem is its channel's file, copied byte for byte (its samples mark the channel).
	var w := FileAccess.get_file_as_bytes(res.stems["Glass Lead"])
	if w.size() != 44 + 441 * 4 or w.decode_s16(44) != 400:
		return "Glass Lead stem: %d bytes, first sample %d" % [w.size(), w.decode_s16(44) if w.size() > 45 else -1]
	return ""


## A kit with a pad map (Battery) gets its sounds per pad; an option overrides it.
func test_known_drum_kit() -> String:
	var m := AKAuxy.read(ProjectSettings.globalize_path(FIXTURE))
	m.channels[0].label = "Battery"
	var warnings := []
	var arr := AKAuxy.to_arrangement(m, {}, warnings)
	var kits: Dictionary = arr.get_meta(&"auxy_build").kits
	var kit: AKKit = kits[0]
	var want: Array = AKAuxy.KIT_MAPS.battery
	# The whole kit, not just the 5 pads this song plays, so every pad is there to write with.
	if kit.pieces.size() != want.size():
		return "Battery kit has %d pieces, want %d" % [kit.pieces.size(), want.size()]
	for i in want.size():
		if kit.piece_name(i) != want[i].name or kit.pieces[i].sound != want[i].sound:
			return "pad %d: %s, want %s" % [i + 1, kit.pieces[i], want[i]]
	if not warnings.filter(func(w: String) -> bool: return w.contains("pad")).is_empty():
		return "warnings %s" % [warnings]
	# Every mapped sound exists.
	for p: Dictionary in want:
		if not ResourceLoader.exists(p.sound):
			return "no %s" % p.sound
	# More pads than the map knows: the rest come from the base kit, with a warning.
	var short := {"Battery": [{name = "kick", sound = want[0].sound}]}
	arr = AKAuxy.to_arrangement(m, {drum_maps = short}, warnings)
	kit = arr.get_meta(&"auxy_build").kits[0]
	if kit.pieces.size() != 5 or kit.piece_name(0) != "kick" or kit.piece_name(1) != "snare":
		return "short map: %s" % [kit.pieces.map(func(p: Dictionary) -> String: return p.name)]
	if warnings.filter(func(w: String) -> bool: return w.contains("knows 1 pads")).is_empty():
		return "no warning for the short map: %s" % [warnings]
	return ""


## Drums in Auxy's own sounds: each pad cut from the song's stem, then the
## song played on that kit sounds like the stem.
func test_drum_samples_cut_from_the_song() -> String:
	AKArrangement.clear_cache()
	var res := AKAuxy.import_file(ProjectSettings.globalize_path(FIXTURE), OUT + "cut/")
	if not res.ok:
		return "import failed: %s" % res.error
	var k := _key()
	var arr: AKArrangement = ResourceLoader.load(res.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var clip: Dictionary = arr.timeline.filter(func(c: Dictionary) -> bool: return c.track == "Kit Alpha")[0]
	var kit: AKKit = AKArrangement.loop_of(clip.loop).instrument
	if kit.resource_path != OUT + "cut/kits/fixture_test_song_kit_alpha.tres":
		return "drums play %s" % kit.resource_path
	if kit.pieces.size() != int(k.kit_pieces):
		return "%d pieces, want %d" % [kit.pieces.size(), k.kit_pieces]
	for i in 4:
		if not String(kit.pieces[i].sound).begins_with(OUT + "cut/samples/auxy/fixture_test_song_kit_alpha/0%d_" % (i + 1)):
			return "pad %d plays %s" % [i + 1, kit.pieces[i].sound]
	# Pad 5 isn't in the song: it keeps the kit it would have had (the punch kit's fifth piece).
	if kit.pieces[4].sound != AKLibrary.kit("punch").pieces[4].sound:
		return "pad 5 plays %s" % kit.pieces[4].sound
	var err := _check_cuts(res.drum_cuts["Kit Alpha"], k.cuts, kit, res.warnings)
	if err != "":
		return err
	# The drums alone, raw, against the stem: the same loudness, 10 ms at a time.
	for t in arr.tracks:
		t["solo"] = t.name == "Kit Alpha"
	arr.master_fx = [] as Array[Dictionary]
	arr.reverb = {room = 0.5, damp = 0.5, width = 1.0, quality = &"full", return_db = -120.0}
	AKArrangement.clear_cache()
	var buf: AKBuffer = arr.to_song("timeline").render().mix
	var mono := PackedFloat32Array()
	mono.resize(buf.l.size())
	for i in buf.l.size():
		mono[i] = 0.5 * (buf.l[i] + buf.r[i])
	var stem := AKAuxy._stem(ProjectSettings.globalize_path(FIXTURE), res.model, 0)
	var a := _envelope(stem.data, stem.rate)
	var b := _envelope(mono, buf.sample_rate)
	var n := mini(a.size(), b.size())
	var sa := 0.0
	var sb := 0.0
	var m := 0
	for i in n:
		if a[i] > -60.0 or b[i] > -60.0:
			sa += a[i]
			sb += b[i]
			m += 1
	sa /= m
	sb /= m
	var num := 0.0
	var da := 0.0
	var db := 0.0
	var diff := 0.0
	for i in n:
		if a[i] > -60.0 or b[i] > -60.0:
			num += (a[i] - sa) * (b[i] - sb)
			da += (a[i] - sa) * (a[i] - sa)
			db += (b[i] - sb) * (b[i] - sb)
			diff += absf(maxf(a[i], -60.0) - maxf(b[i], -60.0))
	var corr := num / sqrt(da * db)
	if corr < 0.97 or diff / m > 2.0:
		return "drums vs stem: envelope correlation %.3f, mean difference %.1f dB" % [corr, diff / m]
	return ""


## A pad test makes a kit of Auxy's sounds; later imports on that kit use it.
func test_kit_from_pads() -> String:
	var dir := OUT + "pads/"
	var res := AKAuxy.kit_from_pads(ProjectSettings.globalize_path("res://tests/auxy/pads.axbw"), dir)
	if not res.ok:
		return "kit_from_pads failed: %s" % res.error
	var k: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/auxy/pads.json"))
	if res.path != dir + "kits/auxy_kit_alpha.tres":
		return "kit at %s" % res.path
	var kit: AKKit = ResourceLoader.load(res.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if kit.pieces.size() != int(k.pads) or kit.piece_name(4) != "pad_5":
		return "pieces %s" % [kit.pieces.map(func(p: Dictionary) -> String: return p.name)]
	if res.warnings.filter(func(w: String) -> bool: return w.contains("pad 5 (note 40) isn't played")).size() != 1:
		return "no warning for the pad the test leaves out: %s" % [res.warnings]
	var err := _check_cuts(res.pads, k.cuts, kit, res.warnings)
	if err != "":
		return err
	# Every sample plays as cut: the kit's piece rendered at its root is the cut, resampled to 48 kHz.
	var s: AKSample = load(kit.pieces[1].sound)
	var r := AK.render(kit.piece_recipe(1))
	var hz := _pitch(r.l, r.sample_rate)
	if absf(hz / 200.0 - 1.0) > 0.02:
		return "pad 2 renders at %.1f Hz" % hz
	# An import on the same Auxy kit, without cutting its own drums, plays this kit.
	AKArrangement.clear_cache()
	var imp := AKAuxy.import_file(ProjectSettings.globalize_path(FIXTURE), dir, {drum_samples = false})
	if not imp.kits.has(res.path):
		return "the import used %s, not the pad kit" % [imp.kits]
	var loop := AKArrangement.loop_of(imp.loop_paths["0_0"])
	if loop.instrument.resource_path != res.path:
		return "loops play %s" % loop.instrument.resource_path
	if imp.warnings.filter(func(w: String) -> bool: return w.contains("pad")).size() != 0:
		return "warnings %s" % [imp.warnings]
	return ""


func test_bad_files() -> String:
	var r := AKAuxy.read(ProjectSettings.globalize_path("res://tests/midi/minuet_g.mid"))
	if r.ok or r.error == "":
		return "a .mid read as a bundle"
	var res := AKAuxy.import_file(ProjectSettings.globalize_path("res://tests/auxy/nope.axbw"), OUT)
	if res.ok or res.error == "":
		return "a missing file imported"
	return ""


## The Sequencer's import: the arrangement opens, its loops show in the browser.
func test_sequencer_import() -> String:
	var lab := AKSequencerLab.new()
	lab.audio_output = false
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	lab.set_save_dir(OUT + "lab/")
	var a := lab.import_auxy(ProjectSettings.globalize_path(FIXTURE))
	var err := ""
	if a == null or lab.arrangement != a:
		err = "the import didn't open"
	elif not lab.arrangement_path.ends_with("arrangements/fixture_test_song.tres"):
		err = "arrangement path %s" % lab.arrangement_path
	elif lab.loops.entries().size() != _key().loops.size():
		err = "loop browser lists %d loops" % lab.loops.entries().size()
	elif not lab._status.text.begins_with("Imported fixture.axbw: 4 tracks, 8 loops, 6 scenes, 20 bars, 4 stems"):
		err = "status: %s" % lab._status.text
	lab.stop()
	lab.queue_free()
	return err


## A real export, when AUXY_FILE points at one: its scenes against the arrangement's timeline.
func test_real_export_if_given() -> String:
	var path := OS.get_environment("AUXY_FILE")
	if path == "":
		return ""
	var res := AKAuxy.import_file(path, OUT + "real/", {stems = false})
	if not res.ok:
		return "import failed: %s" % res.error
	var arr: AKArrangement = ResourceLoader.load(res.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var bm := AKAuxy.bar_map(res.model)
	var total := int(arr.length_bars)
	var tb := _timeline_bars(arr, total)
	var checked := 0
	for ci: int in bm:
		var row: Array = bm[ci]
		var t := String(res.track_of.get(ci, ""))
		for b in total:
			var want: Variant = null if row[b] == null else [res.loop_paths[row[b][0]], int(row[b][1])]
			var got: Variant = null if t == "" or tb[t][b] == null else [(tb[t][b][0] as AKLoop).resource_path, int(tb[t][b][1])]
			if _cell(want) != _cell(got):
				return "channel %d bar %d: %s, timeline %s" % [ci, b + 1, want, got]
			checked += 1
	print("    real export: %s, %d tracks, %d loops, %d scenes, %d bars, %d track-bars checked" % [path.get_file(), arr.tracks.size(),
		res.loops.size(), arr.scenes.size(), total, checked])
	return ""
