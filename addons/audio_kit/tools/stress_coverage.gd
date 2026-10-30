# SPDX-License-Identifier: Apache-2.0
# How much of real dialogue each size of stress dictionary covers: every word
# token of the given texts read the way the runtime reads it (dictionary, a
# known stem + neutral suffix, a compound of two known words, then the rules),
# against each dictionary, and its primary stress checked against the largest
# one (every CMU word). Writes docs/stress/coverage.md.
#   godot --headless --path . -s res://addons/audio_kit/tools/stress_coverage.gd -- \
#       <name>=<en_stress.txt> ... --ref <en_stress.txt> [--skip name,name] <dialogue.txt> ...
# --skip leaves out words a project would put in its lexicon (the characters' names).
# The texts can be any plain text; Project Gutenberg header and footer lines
# are skipped.
extends SceneTree

const OUT := "res://docs/stress/coverage.md"
const DEMO_LINES := [
	"Hey! Where did you come from? Get out of here with that stupid stupid haircut!",
	"Oh, hello there. I wasn't expecting anyone... Who are you?",
	"WHAT have you done to my garden?",
	"Zorblax says the rocket is ready.",
	"I live here. I always lived here.",
	"It's a very nice haircut...",
]


func _init() -> void:
	var dicts := {}
	var names := PackedStringArray()
	var ref: AKStressDict
	var texts := {"demo lines": "\n".join(DEMO_LINES)}
	var skip := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--ref":
			ref = AKStressDict.from_text(FileAccess.get_file_as_string(args[i + 1]))
			i += 2
			continue
		if a == "--skip":
			for w in args[i + 1].split(",", false):
				skip[w] = true
			i += 2
			continue
		if a.contains("="):
			var name := a.get_slice("=", 0)
			dicts[name] = AKStressDict.from_text(FileAccess.get_file_as_string(a.get_slice("=", 1)))
			names.append(name)
		else:
			texts[a.get_file().get_basename()] = _strip_gutenberg(FileAccess.get_file_as_string(a))
		i += 1
	if ref == null or names.is_empty():
		print("FAIL  usage: -- <name>=<en_stress.txt> ... --ref <en_stress.txt> <text> ...")
		quit(1)
		return
	var lines := PackedStringArray(["# Stress dictionary: coverage of real dialogue", "",
		"Written by `addons/audio_kit/tools/stress_coverage.gd`. Regenerate rather than edit.", "",
		"Every word token read the way the runtime reads it (no lexicon), against each dictionary. "
		+ "Function words are never stressed and are left out. \"Wrong\" means the primary stress lands on another "
		+ "syllable than the full CMU dictionary's, or the syllable count differs; tokens the full dictionary lacks "
		+ "(names, coinages) aren't scored.", ""])
	if not skip.is_empty():
		var sk := skip.keys()
		sk.sort()
		lines.append_array(["Left out as lexicon words (the characters' names): %s." % ", ".join(sk), ""])
	for t: String in texts:
		var tokens := _content_tokens(String(texts[t]), skip)
		lines.append_array(["## %s (%d content-word tokens, %d distinct)" % [t, tokens.size(), _distinct(tokens)], "",
			"| Dictionary | Words | In the dictionary | Stem + suffix | Compound | Rules, one syllable | Rules, longer | Wrong primary stress |",
			"| --- | --- | --- | --- | --- | --- | --- | --- |"])
		for name in names:
			var d: AKStressDict = dicts[name]
			var c := {dictionary = 0, stem = 0, compound = 0, one = 0, rules = 0, wrong = 0, scored = 0}
			var wrong_words := {}
			for norm: String in tokens:
				var r := AKSpeechText._read_word(norm, null, d)
				var src := String(r.source)
				if src == "dictionary":
					c.dictionary += 1
				elif src.begins_with("dictionary:"):
					c.stem += 1
				elif src.begins_with("compound"):
					c.compound += 1
				elif src == "rule: one syllable":
					c.one += 1
				else:
					c.rules += 1
				var want := ref.lookup(norm)
				if want.is_empty():
					continue
				c.scored += 1
				var got := PackedInt32Array(r.stress)
				if got.size() != want.stress.size() or Array(got).find(1) != Array(want.stress).find(1):
					c.wrong += 1
					wrong_words[norm] = int(wrong_words.get(norm, 0)) + 1
			var n := maxi(1, tokens.size())
			lines.append("| %s | %d | %s | %s | %s | %s | %s | %s |" % [name, d.size(), _pct(c.dictionary, n),
				_pct(c.stem, n), _pct(c.compound, n), _pct(c.one, n), _pct(c.rules, n), _pct(c.wrong, maxi(1, c.scored))])
			if not wrong_words.is_empty():
				var ws := wrong_words.keys()
				ws.sort_custom(func(a: String, b: String) -> bool:
					return wrong_words[a] > wrong_words[b] or (wrong_words[a] == wrong_words[b] and a < b))
				var shown := PackedStringArray()
				for w: String in ws.slice(0, 25):
					shown.append("%s ×%d" % [w, wrong_words[w]] if wrong_words[w] > 1 else w)
				lines.append("")
				lines.append("Wrong with %s (most frequent first): %s" % [name, ", ".join(shown)])
				lines.append("")
		lines.append("")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines).strip_edges() + "\n")
	print("ok    %s" % OUT)
	quit()


static func _content_tokens(text: String, skip: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for w: Dictionary in AKSpeechText.analyse(text, null, false).words:
		if not w.function and not skip.has(w.norm):
			out.append(String(w.norm))
	return out


static func _distinct(tokens: PackedStringArray) -> int:
	var seen := {}
	for t in tokens:
		seen[t] = true
	return seen.size()


static func _pct(k: int, n: int) -> String:
	return "%.1f%%" % (100.0 * k / n)


static func _strip_gutenberg(text: String) -> String:
	var a := text.find("*** START OF")
	var b := text.find("*** END OF")
	if a >= 0:
		a = text.find("\n", a) + 1
	return text.substr(maxi(a, 0), (b if b > a else text.length()) - maxi(a, 0))
