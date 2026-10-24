# SPDX-License-Identifier: Apache-2.0
@tool
## Bake patches to audio, and play them live.
##
##   var buf := AKSynth.render_notes(patch, [{time_s = 0.0, note = "C4", length_s = 0.5},
##       {time_s = 0.5, note = 64, velocity = 0.7, length_s = 0.5}])     # AKBuffer
##   var one := AKSynth.render_note(patch, "A3", 1.0, 0.4)
##
##   var s := AKSynthStream.new()        # live (native core): any AudioStreamPlayer
##   s.patch = patch
##   $Player.stream = s
##   $Player.play()
##   s.note_on(60, 0.9)                  # sounds at the next mix
##   s.note_off(60, 0.25)                # a quarter second from now, to the sample
##
## Baking uses the native engine when it's installed and AKSynthCore (the
## same steps in GDScript, slower) when it isn't; AKSynthStream is the native
## engine running live. All three give the same samples for the same events.
class_name AKSynth
extends RefCounted

const E_ON := 0
const E_OFF := 1
const E_BEND := 2
const E_MOD := 3
const E_TOUCH := 4
const E_ALL_OFF := 5


## True when AKSynthStream (live play) is available: the native core is built.
static func available() -> bool:
	return ClassDB.class_exists(&"AKSynthStream")


## A MIDI note number from 60, 60.5, "C4" or "F#2".
static func note_number(n: Variant) -> float:
	if n is float or n is int:
		return float(n)
	return float(AKNotes.name_to_midi(n))


## Engine events for a list of notes {time_s, note, velocity (1), length_s}
## and optional controller changes {time_s, bend | mod_wheel | aftertouch}:
## [[frame, type, a, b], ...] in time order (at a tie, offs before ons).
static func events_for(notes: Array, sample_rate := 48000) -> Array:
	var ev := []
	for n: Dictionary in notes:
		var at := roundi(float(n.get("time_s", 0.0)) * sample_rate)
		if n.has("note"):
			var k := note_number(n.note)
			ev.append([at, E_ON, k, float(n.get("velocity", 1.0))])
			var off := roundi((float(n.get("time_s", 0.0)) + float(n.get("length_s", 0.25))) * sample_rate)
			ev.append([maxi(off, at), E_OFF, k, 0.0])
		if n.has("bend"):
			ev.append([at, E_BEND, float(n.bend), 0.0])
		if n.has("mod_wheel"):
			ev.append([at, E_MOD, float(n.mod_wheel), 0.0])
		if n.has("aftertouch"):
			ev.append([at, E_TOUCH, float(n.aftertouch), 0.0])
	# Stable: time, then offs before ons, then the order given.
	var idx := range(ev.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ea: Array = ev[a]
		var eb: Array = ev[b]
		if ea[0] != eb[0]:
			return ea[0] < eb[0]
		var oa := 0 if ea[1] == E_OFF else 1
		var ob := 0 if eb[1] == E_OFF else 1
		if oa != ob:
			return oa < ob
		return a < b)
	var out := []
	for i in idx:
		out.append(ev[i])
	return out


## Render notes (see events_for) through `patch`. `length_s` 0 = to the last
## note's end plus the patch's release tail.
static func render_notes(patch: AKPatch, notes: Array, length_s := 0.0, sample_rate := 0) -> AKBuffer:
	var sr := sample_rate if sample_rate > 0 else AK.sample_rate
	var ev := events_for(notes, sr)
	var frames := roundi(length_s * sr)
	if length_s <= 0.0:
		var last := 0
		for e: Array in ev:
			last = maxi(last, int(e[0]))
		frames = last + roundi(patch.tail_s() * sr) + 1
	return render_events(patch.compile(), ev, frames, sr)


## One note: held `gate_s`, `length_s` long in all (0 = gate plus the tail).
static func render_note(patch: AKPatch, note: Variant, velocity := 1.0, gate_s := 0.3, length_s := 0.0) -> AKBuffer:
	var total := length_s if length_s > 0.0 else gate_s + patch.tail_s()
	return render_notes(patch, [{time_s = 0.0, note = note, velocity = velocity, length_s = gate_s}], total)


## The lowest level: a compiled patch, engine events, a length in frames.
## `force_gdscript` skips the native engine (tests use it).
static func render_events(compiled: Dictionary, events: Array, frames: int, sample_rate := 48000, force_gdscript := false) -> AKBuffer:
	var b := AKBuffer.new(0, sample_rate)
	var nn := AKDsp.nat()
	if nn and not force_gdscript and nn.has_method(&"synth_render"):
		var res: Array = nn.synth_render(compiled, events, frames, sample_rate)
		b.l = res[0]
		b.r = res[1]
		return b
	var core := AKSynthCore.new(compiled, sample_rate)
	for e: Array in events:
		core._queue(int(e[0]), int(e[1]), float(e[2]), float(e[3]) if e.size() > 3 else 0.0)
	var lr := core.render(frames)
	b.l = lr[0]
	b.r = lr[1]
	return b
