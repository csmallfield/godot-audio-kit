# SPDX-License-Identifier: Apache-2.0
# Phase 6: loop data and samples. AKLoop (ticks, divisions, kinds,
# to_pattern), AKSample and the `sample` voice (native = GDScript bit for
# bit), the WAV reader and Godot's OGG decoder, AKKit with choke groups, and
# the kit-made library. The gate: a loop of each kind compiles to the
# expected events; changing division keeps every note; a sample plays at the
# written pitch; live = bake for a sample loop; choke groups cut as specified.
extends RefCounted

const SR := 48000
const DIR := "res://tests/loops/"
const TMP := "user://test_loops/"


func _tempo(bpm := 120.0) -> AKTempoMap:
	var t := AKTempoMap.new()
	t.bpm = bpm
	return t


## A sample from raw data (no recipe, no file): deterministic in both engines.
func _data_sample(data: PackedFloat32Array, root := 60.0, mode := "oneshot") -> AKSample:
	var s := AKSample.new()
	s.data = data
	s.data_rate = SR
	s.root_note = root
	s.mode = mode
	return s


## A bright harmonic tone (fundamental plus five harmonics) at `hz`, decaying.
func _harmonic(hz: float, seconds: float, rate := SR) -> PackedFloat32Array:
	var n := roundi(seconds * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for h in range(1, 7):
			v += sin(TAU * hz * h * t) / h
		out[i] = 0.4 * v * exp(-t / (seconds * 0.6))
	return out


func _kit() -> AKKit:
	var k := AKKit.new()
	k.pieces = [
		{name = "kick", sound = AKRecipe.make(&"kick", {decay_s = 0.2})},
		{name = "snare", sound = AKRecipe.make(&"snare", {})},
		{name = "closed_hat", sound = AKRecipe.make(&"hat", {decay_s = 0.04}), choke = "hats"},
		{name = "open_hat", sound = AKRecipe.make(&"hat", {decay_s = 0.6}), choke = "hats"},
	]
	return k


func _approx(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] is Array:
			if not b[i] is Array or not _approx(a[i], b[i]):
				return false
		elif absf(float(a[i]) - float(b[i])) > 1e-9:
			return false
	return true


static func _snr(a: AKBuffer, ref: AKBuffer) -> float:
	var se := 0.0
	var ss := 0.0
	for i in mini(a.frames(), ref.frames()):
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)


# ------------------------------------------------------------------ gate: compile

func test_gate_each_kind_compiles_to_the_expected_events() -> String:
	# Synth: one bar, unrolled over two.
	var syn := AKLoop.new()
	syn.kind = "synth"
	syn.instrument = load("res://addons/audio_kit/patches/pluck.tres")
	syn.notes = [[288, 96, 52, 1.0], [0, 48, 45, 0.9], [96, 24, 57, 0.7]]
	syn.resource_name = "bass_a"
	var p := syn.to_pattern(8.0)
	if p.lanes.size() != 1 or p.lanes[0].name != "bass_a" or p.lanes[0].patch != syn.instrument:
		return "synth lane: %s" % [p.lanes]
	var want := [[0.0, 0.5, 45, 0.9], [1.0, 0.25, 57, 0.7], [3.0, 1.0, 52, 1.0], [4.0, 0.5, 45, 0.9], [5.0, 0.25, 57, 0.7], [7.0, 1.0, 52, 1.0]]
	if not _approx(p.lanes[0].events, want):
		return "synth events %s, want %s" % [p.lanes[0].events, want]
	if p.beats() != 8.0:
		return "pattern length %.2f beats" % p.beats()
	# ... and what the sequencer makes of them at 120 bpm.
	var evs := p.events(_tempo(), 0.0, 8.0)
	var times := evs.map(func(e: Dictionary) -> float: return snappedf(e.time_s, 1e-9))
	if times != [0.0, 0.5, 1.5, 2.0, 2.5, 3.5] or evs[1].midi != 57 or absf(evs[0].gate_s - 0.25) > 1e-9:
		return "synth timing %s (midi %d, gate %.3f)" % [times, evs[1].midi, evs[0].gate_s]

	# Sample: swing moves the off-beat 16th, nothing else.
	var smp := AKLoop.new()
	smp.kind = "sample"
	smp.instrument = _data_sample(_harmonic(261.63, 0.3))
	smp.swing = 0.66
	smp.notes = [[0, 24, 60, 0.8], [24, 24, 62, 0.8], [48, 24, 64, 0.8]]
	p = smp.to_pattern()
	var swung := (24.0 + 0.16 * 2.0 * 24.0) / 96.0
	want = [[0.0, 0.25, 60, 0.8], [swung, 0.25, 62, 0.8], [0.5, 0.25, 64, 0.8]]
	if p.lanes.size() != 1 or not _approx(p.lanes[0].events, want) or p.lanes[0].recipe.voice != &"sample":
		return "sample events %s, want %s" % [p.lanes[0].events, want]
	if p.beats() != 4.0:
		return "a one-bar loop is %.2f beats" % p.beats()
	evs = p.events(_tempo(), 0.0, 4.0)
	if absf(evs[1].note_hz - AKNotes.midi_to_hz(62)) > 1e-6:
		return "sample note %.3f Hz" % evs[1].note_hz

	# Percussive: a lane per piece in use, named drums.<piece>; hats choke.
	var drum := AKLoop.new()
	drum.kind = "percussive"
	drum.instrument = _kit()
	drum.notes = [[0, 24, 0, 1.0], [48, 24, 3, 0.7], [96, 24, 2, 0.6], [192, 24, 1, 0.9]]
	p = drum.to_pattern(8.0)
	var names := p.lanes.map(func(l: Dictionary) -> String: return l.name)
	if names != ["drums.kick", "drums.snare", "drums.closed_hat", "drums.open_hat"]:
		return "drum lanes %s" % [names]
	var lanes := {}
	for l in p.lanes:
		lanes[l.name] = l.events
	if not _approx(lanes["drums.kick"], [[0.0, 0.0, -1, 1.0], [4.0, 0.0, -1, 1.0]]):
		return "kick %s" % [lanes["drums.kick"]]
	# The open hat at 0.5 is cut by the closed hat at 1.0; the closed hat by the next open hat at 4.5.
	if not _approx(lanes["drums.open_hat"], [[0.5, 0.0, -1, 0.7, 0.5], [4.5, 0.0, -1, 0.7, 0.5]]):
		return "open hat %s" % [lanes["drums.open_hat"]]
	if not _approx(lanes["drums.closed_hat"], [[1.0, 0.0, -1, 0.6, 3.5], [5.0, 0.0, -1, 0.6]]):
		return "closed hat %s" % [lanes["drums.closed_hat"]]
	if not _approx(lanes["drums.snare"], [[2.0, 0.0, -1, 0.9], [6.0, 0.0, -1, 0.9]]):
		return "snare %s" % [lanes["drums.snare"]]
	evs = p.events(_tempo(), 0.0, 8.0)
	var oh: Array = evs.filter(func(e: Dictionary) -> bool: return e.lane == "drums.open_hat")
	if absf(float(oh[0].cut_s) - 0.25) > 1e-9 or AKSong.event_overrides(oh[0]).get("_cut_s", 0.0) != 0.25:
		return "open hat cut %.4f s" % oh[0].cut_s
	return ""


# ------------------------------------------------------------------ gate: division

func test_gate_changing_division_keeps_every_note() -> String:
	var l := AKLoop.new()
	l.kind = "synth"
	l.instrument = AKPatch.new()
	l.bars = 2
	# 16ths, 32nds, triplet 8ths and 16ths, and a note on no grid at all.
	l.notes = [[0, 24, 60, 0.9], [12, 12, 62, 0.5], [32, 32, 64, 0.7], [80, 16, 65, 0.6], [101, 7, 67, 0.4], [700, 68, 72, 1.0]]
	var before := l.sorted_notes()
	var events_before: Array = l.to_pattern(16.0).lanes[0].events
	if l.cell_ticks(16) != 24 or l.cell_ticks(32) != 12 or l.cell_ticks(12) != 32 or l.cell_ticks(24) != 16:
		return "cells: %d %d %d %d ticks" % [l.cell_ticks(16), l.cell_ticks(32), l.cell_ticks(12), l.cell_ticks(24)]
	for d in [32, 12, 24, 16, 24, 32, 12, 16]:
		l.set_division(d)
		if l.sorted_notes() != before:
			return "division %d changed the notes" % d
		if not _approx(l.to_pattern(16.0).lanes[0].events, events_before):
			return "division %d changed what plays" % d
	# Each division's grid holds its own notes and not the others'.
	if not l.on_grid([12, 12, 0, 1.0], 32) or l.on_grid([12, 12, 0, 1.0], 16) or not l.on_grid([32, 32, 0, 1.0], 12) or l.on_grid([101, 7, 0, 1.0], 32):
		return "on_grid is wrong"
	if l.snap(30.0, 16) != 24 or l.snap(40.0, 12) != 32 or l.snap(101.0, 24) != 96:
		return "snap: %d %d %d" % [l.snap(30.0, 16), l.snap(40.0, 12), l.snap(101.0, 24)]
	# Saved and reloaded: the same notes.
	DirAccess.make_dir_recursive_absolute(TMP)
	l.set_division(12)
	var path := TMP + "division.tres"
	if ResourceSaver.save(l, path) != OK:
		return "couldn't save the loop"
	var back: AKLoop = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if back.sorted_notes() != before or back.division != 12:
		return "reloaded: %s (division %d)" % [back.sorted_notes(), back.division]
	return ""


# ------------------------------------------------------------------ gate: pitch

func test_gate_a_sample_plays_at_the_written_pitch() -> String:
	# A sample file (a harmonic tone at C4, written as a 16-bit WAV, read back
	# by the kit's reader) played as a melody over two octaves.
	DirAccess.make_dir_recursive_absolute(TMP)
	var wav := TMP + "tone_c4.wav"
	AKBuffer.from_mono(_harmonic(261.63, 1.2)).save_wav(wav)
	var s := AKSample.new()
	s.source = wav
	var err := s.import_source()
	if err != "":
		return err
	s.root_note = 60.0
	s.mode = "gate"
	s.release_s = 0.02
	var l := AKLoop.new()
	l.kind = "sample"
	l.instrument = s
	l.bars = 4
	var melody := [48, 52, 55, 57, 60, 62, 64, 67, 69, 71, 72, 59, 53, 50, 65, 70]
	for i in melody.size():
		l.notes.append([i * 96, 84, melody[i], 0.9])
	var song := AKSong.new()
	song.tempo = _tempo(120.0)
	song.sections = [{name = "a", bars = 4, patterns = [l.to_pattern(16.0)]}]
	song.master_fx = []
	var out: AKBuffer = song.render().mix
	var good := 0
	for i in melody.size():
		if _pitch_ok(out, i * 0.5 + 0.2, AKNotes.midi_to_hz(melody[i])):
			good += 1
	print("        %d/%d sample notes at the written pitch" % [good, melody.size()])
	if good < melody.size():
		return "only %d of %d notes measure at their pitch" % [good, melody.size()]
	return ""


## As in test_midi: is `hz` the best-scoring pitch of the 25 semitones around
## it, by its first three harmonics together (a harmonic product)?
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


# ------------------------------------------------------------------ gate: live = bake

func test_gate_sample_loop_live_equals_bake() -> String:
	if not AKLive.available():
		print("        (native core not built: skipped)")
		return ""
	var mel := AKLoop.new()
	mel.kind = "sample"
	mel.instrument = _data_sample(_harmonic(220.0, 0.8), 57.0, "gate")
	mel.instrument.release_s = 0.04
	mel.bars = 1
	mel.notes = [[0, 48, 57, 0.9], [96, 48, 60, 0.6], [144, 24, 64, 0.8], [240, 96, 52, 1.0]]
	mel.resource_name = "keys"
	var beat := AKLoop.new()
	beat.kind = "percussive"
	beat.instrument = _kit()
	beat.notes = [[0, 24, 0, 1.0], [48, 24, 3, 0.7], [96, 24, 2, 0.6], [192, 24, 1, 0.9], [240, 24, 3, 0.8], [288, 24, 2, 0.5]]
	var song := AKSong.new()
	song.tempo = _tempo(128.0)
	song.sections = [{name = "a", bars = 2, patterns = [mel.to_pattern(8.0), beat.to_pattern(8.0)]},
		{name = "b", bars = 1, patterns = [beat.to_pattern(4.0)]}]
	song.mix = {"keys": {pan = -0.3, send = 0.2}}
	song.master_fx = [{type = &"limit", ceiling_db = -1.0}]
	var baked: AKBuffer = song.render().mix
	var live := AKLive.new()
	var m := AKCueMap.new()
	m.master_fx = song.master_fx
	m.reverb = song.reverb
	live.prepare([], m)
	live.song_play(song, &"song")
	var got := live.render_playing(baked.frames())
	var snr := _snr(got, baked)
	print("        sample and drum loops live vs baked: SNR %.1f dB" % snr)
	if baked.peak() < 0.05:
		return "the song is silent"
	return "" if snr > 90.0 else "live vs baked: SNR %.1f dB" % snr


# ------------------------------------------------------------------ gate: choke

func test_gate_choke_groups_cut_as_specified() -> String:
	var kit := _kit()
	var open_r := kit.piece_recipe(3)
	var closed_r := kit.piece_recipe(2)
	var kick_r := kit.piece_recipe(0)
	var tempo := _tempo(120.0)
	# Open hat at beat 0, closed hat at beat 0.5 (0.25 s), kick at 0.25 beats.
	var l := AKLoop.new()
	l.kind = "percussive"
	l.instrument = kit
	l.notes = [[0, 24, 3, 1.0], [48, 24, 2, 1.0], [24, 24, 0, 1.0]]
	var song := AKSong.new()
	song.tempo = tempo
	song.sections = [{name = "a", bars = 1, patterns = [l.to_pattern()]}]
	song.master_fx = []
	song.reverb = {room = 0.5, return_db = -120.0}
	var out: AKBuffer = song.render().mix
	# The reference: the open hat stopped at 0.25 s with the choke fade, plus
	# the kick and the closed hat, each rendered alone.
	var ref := AKBuffer.new(out.frames(), SR)
	var oh := AK.render(open_r, 1.0, {}, 0, {_gate_s = 0.0, _cut_s = 0.25})
	var full_oh := AK.render(open_r, 1.0, {}, 0, {_gate_s = 0.0})
	oh.mix_into(ref, 0)
	AK.render(kick_r, 1.0, {}, 0, {_gate_s = 0.0}).mix_into(ref, roundi(0.125 * SR))
	AK.render(closed_r, 1.0, {}, 0, {_gate_s = 0.0}).mix_into(ref, roundi(0.25 * SR))
	if oh.frames() != roundi(0.25 * SR):
		return "the open hat lasts %d frames after the choke, want %d" % [oh.frames(), roundi(0.25 * SR)]
	if full_oh.frames() <= oh.frames() * 2:
		return "the open hat should ring well past the closed hat when not choked"
	# Fades over 3 ms into the cut, untouched before.
	var fade0 := roundi(0.25 * SR) - roundi(AK.CHOKE_FADE_S * SR)
	if oh.l[fade0 - 10] != full_oh.l[fade0 - 10] or absf(oh.l[oh.frames() - 1]) > absf(full_oh.l[oh.frames() - 1]) * 0.02 + 1e-9:
		return "the choke fade is wrong"
	var snr := _snr(out, ref)
	if snr < 100.0:
		return "choked render vs reference: SNR %.1f dB" % snr
	# The kick is in no group: a kick right under the closed hat doesn't stop.
	l.notes = [[0, 24, 0, 1.0], [6, 24, 2, 1.0]]
	var evs := l.to_pattern().events(tempo, 0.0, 4.0)
	for e in evs:
		if e.lane == "drums.kick" and float(e.cut_s) > 0.0:
			return "the closed hat choked the kick"
	# Gated pieces stop at the note's end (with the sample's release).
	kit.pieces[3]["gate"] = true
	kit.refresh()
	l.notes = [[0, 48, 3, 1.0]]
	var p := l.to_pattern()
	if not _approx(p.lanes[0].events, [[0.0, 0.5, -1, 1.0]]):
		return "a gated piece keeps its length: %s" % [p.lanes[0].events]
	var g: AKBuffer = AK.render(p.lanes[0].recipe, 1.0, {}, 0, AKSong.event_overrides(p.events(tempo, 0.0, 4.0)[0]))
	var after := 0.0
	for i in range(roundi(0.6 * SR), mini(g.frames(), roundi(0.7 * SR))):
		after = maxf(after, absf(g.l[i]))
	if g.frames() > roundi((0.25 + 6.0 * 0.05) * SR) or after > 0.01 * g.peak():
		return "a gated open hat should stop after its note (%d frames, %.4f after)" % [g.frames(), after]
	return ""


# ------------------------------------------------------------------ the sample voice

func test_sample_voice_native_equals_gdscript_bit_for_bit() -> String:
	if AKDsp.nat() == null:
		print("        (native core not built: skipped)")
		return ""
	var data := _harmonic(330.0, 0.5)
	var cases := []
	for mode in ["oneshot", "gate", "loop"]:
		for rev in [false, true]:
			var s := _data_sample(data, 64.0, mode)
			s.reverse = rev
			s.start_s = 0.01
			s.end_s = 0.45
			s.loop_start_s = 0.1
			s.loop_end_s = 0.3137
			s.release_s = 0.07
			cases.append(s)
	for s: AKSample in cases:
		for note in [40.0, 64.0, 71.5, 88.0]:
			var r := s.to_recipe(note - 64.0)
			var ov := {_gate_s = 0.6}
			var a := AK.render(r, 0.8, {}, 0, ov)
			AKDsp.native_enabled = false
			var b := AK.render(r, 0.8, {}, 0, ov)
			AKDsp.native_enabled = true
			if a.l != b.l or a.r != b.r:
				return "mode %s reverse %s note %.1f: native and GDScript differ" % [s.mode, s.reverse, note]
	# The kernel itself, odd rates and loop edges included.
	for rate in [0.25, 1.0, 1.4142, 3.7]:
		var x: PackedFloat32Array = AKDsp.nat().sample_play(data, rate, 30000, 17, 20000, 4001, 9999, true)
		AKDsp.native_enabled = false
		var y := AKSampler.play(data, rate, 30000, 17, 20000, 4001, 9999, true)
		AKDsp.native_enabled = true
		if x != y:
			return "sample_play at rate %.4f differs" % rate
	return ""


func test_sample_modes_and_trim() -> String:
	var data := _harmonic(261.63, 0.5)
	var one := _data_sample(data)
	var r := one.to_recipe()
	var a := AK.render(r, 1.0, {}, 0, {_gate_s = 0.05})
	var b := AK.render(r, 1.0, {}, 0, {_gate_s = 2.0})
	if a.l != b.l or absi(a.frames() - data.size()) > 1:
		return "a one-shot should ignore the gate and play to its end (%d, %d, %d frames)" % [a.frames(), b.frames(), data.size()]
	# At the root it is the data itself (Hermite at whole samples).
	for i in range(0, data.size(), 997):
		if absf(a.l[i] - data[i]) > 1e-6:
			return "at the root note the sample should play as is (frame %d)" % i
	# An octave up: half as long.
	var up := AK.render(one.to_recipe(12.0))
	if absi(up.frames() - data.size() / 2) > 1:
		return "an octave up lasts %d frames, want %d" % [up.frames(), data.size() / 2]
	# Gate: ends near gate + release, silent long after the gate.
	var gate := _data_sample(data, 60.0, "gate")
	gate.release_s = 0.02
	var g := AK.render(gate.to_recipe(), 1.0, {}, 0, {_gate_s = 0.1})
	if g.frames() != roundi((0.1 + 5 * 0.02) * SR) or absf(g.l[g.frames() - 1]) > 0.01:
		return "gate mode: %d frames, last %.4f" % [g.frames(), g.l[g.frames() - 1]]
	# Loop: holds past the sample's own length while the note does.
	var lp := _data_sample(PackedFloat32Array(_harmonic(261.63, 0.5)), 60.0, "loop")
	lp.loop_start_s = 0.1
	lp.loop_end_s = 0.2
	lp.release_s = 0.05
	var h := AK.render(lp.to_recipe(), 1.0, {}, 0, {_gate_s = 2.0})
	var late := 0.0
	for i in range(roundi(1.5 * SR), roundi(1.6 * SR)):
		late = maxf(late, absf(h.l[i]))
	if h.frames() != roundi(2.25 * SR) or late < 0.05:
		return "loop mode should sustain while held (%d frames, level %.3f at 1.5 s)" % [h.frames(), late]
	# Trim and reverse.
	var t := _data_sample(data)
	t.start_s = 0.1
	t.end_s = 0.2
	t.reverse = true
	var tr := AK.render(t.to_recipe())
	if tr.frames() != roundi(0.1 * SR) or absf(tr.l[0] - data[roundi(0.2 * SR) - 1]) > 1e-6:
		return "trim and reverse: %d frames" % tr.frames()
	# The default sample voice plays something at once.
	var d := AK.render(AKRecipe.make(&"sample"))
	if d.peak() < 0.05 or d.first_above(1e-4) > 10:
		return "the default sample voice"
	return ""


func test_samples_from_recipes_and_bake_keys() -> String:
	var rec := AKRecipe.make(&"pluck", {freq_hz = 220.0})
	var s := AKSample.from_recipe(rec, 57.0)
	var r := s.to_recipe()
	var a := AK.render(r)
	var direct := AK.render(rec)
	for i in range(0, mini(a.frames(), direct.frames()), 501):
		if absf(a.l[i] - 0.5 * (direct.l[i] + direct.r[i])) > 1e-6:
			return "a recipe sample at its root should be the recipe"
	var k1 := AK.bake_key(r)
	rec.params["freq_hz"] = 230.0
	if AK.bake_key(r) == k1:
		return "editing the sample's recipe should change the bake key"
	var k2 := AK.bake_key(r)
	s.release_s = 0.2
	if AK.bake_key(r) == k2:
		return "editing the sample should change the bake key"
	var ds := _data_sample(_harmonic(300.0, 0.1))
	var k3 := AK.bake_key(ds.to_recipe())
	ds.data = _harmonic(310.0, 0.1)
	if AK.bake_key(ds.to_recipe()) == k3:
		return "new sample data should change the bake key"
	return ""


# ------------------------------------------------------------------ audio files

func test_wav_reader() -> String:
	DirAccess.make_dir_recursive_absolute(TMP)
	# 16-bit, written by the kit: the reader gets the samples the WAV holds.
	var src := _harmonic(440.0, 0.25)
	var buf := AKBuffer.from_mono(src, 44100)
	buf.sample_rate = 44100
	var p16 := TMP + "t16.wav"
	buf.save_wav(p16)
	var f := AKAudioFile.read(p16)
	if f.error != "" or f.rate != 44100 or f.channels != 2 or f.bits != 16 or f.data.size() != src.size():
		return "16-bit: %s, %d Hz, %d ch, %d bits, %d frames" % [f.error, f.rate, f.channels, f.bits, f.data.size()]
	var worst := 0.0
	for i in src.size():
		worst = maxf(worst, absf(f.data[i] - src[i]))
	if worst > 4.0 / 32768.0:
		return "16-bit samples off by %.6f" % worst
	# 8, 24, 32-bit PCM and 32/64-bit float, made by hand; stereo is the mean.
	var vals := [0.0, 0.5, -0.5, 0.25, -1.0, 0.999]
	for fmt in [[1, 8], [1, 24], [1, 32], [3, 32], [3, 64], [0xFFFE, 24]]:
		var bytes := _wav_bytes(int(fmt[0]), int(fmt[1]), vals, 2, 32000)
		var g := AKAudioFile.from_wav_bytes(bytes)
		if g.error != "" or g.rate != 32000 or g.channels != 2 or g.data.size() != vals.size():
			return "format %s: %s (%d frames)" % [fmt, g.error, g.data.size()]
		var tol := 1.0 / 128.0 if int(fmt[1]) == 8 else 1e-6
		for i in vals.size():
			var want := (float(vals[i]) + float(vals[i]) * 0.5) * 0.5   # left v, right v / 2
			if absf(g.data[i] - want) > tol:
				return "format %s frame %d: %.6f, want %.6f" % [fmt, i, g.data[i], want]
	# A smpl chunk gives the root note and loop; import_source can take them.
	var with_smpl := _wav_bytes(1, 16, vals, 1, 48000, 64, [1, 4])
	var h := AKAudioFile.from_wav_bytes(with_smpl)
	if h.root_note != 64 or h.loop != PackedInt32Array([1, 5]):
		return "smpl chunk: root %d loop %s" % [h.root_note, h.loop]
	var bad := AKAudioFile.from_wav_bytes(PackedByteArray([1, 2, 3]))
	if bad.error == "":
		return "garbage should fail"
	if AKAudioFile.read(TMP + "missing.wav").error == "" or AKAudioFile.read("res://README.md").error == "":
		return "a missing or unknown file should fail"
	return ""


## A WAV file's bytes: `vals` on the left, half of them on the right.
func _wav_bytes(fmt: int, bits: int, vals: Array, ch: int, rate: int, root := -1, loop: Array = []) -> PackedByteArray:
	var w := bits / 8
	var pcm := PackedByteArray()
	for v in vals:
		for c in ch:
			var x := float(v) * (1.0 if c == 0 else 0.5)
			var at := pcm.size()
			pcm.resize(at + w)
			if fmt == 3:
				if w == 4:
					pcm.encode_float(at, x)
				else:
					pcm.encode_double(at, x)
			elif bits == 8:
				pcm[at] = clampi(roundi(x * 128.0) + 128, 0, 255)
			elif bits == 16:
				pcm.encode_s16(at, clampi(roundi(x * 32768.0), -32768, 32767))
			elif bits == 24:
				var iv := clampi(roundi(x * 8388608.0), -8388608, 8388607)
				if iv < 0:
					iv += 16777216
				pcm[at] = iv & 255
				pcm[at + 1] = (iv >> 8) & 255
				pcm[at + 2] = (iv >> 16) & 255
			else:
				pcm.encode_s32(at, clampi(roundi(x * 2147483648.0), -2147483648, 2147483647))
	var fmt_body := PackedByteArray()
	fmt_body.resize(40 if fmt == 0xFFFE else 16)
	fmt_body.encode_u16(0, fmt)
	fmt_body.encode_u16(2, ch)
	fmt_body.encode_u32(4, rate)
	fmt_body.encode_u32(8, rate * w * ch)
	fmt_body.encode_u16(12, w * ch)
	fmt_body.encode_u16(14, bits)
	if fmt == 0xFFFE:
		fmt_body.encode_u16(16, 22)
		fmt_body.encode_u16(24, 1)   # sub-format: PCM
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.resize(8)
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array(_chunk("fmt ", fmt_body))
	if root >= 0:
		var smpl := PackedByteArray()
		smpl.resize(60)
		smpl.encode_u32(12, root)
		smpl.encode_u32(28, 1)
		smpl.encode_u32(44, int(loop[0]))
		smpl.encode_u32(48, int(loop[1]))
		out.append_array(_chunk("smpl", smpl))
	out.append_array(_chunk("data", pcm))
	out.encode_u32(4, out.size() - 8)
	return out


func _chunk(id: String, body: PackedByteArray) -> PackedByteArray:
	var c := id.to_ascii_buffer()
	c.resize(8)
	c.encode_u32(4, body.size())
	c.append_array(body)
	if body.size() & 1:
		c.append(0)
	return c


func test_ogg_decodes_through_godot() -> String:
	# noise_stereo.ogg (pink noise, 44.1 kHz, the right channel delayed and
	# quieter) and the same file decoded by ffmpeg to float WAV.
	var o := AKAudioFile.read(DIR + "noise_stereo.ogg")
	var ref := AKAudioFile.read(DIR + "noise_stereo_decoded.wav")
	if o.error != "" or ref.error != "":
		return "read: %s / %s" % [o.error, ref.error]
	if o.rate != 44100 or o.channels != 2 or ref.rate != 44100:
		return "ogg: %d Hz, %d channels" % [o.rate, o.channels]
	var n := mini(o.data.size(), ref.data.size())
	if n < ref.data.size() - 512:
		return "ogg decoded %d frames, the reference has %d" % [o.data.size(), ref.data.size()]
	var se := 0.0
	var ss := 0.0
	for i in n:
		se += pow(o.data[i] - ref.data[i], 2.0)
		ss += ref.data[i] * ref.data[i]
	var snr := 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0)
	print("        OGG through Godot's decoder vs a reference decode: %.1f dB" % snr)
	if snr < 100.0:
		return "OGG decode vs reference: SNR %.1f dB" % snr
	# As a sample: imported, saved with its data, and played without the file.
	var s := AKSample.new()
	s.source = DIR + "noise_stereo.ogg"
	if s.import_source() != "" or s.data_rate != 44100 or s.data.size() != o.data.size():
		return "import_source on the ogg"
	DirAccess.make_dir_recursive_absolute(TMP)
	ResourceSaver.save(s, TMP + "noise.sample.tres")
	var back: AKSample = ResourceLoader.load(TMP + "noise.sample.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	back.source = TMP + "gone.ogg"   # as in an exported game: the data is what plays
	if back.data != s.data or back.data_rate != 44100:
		return "the decoded data should be saved with the sample"
	var played := AK.render(back.to_recipe())
	if absi(played.frames() - roundi(o.data.size() * 48000.0 / 44100.0)) > 2 or played.peak() < 0.05:
		return "the saved sample should play at 48 kHz from its data (%d frames)" % played.frames()
	return ""


func _close(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			var kb: Variant = k if b.has(k) else (String(k) if b.has(String(k)) else StringName(k))
			if not b.has(kb) or not _close(a[k], b[kb]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _close(a[i], b[i]):
				return false
		return true
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	return a == b
