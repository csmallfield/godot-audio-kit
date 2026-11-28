# SPDX-License-Identifier: Apache-2.0
# The converters' mappings onto the engine-expansion features (docs/plans/engine-expansion.md,
# "Converter updates"), on synthetic sidecars: each mapping gives the GAK keys it should, the
# caveats say what's still approximated, and the result compiles and renders finite audio. These
# check the mapping, not the sound: the reference renders (tools/patch_convert/README.md) need the
# patch libraries and DawDreamer.
extends RefCounted

const HELM := "res://tools/patch_convert/helm.gd"


func _finite(patch: AKPatch, frames := 9600) -> String:
	var b := AKSynth.render_events(patch.compile(), [[0, AKSynth.E_ON, 60.0, 0.8], [frames / 2, AKSynth.E_OFF, 60.0, 0.0]], frames, 48000)
	var peak := 0.0
	for x in b.l:
		if is_nan(x) or is_inf(x):
			return "renders a non-finite sample"
		peak = maxf(peak, absf(x))
	return "" if peak > 1e-5 else "renders silence"


func _rows(patch: AKPatch) -> Dictionary:
	var out := {}
	for m: Dictionary in patch.mods:
		out[String(m.source) + ">" + String(m.dest)] = float(m.amount)
	return out


## Helm's formant filter as GAK's formant type: its corners are the tenor set's vowels exactly, it goes
## in filter 2 behind Helm's filter (filter 1 when that's off), its gain (24 dB + the overall) into the
## patch gain, no peaking EQs left; rows to x/y become vowel / vowel2 rows; the caveats follow.
func test_helm_formant() -> String:
	var H = load(HELM)
	if int(H.VERSION) < 4:
		return "helm.gd VERSION should be bumped past 3"
	var base := {name = "t", params = {osc_1_volume = 0.7, formant_on = 1.0, formant_x = 0.0, formant_y = 0.0, filter_on = 1.0}, modulations = []}
	var plain := base.duplicate(true)
	plain.params.formant_on = 0.0
	var gain0: float = H.convert(plain).gain_db
	var p: AKPatch = H.convert(base)
	if p.filter2.get("type", "") != "formant" or absf(float(p.filter2.vowel)) > 1e-9 or p.filter2.get("formant_set", "") != "tenor" \
			or p.filter2.has("formant_shift"):
		return "corner A (0, 0) should be the tenor's a in filter 2: %s" % [p.filter2]
	if p.effects.any(func(e: Dictionary) -> bool: return e.type == "eq"):
		return "the peaking-EQ approximation is still there: %s" % [p.effects]
	if absf(p.gain_db - gain0 - 20.0) > 1e-6:
		return "corner A's gain should be 24 - 4 dB over the formant-less patch, got %s" % (p.gain_db - gain0)
	# The corners: O (1, 0) = o, I (0, 1) = i, E (1, 1) = e; with the filter off, in filter 1.
	for c: Array in [[1.0, 0.0, 0.75], [0.0, 1.0, 0.5], [1.0, 1.0, 0.25]]:
		var s := base.duplicate(true)
		s.params.formant_x = c[0]
		s.params.formant_y = c[1]
		s.params.filter_on = 0.0
		var q: AKPatch = H.convert(s)
		if q.filter.get("type", "") != "formant" or absf(float(q.filter.vowel) - float(c[2])) > 1e-9 or not q.filter2.is_empty():
			return "corner (%s, %s) should be vowel %s in filter 1: %s / %s" % [c[0], c[1], c[2], q.filter, q.filter2]
		if H.caveats(s).any(func(t: String) -> bool: return t.begins_with("formant")):
			return "a corner is exact, no caveat: %s" % [H.caveats(s)]
	# The i-e edge is one stretch of GAK's axis: (0.5, 1) sits between them, nearly unshifted.
	var f: Dictionary = H.formant_fit(0.5, 1.0)
	if absf(float(f.vowel) - 0.375) > 0.03 or absf(float(f.formant_shift)) > 0.1 or float(f.err) > 0.1:
		return "the i-e edge's middle: %s" % [f]
	# Inside the square: fitted, and the caveat says how far off.
	var mid := base.duplicate(true)
	mid.params.formant_x = 0.5
	mid.params.formant_y = 0.0
	if not H.caveats(mid).any(func(t: String) -> bool: return t.contains("fitted onto GAK's vowel axis")):
		return "a fitted point should say so: %s" % [H.caveats(mid)]
	# Rows to formant_y (on a smooth stretch: x = 0, y 0..0.5 runs a toward e) become vowel2 rows.
	var m := base.duplicate(true)
	m.params.formant_y = 0.25
	m.modulations = [{source = "mono_lfo_1", destination = "formant_y", amount = 0.2}, {source = "mod_wheel", destination = "formant_y", amount = 0.3}]
	var pm: AKPatch = H.convert(m)
	var rows := _rows(pm)
	var slope: Array = H.formant_slope(0.0, 0.25)
	if is_nan(float(slope[1])) or float(slope[1]) <= 0.1 or absf(rows.get("mod_wheel>vowel2", 0.0) - 0.3 * float(slope[1])) > 1e-9 \
			or rows.get("lfo1>vowel2", 0.0) == 0.0:
		return "formant_y rows should be vowel2 rows at the fit's slope %s: %s" % [slope, rows]
	var cav: Array = H.caveats(m)
	if cav.any(func(t: String) -> bool: return t.begins_with("modulation not converted") and t.contains("formant")):
		return "formant rows are converted now, not dropped: %s" % [cav]
	if not cav.any(func(t: String) -> bool: return t.contains("formant y modulation as a straight line")):
		return "the linearised x/y rows should be listed: %s" % [cav]
	# With the filter off the rows go to vowel (filter 1).
	m.params.filter_on = 0.0
	if not _rows(H.convert(m)).has("lfo1>vowel"):
		return "with Helm's filter off, formant rows should move vowel: %s" % [_rows(H.convert(m))]
	for s: Dictionary in [base, mid, m]:
		var e := _finite(H.convert(s))
		if e != "":
			return "%s: %s" % [s.params, e]
	return ""
