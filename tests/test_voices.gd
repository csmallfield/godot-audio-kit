# SPDX-License-Identifier: Apache-2.0
extends RefCounted

## Voices that fade in by design may take longer to become audible.
const SWELLS := ["whoosh"]


func test_every_voice_renders_clean() -> String:
	for name in AK.voice_names():
		var b := AK.render(AKRecipe.make(StringName(name)))
		if b.frames() == 0:
			return "%s rendered nothing" % name
		var p := b.peak()
		if not is_finite(p) or p <= 0.01:
			return "%s peak %.4f" % [name, p]
		if p > 1.0:
			return "%s default patch clips (peak %.3f)" % [name, p]
		var first := b.first_above(1e-4)
		var limit := 0.005 if not SWELLS.has(name) else 0.01
		if first < 0 or first > limit * AK.sample_rate:
			return "%s first audible at sample %d (lead-in silence)" % [name, first]
	return ""


func test_every_voice_documents_its_parameters() -> String:
	for name in AK.voice_names():
		var v := AK.voice(StringName(name))
		if v.doc() == "":
			return "%s has no doc()" % name
		for k in v.schema():
			if String(v.schema()[k].get("doc", "")) == "":
				return "%s.%s has no doc" % [name, k]
	return ""


func test_voices_are_deterministic() -> String:
	for name in AK.voice_names():
		var r := AKRecipe.make(StringName(name))
		r.seed = 42
		var a := AK.render(r)
		var b := AK.render(r)
		if a.l != b.l or a.r != b.r:
			return "%s differs between two renders" % name
	return ""
