# SPDX-License-Identifier: Apache-2.0
# Flavor (docs/plans/flavor-tab.md): the base sound, each control's approved end
# values, how controls combine, the limiter, the stored settings and loudness.
extends RefCounted


func _near(got: float, want: float, tol := 1e-6) -> bool:
	return absf(got - want) <= tol


func _fx(p: AKPatch, type: String) -> Array:
	var out := []
	for e: Dictionary in p.effects:
		if String(e.get("type", "")) == type:
			out.append(e)
	return out


func _row(p: AKPatch, source: String, dest: String) -> Dictionary:
	for m: Dictionary in p.mods:
		if m.source == source and m.dest == dest:
			return m
	return {}


func _all_up() -> Dictionary:
	var d := {}
	for k: Dictionary in AKFlavor.KNOBS:
		d[k.id] = 1.0
	for sw: Dictionary in AKFlavor.SWITCHES:
		d[sw.id] = true
	return d


func test_base_sound() -> String:
	var p := AKFlavor.build()
	if p.oscillators.size() != 2:
		return "the base has %d oscillators, want 2" % p.oscillators.size()
	var o: Dictionary = p.oscillators[0]
	if o.shape != "morph" or not _near(o.position, 0.55) or not _near(o.level, 0.6):
		return "main oscillator: %s" % str(o)
	if not _near(p.oscillators[1].semitones, -12.0) or not _near(p.oscillators[1].level, 0.25):
		return "sub oscillator: %s" % str(p.oscillators[1])
	if p.unison != 2 or not _near(p.detune_cents, 8.0) or not _near(p.spread, 0.3):
		return "unison %d, detune %s, spread %s" % [p.unison, p.detune_cents, p.spread]
	if p.filter.type != "ladder" or not _near(p.filter.cutoff_hz, 2500.0) or not _near(p.filter.resonance, 0.2):
		return "filter: %s" % str(p.filter)
	if not _near(p.gain_db, -6.0) or p.mode != "poly" or p.mods.size() != 3:
		return "gain %s, mode %s, %d rows" % [p.gain_db, p.mode, p.mods.size()]
	var types := []
	for e: Dictionary in p.effects:
		types.append(e.type)
	if types != ["saturate", "delay", "reverb", "limiter"]:
		return "effects: %s" % str(types)
	if not _near(_fx(p, "limiter")[0].ceiling_db, AKFlavor.CEILING_DB):
		return "limiter ceiling: %s" % str(_fx(p, "limiter")[0])
	return ""


func test_missing_and_out_of_range_settings() -> String:
	var base := AKFlavor.fingerprint(AKFlavor.build())
	if AKFlavor.fingerprint(AKFlavor.build(AKFlavor.defaults())) != base:
		return "defaults() is not the base"
	# An add-only knob ignores a negative value; a two-way knob clamps at 1.
	if AKFlavor.fingerprint(AKFlavor.build({clean_filthy = -1.0, nonsense = 3.0})) != base:
		return "a negative add-only knob or an unknown key changed the patch"
	if AKFlavor.fingerprint(AKFlavor.build({lean_beefy = 5.0})) != AKFlavor.fingerprint(AKFlavor.build({lean_beefy = 1.0})):
		return "a knob past 1 is not clamped"
	return ""


func test_every_control_changes_the_sound() -> String:
	var base := AKFlavor.fingerprint(AKFlavor.build())
	for k: Dictionary in AKFlavor.KNOBS:
		var ends := [1.0, -1.0] if k.two_way else [1.0]
		for v: float in ends:
			if AKFlavor.fingerprint(AKFlavor.build({k.id: v})) == base:
				return "%s at %s is the base sound" % [k.id, v]
		if AKFlavor.fingerprint(AKFlavor.build({k.id: 0.5})) == AKFlavor.fingerprint(AKFlavor.build({k.id: 1.0})):
			return "%s sounds the same at 0.5 and 1" % k.id
	for sw: Dictionary in AKFlavor.SWITCHES:
		if sw.id == "minor":
			continue
		if AKFlavor.fingerprint(AKFlavor.build({sw.id: true})) == base:
			return "%s does nothing" % sw.id
	return ""


func test_approved_end_values() -> String:
	var p := AKFlavor.build({lean_beefy = 1.0})
	if not _near(p.oscillators[1].level, 0.6) or p.oscillators[2].shape != "square" or not _near(p.oscillators[2].level, 0.6):
		return "Beefy's subs: %s" % str(p.oscillators)
	if not _near(_fx(p, "eq")[0].low_db, 9.0) or not _near(_fx(p, "compressor")[0].ratio, 4.0):
		return "Beefy's eq or compressor"
	p = AKFlavor.build({lean_beefy = -1.0})
	if not _near(p.oscillators[1].level, 0.0) or not _near(_fx(p, "eq")[0].low_db, -24.0) or p.unison != 1:
		return "Lean: sub %s, low %s, unison %d" % [p.oscillators[1].level, _fx(p, "eq")[0].low_db, p.unison]
	p = AKFlavor.build({silky_gritty = -1.0})
	if not _near(p.oscillators[0].position, 0.36) or not _near(p.filter.resonance, 0.05):
		return "Silky: position %s, resonance %s" % [p.oscillators[0].position, p.filter.resonance]
	p = AKFlavor.build({shut_quack = 1.0})
	if not _near(p.filter.resonance, 0.75) or not _near(p.filter.cutoff_hz, 625.0) or not _near(_row(p, "env2", "cutoff").amount, 5.0):
		return "Quack: %s, env throw %s" % [str(p.filter), _row(p, "env2", "cutoff").amount]
	p = AKFlavor.build({pluck_bloom = 1.0})
	if not _near(p.amp_env.attack_s, 1.21) or not _near(p.amp_env.release_s, 1.5) or not _near(p.amp_env.sustain, 1.0):
		return "Bloom's envelope: %s" % str(p.amp_env)
	p = AKFlavor.build({pluck_bloom = -1.0})
	if not _near(p.amp_env.attack_s, 0.001) or not _near(p.amp_env.sustain, 0.05):
		return "Pluck's envelope: %s" % str(p.amp_env)
	p = AKFlavor.build({solo_crowd = 1.0})
	if p.unison != 7 or not _near(p.detune_cents, 45.0) or not _near(p.spread, 1.0):
		return "Crowd: unison %d, detune %s, spread %s" % [p.unison, p.detune_cents, p.spread]
	p = AKFlavor.build({clean_filthy = 1.0})
	if not _near(_fx(p, "saturate")[0].drive_db, 24.0) or not _near(_fx(p, "crush")[0].bits, 3.0) or _fx(p, "growl").size() != 1:
		return "Filthy's saturate, crush or growl"
	p = AKFlavor.build({dry_drenched = 1.0})
	if not _near(_fx(p, "delay")[0].feedback, 0.8) or _fx(p, "reverb").size() != 2 or not _near(_fx(p, "reverb")[0].mix, 1.0):
		return "Drenched's delay or reverbs"
	p = AKFlavor.build({dry_drenched = -1.0})
	if not _near(_fx(p, "delay")[0].mix, 0.0) or not _near(_fx(p, "reverb")[0].mix, 0.0) or not _near(p.amp_env.release_s, 0.0625):
		return "Dry: release %s" % p.amp_env.release_s
	p = AKFlavor.build({polite_farty = 1.0})
	if not _near(p.oscillators[0].cents, -150.0) or not _near(_row(p, "env4", "pitch").amount, 1.5) or not _near(p.lfos[0].rate_hz, 22.0):
		return "Farty's sag or flap"
	p = AKFlavor.build({stiff_slinky = 1.0})
	if p.mode != "mono" or not _near(p.glide_s, 0.5):
		return "Slinky: mode %s, glide %s" % [p.mode, p.glide_s]
	if AKFlavor.build({stiff_slinky = 0.0}).mode != "poly":
		return "Slinky at rest should stay polyphonic"
	return ""


func test_switches() -> String:
	var p := AKFlavor.build({bounce = true})
	if not p.arp.get("on", false) or p.arp.rate != "1/16" or p.arp.octaves != 2:
		return "Bounce's arpeggiator: %s" % str(p.arp)
	p = AKFlavor.build({pump = true})
	# Pump is the fifth LFO: lfo3 and lfo4 are filled in ahead of it.
	if p.lfos.size() != 3 or not p.lfos[2].get("free", false) or p.lfos[2].rate_sync != "1/4" or _row(p, "lfo5", "amp").is_empty():
		return "Pump's LFO: %s" % str(p.lfos)
	p = AKFlavor.build({wide = true})
	if not _near(p.spread, 1.0) or _fx(p, "delay")[0].mode != "pingpong":
		return "Wide: spread %s" % p.spread
	p = AKFlavor.build({lofi = true})
	if _fx(p, "crush").size() != 1 or not _near(_fx(p, "eq")[0].high_db, -15.0):
		return "Lo-Fi's crush or eq"
	# Minor only matters once Note/Chord's third is in (past 0.6).
	var major := AKFlavor.build({note_chord = 1.0})
	var minor := AKFlavor.build({note_chord = 1.0, minor = true})
	if not _near(major.oscillators[4].semitones, 16.0) or not _near(minor.oscillators[4].semitones, 15.0):
		return "the third: %s, %s" % [major.oscillators[4].semitones, minor.oscillators[4].semitones]
	if AKFlavor.fingerprint(AKFlavor.build({note_chord = 0.5})) != AKFlavor.fingerprint(AKFlavor.build({note_chord = 0.5, minor = true})):
		return "Minor changed the sound before the third is in"
	return ""


func test_order_of_keys_does_not_matter() -> String:
	var a := AKFlavor.build({pluck_bloom = 0.7, silky_gritty = -0.4, dry_drenched = -1.0, polite_farty = 0.6, woody_glassy = 1.0})
	var b := AKFlavor.build({woody_glassy = 1.0, polite_farty = 0.6, dry_drenched = -1.0, silky_gritty = -0.4, pluck_bloom = 0.7})
	return "" if AKFlavor.fingerprint(a) == AKFlavor.fingerprint(b) else "the same settings in another order gave another patch"


func test_combinations_stay_inside_the_engine() -> String:
	var p := AKFlavor.build(_all_up())
	if p.oscillators.size() > AKPatch.MAX_OSC or p.mods.size() > AKPatch.MAX_MODS or p.lfos.size() + 2 > AKPatch.MAX_LFO:
		return "everything up: %d oscillators, %d rows, %d LFOs" % [p.oscillators.size(), p.mods.size(), p.lfos.size() + 2]
	if p.oscillators.size() != 13 or p.mods.size() != 16:
		return "everything up should be 13 oscillators and 16 merged rows, got %d and %d" % [p.oscillators.size(), p.mods.size()]
	if p.effects.back().type != "limiter":
		return "the limiter is not last"
	if _fx(p, "chorus").size() != 1:
		return "Sparkly's and Crowd's choruses should merge into one"
	# Four knobs raise the resonance and the envelope's throw: both are held.
	p = AKFlavor.build({silky_gritty = 1.0, woody_glassy = -1.0, shut_quack = 1.0, polite_farty = 1.0})
	if not _near(p.filter.resonance, AKFlavor.MAX_RESONANCE) or not _near(_row(p, "env2", "cutoff").amount, AKFlavor.MAX_ENV_CUTOFF_OCT):
		return "resonance %s, envelope throw %s" % [p.filter.resonance, _row(p, "env2", "cutoff").amount]
	# Gritty and Glassy both send FM into the main oscillator.
	p = AKFlavor.build({silky_gritty = 1.0, woody_glassy = 1.0})
	var o: Dictionary = p.oscillators[0]
	if (o.get("fm", []) as Array).size() != 1 or int(o.get("fm_from", 0)) < 1 or int(o.fm[0].from) == int(o.fm_from):
		return "Gritty's noise and Glassy's bell should be two modulators: %s" % str(o)
	# Rows with the same source and destination merge, amounts added.
	p = AKFlavor.build({solo_crowd = 1.0, polite_farty = 1.0, steady_wonky = 1.0})
	if not _near(_row(p, "random", "pitch").amount, 0.12 + 0.3 + 0.4):
		return "random -> pitch should add up to 0.82, got %s" % _row(p, "random", "pitch").amount
	# Lean's single voice gives way to Crowd.
	if AKFlavor.build({lean_beefy = -1.0, solo_crowd = 1.0}).unison != 7:
		return "Crowd should set the voice count over Lean"
	return ""


func test_each_lfo_control_has_its_own_lfo() -> String:
	var p := AKFlavor.build({solo_crowd = -1.0, still_swirl = 1.0, polite_farty = 1.0, steady_wonky = 1.0, pump = true})
	for pair in [["lfo1", "pitch"], ["lfo2", "pan"], ["lfo3", "amp"], ["lfo4", "pitch"], ["lfo5", "amp"]]:
		if _row(p, pair[0], pair[1]).is_empty():
			return "no %s -> %s row" % pair
	if not _near(p.lfo1.rate_hz, 5.5) or not _near(p.lfo2.rate_hz, 3.5) or p.lfos[1].shape != "smooth":
		return "LFO settings: %s, %s, %s" % [str(p.lfo1), str(p.lfo2), str(p.lfos)]
	return ""


func test_chord_notes_follow_the_main_shape() -> String:
	var p := AKFlavor.build({note_chord = 1.0, silky_gritty = -1.0})
	var want: float = p.oscillators[0].position
	for o: Dictionary in p.oscillators:
		if o.shape == "morph" and not _near(o.position, want):
			return "a chord oscillator is at %s, the main one at %s" % [o.position, want]
	return ""


func test_settings_are_stored_and_go_stale() -> String:
	var st := {lean_beefy = 0.5, shut_quack = -0.25, pump = true}
	var p := AKFlavor.build(st)
	var back := AKFlavor.settings_of(p)
	if not _near(back.lean_beefy, 0.5) or not _near(back.shut_quack, -0.25) or not back.pump or back.wide:
		return "stored settings: %s" % str(back)
	if AKFlavor.is_stale(p):
		return "a fresh patch reads as edited"
	# Through a .tres and back.
	var path := "user://flavor_test.tres"
	if ResourceSaver.save(p, path) != OK:
		return "could not save the patch"
	var q: AKPatch = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if q == null or not _near(AKFlavor.settings_of(q).lean_beefy, 0.5) or AKFlavor.is_stale(q):
		return "the settings did not survive a save and load"
	if AKFlavor.fingerprint(AKFlavor.build(AKFlavor.settings_of(q))) != AKFlavor.fingerprint(p):
		return "rebuilding from the stored settings gave another patch"
	# Edited elsewhere: the settings are kept but no longer describe the patch.
	var f: Dictionary = q.filter.duplicate()
	f.cutoff_hz = 900.0
	q.filter = f
	if not AKFlavor.is_stale(q) or AKFlavor.settings_of(q).is_empty():
		return "an edited patch should be stale and keep its settings"
	if AKFlavor.is_stale(AKPatch.new()) or not AKFlavor.settings_of(AKPatch.new()).is_empty():
		return "a plain patch is not a Flavor patch"
	return ""


func test_limiter_holds_a_resonance_stack() -> String:
	var p := AKFlavor.build({silky_gritty = 1.0, woody_glassy = -1.0, shut_quack = 1.0, polite_farty = 1.0})
	var b := AKSynth.render_notes(p, [{time_s = 0.0, note = "C2", velocity = 0.85, length_s = 0.2}], 0.4)
	var peak := linear_to_db(maxf(b.peak(), 1e-9))
	if peak > AKFlavor.CEILING_DB + 0.01:
		return "peak %.2f dBFS, over the ceiling" % peak
	if peak < -20.0:
		return "the note is nearly silent (%.1f dBFS)" % peak
	return ""


func test_loudness_gain_rule() -> String:
	var base := -15.0
	var w := AKFlavor.LOUDNESS_WINDOW
	# Inside the window: left alone.
	for l: float in [base, base + w, base - w]:
		if not _near(AKFlavor.gain_for({lufs = l, peak_db = -6.0}, base), 0.0):
			return "a sound %.1f LU from the base was changed" % (l - base)
	# Louder: down to the top of the window.
	if not _near(AKFlavor.gain_for({lufs = base + 7.3, peak_db = -1.5}, base), -4.3):
		return "a sound 7.3 LU over should come down 4.3 dB"
	# Quieter with headroom: up to the bottom of the window.
	if not _near(AKFlavor.gain_for({lufs = base - 8.0, peak_db = -12.0}, base), 5.0):
		return "a quiet sound with headroom should come up 5 dB"
	# Quieter but peaking near the ceiling: only as far as the peaks allow.
	if not _near(AKFlavor.gain_for({lufs = base - 5.6, peak_db = -1.7}, base), 0.7):
		return "a plucked sound should rise only 0.7 dB"
	if not _near(AKFlavor.gain_for({lufs = base - 10.4, peak_db = -0.7}, base), 0.0):
		return "a sound already peaking over the ceiling should not be raised"
	return ""


func test_level_sets_one_fixed_gain() -> String:
	var p := AKFlavor.build({lean_beefy = 1.0})
	var g := AKFlavor.level(p)
	if g >= 0.0:
		return "full Beefy is louder than the window and should come down (gain %.2f)" % g
	var stage: Array = _fx(p, "compressor").filter(func(e: Dictionary) -> bool: return e.get("flavor_gain", false))
	if stage.size() != 1 or not _near(stage[0].ratio, 1.0) or not _near(stage[0].makeup_db, g):
		return "the gain stage: %s" % str(stage)
	if p.effects[p.effects.size() - 2] != stage[0] or p.effects.back().type != "limiter":
		return "the gain stage should sit just ahead of the limiter"
	# Measuring ignores the stage, so levelling twice gives the same gain, once.
	if not _near(AKFlavor.level(p), g, 1e-3):
		return "levelling twice changed the result"
	if _fx(p, "compressor").filter(func(e: Dictionary) -> bool: return e.get("flavor_gain", false)).size() != 1:
		return "levelling twice stacked gain stages"
	if AKFlavor.is_stale(p) or not _near(p.get_meta(AKFlavor.META_KEY).level_gain_db, g, 1e-3):
		return "levelling should refresh the stored fingerprint and gain"
	return ""


func test_randomise_and_mutate() -> String:
	var a := AKFlavor.randomise(7)
	if a != AKFlavor.randomise(7) or a == AKFlavor.randomise(8):
		return "randomise should depend on its seed and nothing else"
	var far := 0
	for seed in 40:
		var d := AKFlavor.randomise(seed)
		for k: Dictionary in AKFlavor.KNOBS:
			var v: float = d[k.id]
			if v > 1.0 or v < (-1.0 if k.two_way else 0.0):
				return "%s out of range: %s" % [k.id, v]
			if absf(v) >= 0.5:
				far += 1
	# Three or four knobs pushed far each time, the rest near rest.
	if far < 40 * 3 or far > 40 * 5:
		return "%d knobs pushed far over 40 sounds" % far
	var m := AKFlavor.mutate(a, 3, 0.15)
	if m != AKFlavor.mutate(a, 3, 0.15) or m == a:
		return "mutate should move the settings, the same way for the same seed"
	var moved := 0.0
	for k: Dictionary in AKFlavor.KNOBS:
		moved = maxf(moved, absf(float(m[k.id]) - float(a[k.id])))
		if float(m[k.id]) > 1.0 or float(m[k.id]) < (-1.0 if k.two_way else 0.0):
			return "mutate took %s out of range" % k.id
	if moved > 0.6:
		return "a small mutation moved a knob by %.2f" % moved
	return ""
