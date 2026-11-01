# SPDX-License-Identifier: Apache-2.0
# Matching a recording as a patch (AKSampleMatch): the scale MIDI, the native
# kernels, the minimisers, and a round trip: a known patch played through the
# scale MIDI, packed as an Auxy export, matched back.
extends RefCounted

const OUT := "user://test_sample_match/"
const SR := 44100


func test_scale_midi() -> String:
	var loops := AKSampleMatch.scale_loops()
	var counts := [60, 43, 37]
	for i in 3:
		var lp := AKAuxy._read_loop(AKSampleMatch.scale_midi(i))
		if lp.has("error"):
			return "loop %d: %s" % [i, lp.error]
		if lp.notes.size() != counts[i] or (loops[i].notes as Array).size() != counts[i]:
			return "loop %d has %d notes, want %d" % [i, lp.notes.size(), counts[i]]
		if absf(float(lp.beats) - float(loops[i].beats)) > 1e-9:
			return "loop %d is %.3f beats, want %d" % [i, lp.beats, loops[i].beats]
		for j in counts[i]:
			var want: Array = loops[i].notes[j]
			var got: Array = lp.notes[j]
			if absf(got[0] * 480.0 - want[0]) > 1e-6 or absf(got[1] * 480.0 - want[1]) > 1e-6 or got[2] != want[2] or absf(got[3] * 127.0 - want[3]) > 1e-6:
				return "loop %d note %d: %s, want %s" % [i, j, got, want]
	var run: Array = loops[0].notes
	if run[0][2] != 102 or run[59][2] != 43:
		return "the run should go from 102 down to 43"
	var paths := AKSampleMatch.save_scale_midi(ProjectSettings.globalize_path(OUT + "midi"))
	if paths.size() != 3 or not FileAccess.file_exists(paths[2]):
		return "save_scale_midi wrote %s" % [paths]
	return ""


func test_kernels() -> String:
	if not AKSampleMatch.available():
		return ""
	var m: Object = ClassDB.instantiate(&"AKMatch")
	# A tone of 220 Hz (0.5) with its third harmonic (0.25, phase pi/2), plus DC.
	var x := PackedFloat32Array()
	x.resize(SR)
	for i in SR:
		var t := float(i) / SR
		x[i] = 0.3 + 0.5 * cos(TAU * 220.0 * t) + 0.25 * cos(TAU * 660.0 * t + PI / 2.0)
	var d: PackedFloat64Array = m.dft(x, 1000, 4410, PackedFloat64Array([220.0, 440.0, 660.0]), SR, 1000.0 / SR)
	var a1 := Vector2(d[0], d[1])
	var a3 := Vector2(d[4], d[5])
	if absf(a1.length() - 0.5) > 0.01 or absf(a1.angle()) > 0.01:
		return "dft at 220 Hz: %s" % a1
	if absf(a3.length() - 0.25) > 0.01 or absf(a3.angle() - PI / 2.0) > 0.02 or Vector2(d[2], d[3]).length() > 0.01:
		return "dft at 660 Hz: %s, 440 Hz: %f" % [a3, Vector2(d[2], d[3]).length()]
	var s: PackedFloat64Array = m.spectrum(x, 1000, 4410, 65536)
	var k := roundi(220.0 * 65536 / SR)
	if absf(s[k] - 0.5) > 0.02:
		return "spectrum at 220 Hz: %f" % s[k]
	var hp: PackedFloat32Array = m.highpass(x, SR, 15.0)
	var mean := 0.0
	for i in range(SR / 4, 3 * SR / 4):
		mean += hp[i]
	if absf(mean / (SR / 2)) > 1e-3:
		return "the high-pass left DC %f" % (mean / (SR / 2))
	var f: Array = m.features(x, 0, SR / 2, 220.0, SR, 40, 12000.0)
	var H: PackedFloat64Array = f[0]
	var K: int = f[3]
	if K != 40 or int(f[2]) < 40:
		return "features: %d frames of %d harmonics" % [f[2], K]
	# Harmonic 3 is 6 dB under harmonic 1; harmonic 2 isn't there (only the window's side lobes).
	if absf(H[0] - H[2] - 6.02) > 0.3 or H[0] - H[1] < 25.0:
		return "features: h1 %.1f h2 %.1f h3 %.1f dB" % [H[0], H[1], H[2]]
	return ""


func test_minimisers() -> String:
	var rosen := func(v: PackedFloat64Array) -> float: return pow(1.0 - v[0], 2) + 100.0 * pow(v[1] - v[0] * v[0], 2)
	var nm := AKFit.nelder_mead(rosen, PackedFloat64Array([-1.2, 1.0]), 2000, 1e-8, 1e-10)
	if absf(nm.x[0] - 1.0) > 1e-3 or absf(nm.x[1] - 1.0) > 1e-3:
		return "Nelder-Mead ended at %s" % nm.x
	var bowl := func(v: PackedFloat64Array) -> float: return pow(v[0] - 3.0, 2) + 2.0 * pow(v[1] + 1.0, 2) + pow(v[0] + v[1] - 2.0, 2)
	var pw := AKFit.powell(bowl, PackedFloat64Array([0.0, 0.0]), 200, 1e-6, 1e-10)
	if absf(pw.x[0] - 3.0) > 1e-4 or absf(pw.x[1] + 1.0) > 1e-4:
		return "Powell ended at %s, want [3, -1]" % pw.x
	# With a kink it stops where scipy's Powell does (same steps, same answer).
	var kinked := func(v: PackedFloat64Array) -> float: return bowl.call(v) + absf(v[2] - 0.5)
	var pk := AKFit.powell(kinked, PackedFloat64Array([0.0, 0.0, 0.0]), 200, 1e-6, 1e-10)
	var scipy := [2.94000895, -0.98000298, 0.5]
	for i in 3:
		if absf(pk.x[i] - scipy[i]) > 1e-6:
			return "Powell with a kink ended at %s, scipy at %s" % [pk.x, scipy]
	if absf(AKFit.interp(5.0, PackedFloat64Array([0, 10]), PackedFloat64Array([2, 4])) - 3.0) > 1e-9 or AKFit.interp(-1.0, PackedFloat64Array([0, 10]), PackedFloat64Array([2, 4])) != 2.0:
		return "interp"
	# The EQ's response: +6 dB at its peak, flat where its shelves are at 0 dB.
	var e := {low_hz = 100.0, low_db = 0.0, mid_hz = 1000.0, mid_db = 6.0, mid_q = 1.0, high_hz = 8000.0, high_db = 0.0}
	var g := 20.0 * log(AKFit.eq_response(e, 1000.0, SR).length()) / log(10.0)
	if absf(g - 6.0) > 0.01 or absf(AKFit.eq_response(e, 30.0, SR).length() - 1.0) > 0.01:
		return "the EQ's response at its peak is %.2f dB" % g
	return ""


## A known patch: a saw and a quieter square an octave up, through a low-pass that closes as the note
## goes on, brighter up the keyboard; the sound the match should find.
static func _source() -> AKPatch:
	var p := AKPatch.new()
	p.oscillators = [{shape = "saw", level = 0.6}, {shape = "square", semitones = 12.0, level = 0.2}]
	p.filter = {type = "lowpass", cutoff_hz = 1500.0, q = 1.2, slope_db = 12.0}
	p.env2 = {attack_s = 0.0, decay_s = 0.4, sustain = 0.3, release_s = 0.2, curve = "exp"}
	p.amp_env = {attack_s = 0.002, decay_s = 0.6, sustain = 0.6, release_s = 0.15, curve = "exp"}
	p.mods = [{source = "env2", dest = "cutoff", amount = 2.0}, {source = "key", dest = "cutoff", amount = 0.5}]
	p.velocity_sens = 1.0
	return p


## An Auxy export of `p` playing the scale MIDI at 60 BPM.
static func _export(p: AKPatch, path: String) -> void:
	var notes := []
	var loops := AKSampleMatch.scale_loops()
	for sc in 3:
		var beats: int = loops[sc].beats
		var r := 0
		while r < 32:
			for n: Array in loops[sc].notes:
				notes.append({time_s = sc * 32.0 + r + n[0] / 480.0, note = n[2], velocity = n[3] / 127.0, length_s = n[1] / 480.0})
			r += beats
	var wav := OUT + "stem.wav"
	AKSynth.render_notes(p, notes, 97.0, SR).save_wav(wav)
	var man := {title = "ScaleExport", bpm = 60, scale = "C Major", creator = "test", format_version = "0.1",
		channels = [{kind = "instrument", label = "Known", color = "#FFF269"}],
		scenes = [{number_of_bars = 8, start_offset = 0, loop_locations = ["0_0"]}, {number_of_bars = 8, start_offset = 0, loop_locations = ["0_1"]},
			{number_of_bars = 8, start_offset = 0, loop_locations = ["0_2"]}]}
	var z := ZIPPacker.new()
	z.open(path)
	z.start_file("manifest.json")
	z.write_file(JSON.stringify(man).to_utf8_buffer())
	z.close_file()
	for i in 3:
		z.start_file("loop_0_%d.mid" % i)
		z.write_file(AKSampleMatch.scale_midi(i))
		z.close_file()
	z.start_file("stem_0.wav")
	z.write_file(FileAccess.get_file_as_bytes(wav))
	z.close_file()
	z.close()


func test_match_round_trip() -> String:
	if not AKSampleMatch.available():
		return ""
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := ProjectSettings.globalize_path(OUT + "known.axbw")
	_export(_source(), path)
	var m := AKSampleMatch.new()
	var res := m.run(path)
	if not res.ok:
		return "match failed: %s" % res.error
	var rep: Dictionary = res.report
	if rep.transpose != 0.0 or rep.stereo:
		return "found transpose %+d, stereo %s (want 0, mono)" % [rep.transpose, rep.stereo]
	# Played back without effects or free-running voices, the copy should sit close to the original.
	if rep.full_db > 3.0 or rep.lite_db > 6.0 or rep.lite_db < rep.full_db - 0.5:
		return "scores: full %.1f, lite %.1f dB" % [rep.full_db, rep.lite_db]
	if rep.floor_db > 0.5:
		return "a fixed patch against itself scored %.1f dB" % rep.floor_db
	var lite: AKPatch = res.lite
	if (lite.oscillators[0].table.zones as Array).size() != 1 or lite.filter.type != "lowpass" or lite.key_levels.is_empty():
		return "the lite patch should be one zone, a low-pass and a level by key"
	if absf((res.full as AKPatch).velocity_curve - 1.0) > 0.2:
		return "velocity curve %.2f (the source is linear)" % res.full.velocity_curve
	# Same level as the recording (within 1.5 dB) on a held note, the full patch saved and loaded.
	var file := OUT + "known_full.tres"
	ResourceSaver.save(res.full, file)
	var back: AKPatch = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
	var a := AKSynth.render_note(_source(), 60, 1.0, 0.8, 1.0)
	var b := AKSynth.render_note(back, 60, 1.0, 0.8, 1.0)
	var la := 20.0 * log(_rms(a)) / log(10.0)
	var lb := 20.0 * log(_rms(b)) / log(10.0)
	if absf(la - lb) > 1.5:
		return "the full patch plays %.1f dB against the source's %.1f" % [lb, la]
	return ""


static func _rms(b: AKBuffer) -> float:
	var s := 0.0
	for i in b.frames():
		s += b.l[i] * b.l[i] + b.r[i] * b.r[i]
	return sqrt(s / maxf(2.0 * b.frames(), 1.0))


func test_other_exports_are_refused() -> String:
	if not AKSampleMatch.available():
		return ""
	var res := AKSampleMatch.new().run(ProjectSettings.globalize_path("res://tests/auxy/fixture.axbw"))
	if res.ok or res.error == "":
		return "a song export was matched"
	if not ("scene" in res.error or "scale" in res.error or "stem" in res.error):
		return "unhelpful error: %s" % res.error
	return ""


func test_panel_on_the_synth_page() -> String:
	var lab := AKSynthLab.new()
	var ok := lab.match_panel != null and lab.match_panel.lab == lab
	lab.free()
	return "" if ok else "the Synth page has no Match panel"
