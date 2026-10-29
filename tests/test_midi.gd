# SPDX-License-Identifier: Apache-2.0
# Phase 3: MIDI files (parser, import to songs, the GM starter bank), live
# MIDI input (router, keyboard), the engine's sustain pedal and voice
# stealing, patch lanes in patterns, and the synth page of the lab.
# The corpus in tests/midi/ comes from tools/midi_corpus/make_corpus.py,
# with an answer key (.json) per file written independently of the parser.
extends RefCounted

const SR := 48000
const DIR := "res://tests/midi/"
const FILES := ["minuet_g", "ode_format0", "groove_meter_pedal", "smpte_25fps"]


func _key(name: String) -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + name + ".json"))
	return d.notes if d is Dictionary else []


func test_parser_reads_every_flavour() -> String:
	var m := AKMidiFile.load_file(DIR + "minuet_g.mid")
	if m.error != "" or m.format != 1 or m.ppq != 480 or m.tracks.size() != 3:
		return "minuet: format %d, ppq %d, %d tracks, error '%s'" % [m.format, m.ppq, m.tracks.size(), m.error]
	if m.tracks[1].name != "Melody":
		return "track names: %s" % m.tracks[1].name
	var o := AKMidiFile.load_file(DIR + "ode_format0.mid")
	var ons := 0
	var offs := 0
	for e in o.tracks[0].events:
		if e.type == "note_on":
			ons += 1
		elif e.type == "note_off":
			offs += 1
	if o.format != 0 or ons != 30 or offs != 30:
		return "ode (running status, velocity-0 offs): format %d, %d ons, %d offs" % [o.format, ons, offs]
	if o.tempo_list().size() != 3:
		return "ode tempo changes: %s" % [o.tempo_list()]
	var s := AKMidiFile.load_file(DIR + "smpte_25fps.mid")
	if s.error != "" or absf(s.tick_to_seconds(1000) - 1.0) > 1e-9:
		return "SMPTE 25 fps x 40: 1000 ticks should be 1 s (%.4f), error '%s'" % [s.tick_to_seconds(1000), s.error]
	var t := AKMidiFile.load_file(DIR + "truncated.mid")
	if t.error == "" or t.tracks.is_empty():
		return "a cut-off file should report an error and keep what it read"
	var junk := AKMidiFile.from_bytes("not midi at all".to_ascii_buffer())
	if junk.error == "":
		return "junk should be refused"
	return ""


## Every note of every corpus file lands where the answer key says: time
## within 1 ms, length within 2 ms, the right pitch (drums: unpitched).
func test_import_matches_the_answer_keys() -> String:
	for f in FILES:
		var song := AKMidi.import_file(DIR + f + ".mid")
		if song == null:
			return "%s didn't import" % f
		var evs := song.events()
		var want := _key(f)
		if evs.size() != want.size():
			return "%s: %d notes imported, the key has %d" % [f, evs.size(), want.size()]
		var used := {}
		for w: Dictionary in want:
			var hit := -1
			for i in evs.size():
				var e: Dictionary = evs[i]
				if used.has(i) or absf(float(e.time_s) - float(w.time_s)) > 0.001:
					continue
				var drum := int(w.channel) == 9
				if absf(float(e.velocity) - float(w.velocity) / 127.0) > 0.002:
					continue
				if (drum and int(e.midi) == -1) or (not drum and int(e.midi) == int(w.midi)):
					if absf(float(e.gate_s) - float(w.length_s)) <= 0.002:
						hit = i
						break
			if hit < 0:
				return "%s: no imported note for %s" % [f, w]
			used[hit] = true
			var e: Dictionary = evs[hit]
			if absf(float(e.velocity) - float(w.velocity) / 127.0) > 0.002:
				return "%s: velocity %.3f for %s" % [f, e.velocity, w]
	return ""


func test_import_structure() -> String:
	var g := AKMidi.import_file(DIR + "groove_meter_pedal.mid")
	var names := g.sections.map(func(s: Dictionary) -> String: return s.name)
	if names != ["verse", "chorus"]:
		return "markers should make sections: %s" % [names]
	var segs := g.tempo.segments()
	var last: Dictionary = segs.back()
	if absf(float(last.bpb) - 3.5) > 1e-9 or absf(float(last.bar) - 6.0) > 1e-9:
		return "7/8 from bar 7 should be 3.5 beats a bar: %s" % [segs]
	if absf(float(segs[1].bar) - 2.5) > 1e-9 or absf(float(segs[1].bpm) - 110.0) > 1e-3:
		return "the mid-bar tempo change should sit at bar 2.5: %s" % [segs]
	var lanes := {}
	for s in g.sections:
		for p in s.patterns:
			for l in p.lanes:
				lanes[l.name] = l
	for want in ["drums.kick", "drums.snare", "drums.hat", "bass_2_ch2", "keys_3_ch3"]:
		if not lanes.has(want):
			return "missing lane %s (have %s)" % [want, lanes.keys()]
	if not String(lanes["bass_2_ch2"].patch).ends_with("gm_bass.tres"):
		return "program 38 should play the bass family: %s" % lanes["bass_2_ch2"].patch
	if not String(lanes["drums.kick"].recipe).ends_with("drums/kick.tres"):
		return "kick lane recipe: %s" % lanes["drums.kick"].recipe
	if absf(float(lanes["bass_2_ch2"].pan) - (40.0 - 64.0) / 63.0) > 0.01:
		return "CC 10 should pan the bass: %s" % lanes["bass_2_ch2"].pan
	if absf(float(lanes["keys_3_ch3"].send) - 60.0 / 127.0 * 0.5) > 0.01:
		return "CC 91 should set the send: %s" % lanes["keys_3_ch3"].send
	var m := AKMidi.import_file(DIR + "minuet_g.mid")
	var bass: Dictionary = m.sections[0].patterns[0].lanes[1]
	if absf(float(bass.gain_db) - 40.0 * log(90.0 / 127.0) / log(10.0)) > 0.01:
		return "CC 7 = 90 should be about -6 dB: %s" % bass.gain_db
	# Bars: 16 bars of 3/4.
	if absf(m.length_s() - 16 * 3 * 60.0 / 112.0) > 0.01:
		return "minuet length %.3f s" % m.length_s()
	# The editor import plugin made the same song.
	var imported: Resource = load(DIR + "minuet_g.mid")
	if not (imported is AKSong) or imported.events().size() != m.events().size():
		return "loading a .mid in the project should give the AKSong (%s)" % imported
	return ""


## The phase gate, part 1: real files import and play recognisably. Bake
## each melody and check, note by note, that the strongest pitch around the
## note's middle is the written one (within a third of a semitone), and that
## its loudness follows the notes.
func test_imported_songs_play_recognisably() -> String:
	for f in ["minuet_g", "ode_format0"]:
		var song := AKMidi.import_file(DIR + f + ".mid")
		var t := Time.get_ticks_msec()
		var out := song.render(true, false)
		var ms := Time.get_ticks_msec() - t
		var stem: AKBuffer = null
		for k in out.stems:
			if String(k).begins_with("music.melody") or String(k).begins_with("music.ode"):
				stem = out.stems[k]
		if stem == null:
			return "%s: no melody stem in %s" % [f, out.stems.keys()]
		var good := 0
		var notes: Array = _key(f).filter(func(n: Dictionary) -> bool: return n.part == "melody")
		for n: Dictionary in notes:
			var mid := float(n.time_s) + minf(0.12, float(n.length_s) * 0.5)
			var hz := AKNotes.midi_to_hz(int(n.midi))
			if _pitch_ok(stem, mid, hz):
				good += 1
		var share := float(good) / notes.size()
		print("        %s: %d/%d notes at the written pitch, rendered in %d ms" % [f, good, notes.size(), ms])
		if share < 0.9:
			return "%s: only %d of %d notes measure at their pitch" % [f, good, notes.size()]
		if out.mix.peak() < 0.05:
			return "%s: silent" % f
	return ""


## Is `hz` the best-scoring pitch among the 25 semitones around it (±1
## octave) near `t`? A pitch scores by its first three harmonics together
## (a product, as a harmonic product spectrum), so a bright tone whose second
## harmonic is its loudest partial still reads at its fundamental, as an ear
## hears it.
func _pitch_ok(buf: AKBuffer, t: float, hz: float) -> bool:
	var n := 2048
	var start := clampi(roundi(t * buf.sample_rate) - n / 2, 0, maxi(0, buf.frames() - n))
	var best := -1
	var best_e := -INF
	for k in range(-12, 13):
		var f := hz * pow(2.0, k / 12.0)
		var e := 0.0
		for h in [1, 2, 3]:
			e += log(_goertzel(buf, start, n, f * h) + 1e-12)
		if e > best_e:
			best_e = e
			best = k
	return best == 0


func _goertzel(buf: AKBuffer, start: int, n: int, f: float) -> float:
	var w := TAU * f / buf.sample_rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var win := 0.5 - 0.5 * cos(TAU * i / (n - 1))
		var x := 0.5 * (buf.l[start + i] + buf.r[start + i]) * win
		var s0 := x + c * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - c * s1 * s2


func test_imported_song_plays_live_as_baked() -> String:
	if not AKLive.available():
		return ""
	var song := AKMidi.import_file(DIR + "ode_format0.mid")
	song.master_fx = [{type = &"limit", ceiling_db = -1.0}]
	var baked: AKBuffer = song.render().mix
	var live := AKLive.new()
	var m := AKCueMap.new()
	m.master_fx = song.master_fx
	m.reverb = song.reverb
	live.prepare([], m)
	live.song_play(song, &"song")
	var got := live.render_playing(baked.frames())
	var e := 0.0
	var s := 0.0
	for i in mini(got.frames(), baked.frames()):
		s += baked.l[i] * baked.l[i]
		e += (baked.l[i] - got.l[i]) * (baked.l[i] - got.l[i])
	var snr := 10.0 * log(s / maxf(e, 1e-30)) / log(10.0)
	return "" if snr > 90.0 else "the imported song live vs baked: SNR %.1f dB" % snr


func test_patch_and_event_lanes_in_patterns() -> String:
	var p := AKPattern.new()
	p.steps = 8
	p.lanes = [{name = "lead", patch = "res://addons/audio_kit/patches/pluck.tres", steps = "x.x.x.x.", notes = ["C4", "E4", "G4", "C5"]},
		{name = "free", patch = AKPatchLib.preset(&"organ"), events = [[0.0, 0.5, 60, 1.0], [0.75, 0.25, 64, 0.5], [9.0, 1.0, 67, 1.0]]}]
	var tm := AKTempoMap.make(120.0)
	var evs := p.events(tm, 0.0, 2.0)
	var lead := evs.filter(func(e: Dictionary) -> bool: return e.lane == "lead")
	var free := evs.filter(func(e: Dictionary) -> bool: return e.lane == "free")
	if lead.size() != 4 or free.size() != 2:
		return "lanes gave %d lead and %d free events (want 4, 2: beat 9 is past the pattern)" % [lead.size(), free.size()]
	if absf(float(free[1].time_s) - 0.375) > 1e-9 or absf(float(free[1].gate_s) - 0.125) > 1e-9 or absf(float(free[1].velocity) - 0.5) > 1e-9:
		return "free event timing: %s" % [free[1]]
	if p.lane_recipe(0) != p.lane_recipe(0):
		return "a patch lane should keep one recipe (stable bake keys)"
	var song := AKSong.new()
	song.tempo = tm
	song.sections = [{name = "a", bars = 1, patterns = [p]}]
	var buf: AKBuffer = song.render().mix
	if buf.peak() < 0.05:
		return "a song of patch lanes is silent"
	# Velocity reaches the patch: a soft note is quieter.
	var q := AKPattern.new()
	q.lanes = [{name = "bass", patch = AKGeneralMidi.family_patch(4), steps = "x"}]
	var r := q.lane_recipe(0)
	var loud := AK.render(r, 1.0, {}, 0, {_note_hz = 110.0, _gate_s = 0.3})
	var soft := AK.render(r, 0.2, {}, 0, {_note_hz = 110.0, _gate_s = 0.3})
	return "" if soft.peak() < loud.peak() * 0.8 else "velocity should reach the patch (%.3f vs %.3f)" % [soft.peak(), loud.peak()]


func test_tempo_map_beats() -> String:
	var tm := AKTempoMap.make(120.0, 4)
	tm.changes = [{bar = 2.5, bpm = 60.0}, {bar = 4.0, beats_per_bar = 3.5}]
	# 10 beats at 120 = 5 s; then 6 beats at 60 = 6 s -> beat 16 at 11 s.
	if absf(tm.beat_to_seconds(10.0) - 5.0) > 1e-9 or absf(tm.beat_to_seconds(16.0) - 11.0) > 1e-9:
		return "beat_to_seconds: %.4f, %.4f" % [tm.beat_to_seconds(10.0), tm.beat_to_seconds(16.0)]
	if absf(tm.beats_at_bar(5.0) - (16.0 + 3.5)) > 1e-9:
		return "beats_at_bar(5) = %.3f" % tm.beats_at_bar(5.0)
	if absf(AKMidi.tm_bar(tm, 19.5) - 5.0) > 1e-9:
		return "tm_bar(19.5) = %.4f" % AKMidi.tm_bar(tm, 19.5)
	if not is_equal_approx(tm.beats_per_bar_at(4.5), 3.5):
		return "fractional meter"
	return ""


func test_bank_is_complete_and_fresh() -> String:
	var bank := AKGeneralMidi.default_bank()
	if bank == null or bank.families.size() != 16:
		return "the shipped bank should have 16 families"
	for prog in [0, 8, 16, 24, 33, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 127]:
		var p := bank.patch_for(prog)
		if p == null:
			return "no patch for program %d" % prog
		var code := AKGeneralMidi.family_patch(prog / 8)
		if var_to_str(p.describe()).length() == 0 or not _close(p.describe(), code.describe()):
			return "%s is stale: run tools/make_bank.gd" % p.resource_path
		var buf := AKSynth.render_note(p, 60, 0.9, 0.4)
		if buf.peak() < 0.1 or buf.peak() > 0.8:
			return "%s: peak %.3f" % [AKGeneralMidi.FAMILIES[prog / 8], buf.peak()]
	for note in range(35, 82):
		var d := bank.drum_for(note)
		var r: AKRecipe = load(String(d.recipe))
		if r == null:
			return "no drum for note %d" % note
	if bank.drum_for(36).lane != "kick" or bank.drum_for(42).lane != "hat" or bank.drum_for(81).lane != "perc":
		return "drum lanes: %s %s %s" % [bank.drum_for(36), bank.drum_for(42), bank.drum_for(81)]
	return ""


func _close(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _close(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _close(a[i], b[i]):
				return false
		return true
	return a == b


func test_sustain_pedal_and_stealing() -> String:
	var p := AKPatch.new()
	p.oscillators = [{shape = "sine", level = 1.0}]
	p.filter = {type = "off"}
	p.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.02}
	var c := p.compile()
	# Pedal down, note on, note off: it keeps sounding until the pedal lifts.
	var ev := [[0, AKSynth.E_SUSTAIN, 1.0, 0.0], [0, AKSynth.E_ON, 60.0, 1.0], [4800, AKSynth.E_OFF, 60.0, 0.0], [24000, AKSynth.E_SUSTAIN, 0.0, 0.0]]
	for gd in [false, true]:
		var b := AKSynth.render_events(c, ev, 36000, SR, gd)
		if _rms(b, 20000, 22000) < 0.3 or _rms(b, 30000, 32000) > 0.01:
			return "sustain (gd %s): %.3f while held, %.3f after the pedal" % [gd, _rms(b, 20000, 22000), _rms(b, 30000, 32000)]
	# Stealing fades: one voice, a second note takes over. The first must not
	# stop in a single sample: the largest sample-to-sample jump stays small.
	p.polyphony = 1
	p.amp_env.sustain = 1.0
	var ev2 := [[0, AKSynth.E_ON, 57.0, 1.0], [2410, AKSynth.E_ON, 81.0, 1.0]]
	var b2 := AKSynth.render_events(p.compile(), ev2, 4800)
	var gd2 := AKSynth.render_events(p.compile(), ev2, 4800, SR, true)
	var diff := 0.0
	for i in b2.frames():
		diff = maxf(diff, absf(b2.l[i] - gd2.l[i]))
	if diff > 1e-6:
		return "stealing: native and GDScript differ by %.2e" % diff
	var jump := 0.0
	for i in range(2405, 2440):
		jump = maxf(jump, absf(b2.l[i] - b2.l[i - 1]))
	# A 220 Hz sine at full level moves at most ~0.03 a sample; a hard cut at
	# the steal would jump up to 1.
	return "" if jump < 0.2 else "a stolen voice cut off (jump %.3f)" % jump


func _rms(b: AKBuffer, a: int, z: int) -> float:
	var s := 0.0
	for i in range(a, z):
		s += b.l[i] * b.l[i]
	return sqrt(s / (z - a))


## The phase gate, part 2: patches play from a keyboard. MIDI events (as a
## MIDI keyboard sends them) go through the router to a live synth: notes,
## velocity, pitch bend, mod wheel, sustain, all-notes-off.
func test_router_plays_midi_events() -> String:
	if not AKSynth.available():
		return ""
	var r := AKMidiRouter.new()
	r.open_inputs = false
	r.listen = false
	r.patch = AKPatchLib.preset(&"organ")
	(Engine.get_main_loop() as SceneTree).root.add_child(r)
	var out := _router_checks(r)
	r.queue_free()
	return out


func _router_checks(r: AKMidiRouter) -> String:
	var s: Object = r.synth()
	r.handle(_midi(MIDI_MESSAGE_NOTE_ON, 0, {pitch = 60, velocity = 100}))
	r.handle(_midi(MIDI_MESSAGE_NOTE_ON, 0, {pitch = 64, velocity = 50}))
	var a: Array = s.render_offline(2400)
	if s.voice_count() != 2 or _peak(a[0]) < 0.05:
		return "two notes should sound (%d voices, peak %.3f)" % [s.voice_count(), _peak(a[0])]
	r.handle(_midi(MIDI_MESSAGE_NOTE_ON, 0, {pitch = 64, velocity = 0}))   # velocity 0 = off
	r.handle(_midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, {controller_number = 64, controller_value = 127}))
	r.handle(_midi(MIDI_MESSAGE_NOTE_OFF, 0, {pitch = 60}))
	s.render_offline(SR / 2)
	if s.voice_count() != 1:
		return "the pedal should hold the first note (%d voices)" % s.voice_count()
	r.handle(_midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, {controller_number = 64, controller_value = 0}))
	s.render_offline(SR)
	if s.voice_count() != 0:
		return "lifting the pedal should release it (%d voices)" % s.voice_count()
	# Bend: a sine patch, bent up a whole tone, measures two semitones higher.
	var sine := AKPatch.new()
	sine.oscillators = [{shape = "sine", level = 0.8}]
	sine.filter = {type = "off"}
	sine.amp_env = {attack_s = 0.0, decay_s = 0.1, sustain = 1.0, release_s = 0.05}
	r.patch = sine
	r.handle(_midi(MIDI_MESSAGE_PITCH_BEND, 0, {pitch = 16383}))
	r.handle(_midi(MIDI_MESSAGE_NOTE_ON, 0, {pitch = 69, velocity = 127}))
	s.render_offline(2400)
	var lr: Array = s.render_offline(SR / 2)
	var b := AKBuffer.new(0, SR)
	b.l = lr[0]
	b.r = lr[1]
	var f := AKSoundFeatures.of(b)
	if absf(12.0 * log(f.pitch_start_hz / 440.0) / log(2.0) - 2.0) > 0.1:
		return "full bend should be +2 semitones (measured %.1f Hz)" % f.pitch_start_hz
	r.handle(_midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, {controller_number = 123, controller_value = 0}))
	s.render_offline(SR)
	if s.voice_count() != 0:
		return "all notes off (CC 123)"
	# Program change picks the bank's family patch.
	r.follow_program_changes = true
	r.handle(_midi(MIDI_MESSAGE_PROGRAM_CHANGE, 0, {instrument = 33}))
	var now: AKPatch = s.get(&"patch")
	if now == null or not now.resource_path.ends_with("gm_bass.tres"):
		return "program 33 should load the bass family (%s)" % (now.resource_path if now else "none")
	return ""


func _midi(msg: int, ch: int, props: Dictionary) -> InputEventMIDI:
	var e := InputEventMIDI.new()
	e.message = msg
	e.channel = ch
	for k in props:
		e.set(k, props[k])
	return e


func _peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for x in a:
		p = maxf(p, absf(x))
	return p


func test_keyboard_and_synth_page() -> String:
	var lab := AKSynthLab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	var out := _lab_checks(lab)
	lab.router.all_notes_off()
	lab.queue_free()
	return out


func _lab_checks(lab: AKSynthLab) -> String:
	var kb := lab.keyboard
	kb.size = Vector2(700, 100)
	kb.low_note = 48
	# Keys under the mouse: white C at the left, a black C# above.
	if kb.note_at(Vector2(5, 90)) != 48:
		return "bottom-left should be C3 (%d)" % kb.note_at(Vector2(5, 90))
	var ww := kb.size.x / kb.white_count()
	if kb.note_at(Vector2(ww, 10)) != 49:
		return "the black key between C and D should be C# (%d)" % kb.note_at(Vector2(ww, 10))
	var got := []
	kb.note_on.connect(func(n: int, _v: float) -> void: got.append(n))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(ww * 2.5, 90)
	kb._gui_input(press)
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	kb._gui_input(key)
	if got != [52, 60]:
		return "mouse on the third white key and the Q key: %s (want [52, 60])" % [got]
	kb.release_all()
	lab.router.all_notes_off()
	lab.select_patch("res://addons/audio_kit/patches/organ.tres")   # a polyphonic patch
	kb._gui_input(press)
	kb._gui_input(key)
	if AKSynth.available():
		var s: Object = lab.router.synth()
		s.render_offline(1200)
		if s.voice_count() != 2:
			return "the keyboard should play the patch (%d voices)" % s.voice_count()
	var song := lab.open_song(DIR + "minuet_g.mid")
	if song == null or lab.patch_lanes().size() != 2:
		return "the lab should open a .mid as a song with 2 patch lanes"
	lab.set_lane_patch("melody_1", "res://addons/audio_kit/patches/fm_bell.tres")
	var lanes := lab.patch_lanes()
	if String(lanes["melody_1"]) != "res://addons/audio_kit/patches/fm_bell.tres":
		return "re-voicing a lane: %s" % [lanes]
	var r: AKRecipe = song.sections[0].patterns[0].lane_recipe(0)
	if String(r.params.patch) != "res://addons/audio_kit/patches/fm_bell.tres":
		return "the lane's recipe should follow its new patch"
	if lab.live:
		lab.play_song()
		var a := lab.live.render_playing(SR)
		lab.stop_song()
		if a.peak() < 0.02:
			return "the opened song didn't play live"
	return ""
