# SPDX-License-Identifier: Apache-2.0
@tool
## Pseudo-speech, stage 2: an analysed line (AKSpeechText.analyse) and a
## voice become timed syllable events and neutral curves.
##
## Pitch is a simplified Fujisaki model, summed in semitones (log pitch):
##
##   pitch(t) = R * (P_clause(t) + sum_i A_i g(t - t_i) + escalation) + word melody
##
## R is the voice's range, P the clause's phrase shape (from its end mark), A_i
## the accent on syllable i (peaking at t_i, a raised-cosine bump g 80-150 ms
## wide) and the word melody a small seeded offset per syllable that makes a
## word sound like itself every time. Intensity and brightness ride the same
## accents with their own gains; noise follows fricatives and plosives;
## formant glides between vowel targets.
##
## Rules, from the design doc:
##   - the first content word of a clause gets a strong accent; a one-word
##     exclamation ("Hey!") the strongest, clipped short
##   - the last stressed syllable before the end mark carries the nuclear
##     accent and the clause's final tone
##   - function words: no accent, 60-70% length, quieter
##   - a content word repeated in its clause gets a stronger accent each time
##     (x1.0, x1.4, x1.8) and a step up in pitch
##   - punctuation sets the clause shape and the pause after it
class_name AKSpeechProsody
extends RefCounted

const CURVE_RATE := 200
## Accent weight per stress level (none, primary, secondary).
const STRESS_WEIGHT := [0.0, 1.0, 0.45]
## A plain accent's height, in units of the voice's range.
const ACCENT := 0.35
const FIRST_GAIN := 1.6
const NUCLEAR_GAIN := 1.3
## In a question the final rise does the work, so the nuclear bump is small.
const NUCLEAR_GAIN_QUESTION := 0.6
## The accent of a one-word exclamation.
const EXCLAIM_ACCENT := 1.0
## Per repeat: accent x(1 + 0.4 k), pitch +0.12 R k.
const REPEAT_GAIN := 0.4
const REPEAT_STEP := 0.12
const REPEAT_MAX := 2.2
const FUNCTION_LENGTH := 0.65
const FUNCTION_LEVEL := 0.75
## Lengthening of a clause's last syllable, by end mark.
const FINAL_LENGTH := {".": 1.35, "?": 1.2, "!": 0.9, ",": 1.1, ";": 1.1, ":": 1.1, "…": 1.5}
## Pause after a clause, seconds at tempo 1.
const PAUSE_S := {".": 0.38, "?": 0.38, "!": 0.3, ",": 0.16, ";": 0.22, ":": 0.22, "…": 0.55}
const WORD_GAP_S := 0.03
## Markup: a / pause, a ~ stretch per tilde, a ** word's clip, a * accent,
## and how far ^ and _ move the pitch (in units of the range).
const MARK_PAUSE_S := 0.18
const MARK_STRETCH := 0.6
const MARK_CLIP := 0.85
const MARK_ACCENT := ACCENT * FIRST_GAIN * 1.25
const MARK_CONTOUR := 0.6
## How quickly a ^ or _ contour lets go after its word.
const CONTOUR_RELEASE_S := 0.2


## {events, curves, curve_rate, duration} for an analysis and a voice.
static func build(a: Dictionary, voice: AKSpeechVoice) -> Dictionary:
	var words: Array = a.words
	var clauses: Array = a.clauses
	var line_hash := int(a.line_hash)
	var salt_hash := AKSpeechText.hash32(voice.salt)
	var tempo := maxf(0.05, voice.tempo)
	var base := voice.syllable_s / tempo
	var events: Array[Dictionary] = []
	var t := 0.0
	var gi := 0
	var fw_seen := {}
	for ci in clauses.size():
		var cl: Dictionary = clauses[ci]
		var end_mark := String(cl.end)
		var content := 0
		for wi in range(cl.first, cl.last + 1):
			if not words[wi].function:
				content += 1
		var one_word: bool = content == 1 and int(cl.last) == int(cl.first) and end_mark == "!"
		var first_content := -1
		var clause_events: Array[Dictionary] = []
		for wi in range(cl.first, cl.last + 1):
			var w: Dictionary = words[wi]
			var emph := int(w.get("emphasis", 0))
			# An accented function word is spoken as a content word.
			var fn: bool = bool(w.function) and emph == 0
			var state := AKSpeechMarkup.state_of(voice, String(w.get("state", "normal")))
			var shout := AKSpeechMarkup.state_of(voice, "shout") if emph == 2 else {}
			if first_content < 0 and not fn:
				first_content = wi
			var wseed := AKSpeechText.mix(AKSpeechText.hash32(String(w.norm) + "|" + voice.salt), salt_hash)
			if w.function:
				# One of four seeded variants, picked per occurrence in the line.
				var occ := int(fw_seen.get(w.norm, 0))
				fw_seen[w.norm] = occ + 1
				var variant := AKSpeechText.mix(AKSpeechText.hash32(String(w.norm)), line_hash, occ) % 4
				wseed = AKSpeechText.mix(wseed, variant + 1, 4)
			var syl: Array = w.syllables
			var has_stress := false
			for s in syl:
				if int(s.stress) == 1:
					has_stress = true
			for si in syl.size():
				var s: Dictionary = syl[si]
				var sseed := AKSpeechText.mix(wseed, si, 1)
				var ws := int(s.stress)
				if emph > 0 and not has_stress and si == 0:
					ws = 1
				var d := base / maxf(0.05, float(state.get("tempo", 1.0)))
				if fn:
					d *= FUNCTION_LENGTH
				else:
					d *= [0.85, 1.25, 1.05][ws]
				if emph == 2:
					d *= MARK_CLIP
				if si == syl.size() - 1 and int(w.get("stretch", 0)) > 0:
					d *= 1.0 + MARK_STRETCH * int(w.stretch)
				d *= _class_length(s)
				d *= 1.0 + voice.seed_time * (_unit(sseed, 2) * 2.0 - 1.0)
				d *= 1.0 + voice.jitter * 0.25 * (_unit(AKSpeechText.mix(line_hash, gi, 7), 3) * 2.0 - 1.0)
				if one_word:
					d *= 0.8
				var s_int := float(state.get("intensity", 1.0)) * float(shout.get("intensity", 1.0))
				var s_bri := float(state.get("brightness", 0.0)) + float(shout.get("brightness", 0.0))
				var pstate := String(w.get("state", "normal"))
				if emph == 2 and not AKSpeechMarkup.state_of(voice, pstate).has("patch"):
					pstate = "shout"
				clause_events.append({t_start = 0.0, t_end = d, word_index = wi, syllable_index = si, seed = sseed,
					onset_class = int(s.onset_class), coda_class = int(s.coda_class), vowel = int(s.vowel),
					stress = 0.0, accent = 0.0, raise = 0.0, function = fn,
					melody = voice.seed_pitch_semitones * (_unit(sseed, 5) * 2.0 - 1.0),
					word_stress = ws, emphasis = emph, contour = String(w.get("contour", "")),
					state = String(w.get("state", "normal")), patch_state = pstate,
					pause_after = bool(w.get("pause_after", false)) and si == syl.size() - 1,
					s_pitch = float(state.get("pitch", 0.0)), s_range = float(state.get("range", 1.0)),
					s_intensity = s_int, s_bright = s_bri})
				gi += 1
		if clause_events.is_empty():
			continue
		# The clause's last syllable is lengthened (or clipped) by its end mark.
		clause_events.back().t_end *= float(FINAL_LENGTH.get(end_mark, 1.0))
		# Lay out in time: syllables of a word touch, words have a small gap.
		var n_ev := clause_events.size()
		for k in n_ev:
			var e := clause_events[k]
			var d := float(e.t_end)
			if end_mark == "…":
				d *= 1.0 + 0.3 * float(k) / maxf(1.0, n_ev - 1)
			e.t_start = t
			e.t_end = t + d
			t += d
			if k + 1 < n_ev and int(clause_events[k + 1].word_index) != int(e.word_index):
				t += WORD_GAP_S * voice.pause_scale / tempo
				if e.pause_after:
					t += MARK_PAUSE_S * voice.pause_scale / tempo
		_accents(clause_events, words, cl, first_content, one_word)
		events.append_array(clause_events)
		if ci + 1 < clauses.size():
			t += float(PAUSE_S.get(end_mark, 0.2)) * voice.pause_scale / tempo
	var duration := float(events.back().t_end) if not events.is_empty() else 0.0
	var curves := _curves(events, clauses, voice, duration)
	# The note each syllable plays: the curves at its accent.
	for e in events:
		var at := _accent_time(e)
		e.pitch = _sample(curves.pitch, at)
		e.velocity = clampf(_sample(curves.intensity, at), 0.05, 1.0)
		for k in ["raise", "melody", "word_stress", "function", "contour", "pause_after", "s_pitch", "s_range",
				"s_intensity", "s_bright"]:
			e.erase(k)
	return {events = events, curves = curves, curve_rate = CURVE_RATE, duration = duration}


# ------------------------------------------------------------------ inside

static func _accents(evs: Array[Dictionary], words: Array, cl: Dictionary, first_content: int, one_word: bool) -> void:
	var end_mark := String(cl.end)
	var nuclear := -1
	for k in range(evs.size() - 1, -1, -1):
		if not evs[k].function and int(evs[k].word_stress) == 1:
			nuclear = k
			break
	for k in evs.size():
		var e := evs[k]
		if e.function:
			continue
		var w: Dictionary = words[int(e.word_index)]
		var occ := int(w.get("occurrence", 0))
		var a := ACCENT * float(STRESS_WEIGHT[int(e.word_stress)])
		if a <= 0.0:
			continue
		if int(e.word_index) == first_content and int(e.word_stress) == 1:
			a *= FIRST_GAIN
		if k == nuclear:
			a *= NUCLEAR_GAIN_QUESTION if end_mark == "?" else NUCLEAR_GAIN
		if end_mark == "!":
			a *= 1.2
		if one_word and int(e.word_stress) == 1:
			a = EXCLAIM_ACCENT
		# Markup: * at least a strong accent, ** the strongest; escalation stacks on top.
		if int(e.word_stress) == 1:
			if int(e.emphasis) == 1:
				a = maxf(a, MARK_ACCENT)
			elif int(e.emphasis) == 2:
				a = EXCLAIM_ACCENT
		a *= minf(REPEAT_MAX, 1.0 + REPEAT_GAIN * occ)
		e.accent = a
		e.stress = clampf(a / EXCLAIM_ACCENT, 0.0, 1.0)
	# A repeated word steps up as a whole.
	for e in evs:
		var occ := int(words[int(e.word_index)].get("occurrence", 0))
		if not e.function and occ > 0:
			e.raise = REPEAT_STEP * occ


static func _curves(events: Array[Dictionary], clauses: Array, voice: AKSpeechVoice, duration: float) -> Dictionary:
	var n := ceili(duration * CURVE_RATE) + 1
	var pitch := PackedFloat32Array()
	var intensity := PackedFloat32Array()
	var bright := PackedFloat32Array()
	var noise := PackedFloat32Array()
	var formant := PackedFloat32Array()
	for arr in [pitch, intensity, bright, noise, formant]:
		arr.resize(n)
		arr.fill(0.0)
	var r := voice.range_semitones
	# Clause spans, in events.
	var spans := []
	var k0 := 0
	for ci in clauses.size():
		var cl: Dictionary = clauses[ci]
		var k1 := k0
		while k1 < events.size() and int(events[k1].word_index) <= int(cl.last):
			k1 += 1
		if k1 > k0:
			spans.append({end = String(cl.end), excited = bool(cl.get("excited", false)), a = k0, b = k1 - 1})
		k0 = k1
	var accent_sum := PackedFloat32Array()
	accent_sum.resize(n)
	accent_sum.fill(0.0)
	# Markup contours: ^ rises across its word, _ falls, then each lets go.
	var contour := PackedFloat32Array()
	contour.resize(n)
	contour.fill(0.0)
	var k := 0
	while k < events.size():
		var c := String(events[k].get("contour", ""))
		var k2 := k
		while k2 + 1 < events.size() and int(events[k2 + 1].word_index) == int(events[k].word_index):
			k2 += 1
		if c != "":
			var sign := 1.0 if c == "rise" else -1.0
			var ws := float(events[k].t_start)
			var we := float(events[k2].t_end)
			for i in range(maxi(0, floori(ws * CURVE_RATE)), mini(n, ceili((we + CONTOUR_RELEASE_S) * CURVE_RATE) + 1)):
				var t := float(i) / CURVE_RATE
				var v := _smooth((t - ws) / maxf(1e-4, we - ws)) if t <= we else 1.0 - _smooth((t - we) / CONTOUR_RELEASE_S)
				contour[i] += sign * MARK_CONTOUR * v
		k = k2 + 1
	for e in events:
		var a := float(e.accent)
		if a <= 0.0:
			continue
		var ti := _accent_time(e)
		var half := 0.5 * clampf(1.2 * (float(e.t_end) - float(e.t_start)), 0.08, 0.15)
		for i in range(maxi(0, floori((ti - half) * CURVE_RATE)), mini(n, ceili((ti + half) * CURVE_RATE) + 1)):
			accent_sum[i] += a * _bump((float(i) / CURVE_RATE - ti) / half)
	# Phrase, held between clauses.
	var phrase := PackedFloat32Array()
	phrase.resize(n)
	var held := 0.0
	var si := 0
	for i in n:
		var t := float(i) / CURVE_RATE
		while si < spans.size() and t > float(events[spans[si].b].t_end) + 1e-6:
			held = _phrase(spans[si], events, float(events[spans[si].b].t_end))
			si += 1
		if si < spans.size() and t >= float(events[spans[si].a].t_start):
			phrase[i] = _phrase(spans[si], events, t)
		else:
			phrase[i] = held
	# Per-syllable values, held to the next syllable.
	var ev := 0
	var formant_y := _vowel_target(events[0].vowel) if not events.is_empty() else 0.5
	var alpha := 1.0 - exp(-1.0 / (0.03 * CURVE_RATE))
	for i in n:
		var t := float(i) / CURVE_RATE
		while ev + 1 < events.size() and t >= float(events[ev + 1].t_start):
			ev += 1
		var e: Dictionary = events[ev] if not events.is_empty() else {}
		var inside := not e.is_empty() and t >= float(e.t_start) and t <= float(e.t_end)
		var since := t - float(e.get("t_start", 0.0))
		var left := float(e.get("t_end", 0.0)) - t
		var span: Dictionary = _span_of(spans, ev)
		var u := _clause_u(span, events, t)
		var mark := String(span.get("end", "."))
		# Pitch.
		pitch[i] = r * float(e.get("s_range", 1.0)) * (phrase[i] + accent_sum[i] + float(e.get("raise", 0.0)) + contour[i]) \
			+ float(e.get("s_pitch", 0.0)) + float(e.get("melody", 0.0))
		# Intensity.
		var lvl := 0.55
		if mark == "!":
			lvl = 0.7
		elif mark == "…":
			lvl = lerpf(0.5, 0.35, u)
		if inside and e.function:
			lvl *= FUNCTION_LEVEL
		intensity[i] = clampf((lvl + 0.35 * accent_sum[i]) * float(e.get("s_intensity", 1.0)), 0.0, 1.0)
		# Brightness.
		var b := 0.3 + 0.3 * accent_sum[i] + 0.25 * _vowel_target(int(e.get("vowel", 2)))
		if mark == "!":
			b += 0.15
		b += float(e.get("s_bright", 0.0)) + 0.1 * int(e.get("emphasis", 0))
		if inside and int(e.onset_class) == AKSpeechText.FRICATIVE and since < 0.04:
			b += 0.25 * (1.0 - since / 0.04)
		bright[i] = clampf(b, 0.0, 1.0)
		# Noise: fricatives hiss, plosives burst.
		var nz := 0.0
		if inside:
			match int(e.onset_class):
				AKSpeechText.FRICATIVE:
					if since < 0.06:
						nz = 1.0 - since / 0.06
				AKSpeechText.PLOSIVE:
					if since < 0.015:
						nz = 0.7
			if int(e.coda_class) == AKSpeechText.FRICATIVE and left < 0.05:
				nz = maxf(nz, 0.8 * (1.0 - left / 0.05))
		noise[i] = nz
		# Formant: glides toward the vowel's target.
		formant_y += alpha * (_vowel_target(int(e.get("vowel", 2))) - formant_y)
		formant[i] = formant_y
	return {pitch = pitch, intensity = intensity, brightness = bright, noise = noise, formant = formant}


## The phrase shape (in units of the voice's range) of a clause at `t`.
static func _phrase(span: Dictionary, events: Array[Dictionary], t: float) -> float:
	var u := _clause_u(span, events, t)
	var last: Dictionary = events[span.b]
	var fin := _smooth((t - float(last.t_start)) / maxf(1e-4, float(last.t_end) - float(last.t_start)))
	match String(span.end):
		"?":
			# Flat, a little falling, then a high rise from the last stressed syllable.
			var from := float(last.t_start)
			for k in range(span.b, span.a - 1, -1):
				if float(events[k].accent) > 0.0:
					from = float(events[k].t_start)
					break
			var rise := _smooth((t - from) / maxf(1e-4, float(last.t_end) - from))
			return 0.15 - 0.1 * u + 0.75 * rise + (0.15 if span.excited else 0.0)
		"!":
			return 0.55 - 0.8 * pow(u, 0.7)
		",", ";", ":":
			return 0.3 - 0.2 * u + 0.15 * fin
		"…":
			return 0.2 - 0.45 * u
		_:
			return 0.3 * (1.0 - u) - 0.35 * fin


static func _clause_u(span: Dictionary, events: Array[Dictionary], t: float) -> float:
	if span.is_empty():
		return 0.0
	var c0 := float(events[span.a].t_start)
	var c1 := float(events[span.b].t_end)
	return clampf((t - c0) / maxf(1e-4, c1 - c0), 0.0, 1.0)


static func _span_of(spans: Array, ev: int) -> Dictionary:
	for s in spans:
		if ev >= int(s.a) and ev <= int(s.b):
			return s
	return {}


## Where a syllable's accent peaks (and where its note's pitch is read).
static func _accent_time(e: Dictionary) -> float:
	return float(e.t_start) + 0.35 * (float(e.t_end) - float(e.t_start))


## Length factor from the letters: plosive onsets are short, long vowels and
## consonant codas carry length.
static func _class_length(s: Dictionary) -> float:
	var f := 1.0
	match int(s.onset_class):
		AKSpeechText.PLOSIVE:
			f = 0.9
		AKSpeechText.FRICATIVE:
			f = 1.05
		AKSpeechText.NONE:
			f = 0.95
	if String(s.nucleus).length() >= 2:
		f *= 1.1
	var coda := 0
	for c in String(s.coda):
		if not "aeiou".contains(c):
			coda += 1
	return f * (1.0 + 0.05 * mini(2, coda))


static func _vowel_target(v: int) -> float:
	return float(AKSpeechText.VOWEL_BRIGHTNESS[clampi(v, 0, 4)])


## 0..1 from a seed and a salt.
static func _unit(seed: int, salt: int) -> float:
	return float(AKSpeechText.mix(seed, salt, 11)) / float(0x7FFFFFFF)


## A raised cosine: 1 at 0, 0 at +-1.
static func _bump(x: float) -> float:
	if absf(x) >= 1.0:
		return 0.0
	return 0.5 * (1.0 + cos(PI * x))


static func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


static func _sample(c: PackedFloat32Array, t: float) -> float:
	if c.is_empty():
		return 0.0
	var x := clampf(t * CURVE_RATE, 0.0, float(c.size() - 1))
	var i := int(x)
	if i >= c.size() - 1:
		return c[c.size() - 1]
	return lerpf(c[i], c[i + 1], x - i)
