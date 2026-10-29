# SPDX-License-Identifier: Apache-2.0
# Phase 10: games and polish. Pattern lanes and .mid tracks to loops (and
# the Loops tab's import), arrangements in AKLivePlayer (play_scene,
# play_timeline), AKCueBridge and AK.render_cues; "Neon Circuit" re-made as
# loops and an arrangement; and the gate: that arrangement plays in a demo
# scene that switches scenes from game state, each switch on the next bar,
# the music what a bake of the same scenes gives.
extends RefCounted

const SR := 48000
const MIDI := "res://tests/midi/"
const RACE := "res://demo/racing/"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _snr(a: AKBuffer, ref: AKBuffer, n: int) -> float:
	var se := 0.0
	var ss := 0.0
	for i in mini(n, mini(a.frames(), ref.frames())):
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)


# ------------------------------------------------------------------ to loops

func test_pattern_lanes_to_loops() -> String:
	var kick := AKRecipe.make(&"kick", {})
	var hat := AKRecipe.make(&"hat", {})
	var p := AKPattern.new()
	p.steps = 16
	p.lanes = [{name = "kick", recipe = kick, steps = "X...x...X...x..."}, {name = "hat", recipe = hat, steps = "..o...o...o...o.", gain_db = -4.0},
		{name = "bass", patch = "res://addons/audio_kit/patches/pluck.tres", events = [[0.0, 0.5, 45, 0.9], [1.25, 0.25, 48, 0.6], [3.0, 1.0, 43, 1.0]]}]
	var beat := AKLoop.from_pattern(p, ["kick", "hat"])
	var kit := beat.instrument as AKKit
	if beat.kind != "percussive" or kit.piece_count() != 2 or kit.piece_name(1) != "hat" or float(kit.pieces[1].gain_db) != -4.0:
		return "drums: %s, %s" % [beat.kind, kit.pieces if kit else null]
	var want := [[0, 24, 0, 1.0], [96, 24, 0, 0.85], [192, 24, 0, 1.0], [288, 24, 0, 0.85]]
	for t in [48, 144, 240, 336]:
		want.append([t, 24, 1, 0.5])
	want.sort()
	var got := beat.sorted_notes()
	if got.size() != want.size():
		return "drum notes %s" % [got]
	for i in got.size():
		if got[i][0] != want[i][0] or got[i][2] != want[i][2]:
			return "drum note %d: %s, want %s" % [i, got[i], want[i]]
	var bass := AKLoop.from_pattern(p, ["bass"])
	var bass_want := [[0, 48, 45, 0.9], [120, 24, 48, 0.6], [288, 96, 43, 1.0]]
	var bass_got := bass.sorted_notes()
	var bass_ok := bass.kind == "synth" and bass.instrument is AKPatch and bass_got.size() == 3
	for i in 3 if bass_ok else 0:
		for j in 3:
			bass_ok = bass_ok and int(bass_got[i][j]) == int(bass_want[i][j])
		bass_ok = bass_ok and absf(float(bass_got[i][3]) - float(bass_want[i][3])) < 1e-6
	if not bass_ok:
		return "bass: %s %s" % [bass.kind, bass_got]
	# Compiled back, the loop plays what the pattern did.
	var tm := AKTempoMap.make(120.0)
	var a := p.events(tm, 0.0, 4.0).filter(func(e: Dictionary) -> bool: return e.lane == "kick").map(func(e: Dictionary) -> float: return snappedf(e.time_s, 1e-6))
	var b := beat.to_pattern().events(tm, 0.0, 4.0).filter(func(e: Dictionary) -> bool: return e.lane == "drums.kick").map(func(e: Dictionary) -> float: return snappedf(e.time_s, 1e-6))
	if a != b:
		return "the loop's kicks %s, the pattern's %s" % [b, a]
	# A recipe lane with pitches becomes a sample loop rooted at the recipe's pitch.
	p.lanes.append({name = "bell", recipe = AKRecipe.make(&"mallet", {freq_hz = 440.0}), steps = "x...x...", notes = ["C5", "E5"]})
	var bell := AKLoop.from_pattern(p, ["bell"])
	if bell.kind != "sample" or absf((bell.instrument as AKSample).root_note - 69.0) > 0.01 or bell.sorted_notes()[1][2] != 76:
		return "bell: %s %s" % [bell.kind, bell.sorted_notes()]
	return ""


func test_mid_tracks_to_loops() -> String:
	var song := AKMidi.import_file(MIDI + "groove_meter_pedal.mid")
	var drums: Array = []
	var pitched := ""
	for e in song.events():
		var ln := String(e.lane)
		if ln.begins_with("drums.") and not drums.has(ln):
			drums.append(ln)
		elif not ln.begins_with("drums.") and pitched == "" and int(e.midi) >= 0:
			pitched = ln
	if drums.is_empty() or pitched == "":
		return "the groove should have drums and a pitched track: %s %s" % [drums, pitched]
	var L := song.layout()
	var sec0: Dictionary = L[0]
	var bars := mini(2, floori(float(sec0.bars)))
	var beat := AKLoop.from_song(song, drums, 0, 0.0, bars)
	var mel := AKLoop.from_song(song, [pitched], 0, 0.0, bars)
	if beat == null or beat.kind != "percussive" or mel == null or mel.kind != "synth":
		return "loops from the .mid: %s %s" % [beat.kind if beat else null, mel.kind if mel else null]
	# Every note of those bars is in the loop, at its tick (the corpus is on a 16th grid or finer).
	var bpb := song.tempo.beats_per_bar_at(0.0)
	var spb := 60.0 / song.tempo.bpm
	var want := song.events().filter(func(e: Dictionary) -> bool:
		return String(e.lane) == pitched and e.section == sec0.name and float(e.time_s) < song.tempo.bar_to_seconds(bars) - 1e-9)
	if mel.notes.size() != want.size():
		return "%d melody notes in the loop, %d in the file's first %d bars" % [mel.notes.size(), want.size(), bars]
	var sorted := mel.sorted_notes()
	for i in want.size():
		var t := roundi(song.tempo.beats_at_bar(song.tempo.seconds_to_bar(float(want[i].time_s))) * AKLoop.TICKS_PER_BEAT)
		if sorted[i][0] != t or sorted[i][2] != int(want[i].midi):
			return "melody note %d: %s, want tick %d midi %d" % [i, sorted[i], t, want[i].midi]
	var dcount := song.events().filter(func(e: Dictionary) -> bool:
		return drums.has(String(e.lane)) and e.section == sec0.name and float(e.time_s) < song.tempo.bar_to_seconds(bars) - 1e-9).size()
	if beat.notes.size() != dcount or (beat.instrument as AKKit).piece_count() != drums.size():
		return "%d drum notes (want %d), %d pieces" % [beat.notes.size(), dcount, (beat.instrument as AKKit).piece_count()]
	if bpb <= 0.0 or spb <= 0.0:
		return "tempo"
	return ""


func test_loops_tab_imports_a_lane() -> String:
	var lab := AKLoopLab.new()
	lab.audio_output = false
	_tree().root.add_child(lab)
	lab.set_save_dir("user://test_games/")
	lab._imp_path.text = MIDI + "minuet_g.mid"
	(lab.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Load")[0] as Button).pressed.emit()
	if lab._imp_lane.item_count == 0 or lab._imp_section.item_count == 0:
		lab.queue_free()
		return "Load should list the file's lanes and sections"
	lab._imp_lane.select(0)
	lab._imp_bars.value = 4
	(lab.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Make loop")[0] as Button).pressed.emit()
	var l := lab.loop
	var ok := l.kind == "synth" and l.bars == 4 and l.notes.size() > 8 and lab.grid.loop == l
	lab.queue_free()
	return "" if ok else "the imported loop: %s, %d bars, %d notes" % [l.kind, l.bars, l.notes.size()]


# ------------------------------------------------------------------ the racing song as an arrangement

func test_racing_arrangement_matches_the_song() -> String:
	var arr: AKArrangement = load(RACE + "arrangement/neon_circuit.tres")
	var song: AKSong = load(RACE + "song/neon_circuit.tres")
	if arr == null or arr.scene_names() != ["intro", "build", "race", "break", "final_lap", "finish"]:
		return "the arrangement's scenes: %s" % [arr.scene_names() if arr else null]
	# The loops are what the song's patterns convert to (fresh files).
	for pair in [["pad", "race", ["pad"], 4], ["arp", "race", ["arp"], 4], ["bass", "race", ["bass"], 4], ["lead", "race", ["lead"], 8], ["break_lead", "break", ["lead"], 4]]:
		var saved: AKLoop = load(RACE + "loops/%s.tres" % pair[0])
		var made := AKLoop.from_pattern(load(RACE + "song/p_%s.tres" % pair[1]), pair[2], pair[3])
		if saved.sorted_notes() != made.sorted_notes():
			return "loops/%s.tres is stale: run demo/racing/make_arrangement.gd" % pair[0]
	# The timeline plays the song's notes: in the race section, every pad,
	# arp, bass and lead note and every kick and snare at the same time and pitch.
	var tl := arr.to_song("timeline")
	if absf(tl.length_s() - song.length_s()) > 1e-6 or tl.layout().map(func(L: Dictionary) -> String: return L.name) != song.layout().map(func(L: Dictionary) -> String: return L.name):
		return "the timeline's sections should be the song's: %.2f s vs %.2f s" % [tl.length_s(), song.length_s()]
	var key := func(e: Dictionary, lane: String) -> String: return "%s %.6f %d" % [lane, e.time_s, e.midi]
	for sec in ["race", "final_lap", "break"]:
		var want := {}
		for e in song.events():
			if e.section == sec and String(e.lane) in ["pad", "arp", "bass", "lead", "lead_low", "kick", "snare"]:
				want[key.call(e, String(e.lane))] = true
		var got := {}
		for e in tl.events():
			if e.section == sec:
				var ln := String(e.lane).trim_prefix("drums.")
				if ln in ["pad", "arp", "bass", "lead", "lead_low", "kick", "snare"]:
					got[key.call(e, ln)] = true
		if got.size() != want.size():
			return "%s: %d notes in the arrangement, %d in the song" % [sec, got.size(), want.size()]
		for k in want:
			if not got.has(k):
				return "%s: the arrangement is missing %s" % [sec, k]
	return ""


func test_live_player_and_bridge_take_arrangements() -> String:
	var arr: AKArrangement = load(RACE + "arrangement/neon_circuit.tres")
	# render_cues and track_key take an arrangement as the music.
	var m := AKCueMap.new()
	m.master_fx = [{type = &"limit", ceiling_db = -1.0}]
	if AK.track_key([], m, 30.0, 2.0, arr) != AK.track_key([], m, 30.0, 2.0, arr.to_song("timeline")):
		return "track_key should treat an arrangement as its timeline"
	var b := AKCueBridge.new()
	b.arrangement = arr
	if b.get("arrangement") != arr:
		return "AKCueBridge.arrangement"
	b.free()
	if not AKLive.available():
		print("        (native core not built: live parts skipped)")
		return ""
	var p := AKLivePlayer.new()
	p.arrangement = arr
	p.audio_output = false
	_tree().root.add_child(p)
	p.play_scene("intro")
	var started := []
	p.live.section_started.connect(func(n: String, _f: int) -> void: started.append(n))
	p.live.render_playing(SR)
	p.play_scene("race", &"bar")
	p.live.render_playing(roundi(3.0 * SR))
	var ok := p.current_scene == "race" and p.arrangement_mode == "scenes" and started.has("race")
	p.play_timeline("break")
	p.live.render_playing(SR / 2)
	ok = ok and p.arrangement_mode == "timeline" and p.live.song_position().section == "break"
	p.queue_free()
	return "" if ok else "play_scene / play_timeline: %s, %s, %s" % [p.current_scene, p.arrangement_mode, started]


# ------------------------------------------------------------------ the gate

func test_gate_race_demo_switches_scenes_from_game_state() -> String:
	var arr: AKArrangement = (load(RACE + "arrangement/neon_circuit.tres") as AKArrangement).duplicate(true)
	# Without the loudness step: live it's measured over every scene in turn,
	# a bake over what it renders (see docs/loops.md).
	arr.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	var demo: Node2D = load(RACE + "race_demo.tscn").instantiate()
	demo.set("arrangement", arr)
	demo.set("audio", false)
	demo.set("sfx", false)
	demo.set("laps", 3)
	demo.set("lap_time_s", 8.0)
	demo.set("menu_s", 2.0)
	_tree().root.add_child(demo)
	var player: AKLivePlayer = demo.get("player")
	if player.live == null:
		demo.queue_free()
		print("        (native core not built: the race runs, the music is skipped)")
		return ""
	var live := player.live
	var origin: int = live._seq_origin
	var states := []
	demo.connect("state_changed", func(s: String) -> void: states.append([s, live.get_frame()]))
	# The intro started in _ready, before we could listen.
	var starts := [[player.current_scene, 0]] if player.current_scene != "" else []
	live.section_started.connect(func(n: String, f: int) -> void: starts.append([n, f - origin]))
	# Drive the race at 60 frames a second, pulling the music as it goes.
	var out := AKBuffer.new(0, SR)
	var frame_dt := 1.0 / 60.0
	var guard := 0
	while guard < 60 * 90:
		guard += 1
		demo.call("advance", frame_dt)
		var chunk := live.render_playing(SR / 60)
		out.l.append_array(chunk.l)
		out.r.append_array(chunk.r)
		if String(demo.get("state")) == "finished" and states.size() > 0 and live.get_frame() - int(states[-1][1]) > 4 * SR:
			break
	demo.queue_free()
	var order := starts.map(func(x: Array) -> String: return x[0])
	var dedup := []
	for n in order:
		if dedup.is_empty() or dedup[-1] != n:
			dedup.append(n)
	if dedup != ["intro", "build", "race", "final_lap", "finish"]:
		return "scenes played in the order %s (states %s)" % [order, states.map(func(x: Array) -> String: return x[0])]
	# Each switch lands on the first bar after the game asked for it.
	var bar_f := roundi(arr.tempo.bar_to_seconds(1.0) * SR)
	var scene_of := {menu = "intro", countdown = "build", racing = "race", final_lap = "final_lap", finished = "finish"}
	for st in states.slice(1):
		var want_scene: String = scene_of[st[0]]
		var asked: int = int(st[1]) - origin
		var landing := ceili(float(asked) / bar_f) * bar_f
		var hit := starts.filter(func(x: Array) -> bool: return x[0] == want_scene and int(x[1]) >= asked)
		if hit.is_empty() or int(hit[0][1]) != landing:
			return "%s asked at frame %d should start at %d (the next bar), started %s" % [want_scene, asked, landing, hit]
	# And the music is a bake of the scenes as they played (each instance:
	# its scene for as many bars as it sounded).
	var scenes := arr.to_song("scenes")
	var ref := AKSong.new()
	ref.tempo = arr.tempo
	ref.mix = scenes.mix
	ref.intensity_lanes = scenes.intensity_lanes
	ref.lane_groups = scenes.lane_groups
	ref.group_fx = scenes.group_fx
	ref.reverb = scenes.reverb
	ref.master_fx = scenes.master_fx
	ref.stingers = scenes.stingers
	var secs: Array[Dictionary] = []
	for i in starts.size():
		var end_f: int = int(starts[i + 1][1]) if i + 1 < starts.size() else out.frames()
		var bars := float(end_f - int(starts[i][1])) / bar_f
		var s: Dictionary = scenes.sections[arr.scene_index(starts[i][0])].duplicate()
		s["bars"] = bars
		secs.append(s)
	ref.sections = secs
	var want: AKBuffer = ref.render().mix
	var snr := _snr(out, want, out.frames())
	print("        the race demo: %d scene starts %s, every switch on the next bar; music vs a bake of the same scenes SNR %.1f dB" % [starts.size(), dedup, snr])
	if out.peak() < 0.05:
		return "the race was silent"
	return "" if snr > 90.0 else "the demo's music vs its bake: SNR %.1f dB" % snr
