# SPDX-License-Identifier: Apache-2.0
@tool
extends AKVoice
## A synth patch as a recipe voice, so a recipe layer (and so a song lane, a
## cue, a recipe stream) can play an AKPatch:
##   {voice = &"patch", params = {patch = "res://addons/audio_kit/patches/saw_bass.tres", freq_hz = 110.0}}


func version() -> int:
	return 100 + AKSynthCore.VERSION


func doc() -> String:
	return "Plays one note of an AKPatch (a resource or its path) through the synth engine: any sound the patch engine can make, in a recipe."


func schema() -> Dictionary:
	return {
		patch = param("", null, null, "The AKPatch, or its res:// path"),
		freq_hz = param(261.63, 8.0, 12000.0, "Pitch (sets the note; the sequencer retunes it)"),
		velocity = param(1.0, 0.0, 1.0, "Note velocity"),
		gate_s = param(0.3, 0.0, 30.0, "How long the note is held"),
		length_s = param(0.0, 0.0, 30.0, "Total length; 0 = gate plus five amp-release times"),
	}


func render(p: Dictionary, sr: int, _rng: RandomNumberGenerator) -> PackedFloat32Array:
	var patch := resolve(p.patch)
	if patch == null:
		return PackedFloat32Array()
	var note := 69.0 + 12.0 * log(maxf(1.0, float(p.freq_hz)) / 440.0) / log(2.0)
	var gate := float(p.gate_s)
	var total: float = p.length_s if p.length_s > 0.0 else gate + patch.tail_s()
	var buf := AKSynth.render_notes(patch, [{time_s = 0.0, note = note, velocity = float(p.velocity), length_s = gate}], total, sr)
	# Mono: the recipe pans the layer. A panned patch keeps its balance as level.
	if is_equal_approx(patch.pan, 0.0) and not _pans(patch):
		return buf.l
	var out := buf.l.duplicate()
	for i in out.size():
		out[i] = 0.5 * (buf.l[i] + buf.r[i])
	return out


## The patch's content, so editing a patch saved in its own file re-bakes.
func key_extra(params: Dictionary) -> Variant:
	var v: Variant = params.get("patch", "")
	if (v is String or v is StringName) and String(v) != "" and ResourceLoader.exists(String(v)):
		var p := resolve(v)
		return p.describe() if p else null
	return null


## An AKPatch from a resource or a path; no patch at all gives the default
## patch (a plain saw), anything else null with an error.
static func resolve(v: Variant) -> AKPatch:
	if v is AKPatch:
		return v
	if v == null or ((v is String or v is StringName) and String(v) == ""):
		return AKPatch.new()
	if (v is String or v is StringName) and String(v) != "":
		var r: Resource = load(String(v))
		if r is AKPatch:
			return r
	push_error("AK patch voice: '%s' is not an AKPatch" % [v])
	return null


static func _pans(patch: AKPatch) -> bool:
	for m in patch.mods:
		if String(m.get("dest", "")) == "pan":
			return true
	return false
