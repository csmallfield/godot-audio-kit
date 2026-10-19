# SPDX-License-Identifier: Apache-2.0
extends RefCounted


func _tempo() -> AKTempoMap:
	return AKTempoMap.make(120.0, 4, 0.25)


func _hits(p: AKPattern, beats := 4.0) -> Array:
	return p.events(_tempo(), 0.0, beats)


func _pat(lanes: Array, steps := 16) -> AKPattern:
	var p := AKPattern.new()
	p.steps = steps
	p.lanes.assign(lanes)
	return p


func _crossings(b: AKBuffer) -> int:
	var c := 0
	for i in range(1, b.frames()):
		if b.l[i - 1] > 0.0 and b.l[i] <= 0.0:
			c += 1
	return c


func test_tempo_map() -> String:
	var t := _tempo()
	if not is_equal_approx(t.bar_to_seconds(1.0), 2.25):
		return "bar 1 at %.3f, expected 2.25" % t.bar_to_seconds(1.0)
	if not is_equal_approx(t.to_seconds(1.0, 2.0), 3.25):
		return "bar 1 beat 2 at %.3f" % t.to_seconds(1.0, 2.0)
	t.changes = [{bar = 2, bpm = 60.0}] as Array[Dictionary]
	if not is_equal_approx(t.bar_to_seconds(3.0), 8.25):
		return "after a change to 60 bpm, bar 3 at %.3f, expected 8.25" % t.bar_to_seconds(3.0)
	if not is_equal_approx(t.seconds_to_bar(8.25), 3.0):
		return "seconds_to_bar(8.25) = %.3f" % t.seconds_to_bar(8.25)
	return ""


func test_note_names_and_degrees() -> String:
	var cases := {"A4": 69, "C4": 60, "F#2": 42, "Bb3": 58, "C-1": 0}
	for k in cases:
		if AKNotes.name_to_midi(k) != cases[k]:
			return "%s -> %d, expected %d" % [k, AKNotes.name_to_midi(k), cases[k]]
	if AKNotes.degree_to_midi(8, &"minor", "A3") != 69 or AKNotes.degree_to_midi(3, &"minor", "A3") != 60:
		return "scale degrees wrong"
	if AKNotes.degree_to_midi(0, &"major", "C4") != 59:
		return "degree 0 should be the note below the root"
	return "" if absf(AKNotes.note_hz("A4") - 440.0) < 1e-6 else "A4 not 440 Hz"


func test_step_strings() -> String:
	var s := AKNotes.parse_steps("X.x- o?9 |")
	if s.size() != 7:
		return "expected 7 steps, got %d" % s.size()
	var vels := s.map(func(e): return snappedf(e.vel, 0.01))
	if vels != [1.0, 0.0, 0.75, 0.0, 0.5, 0.75, 1.0]:
		return "velocities %s" % str(vels)
	if not s[3].tie or s[5].chance != 0.5:
		return "tie or chance not parsed"
	return ""


func test_pattern_timing_and_velocity() -> String:
	var kick := AKRecipe.make(&"kick")
	var ev := _hits(_pat([{name = "kick", recipe = kick, steps = "X...x...X...x..."}]))
	if ev.size() != 4:
		return "expected 4 kicks, got %d" % ev.size()
	var times := ev.map(func(e): return snappedf(e.time_s, 0.0001))
	if times != [0.25, 0.75, 1.25, 1.75]:
		return "kick times %s" % str(times)
	if ev.map(func(e): return e.velocity) != [1.0, 0.75, 1.0, 0.75]:
		return "kick velocities wrong"
	return ""


func test_swing_delays_off_steps() -> String:
	var p := _pat([{name = "hat", recipe = AKRecipe.make(&"hat"), steps = "xxxx"}], 4)
	p.swing = 0.66
	var ev := _hits(p, 1.0)
	var off := float(ev[1].time_s) - 0.25
	return "" if absf(off - 0.165) < 1e-4 else "second step at +%.4f s, expected +0.165" % off


func test_ties_extend_gate() -> String:
	var lane := {name = "lead", recipe = AKRecipe.make(&"tone"), notes = ["C4", "~", "~", "."], gate = 0.8}
	var ev := _hits(_pat([lane], 4), 1.0)
	if ev.size() != 1:
		return "expected one note, got %d" % ev.size()
	return "" if absf(float(ev[0].gate_s) - 0.35) < 1e-6 else "gate %.4f, expected 0.35" % ev[0].gate_s


func test_polymeter_lane_loops_on_its_own() -> String:
	var ev := _hits(_pat([{name = "perc", recipe = AKRecipe.make(&"click"), steps = "x..", length = 3}]))
	return "" if ev.size() == 6 else "a 3-step lane over 16 steps hit %d times, expected 6" % ev.size()


func test_notes_cycle_over_hits() -> String:
	var lane := {name = "bass", recipe = AKRecipe.make(&"wavetable"), steps = "x.x.x.x.", notes = ["A1", "E2"]}
	var ev := _hits(_pat([lane], 8), 2.0)
	var m := ev.map(func(e): return e.midi)
	if m != [33, 40, 33, 40]:
		return "notes %s" % str(m)
	var ints := _hits(_pat([{name = "b", recipe = AKRecipe.make(&"tone"), steps = "x.x.", notes = [45, 52]}], 4), 1.0)
	return "" if ints.map(func(e): return e.midi) == [45, 52] else "MIDI-number notes failed"


func test_probability_is_seeded() -> String:
	var p := _pat([{name = "hat", recipe = AKRecipe.make(&"hat"), steps = "????????????????"}])
	var a := _hits(p).size()
	var b := _hits(p).size()
	if a != b:
		return "the same pattern gave %d then %d hits" % [a, b]
	return "" if a > 2 and a < 14 else "half-chance steps all or nothing (%d)" % a


func test_note_override_retunes() -> String:
	var r := AKRecipe.make(&"tone", {wave = &"saw", freq_hz = 440.0, sustain = 1.0, gate_s = 1.0, length_s = 1.0})
	var b := AK.render(r, 1.0, {}, 0, {_note_hz = 220.0})
	var c := _crossings(b)
	return "" if absi(c - 220) <= 2 else "retuned to 220 Hz but counted %d" % c


func _song() -> AKSong:
	var kick := {name = "kick", recipe = AKRecipe.make(&"kick"), steps = "x...x...x...x..."}
	var bass := {name = "bass", recipe = AKRecipe.make(&"wavetable", {sustain = 0.8}), steps = "..x...x...x...x.", notes = ["A1"], gate = 0.5}
	var song := AKSong.new()
	song.tempo = _tempo()
	song.sections.assign([
		{name = "intro", bars = 1, patterns = [_pat([bass])]},
		{name = "full", bars = 2, patterns = [_pat([kick, bass])], automation = {"bass.cutoff_hz": [[0.0, 300.0], [1.0, 3000.0]]}},
	])
	return song


func test_song_layout_and_events() -> String:
	var s := _song()
	if not is_equal_approx(s.length_s(), 6.25):
		return "length %.3f, expected 6.25" % s.length_s()
	var ev := s.events()
	var kicks := ev.filter(func(e): return e.lane == "kick").size()
	var basses := ev.filter(func(e): return e.lane == "bass").size()
	if kicks != 8 or basses != 12:
		return "expected 8 kicks and 12 bass notes, got %d and %d" % [kicks, basses]
	var last_bass: Dictionary = ev.filter(func(e): return e.lane == "bass").back()
	var first_full: Dictionary = ev.filter(func(e): return e.lane == "bass" and e.section == "full").front()
	if not (float(last_bass.overrides.cutoff_hz) > float(first_full.overrides.cutoff_hz)):
		return "automation did not open the cutoff across the section"
	return ""


func test_song_renders_with_stems() -> String:
	var r := _song().render(true)
	if not r.stems.has("music.kick") or not r.stems.has("music.bass"):
		return "missing lane stems: %s" % str(r.stems.keys())
	if r.mix.seconds() < 6.25:
		return "render shorter than the song"
	var l := AKDynamics.lufs(r.mix)
	return "" if absf(l + 16.0) < 0.6 else "song master at %.1f LUFS" % l


func test_song_cues_skip_in_render() -> String:
	var s := _song()
	var cues := s.to_cues(30.0)
	if cues.filter(func(c): return c.name == "music.section").size() != 2:
		return "expected 2 section cues"
	var m := AKCueMap.new()
	m.sounds = {"go": AKRecipe.make(&"click")}
	cues.append({name = "go", time = 1.0})
	var r := AK.render_cues(cues, m, 30.0, 6.0, false, s)
	for c in r.cues:
		if c.get("missing", false):
			return "a song cue was treated as a sound cue: %s" % c.name
	return "" if r.cues.size() == 1 else "expected only the go cue placed, got %d" % r.cues.size()


func test_song_key_changes_with_patterns() -> String:
	var s := _song()
	var k1 := s.key()
	s.sections[0].transpose = 2
	return "" if s.key() != k1 else "transposing did not change the song key"
