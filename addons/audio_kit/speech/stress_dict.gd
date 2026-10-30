# SPDX-License-Identifier: Apache-2.0
@tool
## The English stress dictionary pseudo-speech reads words from: for each
## word, its letters split into syllables and each syllable's stress (1
## primary, 2 secondary, 0 none). Built offline by tools/build_stress_dict.py
## into speech/data/en_stress.txt (readable, one word a line:
## `haircut hair|cut 12`), then packed into en_stress.res by
## addons/audio_kit/tools/make_stress_dict.gd.
##
## The packed form keeps the sorted text gzipped plus each line's offset, and
## looks words up by binary search, so the ~41,000 words cost about 1.3 MB in
## memory once loaded instead of a large Dictionary. Loaded on first use.
##
##   AKStressDict.shared().lookup("haircut")   # {groups = ["hair", "cut"], stress = [1, 2]}
@icon("res://addons/audio_kit/icons/recipe.svg")
class_name AKStressDict
extends Resource

const TEXT_PATH := "res://addons/audio_kit/speech/data/en_stress.txt"
const RES_PATH := "res://addons/audio_kit/speech/data/en_stress.res"

## The dictionary's lines (comments dropped), sorted, gzipped.
@export_storage var data := PackedByteArray()
## Unpacked size of `data`.
@export_storage var raw_size := 0
## Where each line starts in the unpacked text.
@export_storage var offsets := PackedInt32Array()
## MD5 of the text it was packed from (the bake key uses it).
@export_storage var source_md5 := ""

static var _shared: AKStressDict
static var _shared_tried := false
var _text := PackedByteArray()


## The kit's dictionary (null, with a warning, if en_stress.res is missing).
static func shared() -> AKStressDict:
	if not _shared_tried:
		_shared_tried = true
		if ResourceLoader.exists(RES_PATH):
			_shared = load(RES_PATH)
		else:
			push_warning("AKStressDict: %s is missing; stress comes from the rules only (run tools/make_stress_dict.gd)" % RES_PATH)
	return _shared


## Pack dictionary text (the en_stress.txt format).
static func from_text(text: String) -> AKStressDict:
	var lines := PackedStringArray()
	for line in text.split("\n", false):
		var l := line.strip_edges()
		if l != "" and not l.begins_with("#"):
			lines.append(l)
	lines.sort()
	var d := AKStressDict.new()
	var joined := "\n".join(lines) + "\n"
	var raw := joined.to_utf8_buffer()
	d.raw_size = raw.size()
	d.data = raw.compress(FileAccess.COMPRESSION_GZIP)
	var at := 0
	for l in lines:
		d.offsets.append(at)
		at += l.to_utf8_buffer().size() + 1
	d.source_md5 = text.md5_text()
	return d


## How many words it holds.
func size() -> int:
	return offsets.size()


## {groups: PackedStringArray, stress: PackedInt32Array} for a lowercase
## word, or an empty Dictionary when it isn't there.
func lookup(word: String) -> Dictionary:
	if offsets.is_empty() or word == "":
		return {}
	if _text.is_empty():
		_text = data.decompress(raw_size, FileAccess.COMPRESSION_GZIP)
	var lo := 0
	var hi := offsets.size() - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var key := _word_at(mid)
		if key == word:
			return _entry(mid)
		if key < word:
			lo = mid + 1
		else:
			hi = mid - 1
	return {}


## The i-th entry in sorted order: {word, groups, stress}.
func entry_at(i: int) -> Dictionary:
	if _text.is_empty():
		_text = data.decompress(raw_size, FileAccess.COMPRESSION_GZIP)
	return _entry(i)


func _word_at(i: int) -> String:
	var a := offsets[i]
	var b := a
	while b < _text.size() and _text[b] != 32 and _text[b] != 10:
		b += 1
	return _text.slice(a, b).get_string_from_utf8()


func _entry(i: int) -> Dictionary:
	var a := offsets[i]
	var b := offsets[i + 1] - 1 if i + 1 < offsets.size() else _text.size() - 1
	return parse_line(_text.slice(a, b).get_string_from_utf8())


## A dictionary or lexicon line: "word groups digits" (haircut hair|cut 12),
## or "word digits" with the runtime's own split. {} when it doesn't parse or
## the split doesn't match the digits.
static func parse_line(line: String) -> Dictionary:
	var parts := line.strip_edges().split(" ", false)
	if parts.size() < 2:
		return {}
	var word := AKSpeechText.fold(parts[0])
	var digits := parts[parts.size() - 1]
	var groups := PackedStringArray()
	if parts.size() >= 3:
		groups = parts[1].to_lower().split("|", false)
		if "".join(groups) != word:
			return {}
	else:
		for s in AKSpeechText.syllables(word):
			groups.append(s.letters)
	var stress := PackedInt32Array()
	for c in digits:
		if not c in ["0", "1", "2"]:
			return {}
		stress.append(int(c))
	if stress.size() != groups.size():
		return {}
	return {word = word, groups = groups, stress = stress}
