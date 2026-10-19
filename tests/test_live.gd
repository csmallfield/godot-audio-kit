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
