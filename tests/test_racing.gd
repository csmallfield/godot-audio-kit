# SPDX-License-Identifier: Apache-2.0
# The racing demo (demo/racing/): its sound effects measure like what their
# names say, and its song, "Neon Circuit", is well formed and balanced.
extends RefCounted

const SFX := "res://demo/racing/sfx/"
const SONG := "res://demo/racing/song/neon_circuit.tres"
## Sounds played by synth patches: slow in GDScript, so checked only natively
## (except one, so the patch path is covered both ways).
const PATCHY := ["engine_idle", "engine_mid", "engine_high", "engine_rev", "engine_start", "tire_screech", "finish_fanfare"]


func _names() -> Array:
	var out := []
	for f in DirAccess.get_files_at(SFX):
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	out.sort()
	return out


func test_every_sound_renders_cleanly() -> String:
	var names := _names()
	if names.size() < 20:
		return "expected the full collection (%d sounds)" % names.size()
	for n in names:
		if PATCHY.has(n) and not AKSynth.available():
			continue
		var buf := AK.render(load(SFX + n + ".tres"))
		var f := AKSoundFeatures.of(buf)
		if buf.peak() < 0.05:
			return "%s is nearly silent (peak %.3f)" % [n, buf.peak()]
		if buf.peak() > 0.95:
			return "%s peaks at %.2f (should stay under -0.5 dBFS)" % [n, buf.peak()]
		for i in range(0, buf.frames(), 97):
			if not is_finite(buf.l[i]):
				return "%s has a bad sample" % n
		if buf.seconds() > 3.5:
			return "%s runs %.1f s (game sounds here stay short)" % [n, buf.seconds()]
		if float(f.length_s) < 0.015:
			return "%s is too short to hear (%.3f s)" % [n, f.length_s]
	return ""


func test_sounds_do_what_they_say() -> String:
	var f := func(n: String) -> Dictionary: return AKSoundFeatures.of(AK.render(load(SFX + n + ".tres")))
	var pass_by: Dictionary = f.call("pass_by")
	if float(pass_by.pitch_end_hz) >= float(pass_by.pitch_start_hz):
		return "a pass-by should fall in pitch (Doppler): %.0f -> %.0f Hz" % [pass_by.pitch_start_hz, pass_by.pitch_end_hz]
	var go: Dictionary = f.call("countdown_go")
	var beep: Dictionary = f.call("countdown_beep")
	if float(go.length_s) <= float(beep.length_s) or float(go.centroid_hz) <= float(beep.centroid_hz):
		return "GO should be longer and higher than the countdown beeps"
	var crash: Dictionary = f.call("crash_heavy")
	var bump: Dictionary = f.call("bump")
	if float(crash.lufs) <= float(bump.lufs) + 6.0:
		return "a crash should be far louder than a bump (%.1f vs %.1f LUFS)" % [crash.lufs, bump.lufs]
	if float(f.call("turbo_blowoff").tonality) > 0.4 or float(f.call("wall_scrape").tonality) > 0.4:
		return "the blow-off and the scrape are noises"
	if not AKSynth.available():
		var skid: Dictionary = f.call("skid_short")
		if float(skid.centroid_hz) < 800.0:
			return "a skid squeals (centroid %.0f Hz)" % skid.centroid_hz
		return ""
	# Engines: higher revs, higher pitch and brighter.
	var last := 0.0
	for n in ["engine_idle", "engine_mid", "engine_high"]:
		var buf := AK.render(load(SFX + n + ".tres"))
		var m := PackedFloat32Array()
		m.resize(buf.frames())
		for i in m.size():
			m[i] = 0.5 * (buf.l[i] + buf.r[i])
		var c := float(AKSoundFeatures.of(buf).centroid_hz)
		if c <= last:
			return "%s should be brighter than the slower engine (%.0f Hz vs %.0f Hz)" % [n, c, last]
		last = c
	var screech: Dictionary = f.call("tire_screech")
	if float(screech.centroid_hz) < 1000.0 or float(screech.centroid_hz) > 3000.0:
		return "a tyre squeal sits around 1-3 kHz (%.0f Hz)" % screech.centroid_hz
	# Engine loops are seamless once make_loop has crossfaded them.
	var loop := AKLive.make_loop(AK.render(load(SFX + "engine_mid.tres")), 0.3)
	var jump := absf(loop.l[0] - loop.l[loop.frames() - 1])
	if jump > 0.1:
		return "the engine loop's seam jumps by %.3f" % jump
	return ""


func test_song_structure() -> String:
	var song: AKSong = load(SONG)
	if song == null:
		return "Neon Circuit doesn't load"
	var names := song.sections.map(func(s: Dictionary) -> String: return s.name)
	if names != ["intro", "build", "race", "break", "final_lap", "finish"]:
		return "sections: %s" % [names]
	var bars := 0.0
	for s in song.sections:
		bars += float(s.bars)
	if bars != 32.0 or absf(song.length_s() - 32 * 4 * 60.0 / 128.0) > 0.01:
		return "32 bars at 128 bpm: %s bars, %.2f s" % [bars, song.length_s()]
	# Songs may name their patterns by path; the summary must cope.
	var sm := AKMidi.summary(song)
	if not sm.contains("lead") or not sm.contains("6 sections"):
		return "summary: %s" % sm
	# Every melodic note is in A minor (A B C D E F G).
	for e in song.events():
		if int(e.get("midi", -1)) >= 0 and not [9, 11, 0, 2, 4, 5, 7].has(int(e.midi) % 12):
			return "%s plays %d, outside A minor" % [e.lane, e.midi]
	if not AKSynth.available():
		return ""
	# The mix: quiet intro, full race sections, every section audible, no clipping.
	var mix: AKBuffer = song.render().mix
	if mix.peak() > 0.9:
		return "the song peaks at %.2f" % mix.peak()
	var bar_s := 4 * 60.0 / 128.0
	var rms := func(a: float, b: float) -> float:
		var s := 0.0
		var i0 := int(a * bar_s * 48000)
		var i1 := int(b * bar_s * 48000)
		for i in range(i0, i1, 7):
			s += mix.l[i] * mix.l[i]
		return 10.0 * log(s / ((i1 - i0) / 7.0)) / log(10.0)
	var intro: float = rms.call(0, 4)
	var race: float = rms.call(8, 16)
	var brk: float = rms.call(16, 20)
	if intro < -40.0 or race < intro + 6.0 or race < brk + 6.0:
		return "levels: intro %.1f, race %.1f, break %.1f dB" % [intro, race, brk]
	return ""
