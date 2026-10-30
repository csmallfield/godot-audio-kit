# SPDX-License-Identifier: Apache-2.0
# Measures the stress rules (the fallback for words the dictionary lacks)
# against the dictionary: 2,000 words with two or more syllables, picked by a
# fixed hash, run through the rules alone; writes docs/stress/fallback_report.md
# with the primary-stress accuracy per rule, so the weakest rule is fixed first.
#   godot --headless --path . -s res://addons/audio_kit/tools/stress_report.gd
extends SceneTree

const SAMPLE := 2000
const OUT := "res://docs/stress/fallback_report.md"


func _init() -> void:
	var d := AKStressDict.shared()
	if d == null:
		print("FAIL  no dictionary")
		quit(1)
		return
	var r := measure(d, SAMPLE)
	var lines := PackedStringArray(["# Stress dictionary: how good the fallback rules are", "",
		"Written by `addons/audio_kit/tools/stress_report.gd`. Regenerate rather than edit.", "",
		"%d dictionary words of two or more syllables (picked by a fixed hash) read by the rules alone, against the dictionary (CMUdict)." % r.total, "",
		"| | |", "| --- | --- |",
		"| The rules split the word into as many syllables as the dictionary | %d (%.1f%%) |" % [r.same_count, 100.0 * r.same_count / maxi(1, r.total)],
		"| ... and put the primary stress on the same syllable | %d (%.1f%% of those) |" % [r.right, 100.0 * r.right / maxi(1, r.same_count)], "",
		"## By rule", "", "Words where the syllable counts agree, by the rule that placed the stress, most used first.", "",
		"| Rule | Words | Right | Accuracy |", "| --- | --- | --- | --- |"])
	var rules: Array = r.by_rule.keys()
	rules.sort_custom(func(a: String, b: String) -> bool: return r.by_rule[a][0] > r.by_rule[b][0])
	for k in rules:
		var c: Array = r.by_rule[k]
		lines.append("| %s | %d | %d | %.1f%% |" % [k, c[0], c[1], 100.0 * c[1] / maxi(1, c[0])])
	lines.append_array(["", "## Some misses", "", "word: rules / dictionary (capitals: the primary stress)", ""])
	for m in r.misses.slice(0, 40):
		lines.append("- %s" % m)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	print("ok    %s: %d words, %.1f%% same split, %.1f%% right primary" % [OUT, r.total, 100.0 * r.same_count / maxi(1, r.total),
		100.0 * r.right / maxi(1, r.same_count)])
	quit()


## {total, same_count, right, by_rule: rule -> [words, right], misses}.
static func measure(d: AKStressDict, sample: int) -> Dictionary:
	var out := {total = 0, same_count = 0, right = 0, by_rule = {}, misses = []}
	var n := d.size()
	# Every word gets a hash; the lowest-hashed multi-syllable words are the sample.
	var picks := []
	for i in n:
		picks.append([AKSpeechText.hash32("sample|%d" % i), i])
	picks.sort()
	for p in picks:
		if out.total >= sample:
			break
		var e := d.entry_at(int(p[1]))
		if e.stress.size() < 2 or not Array(e.stress).has(1) or AKSpeechText.FUNCTION_WORDS.has(e.word):
			continue
		out.total += 1
		var rs := AKSpeechText.rule_stress(e.word)
		if rs.stress.size() != e.stress.size():
			continue
		out.same_count += 1
		var rule := String(rs.rule)
		if not out.by_rule.has(rule):
			out.by_rule[rule] = [0, 0]
		out.by_rule[rule][0] += 1
		if Array(rs.stress).find(1) == Array(e.stress).find(1):
			out.right += 1
			out.by_rule[rule][1] += 1
		elif out.misses.size() < 200:
			out.misses.append("%s: %s / %s (%s)" % [e.word, _show(AKSpeechText.syllables(e.word), rs.stress),
				_show_groups(e.groups, e.stress), rule])
	return out


static func _show(syl: Array, st: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for k in syl.size():
		parts.append(String(syl[k].letters).to_upper() if st[k] == 1 else String(syl[k].letters))
	return "·".join(parts)


static func _show_groups(groups: PackedStringArray, st: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for k in groups.size():
		parts.append(groups[k].to_upper() if st[k] == 1 else groups[k])
	return "·".join(parts)
