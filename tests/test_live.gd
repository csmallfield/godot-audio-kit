# SPDX-License-Identifier: Apache-2.0
# The live mixer. The Phase 3 gate: a prepared live timeline, rendered
# offline through the same code the audio thread runs, matches render_cues.
# Passes trivially without the native core.
extends RefCounted

const SR := 48000


func _skip() -> bool:
	if AKLive.available():
		return false
	print("        (native core not built: skipped)")
	return true


## Largest difference relative to the reference's peak, and the SNR in dB.
static func _compare(a: AKBuffer, ref: AKBuffer) -> Dictionary:
	var n := mini(a.frames(), ref.frames())
	var d := 0.0
	var p := 1e-9
	var se := 0.0
	var ss := 0.0
	for i in n:
		var el := a.l[i] - ref.l[i]
		var er := a.r[i] - ref.r[i]
		d = maxf(d, maxf(absf(el), absf(er)))
		p = maxf(p, maxf(absf(ref.l[i]), absf(ref.r[i])))
		se += el * el + er * er
		ss += ref.l[i] * ref.l[i] + ref.r[i] * ref.r[i]
	return {rel = d / p, snr = 10.0 * log(ss / maxf(se, 1e-30)) / log(10.0), frames = n}


func _gate(sheet: Dictionary, map: AKCueMap, length_s: float, song: AKSong = null) -> String:
	var ref: AKBuffer = AK.render_cues(sheet.cues, map, float(sheet.get("fps", 30.0)), length_s, false, song).mix
	var live := AKLive.new()
	live.prepare(sheet.cues, map, float(sheet.get("fps", 30.0)), length_s, song)
	if live.length_frames() != ref.frames():
		return "live length %d frames, baked %d" % [live.length_frames(), ref.frames()]
	var out := live.render_offline(live.length_frames())
	var c := _compare(out, ref)
	print("        max diff %s of peak, SNR %.0f dB over %d frames" % [String.num_scientific(c.rel), c.snr, c.frames])
	return "" if c.rel < 1e-3 and c.snr > 60.0 else "live differs from baked: %s of peak, SNR %.1f dB" % [String.num_scientific(c.rel), c.snr]


func test_gate_race_ident() -> String:
	if _skip():
		return ""
	var sheet := AK.load_cue_sheet("res://demo/cues/race_ident.json")
	var map: AKCueMap = load("res://demo/recipes/race_ident_map.tres")
	return _gate(sheet, map, 6.0)


func test_gate_e1_with_music() -> String:
	if _skip():
		return ""
	var sheet := AK.load_cue_sheet("res://demo/cues/e1_supergraphic.json")
	var map: AKCueMap = load("res://demo/recipes/supergraphic/e1_map.tres")
	var song: AKSong = load("res://demo/music/e1/e1_song.tres")
	return _gate(sheet, map, float(sheet.duration) / float(sheet.fps), song)


func _dry_map() -> AKCueMap:
	var m := AKCueMap.new()
	m.sounds = {"go": AKRecipe.make(&"tone")}
	m.master_fx = []
	return m


func test_seek_keeps_the_timeline() -> String:
	if _skip():
		return ""
	var cues := [{name = "go", time = 0.5}, {name = "go", time = 1.0}]
	var ref: AKBuffer = AK.render_cues(cues, _dry_map(), 30.0, 2.0).mix
	var live := AKLive.new()
	live.prepare(cues, _dry_map(), 30.0, 2.0)
	live.seek(0.75)
	var out := live.render_offline(SR / 2)
	var seg := AKBuffer.new(0, SR)
	seg.l = ref.l.slice(36000, 36000 + SR / 2)
	seg.r = ref.r.slice(36000, 36000 + SR / 2)
	var c := _compare(out, seg)
	return "" if c.rel < 1e-5 else "after a seek the mix differs by %s" % String.num_scientific(c.rel)


func test_trigger_plays_once() -> String:
	if _skip():
		return ""
	var live := AKLive.new()
	live.prepare([], _dry_map())
	live.trigger(&"go", 1.0, {}, 0.1)
	if live.stream.hit_count() != 1:
		return "trigger did not schedule a hit"
	var out := live.render_offline(SR)
	var first := out.first_above(1e-4)
	if absi(first - SR / 10) > 2:
		return "trigger landed at %d, wanted %d" % [first, SR / 10]
	live.render_offline(SR * 3)
	if live.stream.hit_count() != 0:
		return "one-shot hit was not dropped after it finished"
	return ""


static func _zero_crossings(b: AKBuffer, from: int, to: int) -> int:
	var z := 0
	for i in range(from + 1, to):
		if (b.l[i - 1] < 0.0) != (b.l[i] < 0.0):
			z += 1
	return z


func test_voice_glides_and_releases() -> String:
	if _skip():
		return ""
	var live := AKLive.new()
	live.prepare([], _dry_map())
	var v := live.voice_start({shape = "sine", freq_hz = 440.0, gain = 0.5, attack_s = 0.005})
	var a := live.render_offline(SR)
	var hz := _zero_crossings(a, SR / 2, SR) / 2.0 / 0.5
	if absf(hz - 440.0) > 4.0:
		return "voice at %.1f Hz, wanted 440" % hz
	if absf(a.peak() - 0.5 * sqrt(2.0) * cos(PI * 0.25)) > 0.02:
		return "voice peak %.3f, wanted 0.5" % a.peak()
	live.voice_set(v, "freq_hz", 880.0, 0.02)
	var b := live.render_offline(SR)
	hz = _zero_crossings(b, SR / 2, SR) / 2.0 / 0.5
	if absf(hz - 880.0) > 6.0:
		return "after the glide the voice is at %.1f Hz, wanted 880" % hz
	live.voice_stop(v, 0.05)
	live.render_offline(SR)
	if live.stream.voice_count() != 0:
		return "voice still running after its release"
	return ""


func test_filtered_noise_voice() -> String:
	if _skip():
		return ""
	var live := AKLive.new()
	live.prepare([], _dry_map())
	var v := live.voice_start({shape = "noise", gain = 0.3, cutoff_hz = 400.0, q = 0.7, seed = 3})
	var dark := live.render_offline(SR / 2)
	live.voice_set(v, "cutoff_hz", 8000.0, 0.01)
	live.render_offline(SR / 10)
	var bright := live.render_offline(SR / 2)
	# More high frequency content: count sign changes.
	var zd := _zero_crossings(dark, 0, dark.frames())
	var zb := _zero_crossings(bright, 0, bright.frames())
	return "" if zb > zd * 3 else "opening the filter barely changed the noise (%d vs %d crossings)" % [zd, zb]


func test_playback_through_the_engine() -> String:
	if _skip():
		return ""
	var live := AKLive.new()
	live.prepare([{name = "go", time = 0.0}], _dry_map())
	var pb: AudioStreamPlayback = live.stream.instantiate_playback()
	pb.start(0.0)
	var frames: PackedVector2Array = pb.mix_audio(1.0, 4800)
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f.x))
	pb.stop()
	if peak < 0.05:
		return "the playback mixed silence (peak %.3f)" % peak
	if live.get_frame() < 4000:
		return "the timeline did not advance (frame %d)" % live.get_frame()
	return ""


func test_gate_every_master_effect() -> String:
	if _skip():
		return ""
	var m := AKCueMap.new()
	m.sounds = {"go": AKRecipe.make(&"pluck"), "tick": AKRecipe.make(&"click")}
	m.master_fx = [{type = &"dcblock"}, {type = &"drive", amount = 0.4}, {type = &"echo", time_s = 0.18, feedback = 0.4, mix = 0.35, tail_s = 0.8},
		{type = &"room", room = 0.6, mix = 0.25, quality = &"small"},
		{type = &"lowpass", cutoff_hz = 6000.0, slope_db = 24.0}, {type = &"loudness", target_lufs = -18.0}, {type = &"limit", ceiling_db = -1.0}]
	m.end_fade_s = 0.3
	var cues := [{name = "go", time = 0.1}, {name = "tick", time = 0.4}, {name = "go", time = 0.9, intensity = 0.6}]
	return _gate({cues = cues, fps = 30.0}, m, 1.5)


# A quantiser turns float-rounding differences upstream into whole steps, so
# bitcrush is held to "nearly every sample identical, the rest one step off".
func test_live_bitcrush() -> String:
	if _skip():
		return ""
	var m := AKCueMap.new()
	m.sounds = {"go": AKRecipe.make(&"pluck")}
	m.master_fx = [{type = &"room", room = 0.5, mix = 0.3}, {type = &"bitcrush", bits = 8.0, hold = 3}]
	var cues := [{name = "go", time = 0.05}]
	var ref: AKBuffer = AK.render_cues(cues, m, 30.0, 1.0).mix
	var live := AKLive.new()
	live.prepare(cues, m, 30.0, 1.0)
	var out := live.render_offline(live.length_frames())
	var step := 1.0 / 128.0
	var off := 0
	for i in ref.frames():
		var d := maxf(absf(out.l[i] - ref.l[i]), absf(out.r[i] - ref.r[i]))
		if d > step * 1.01:
			return "sample %d is %.4f off, more than one step" % [i, d]
		if d > 1e-6:
			off += 1
	return "" if off < ref.frames() / 1000 else "%d of %d samples differ" % [off, ref.frames()]


func test_gate_ducked_music() -> String:
	if _skip():
		return ""
	var sheet := AK.load_cue_sheet("res://demo/cues/e1_supergraphic.json")
	var map: AKCueMap = load("res://demo/recipes/supergraphic/e1_map.tres").duplicate()
	map.duck = {depth_db = 8.0, full_at_db = -18.0, attack_s = 0.005, release_s = 0.25}
	var song: AKSong = load("res://demo/music/e1/e1_song.tres")
	var length := float(sheet.duration) / float(sheet.fps)
	var plain: AKBuffer = AK.render_cues(sheet.cues, load("res://demo/recipes/supergraphic/e1_map.tres"), 30.0, length, false, song).mix
	var ducked: AKBuffer = AK.render_cues(sheet.cues, map, 30.0, length, false, song).mix
	if _compare(ducked, plain).snr > 40.0:
		return "ducking barely changed the baked mix"
	return _gate(sheet, map, length, song)


func test_lane_fader_glides() -> String:
	if _skip():
		return ""
	var song: AKSong = load("res://demo/music/e1/e1_song.tres")
	var live := AKLive.new()
	live.prepare([], _dry_map(), 30.0, 0.0, song)
	live.stream.set_chain([])
	var a := live.render_offline(SR * 2)
	live.seek(0.0)
	for lane in [&"bass", &"kick", &"clap", &"hat", &"pad"]:
		live.set_lane_gain(lane, -120.0, 0.0)
	var b := live.render_offline(SR * 2)
	if a.peak() < 0.05:
		return "the song made no sound"
	return "" if b.peak() < 1e-4 else "muting every lane left a peak of %f" % b.peak()


func _e1() -> Dictionary:
	var sheet := AK.load_cue_sheet("res://demo/cues/e1_supergraphic.json")
	return {sheet = sheet, map = load("res://demo/recipes/supergraphic/e1_map.tres"),
		song = (load("res://demo/music/e1/e1_song.tres") as AKSong).duplicate(true),
		length = float(sheet.duration) / float(sheet.fps)}


func test_gate_sequenced_song() -> String:
	if _skip():
		return ""
	var d := _e1()
	var ref: AKBuffer = AK.render_cues(d.sheet.cues, d.map, 30.0, d.length, false, d.song).mix
	var live := AKLive.new()
	live.prepare(d.sheet.cues, d.map, 30.0, d.length, d.song, true)
	if live.stream.hit_count() > 80:
		return "live_song scheduled the whole song up front (%d hits)" % live.stream.hit_count()
	var out := live.render_playing(live.length_frames())
	var c := _compare(out, ref)
	print("        sequenced: max diff %s of peak, SNR %.0f dB" % [String.num_scientific(c.rel), c.snr])
	return "" if c.rel < 1e-3 and c.snr > 60.0 else "sequenced song differs from the bake: SNR %.1f dB" % c.snr


func test_section_loops_and_queues_on_the_bar() -> String:
	if _skip():
		return ""
	var d := _e1()
	var live := AKLive.new()
	live.prepare([], _dry_map())
	var starts := []
	live.section_started.connect(func(n: String, f: int) -> void: starts.append([n, f]))
	live.song_play(d.song, &"loop", "full")
	var L: Dictionary = d.song.layout()[1]
	var sec_f := roundi((float(L.end_s) - float(L.start_s)) * SR)
	live.render_playing(sec_f + SR / 2)
	if starts.size() < 2 or starts[1][0] != "full":
		return "the section did not loop: %s" % [starts]
	if absi(int(starts[1][1]) - sec_f) > 1:
		return "the loop restarted at %d, wanted %d" % [starts[1][1], sec_f]
	# Queue the light section; it must start on the next bar line.
	var bar_f := float(L.end_s - L.start_s) / float(L.bars) * SR
	live.song_queue("light", &"bar")
	var now := live.get_frame()
	var want := int(starts[1][1]) + roundi(ceilf(float(now - int(starts[1][1])) / bar_f) * bar_f)
	live.render_playing(SR * 2)
	var light := starts.filter(func(s: Array) -> bool: return s[0] == "light")
	if light.is_empty():
		return "queued section never started: %s" % [starts]
	return "" if absi(int(light[0][1]) - want) <= 1 else "queued section started at %d, wanted the bar at %d" % [light[0][1], want]


func test_song_edit_takes_effect() -> String:
	if _skip():
		return ""
	var d := _e1()
	var song: AKSong = d.song
	var live := AKLive.new()
	live.prepare([], _dry_map())
	live.stream.set_chain([])
	live.song_play(song, &"loop", "full")
	live.render_playing(SR)
	# Mute everything in the section from here on.
	song.sections[1]["mute"] = ["bass", "kick", "clap", "hat", "pad"]
	live.song_changed()
	live.render_playing(SR * 3)   # let what was sounding ring out
	var quiet := live.render_playing(SR)
	return "" if quiet.peak() < 1e-3 else "muted lanes still play (peak %f)" % quiet.peak()


func test_song_seek() -> String:
	if _skip():
		return ""
	var d := _e1()
	var live := AKLive.new()
	live.prepare([], _dry_map())
	var starts := []
	live.section_started.connect(func(n: String, f: int) -> void: starts.append(n))
	live.song_play(d.song)
	live.render_playing(SR / 2)
	live.seek(9.0)
	live.song_seek(9.0)
	var out := live.render_playing(SR)
	if starts.is_empty() or starts[-1] != d.song.layout()[1].name:
		return "seek to 9 s started %s" % [starts]
	return "" if out.peak() > 0.05 else "silence after the seek"


static func _drone_recipe(hz := 500.0) -> AKRecipe:
	var r := AKRecipe.make(&"tone")
	r.params = {freq_hz = hz, attack_s = 0.0, decay_s = 0.01, sustain = 1.0, gate_s = 1.2, release_s = 0.01, length_s = 1.2}
	return r


func test_make_loop_is_seamless() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var b := AKBuffer.from_mono(AKFilter.lowpass1(AKNoise.white(SR, rng), 800.0, SR), SR)
	var loop := AKLive.make_loop(b, 0.1)
	if loop.frames() != SR - SR / 10:
		return "loop length %d" % loop.frames()
	var step := 0.0
	for i in range(1, loop.frames()):
		step = maxf(step, absf(loop.l[i] - loop.l[i - 1]))
	var seam := absf(loop.l[0] - loop.l[loop.frames() - 1])
	return "" if seam <= step * 1.5 else "seam jumps %f (largest step inside %f)" % [seam, step]


func test_loop_voice_plays_the_loop() -> String:
	if _skip():
		return ""
	var live := AKLive.new()
	live.prepare([], _dry_map())
	var rec := _drone_recipe()
	var loop := AKLive.make_loop(AK.render(rec), 0.1)
	var v := live.loop_start(rec, {gain = 1.0, attack_s = 0.0005}, 0.1)
	if v < 0:
		return "loop_start failed"
	var out := live.render_offline(loop.frames() * 2)
	var d := 0.0
	for i in range(SR / 10, out.frames()):
		var j := i % loop.frames()
		d = maxf(d, absf(out.l[i] - 0.5 * (loop.l[j] + loop.r[j])))
	if d > 1e-4:
		return "loop voice at rate 1 differs from the loop by %f" % d
	live.voice_set(v, "rate", 2.0, 0.0)
	var up := live.render_offline(SR)
	var z := 0
	for i in range(1, up.frames()):
		if (up.l[i - 1] < 0.0) != (up.l[i] < 0.0):
			z += 1
	var hz := z / 2.0
	return "" if absf(hz - 1000.0) < 15.0 else "rate 2 plays at %.0f Hz, wanted 1000" % hz


static func _with_stingers(song: AKSong) -> AKSong:
	var riser := AKRecipe.make(&"whoosh")
	riser.params = {length_s = 0.35}
	riser.offset_s = -0.3
	var hit := AKRecipe.make(&"click")
	song.stingers = [{to = "full", recipe = riser, gain_db = -3.0}, {to = "*", recipe = hit, gain_db = -6.0},
		{from = "full", to = "light", recipe = hit, gain_db = 0.0}]
	return song


func test_stingers_pick_the_most_specific() -> String:
	var song := _with_stingers((load("res://demo/music/e1/e1_song.tres") as AKSong).duplicate(true))
	var st := song.events().filter(func(e: Dictionary) -> bool: return e.lane == "stinger")
	if st.size() != 2:
		return "wanted a stinger into full and into light, got %d" % st.size()
	var lay := song.layout()
	if absf(float(st[0].time_s) - float(lay[1].start_s)) > 1e-9 or (st[0].recipe as AKRecipe).voice != &"whoosh":
		return "the stinger into full should be the riser on its first beat"
	if absf(float(st[1].gain_db)) > 1e-9:
		return "full>light should beat the * stinger (gain %f)" % st[1].gain_db
	return ""


func test_gate_sequenced_stingers() -> String:
	if _skip():
		return ""
	var d := _e1()
	_with_stingers(d.song)
	var ref: AKBuffer = AK.render_cues(d.sheet.cues, d.map, 30.0, d.length, false, d.song).mix
	var live := AKLive.new()
	live.prepare(d.sheet.cues, d.map, 30.0, d.length, d.song, true)
	var out := live.render_playing(live.length_frames())
	var c := _compare(out, ref)
	return "" if c.rel < 1e-3 and c.snr > 60.0 else "sequenced song with stingers differs from the bake: SNR %.1f dB" % c.snr


func test_stinger_on_a_queued_jump() -> String:
	if _skip():
		return ""
	var d := _e1()
	var song: AKSong = d.song
	var hit := AKRecipe.make(&"click")
	song.stingers = [{to = "light", recipe = hit}]
	var live := AKLive.new()
	live.prepare([], _dry_map())
	live.stream.set_chain([])
	var starts := []
	live.section_started.connect(func(n: String, f: int) -> void: starts.append([n, f]))
	live.song_play(song, &"loop", "arp")
	for lane in [&"bass", &"kick", &"clap", &"hat", &"pad"]:
		live.set_lane_gain(lane, -200.0, 0.0)
	live.render_playing(SR / 2)
	live.song_queue("light", &"bar")
	var start := live.get_frame()
	var out := live.render_playing(SR * 3)
	var light := starts.filter(func(s: Array) -> bool: return s[0] == "light")
	if light.is_empty():
		return "the queued section never started"
	var onset := start + out.first_above(1e-3)
	var lead := AK.render(hit).first_above(1e-3)
	return "" if absi(onset - (int(light[0][1]) + lead)) <= 2 else "stinger at %d, the section starts at %d" % [onset, light[0][1]]
