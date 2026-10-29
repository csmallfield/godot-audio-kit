# SPDX-License-Identifier: Apache-2.0
# "Neon Circuit" re-made as loops and an arrangement, from the song's own
# patterns (demo/racing/song/p_*.tres, written by make_racing.gd), through
# AKLoop.from_pattern, the same conversion the Loops tab's import uses.
#
#   godot --headless --path . -s res://demo/racing/make_arrangement.gd
#
# Writes, all as text:
#   demo/racing/loops/        a loop per part (pad, arp, bass, beats, leads ...) and neon_kit
#   demo/racing/arrangement/  neon_circuit.tres: tracks, a scene per section, the timeline
#   demo/racing/race_cues.tres  the cue map the race demo's sound effects play from
extends SceneTree

const D := "res://demo/racing/"
const S := "res://demo/racing/song/"
const L := "res://demo/racing/loops/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(L)
	DirAccess.make_dir_recursive_absolute(D + "arrangement")
	var kit := _kit()
	_save(kit, L + "neon_kit.tres")
	kit = load(L + "neon_kit.tres")
	var loops := {
		pad = _loop("race", ["pad"], 4),
		pad_end = _loop("finish", ["pad"], 4),
		arp = _loop("race", ["arp"], 4),
		arp_soft = _loop("break", ["arp"], 4),
		bass = _loop("race", ["bass"], 4),
		bass_end = _loop("finish", ["bass"], 4),
		beat = _onto(_loop("race", ["kick", "snare", "clap", "hat", "open_hat"], 1), kit),
		build_beat = _onto(_loop("build", ["kick", "hat"], 4), kit),
		end_hit = _onto(_loop("finish", ["kick", "crash"], 4), kit),
		lead = _loop("race", ["lead"], 8),
		lead_high = _loop("final_lap", ["lead"], 8),
		lead_low = _loop("final_lap", ["lead_low"], 8),
		break_lead = _loop("break", ["lead"], 4),
	}
	var cats := {pad = "pad", pad_end = "pad", arp = "arp", arp_soft = "arp", bass = "bass", bass_end = "bass", beat = "beat",
		build_beat = "beat", end_hit = "beat", lead = "lead", lead_high = "lead", lead_low = "lead", break_lead = "lead"}
	var paths := {}
	for k in loops:
		var l: AKLoop = loops[k]
		l.category = cats[k]
		paths[k] = L + "%s.tres" % k
		_save(l, paths[k])
	_save(_arrangement(paths), D + "arrangement/neon_circuit.tres")
	_save(_cues(), D + "race_cues.tres")
	quit()


func _save(r: Resource, path: String) -> void:
	if r.resource_name == "":
		r.resource_name = path.get_file().get_basename()
	if ResourceSaver.save(r, path) != OK:
		push_error("couldn't save " + path)
	else:
		print("wrote ", path)


## A loop of `lanes` from the song's pattern for `section`.
func _loop(section: String, lanes: Array, bars: int) -> AKLoop:
	var p: AKPattern = load(S + "p_%s.tres" % section)
	var l := AKLoop.from_pattern(p, lanes, bars)
	l.resource_name = ""
	return l


## The song's drum recipes as one kit, levelled as the song mixes them.
func _kit() -> AKKit:
	var k := AKKit.new()
	k.resource_name = "neon_kit"
	k.pieces = [
		{name = "kick", sound = S + "kick.tres"},
		{name = "snare", sound = S + "snare.tres", gain_db = -3.0},
		{name = "clap", sound = S + "clap.tres", gain_db = -6.0},
		{name = "hat", sound = S + "hat.tres", gain_db = -5.0, choke = "hats"},
		{name = "open_hat", sound = S + "open_hat.tres", gain_db = -9.0, choke = "hats"},
		{name = "crash", sound = S + "crash.tres", gain_db = -6.0},
	]
	return k


## Move a drum loop made by from_pattern (its own kit) onto the shared kit,
## row by piece name.
func _onto(l: AKLoop, kit: AKKit) -> AKLoop:
	var own := l.instrument as AKKit
	var notes := []
	for n: Array in l.notes:
		var row := kit.find_piece(own.piece_name(int(n[2])))
		if row >= 0:
			notes.append([n[0], n[1], row, n[3]])
	l.notes = notes
	l.instrument = kit
	return l


func _arrangement(p: Dictionary) -> AKArrangement:
	var song: AKSong = load(S + "neon_circuit.tres")
	var a := AKArrangement.new()
	a.resource_name = "neon_circuit"
	a.tempo = load(S + "tempo.tres")
	a.tracks = [
		{name = "pad", gain_db = 7.0, send = 0.35},
		{name = "arp", gain_db = 5.0, send = 0.25},
		{name = "bass"},
		{name = "drums", send = 0.12, fx = [{type = "compressor", threshold_db = -16.0, ratio = 3.0, attack_s = 0.005, release_s = 0.1, makeup_db = 2.0}]},
		{name = "lead", gain_db = 1.0, send = 0.3},
		{name = "lead_low", gain_db = 1.0, send = 0.3},
	]
	a.scenes = [
		{name = "intro", bars = 4.0, clips = {"pad": p.pad, "arp": p.arp}},
		{name = "build", bars = 4.0, clips = {"pad": p.pad, "arp": p.arp, "bass": p.bass, "drums": p.build_beat}},
		{name = "race", bars = 8.0, clips = {"pad": p.pad, "arp": p.arp, "bass": p.bass, "drums": p.beat, "lead": p.lead}},
		{name = "break", bars = 4.0, clips = {"pad": p.pad, "arp": p.arp_soft, "lead": p.break_lead}},
		{name = "final_lap", bars = 8.0, clips = {"pad": p.pad, "arp": p.arp, "bass": p.bass, "drums": p.beat, "lead": p.lead_high, "lead_low": p.lead_low}},
		{name = "finish", bars = 4.0, clips = {"pad": p.pad_end, "arp": p.arp_soft, "bass": p.bass_end, "drums": p.end_hit}},
	]
	# The timeline: the scenes in the song's order, a marker at each.
	var bar := 0.0
	for si in a.scenes.size():
		var bars := float(a.scenes[si].bars)
		a.timeline = a.painted(si, bar, bar + bars)
		a.markers.append({name = String(a.scenes[si].name), bar = bar})
		bar += bars
	# A crash on the downbeat into the race (from the build) and into the
	# final lap (from the race), not again each time a looping scene comes
	# round. The song's riser leads in 1.85 s before the bar, longer than a
	# game's switch is known in advance (at most a bar, 1.9 s), so here the
	# stinger has no lead-in.
	a.stingers = [{to = "race", from = "build", recipe = S + "crash.tres", gain_db = -4.0},
		{to = "final_lap", from = "race", recipe = S + "crash.tres", gain_db = -4.0}]
	a.reverb = song.reverb.duplicate(true)
	a.master_fx = song.master_fx.duplicate(true)
	return a


## The race demo's sound effects, by cue name.
func _cues() -> AKCueMap:
	var m := AKCueMap.new()
	var sfx := D + "sfx/"
	for n in ["countdown_beep", "countdown_go", "checkpoint", "lap_complete", "finish_fanfare", "gear_shift", "nitro_boost", "menu_select"]:
		m.sounds[n] = load(sfx + n + ".tres")
	m.duck = {depth_db = 4.0, full_at_db = -18.0, attack_s = 0.01, release_s = 0.35}
	return m
