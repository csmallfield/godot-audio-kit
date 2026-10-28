# SPDX-License-Identifier: Apache-2.0
# Recording, phase 1 (docs/plans/recording.md): AKRecorder (song frames to
# ticks, the sustain pedal, the pad map, takes), AKArrangement.with_clip, and
# the gate: a drum take and a synth take recorded through the Sequencer from
# MIDI events at known song times, after a count-in whose clicks fall on its
# beats; the takes land as clips, undo removes them, and the timeline with
# them plays live as it bakes.
extends RefCounted

const OUT := "user://test_recording/"
const SR := 48000
const TPB := 96


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _lab() -> AKSequencerLab:
	var lab := AKSequencerLab.new()
	lab.audio_output = false
	lab.open_midi = false
	_tree().root.add_child(lab)
	lab.set_save_dir(OUT)
	return lab


func _done(lab: AKSequencerLab) -> void:
	lab.stop()
	lab.queue_free()


func _snr(a: AKBuffer, ref: AKBuffer, n: int) -> float:
	var se := 0.0
	var ss := 0.0
	for i in mini(n, mini(a.frames(), ref.frames())):
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)


func _rms(b: AKBuffer, from: int, to: int) -> float:
	var s := 0.0
	var n := 0
	for i in range(maxi(0, from), mini(b.frames(), to)):
		s += b.l[i] * b.l[i] + b.r[i] * b.r[i]
		n += 2
	return sqrt(s / maxf(1.0, n))


## RMS of the sample-to-sample differences: the highs.
func _hf(b: AKBuffer, from: int, to: int) -> float:
	var s := 0.0
	var n := 0
	for i in range(maxi(1, from), mini(b.frames(), to)):
		var d := b.l[i] - b.l[i - 1]
		s += d * d
		n += 1
	return sqrt(s / maxf(1.0, n))


func _midi(message: int, pitch := 0, velocity := 0, controller := 0, value := 0) -> InputEventMIDI:
	var e := InputEventMIDI.new()
	e.message = message
	e.pitch = pitch
	e.velocity = velocity
	e.controller_number = controller
	e.controller_value = value
	return e


# ------------------------------------------------------------------ recorder

func test_recorder_times_notes_in_ticks() -> String:
	var tm := AKTempoMap.make(120.0)
	var r := AKRecorder.new()
	r.start(tm, load("res://addons/audio_kit/patches/pluck.tres"), 1000, 0.0)
	# At 120 bpm a beat is 0.5 s: 24000 frames.
	r.note_on(60, 0.8, 1000 + 24000)              # beat 1
	r.note_off(60, 1000 + 36000)                  # half a beat later
	r.note_on(64, 0.5, 1000 + 48000 + 125)        # 2.6 ms late: tick 192.5 rounds to 192 or 193
	r.sustain(true, 1000 + 50000)
	r.note_off(64, 1000 + 60000)                  # held by the pedal...
	r.sustain(false, 1000 + 96000)                # ...until here (beat 4)
	r.note_on(67, 1.0, 1000 + 96000)
	r.stop(1000 + 120000)                         # still held: ends at the stop
	var got := r.notes.duplicate()
	got.sort()
	var want := [[96, 48, 60, 0.8], [192, 192, 64, 0.5], [384, 96, 67, 1.0]]
	if got.size() != 3:
		return "notes: %s" % [got]
	for i in 3:
		if absi(int(got[i][0]) - int(want[i][0])) > 1 or absi(int(got[i][1]) - int(want[i][1])) > 1 or int(got[i][2]) != int(want[i][2]) or absf(float(got[i][3]) - float(want[i][3])) > 0.001:
			return "note %d: %s, want %s" % [i, got[i], want[i]]
	# Before the punch-in, notes are dropped; just before it, they start on it.
	var p := AKRecorder.new()
	p.start(tm, load("res://addons/audio_kit/patches/pluck.tres"), 0, tm.bar_to_seconds(2.0), 2.0)
	p.note_on(50, 0.7, -48000)                    # a beat before bar 3 (bar 2 is 0-based): dropped
	p.note_off(50, -40000)
	p.note_on(52, 0.7, -500)                      # 10 ms early: a pickup, starts on the bar
	p.note_off(52, 12000)
	p.stop(24000)
	if p.notes.size() != 1 or int(p.notes[0][0]) != 2 * 4 * TPB:
		return "punch-in: %s" % [p.notes]
	# The take: from its first note's bar, whole bars, notes from the take's start.
	var t := p.take("t")
	if t.is_empty() or float(t.bar) != 2.0 or float(t.bars) != 1.0 or (t.loop as AKLoop).notes[0][0] != 0:
		return "take: %s %s" % [t, (t.loop as AKLoop).notes if t else []]
	var e := AKRecorder.new()
	e.start(tm, load("res://addons/audio_kit/patches/pluck.tres"), 0)
	e.stop(1000)
	if not e.take().is_empty():
		return "an empty take should be {}"
	return ""


func test_pads_map_to_kit_pieces() -> String:
	var punch: AKKit = load("res://addons/audio_kit/library/kits/punch.tres")
	for pair in [[36, "kick"], [38, "snare"], [39, "clap"], [42, "closed_hat"], [46, "open_hat"], [44, "pedal_hat"],
			[49, "crash"], [51, "ride"], [37, "rim"], [45, "tom_mid"]]:
		var row := AKRecorder.kit_row(punch, pair[0])
		if punch.piece_name(row) != pair[1]:
			return "note %d plays %s, want %s" % [pair[0], punch.piece_name(row), pair[1]]
	# A kit without those names plays by pad order from 36.
	var odd := AKKit.new()
	odd.pieces = [{name = "a", sound = "res://addons/audio_kit/library/drums/kick/kick_punch.tres"},
		{name = "b", sound = "res://addons/audio_kit/library/drums/kick/kick_punch.tres"},
		{name = "c", sound = "res://addons/audio_kit/library/drums/kick/kick_punch.tres"}]
	if AKRecorder.kit_row(odd, 36) != 0 or AKRecorder.kit_row(odd, 38) != 2 or AKRecorder.kit_row(odd, 40) != 1:
		return "pad order: %d %d %d" % [AKRecorder.kit_row(odd, 36), AKRecorder.kit_row(odd, 38), AKRecorder.kit_row(odd, 40)]
	# A hat-only name still finds "hat".
	var hat := AKKit.new()
	hat.pieces = [{name = "kick", sound = ""}, {name = "hat", sound = ""}]
	if AKRecorder.kit_row(hat, 42) != 1:
		return "closed hat on a kit with 'hat': %d" % AKRecorder.kit_row(hat, 42)
	return ""


func test_a_clip_placed_trims_its_track() -> String:
	var a := AKArrangement.new()
	a.tracks = [{name = "keys"}, {name = "drums"}]
	a.timeline = [{track = "keys", loop = "x", bar = 0.0, bars = 8.0, offset_bars = 0.0},
		{track = "drums", loop = "d", bar = 0.0, bars = 8.0, offset_bars = 0.0}]
	var tl := a.with_clip({track = "keys", loop = "take", bar = 2.0, bars = 3.0})
	var spans := tl.map(func(c: Dictionary) -> String: return "%s %s %s+%s@%s" % [c.track, c.loop, c.bar, c.bars, c.offset_bars])
	spans.sort()
	var want := ["drums d 0.0+8.0@0.0", "keys take 2.0+3.0@0.0", "keys x 0.0+2.0@0.0", "keys x 5.0+3.0@5.0"]
	return "" if spans == want else "with_clip: %s" % [spans]


# ------------------------------------------------------------------ the Sequencer

func _arrangement() -> AKArrangement:
	DirAccess.make_dir_recursive_absolute(OUT + "loops/")
	var bass := AKLoop.new()
	bass.kind = "synth"
	bass.instrument = load("res://addons/audio_kit/patches/sub_bass.tres")
	bass.bars = 2
	# Only the first bar plays, so hits in the second are heard on their own.
	bass.notes = [[0, 168, 45, 0.9], [192, 168, 48, 0.8]]
	bass.resource_name = "rec_bass"
	ResourceSaver.save(bass, OUT + "loops/rec_bass.tres")
	var a := AKArrangement.new()
	a.resource_name = "rec_song"
	a.tempo = AKTempoMap.make(120.0)
	a.tracks = [{name = "bass"}, {name = "drums"}, {name = "keys"}]
	a.timeline = [{track = "bass", loop = OUT + "loops/rec_bass.tres", bar = 0.0, bars = 2.0, offset_bars = 0.0}]
	a.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	return a


## Play `events` ([song seconds, InputEventMIDI]) into the lab while it
## records, pulling the live stream; returns everything heard from Record on.
func _perform(lab: AKSequencerLab, events: Array, until_s: float) -> AKBuffer:
	var live := lab.live
	var out := AKBuffer.new(0, SR)
	var origin := lab.recorder.origin_frame
	var origin_s := lab.recorder.origin_s
	var start := live.get_frame()
	events.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for ev: Array in events:
		var f := origin + roundi((float(ev[0]) - origin_s) * SR)
		var chunk := live.render_playing(f - live.get_frame())
		out.l.append_array(chunk.l)
		out.r.append_array(chunk.r)
		lab.handle_midi(ev[1])
	var end_f := origin + roundi((until_s - origin_s) * SR)
	var rest := live.render_playing(end_f - live.get_frame())
	out.l.append_array(rest.l)
	out.r.append_array(rest.r)
	if out.frames() != live.get_frame() - start:
		push_error("frames")
	return out


func test_gate_recording_takes_in_the_sequencer() -> String:
	if not AKLive.available():
		print("        (native core not built: recording needs the live mixer; skipped)")
		return ""
	for f in ["rec_song_drums_take1.tres", "rec_song_keys_take1.tres", "rec_song_drums_take2.tres"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + "loops/takes/" + f))
	var lab := _lab()
	lab.open_arrangement(_arrangement())
	lab.clock = func() -> float: return float(lab.live.get_frame())
	# Drums: armed, the punch kit (the track has no clips: a "drums" track
	# defaults to it), a one-bar count-in with the click.
	lab.arm_track("drums")
	if not lab.record_instrument() is AKKit:
		_done(lab)
		return "a drums track should record with a kit: %s" % lab.record_instrument()
	lab.count_in_bars = 1
	lab.click = true
	lab.timeline_view.playhead_bar = 0.0
	var before := lab.live.get_frame()
	if not lab.record():
		_done(lab)
		return "Record refused: %s" % lab._status.text
	var origin := lab.recorder.origin_frame
	if origin - before != 2 * SR:
		_done(lab)
		return "a one-bar count-in at 120 bpm should start the song 2 s on (%d frames)" % (origin - before)
	# Hits (song seconds): kicks on 1 and 3 of bars 1-2, snares on 2 and 4 a
	# little late, a closed hat off the grid, and an open hat at 3.25 s.
	var hits := [[0.0, 36, 120], [1.0, 36, 110], [2.0, 36, 120], [3.0, 36, 100], [0.5132, 38, 100], [1.5071, 38, 95],
		[2.5, 38, 100], [3.5049, 38, 90], [0.7563, 42, 70], [3.25, 46, 80]]
	var evs := []
	for h in hits:
		evs.append([h[0], _midi(MIDI_MESSAGE_NOTE_ON, h[1], h[2])])
		evs.append([h[0] + 0.1, _midi(MIDI_MESSAGE_NOTE_OFF, h[1])])
	var heard := _perform(lab, evs, 4.2)
	# The count-in's clicks fall on its four beats, before the music.
	var lead := origin - before
	for b in 4:
		var f := b * SR / 2
		var on := _rms(heard, f, f + 480)
		var pre := _rms(heard, f - 240, f) if b > 0 else 0.0
		if on < 0.01 or pre > on * 0.1:
			_done(lab)
			return "count-in click %d: %.4f at the beat, %.4f just before" % [b + 1, on, pre]
	# The open hat was heard as it was hit: its highs arrive at once (the
	# kick ringing from 3 s is low; compare the highs with just before).
	var oh := lead + roundi(3.25 * SR)
	if _hf(heard, oh, oh + 240) < 3.0 * _hf(heard, oh - 240, oh):
		_done(lab)
		return "the open hat wasn't heard when hit (highs %.4f vs %.4f)" % [_hf(heard, oh, oh + 240), _hf(heard, oh - 240, oh)]
	lab.stop()
	var a := lab.arrangement
	var clips := a.timeline.filter(func(c: Dictionary) -> bool: return String(c.track) == "drums")
	if clips.size() != 1 or float(clips[0].bar) != 0.0 or float(clips[0].bars) != 2.0:
		_done(lab)
		return "the drum take's clip: %s" % [clips]
	var take: AKLoop = ResourceLoader.load(String(clips[0].loop), "", ResourceLoader.CACHE_MODE_IGNORE)
	if take == null or take.kind != "percussive" or not take.instrument is AKKit or take.bars != 2:
		_done(lab)
		return "the drum take: %s" % take
	var kit := take.instrument as AKKit
	var got := take.sorted_notes()
	var want := []
	for h in hits:
		want.append([float(h[0]) * 2.0 * TPB, kit.piece_name(AKRecorder.kit_row(kit, h[1])), float(h[2]) / 127.0])
	want.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	if got.size() != want.size():
		_done(lab)
		return "%d notes taken, want %d: %s" % [got.size(), want.size(), got]
	var worst := 0.0
	for i in got.size():
		var err := absf(float(got[i][0]) - float(want[i][0]))
		worst = maxf(worst, err)
		if err > 0.5 or kit.piece_name(int(got[i][2])) != want[i][1] or absf(float(got[i][3]) - float(want[i][2])) > 0.002:
			_done(lab)
			return "hit %d: %s, want tick %.2f %s %.3f" % [i, got[i], want[i][0], want[i][1], want[i][2]]
	# Keys: a synth take later in the song, the sustain pedal holding a chord.
	lab.arm_track("keys")
	lab.record_with = load("res://addons/audio_kit/patches/fm_epiano.tres")
	lab.count_in_bars = 0
	lab.timeline_view.playhead_bar = 0.0
	lab.record()
	var keys := [[4.0, _midi(MIDI_MESSAGE_NOTE_ON, 60, 100)], [4.0, _midi(MIDI_MESSAGE_NOTE_ON, 64, 90)],
		[4.2, _midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 0, 64, 127)], [4.4, _midi(MIDI_MESSAGE_NOTE_OFF, 60)],
		[4.4, _midi(MIDI_MESSAGE_NOTE_ON, 64, 0)], [5.5, _midi(MIDI_MESSAGE_CONTROL_CHANGE, 0, 0, 64, 0)],
		[5.0, _midi(MIDI_MESSAGE_NOTE_ON, 67, 80)], [5.25, _midi(MIDI_MESSAGE_NOTE_OFF, 67)]]
	_perform(lab, keys, 6.0)
	lab.stop()
	var kc := a.timeline.filter(func(c: Dictionary) -> bool: return String(c.track) == "keys")
	if kc.size() != 1 or float(kc[0].bar) != 2.0 or float(kc[0].bars) != 1.0:
		_done(lab)
		return "the keys take should be a clip at bar 3 for one bar: %s" % [kc]
	var kt: AKLoop = ResourceLoader.load(String(kc[0].loop), "", ResourceLoader.CACHE_MODE_IGNORE)
	var kn := kt.sorted_notes()
	# 4.0 s is bar 2 (0-based) at 120 bpm. The pedal is down from 4.2 to
	# 5.5 s, so 60, 64 and 67 (let go at 5.25 s, under the pedal) all run to 5.5 s.
	var kwant := [[0, 288, 60], [0, 288, 64], [192, 96, 67]]
	if kn.size() != 3 or not kt.instrument is AKPatch:
		_done(lab)
		return "the keys take: %s" % [kn]
	for i in 3:
		if int(kn[i][0]) != kwant[i][0] or int(kn[i][1]) != kwant[i][1] or int(kn[i][2]) != kwant[i][2]:
			_done(lab)
			return "keys note %d: %s, want %s" % [i, kn[i], kwant[i]]
	# Undo takes the last take off the timeline; redo puts it back.
	lab.undo_last()
	if a.timeline.any(func(c: Dictionary) -> bool: return String(c.track) == "keys"):
		_done(lab)
		return "undo should remove the keys take"
	lab.redo_last()
	if not a.timeline.any(func(c: Dictionary) -> bool: return String(c.track) == "keys"):
		_done(lab)
		return "redo should restore the keys take"
	# The timeline with both takes plays live as it bakes.
	lab.arm_track("")
	lab.play_timeline(0.0)
	var n := roundi(a.to_song("timeline").length_s() * SR)
	var live_buf := lab.live.render_playing(n)
	var baked: AKBuffer = a.to_song("timeline").render().mix
	var snr := _snr(live_buf, baked, n)
	print("        takes recorded: %d drum hits (worst %.2f ticks from where played), 3 keys notes under the pedal; timeline live vs baked SNR %.1f dB" % [got.size(), worst, snr])
	_done(lab)
	return "" if snr > 90.0 else "the timeline with the takes, live vs baked: SNR %.1f dB" % snr


func test_record_controls() -> String:
	var lab := _lab()
	lab.open_arrangement(_arrangement())
	# Record with nothing armed says what to do.
	var rec: Button = null
	var arms: Array = []
	for b in lab.find_children("*", "Button", true, false):
		if (b as Button).text == "● Record":
			rec = b
		elif (b as Button).text == "●":
			arms.append(b)
	if rec == null or arms.size() != 3:
		_done(lab)
		return "the record button and an arm button per track: %s, %d" % [rec, arms.size()]
	rec.pressed.emit()
	if lab.recording or not "Arm a track" in lab._status.text:
		_done(lab)
		return "Record unarmed: %s" % lab._status.text
	# The arm button arms its track; the bass track records with its loop's patch.
	(arms[0] as Button).pressed.emit()
	if lab.armed_track != "bass" or not lab.record_instrument() is AKPatch or String(lab.record_instrument().resource_path).get_file() != "sub_bass.tres":
		_done(lab)
		return "armed %s with %s" % [lab.armed_track, lab.record_instrument()]
	# The menu offers kits and patches; picking one records with it.
	var menu: OptionButton = lab._rec_with
	var pick := -1
	for i in menu.item_count:
		if menu.get_item_text(i).begins_with("electro · drum kit"):
			pick = i
	if pick < 0 or not menu.get_item_text(0).begins_with("track's own (sub_bass"):
		_done(lab)
		return "Record with: %s" % [range(menu.item_count).map(func(i: int) -> String: return menu.get_item_text(i))]
	menu.select(pick)
	menu.item_selected.emit(pick)
	if not lab.record_instrument() is AKKit:
		_done(lab)
		return "picking a kit should record with it"
	# Armed again from the rebuilt row, it disarms.
	for b in lab.find_children("*", "Button", true, false):
		if (b as Button).text == "●" and (b as Button).modulate.g < 0.5:
			(b as Button).pressed.emit()
			break
	if lab.armed_track != "":
		_done(lab)
		return "pressing the lit arm button should disarm (%s)" % lab.armed_track
	if AKLive.available():
		lab.arm_track("keys")
		lab.clock = func() -> float: return float(lab.live.get_frame())
		rec.pressed.emit()
		lab.live.render_playing(SR)
		if not lab.recording:
			_done(lab)
			return "Record should be recording"
		rec.pressed.emit()
		if lab.recording or not "Nothing was played" in lab._status.text:
			_done(lab)
			return "Record pressed again should stop (%s)" % lab._status.text
	# Deleting the armed track disarms.
	lab.arm_track("keys")
	lab.delete_track(2)
	var ok := lab.armed_track == ""
	_done(lab)
	return "" if ok else "deleting the armed track should disarm it"
