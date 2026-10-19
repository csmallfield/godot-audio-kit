# SPDX-License-Identifier: Apache-2.0
@tool
## Pitch and step-string helpers for the sequencer.
##
## Step strings, one character per step:
##   X accent (1.0)   x normal (0.75)   o soft (0.5)   1-9 velocity n/9
##   ? normal, plays half the time (seeded)   . rest   - or ~ tie (holds the
##   previous note one more step)   spaces and | are ignored (use them to group)
## Note names: C4 = 261.63 Hz, A4 = 440 Hz, sharps as C#4, flats as Db4.
class_name AKNotes
extends RefCounted

const NAMES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
const SCALES := {
	major = [0, 2, 4, 5, 7, 9, 11],
	minor = [0, 2, 3, 5, 7, 8, 10],
	dorian = [0, 2, 3, 5, 7, 9, 10],
	mixolydian = [0, 2, 4, 5, 7, 9, 10],
	phrygian = [0, 1, 3, 5, 7, 8, 10],
	major_pentatonic = [0, 2, 4, 7, 9],
	minor_pentatonic = [0, 3, 5, 7, 10],
	blues = [0, 3, 5, 6, 7, 10],
	chromatic = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
}


static func midi_to_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## "C4" -> 60, "F#2" -> 42, "Bb3" -> 58; an int or a numeric string passes through.
static func name_to_midi(n: Variant) -> int:
	if n is int or n is float:
		return int(n)
	var s := String(n).strip_edges()
	if s.is_valid_int():
		return s.to_int()
	var letter := s.substr(0, 1).to_upper()
	if not NAMES.has(letter):
		push_error("AKNotes: bad note '%s'" % s)
		return 60
	var semi: int = NAMES[letter]
	var i := 1
	while i < s.length() and (s[i] == "#" or s[i] == "b"):
		semi += 1 if s[i] == "#" else -1
		i += 1
	var octave := s.substr(i).to_int() if i < s.length() else 4
	return (octave + 1) * 12 + semi


static func note_hz(n: Variant) -> float:
	return midi_to_hz(name_to_midi(n))


## Scale degree (1-based; 8 is the octave above 1; 0 and negatives go down)
## to a MIDI note.
static func degree_to_midi(degree: int, scale: StringName, root: Variant) -> int:
	var steps: Array = SCALES.get(String(scale), SCALES.major)
	var d := degree - 1
	var octave := floori(float(d) / steps.size())
	var idx := d - octave * steps.size()
	return name_to_midi(root) + octave * 12 + int(steps[idx])


## Parse a step string into [{vel, chance, tie}] per step.
static func parse_steps(s: String) -> Array:
	var out := []
	for ch in s:
		match ch:
			" ", "|", "\t", "\n":
				continue
			"X": out.append({vel = 1.0, chance = 1.0, tie = false})
			"x": out.append({vel = 0.75, chance = 1.0, tie = false})
			"o": out.append({vel = 0.5, chance = 1.0, tie = false})
			"?": out.append({vel = 0.75, chance = 0.5, tie = false})
			".": out.append({vel = 0.0, chance = 0.0, tie = false})
			"-", "~": out.append({vel = 0.0, chance = 0.0, tie = true})
			_:
				if ch.is_valid_int() and ch != "0":
					out.append({vel = ch.to_int() / 9.0, chance = 1.0, tie = false})
				else:
					out.append({vel = 0.0, chance = 0.0, tie = false})
	return out
