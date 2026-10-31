# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's Pseudo-Speech page: type a line, pick a voice, hear it.
##
##   Text       the line; it replays a moment after each edit
##   Voice      the kit's voices and the project's (res://audio/speech/voices/)
##   Play/Stop  bakes the line and plays it; the subtitle below lights each
##              word as it's spoken
##   Sound      what the voice is made of: a synth patch (the speech ones
##              first, then the kit's, the GM bank's and yours) or scratched
##              vowel records. A patch that isn't mono is played as a mono copy
##              with a wide bend range, as speech needs. "Edit sound" opens it
##              on the Synth page
##   Consonants the voice's onset level (its onset_gain_db)
##   Effects    a character for the whole line (demon, angel, alien, beast,
##              sprite, ghost, robot, radio: AKSpeechFx.PRESETS); Amount
##              scales it, Size makes the body bigger or smaller at the same
##              pitch. Inspect edits the effects one by one
##   Save       edits are made on a copy of the voice; Save writes it to
##              res://audio/speech/voices/<name>.tres (a kit voice is never
##              overwritten: saving one makes a new voice, with its own salt)
##   Inspect    the voice in the Inspector; changes there replay
##   Live       plays the line on the live synth instead (it starts at once;
##              needs the native core and a patch voice), then bakes it for
##              the waveform and curves
##   Replay     replays a moment after each edit, unless the voice took longer
##              than SLOW_MS to bake (no native core): then press Play
##   Curves     the line on the waveform's time axis: words, syllables,
##              accents and the curves the voice hears (pick which); click a
##              word to hear it alone, in its place in the line
##   Analysis   how the text was read: syllables split with "·", stressed
##              syllables in capitals, clauses with their end marks, markup
##              as written, (?) on words the rules guessed
@tool
class_name AKSpeechLab
extends VBoxContainer

## "Edit sound": the plugin opens this patch on the Synth page.
signal open_patch(patch: AKPatch)

const DEFAULT_TEXT := "Hey! Where did you come from? Get out of here with that stupid stupid haircut!"
const AUTO_DELAY_S := 0.4
## A voice whose last bake took longer than this doesn't replay on every edit.
const SLOW_MS := 1500.0
## Where synth patches for the Sound menu come from: [folder, label].
const SOUND_DIRS := [["res://addons/audio_kit/patches/", "kit"], ["res://addons/audio_kit/bank/patches/", "bank"],
	["res://audio/patches/", "yours"]]
## The Sound menu's entry for scratched vowel records.
const SCRATCH := "scratch"
## Speech needs pitch bend this wide (in semitones) for its melody.
const SPEECH_BEND := 12.0
const CONSONANT_TIP := "How loud the voice's consonants are (its onset_gain_db): the clicks of p, t, k and the hiss of s, f, h. Save keeps it."

## The line being worked on (its voice is the picked one).
var line: AKSpeechLine
## The last render: {length_s, peak_db, ms, syllables, words}.
var last_stats := {}
var player: AudioStreamPlayer
## Speaks the line when Live is on.
var speaker: AKSpeaker
## Where the voice being edited came from ("" for none), and whether that is
## the kit's ("kit") or the project's ("yours"). line.voice is a copy of it.
var voice_path := ""
var voice_source := ""
## Where your voices are listed from and saved to (tests point it elsewhere).
var user_voice_dir := AKSpeech.USER_VOICE_DIR

var _voices: Array[Dictionary] = []
var _text: TextEdit
var _voice: OptionButton
var _auto: CheckBox
var _live: CheckBox
var _consonants: AKParamSlider
var _fx: OptionButton
var _fx_amount: AKParamSlider
var _size: AKParamSlider
var _sound: OptionButton
## The Sound menu's entries: [{label, path}] (path SCRATCH for the records, "" for the voice's own patch).
var _sounds: Array[Dictionary] = []
var _name: LineEdit
var _save: Button
var _inspect: Button
## describe() of the voice as loaded or last saved, and as last seen (to catch Inspector edits).
## The Sound menu's choices before the voice's own patch is added (sound_choices()).
var _sound_list: Array[Dictionary] = []
var _edit_sound: Button
var _saved_sig := 0
var _seen_sig := 0
var _sig_wait := 0.0
## Voice path -> how long its last bake took (ms).
var _bake_ms := {}
var _stats: Label
var _subtitle: RichTextLabel
var _wave: Control
var _curves: AKSpeechCurves
var _last_buf: AKBuffer
## Where the playing stream starts in the line (a word's audition starts mid-line).
var _play_from := 0.0
var _analysis: Label
var _status: Label
var _replay_at := -1.0
var _rendered_key := ""
var _shown_word := -2
var _quiet := false


func _init() -> void:
	name = "Pseudo-Speech"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	player = AudioStreamPlayer.new()
	add_child(player)
	speaker = AKSpeaker.new()
	speaker.mode = "live"
	add_child(speaker)
	line = AKSpeechLine.make(DEFAULT_TEXT, null)
	_build()
	refresh_voices()
	_show_analysis()


func _process(delta: float) -> void:
	_sig_wait -= delta
	if _sig_wait <= 0.0:
		_sig_wait = 0.3
		_watch_voice()
	if _replay_at >= 0.0:
		_replay_at -= delta
		if _replay_at < 0.0:
			play()
	var w := -1
	if speaker.is_speaking():
		var t := speaker.position()
		if t >= 0.0:
			w = line.word_at(t)
			if _curves:
				_curves.set_playhead(t)
	elif player.playing:
		var t := _play_from + player.get_playback_position()
		w = line.word_at(t)
		if _curves:
			_curves.set_playhead(t)
	elif _curves and _curves.playhead >= 0.0:
		_curves.set_playhead(-1.0)
	if w != _shown_word:
		_shown_word = w
		_draw_subtitle(w)


# ------------------------------------------------------------------ actions

## Say `text` (replaces the text box) and play it unless `audible` is false.
func set_text(text: String, audible := true) -> void:
	_quiet = true
	_text.text = text
	_quiet = false
	line.source_text = text
	_show_analysis()
	if audible:
		play()


## Pick a voice by path (or resource); returns false if it isn't listed or loadable.
func select_voice(v: Variant) -> bool:
	var path: String = (v as AKSpeechVoice).resource_path if v is AKSpeechVoice else String(v)
	for i in _voices.size():
		if _voices[i].path == path:
			_voice.select(i)
			_use_voice(i)
			return true
	var res := AKSpeech.resolve_voice(v)
	if res == null:
		return false
	_edit_copy(res, res.resource_path, "")
	return true


## Read the voice folders again (after saving one, say).
## The voice being edited is kept (unsaved changes and all) when it's still listed.
func refresh_voices() -> void:
	_voices = AKSpeech.voices(user_voice_dir)
	_voice.clear()
	var pick := -1
	for i in _voices.size():
		var e := _voices[i]
		_voice.add_item("%s%s" % [e.name, "  (yours)" if e.source == "yours" else ""])
		if e.path == voice_path:
			pick = i
	if pick >= 0:
		_voice.select(pick)
	elif not _voices.is_empty():
		_voice.select(0)
		_use_voice(0)
	_refresh_sounds()


## Compile and bake the line: the buffer, or an empty one.
func render() -> AKBuffer:
	_replay_at = -1.0
	var t := Time.get_ticks_usec()
	var buf := AKSpeech.render(line)
	_rendered_key = line.key()
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	if line.voice:
		_bake_ms[voice_path] = ms
	var peak := buf.peak()
	last_stats = {length_s = buf.seconds(), peak_db = linear_to_db(peak) if peak > 0.0 else -INF, ms = ms,
		syllables = line.events.size(), words = line.words.size()}
	if _stats:
		_stats.text = "%d words, %d syllables   %.2f s   peak %.1f dBFS   rendered in %.0f ms" % [last_stats.words,
			last_stats.syllables, last_stats.length_s, last_stats.peak_db, ms]
	if _wave:
		_wave.call(&"set_buffer", buf)
	_last_buf = buf
	if _curves:
		_curves.set_line(line, buf.seconds())
	_show_analysis()
	return buf


## Play word `index` alone, cut from the line as rendered (so it keeps its
## place in the melody), with a little of the tail; returns the cut.
func audition_word(index: int) -> AKBuffer:
	speaker.stop()
	if _last_buf == null or _last_buf.frames() == 0 or line.key() != _rendered_key:
		render()
	var a := -1.0
	var b := -1.0
	for e in line.events:
		if int(e.word_index) == index:
			if a < 0.0:
				a = float(e.t_start)
			b = float(e.t_end)
	if a < 0.0 or _last_buf.frames() == 0:
		return AKBuffer.new(0, _last_buf.sample_rate if _last_buf else AK.sample_rate)
	var sr := _last_buf.sample_rate
	var i0 := clampi(roundi(a * sr), 0, _last_buf.frames())
	var i1 := clampi(roundi((b + 0.08) * sr), i0, _last_buf.frames())
	var cut := AKBuffer.new(i1 - i0, sr)
	for i in i1 - i0:
		cut.l[i] = _last_buf.l[i0 + i]
		cut.r[i] = _last_buf.r[i0 + i]
	# A short fade at the cut so it doesn't click.
	var fade := mini(cut.frames(), roundi(0.004 * sr))
	for i in fade:
		var g := float(i) / fade
		cut.l[cut.frames() - 1 - i] *= g
		cut.r[cut.frames() - 1 - i] *= g
	_play_from = a
	player.stream = cut.to_stream()
	if player.is_inside_tree():
		player.play()
	_say("“%s”" % String(line.words[index].text))
	return cut


## True when the picked voice can play live (the native core and a patch).
func live_available() -> bool:
	return AKSynth.available() and line.voice != null and line.voice.source == "patch" and line.voice.patch != null


## True when the picked voice's last bake took longer than SLOW_MS.
func is_slow() -> bool:
	return line.voice != null and float(_bake_ms.get(voice_path, 0.0)) > SLOW_MS


## Play the line: live when Live is on and the voice can, baked otherwise
## (a line already baked plays again without baking).
func play() -> void:
	_replay_at = -1.0
	speaker.stop()
	if _live and _live.button_pressed and live_available():
		_play_live()
		return
	var buf := _last_buf if _last_buf and _last_buf.frames() > 0 and line.key() == _rendered_key else render()
	if buf.frames() == 0:
		_say("Nothing to say: type a line and pick a voice." if line.voice else "Pick a voice.")
		player.stop()
		return
	_say("Live needs the native core and a patch voice: this one plays baked." if _live and _live.button_pressed else "")
	_play_from = 0.0
	player.stream = buf.to_stream()
	if player.is_inside_tree():
		player.play()


func stop() -> void:
	_replay_at = -1.0
	player.stop()
	speaker.stop()


func _play_live() -> void:
	line.compile()
	if line.events.is_empty():
		_say("Nothing to say: type a line.")
		return
	player.stop()
	speaker.voice = line.voice
	speaker.say(line.source_text)
	_say("")
	# The notes are all scheduled, so baking now doesn't hold the sound up.
	if line.key() != _rendered_key:
		render()


# ------------------------------------------------------------------ voices

## What a voice can be made of, for the Sound menu: [{label, path}], the
## speech patches first, then the kit's, the bank's and yours, then the
## scratched records (path SCRATCH).
static func sound_choices() -> Array[Dictionary]:
	var speech: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for src: Array in SOUND_DIRS:
		var dir := String(src[0])
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			var fname := f.trim_suffix(".remap")
			if not fname.ends_with(".tres"):
				continue
			var e := {label = "%s · %s" % [fname.get_basename(), src[1]], path = dir + fname}
			if fname.begins_with("speech_"):
				speech.append(e)
			else:
				rest.append(e)
	speech.append_array(rest)
	speech.append({label = "scratch · vowel records", path = SCRATCH})
	return speech


## A patch as speech plays it: mono (each syllable restarts the envelopes)
## with a wide bend range for the melody. A copy when that changes anything.
static func speech_ready(p: AKPatch) -> AKPatch:
	if p.mode != "poly" and p.bend_range >= SPEECH_BEND:
		return p
	var c: AKPatch = p.duplicate(true)
	c.resource_name = p.resource_path.get_file().get_basename() if p.resource_path != "" else p.resource_name
	if c.mode == "poly":
		c.mode = "mono"
	c.bend_range = maxf(c.bend_range, SPEECH_BEND)
	return c


## Make the voice of a patch (a path from sound_choices) or of the scratched
## vowel records (SCRATCH); the change replays like any edit.
func set_sound(path: String) -> void:
	var v := line.voice
	if v == null:
		return
	if path == SCRATCH:
		v.source = "scratch"
		if v.scratch_samples.is_empty():
			var king := AKSpeech.resolve_voice(AKSpeech.KIT_VOICE_DIR + "scratch_king.tres")
			if king:
				v.scratch_samples = king.scratch_samples.duplicate()
		_say("Sound: scratched vowel records (the voice's Scratch settings shape the hand).")
	else:
		var p: AKPatch = load(path) as AKPatch if ResourceLoader.exists(path) else null
		if p == null:
			_say("Not a patch: %s" % path)
			return
		var sp := speech_ready(p)
		v.patch = sp
		v.source = "patch"
		_say("Sound: %s%s." % [path.get_file().get_basename(),
			" (played mono with a 12-semitone bend, as speech needs; the copy is kept inside the voice)" if sp != p else ""])
	_show_sound()
	_voice_edited()


## Open the voice's patch on the Synth page. A file outside your patches is
## first copied into the voice, so what you change there is what it speaks with.
func edit_sound() -> void:
	var v := line.voice
	if v == null or v.source != "patch" or v.patch == null:
		_say("This voice has no patch to edit (scratch voices play records).")
		return
	if v.patch.resource_path != "" and not v.patch.resource_path.begins_with(String(SOUND_DIRS[2][0])):
		var c: AKPatch = v.patch.duplicate(true)
		c.resource_name = v.patch.resource_path.get_file().get_basename()
		v.patch = c
		_show_sound()
		_voice_edited()
	open_patch.emit(v.patch)
	_say("Editing %s on the Synth page: come back here to hear the voice; Save keeps it." % v.patch.resource_name)


## Save the voice to res://audio/speech/voices/<name>.tres (the name box's
## by default): over its own file when it's yours, else as a new voice with
## its own salt. Returns the path, or "" (the status says why).
func save_voice(voice_name := "") -> String:
	var v := line.voice
	if v == null:
		return ""
	var base := (voice_name if voice_name != "" else (_name.text if _name else "")).strip_edges().to_lower() \
		.replace(" ", "_").validate_filename()
	if base == "":
		_say("Name the voice first.")
		return ""
	var path := user_voice_dir + base + ".tres"
	var own := voice_source == "yours" and path == voice_path
	if not own and FileAccess.file_exists(path):
		_say("There's already a voice called %s: pick it in Voice to save over it, or choose another name." % base)
		return ""
	if not own:
		v.salt = base
	v.resource_name = base
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_voice_dir))
	var err := ResourceSaver.save(v, path)
	if err != OK:
		_say("Couldn't save %s (error %d)." % [path, err])
		return ""
	# Whatever already holds the saved voice (a speaker in an open scene) takes the new settings.
	if ResourceLoader.has_cached(path):
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	voice_path = path
	voice_source = "yours"
	_saved_sig = _sig()
	_seen_sig = _saved_sig
	var ei: Object = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() else null
	if ei:
		ei.call(&"get_resource_filesystem").call(&"update_file", path)
	refresh_voices()
	_show_save()
	_say("Saved %s.%s" % [path, "" if own else " A new character: its own salt, so its words get their own melodies."])
	return path


## Show the voice being edited in the Inspector (in the editor); edits there replay.
func inspect_voice() -> void:
	var ei: Object = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() else null
	if ei == null or line.voice == null:
		_say("The Inspector is the editor's: open the voice's .tres there.")
		return
	ei.call(&"inspect_object", line.voice)


## True when the voice has changes Save hasn't written.
func is_dirty() -> bool:
	return line.voice != null and _sig() != _saved_sig


# ------------------------------------------------------------------ inside

func _sig() -> int:
	return hash(line.voice.describe()) if line.voice else 0


## Something changed the voice (a control here): show it and replay.
func _voice_edited() -> void:
	_seen_sig = _sig()
	_show_save()
	_schedule_replay()


## Catch changes made elsewhere (the Inspector, the Synth page) and replay.
func _watch_voice() -> void:
	if line.voice == null:
		return
	var sg := _sig()
	if sg == _seen_sig:
		return
	_seen_sig = sg
	_show_sound()
	_show_consonants()
	_show_effects()
	_show_save()
	_schedule_replay()


func _refresh_sounds() -> void:
	_sound_list = sound_choices()
	_show_sound()


## The Sound menu, on the voice's sound (its own copied patch listed first when it has one).
func _show_sound() -> void:
	if _sound == null:
		return
	var v := line.voice
	var cur := ""
	if v and v.source == "scratch":
		cur = SCRATCH
	elif v and v.patch:
		cur = v.patch.resource_path
	var list: Array[Dictionary] = []
	var pick := -1
	if v and v.source == "patch" and v.patch and cur == "":
		list.append({label = "%s · this voice's copy" % (v.patch.resource_name if v.patch.resource_name != "" else "patch"), path = ""})
		pick = 0
	list.append_array(_sound_list)
	for i in list.size():
		if cur != "" and list[i].path == cur:
			pick = i
	_sounds = list
	_sound.clear()
	for e in list:
		_sound.add_item(String(e.label))
	if pick >= 0:
		_sound.select(pick)
	if _edit_sound:
		_edit_sound.disabled = v == null or v.source != "patch" or v.patch == null


func _show_save() -> void:
	if _save == null:
		return
	var base := _name.text.strip_edges().to_lower().replace(" ", "_").validate_filename() if _name else ""
	var own := voice_source == "yours" and user_voice_dir + base + ".tres" == voice_path
	_save.text = ("Save" if own else "Save as new") + (" •" if is_dirty() else "")
	_save.tooltip_text = ("Write the changes to %s." % voice_path) if own else \
		"Save as %s%s.tres, a new voice (kit voices are never overwritten)." % [user_voice_dir, base]


func _enter_tree() -> void:
	var ei: Object = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() else null
	if ei:
		var fs: Object = ei.call(&"get_resource_filesystem")
		if not fs.is_connected(&"filesystem_changed", refresh_voices):
			fs.connect(&"filesystem_changed", refresh_voices)


func _exit_tree() -> void:
	var ei: Object = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() else null
	if ei:
		var fs: Object = ei.call(&"get_resource_filesystem")
		if fs.is_connected(&"filesystem_changed", refresh_voices):
			fs.disconnect(&"filesystem_changed", refresh_voices)


func _use_voice(i: int) -> void:
	if i < 0 or i >= _voices.size():
		return
	var res := AKSpeech.resolve_voice(_voices[i].path)
	if res:
		_edit_copy(res, _voices[i].path, _voices[i].source)


## Edit a copy of `v` (the kit's voices and saved ones stay as they are until Save).
func _edit_copy(v: AKSpeechVoice, path: String, source: String) -> void:
	line.voice = v.duplicate(true)
	voice_path = path
	voice_source = source
	_saved_sig = _sig()
	_seen_sig = _saved_sig
	if _name:
		var base := path.get_file().get_basename() if path != "" else "voice"
		_name.text = base if source == "yours" else "my_" + base
	_show_consonants()
	_show_effects()
	_show_sound()
	_show_save()
	_show_analysis()


## The consonant slider follows the picked voice (off for one without onsets).
func _show_consonants() -> void:
	if _consonants == null:
		return
	var v := line.voice
	var has := v != null and (v.plosive != null or v.fricative != null or v.breath != null)
	_consonants.set_value(v.onset_gain_db if v else 0.0)
	_consonants.modulate.a = 1.0 if has else 0.4
	_consonants.tooltip_text = CONSONANT_TIP if has else "This voice has no consonant sounds."


func _set_consonants(db: float) -> void:
	var v := line.voice
	if v == null or (v.plosive == null and v.fricative == null and v.breath == null):
		_show_consonants()
		return
	v.onset_gain_db = db
	_say("Consonants %+.1f dB (Save keeps it)." % db)
	_voice_edited()


## Give the voice a character preset ("" for none): its effects and size.
func set_effects(preset: String) -> void:
	var v := line.voice
	if v == null:
		return
	AKSpeechFx.apply(v, preset)
	_show_effects()
	_say("Effects: %s (Save keeps them)." % (preset.capitalize() if preset != "" else "none"))
	_voice_edited()


func set_effects_amount(amount: float) -> void:
	var v := line.voice
	if v == null:
		return
	v.effects_amount = clampf(amount, 0.0, 1.0)
	_voice_edited()


func set_body_size(semitones: float) -> void:
	var v := line.voice
	if v == null:
		return
	v.size_semitones = clampf(semitones, -12.0, 12.0)
	_show_effects()
	_voice_edited()


## The Effects menu and sliders follow the voice.
func _show_effects() -> void:
	if _fx == null:
		return
	var v := line.voice
	var cur := AKSpeechFx.preset_of(v) if v else ""
	_fx.clear()
	_fx.add_item("None")
	_fx.set_item_metadata(0, "")
	for k in AKSpeechFx.names():
		_fx.add_item(k.capitalize())
		var i := _fx.item_count - 1
		_fx.set_item_metadata(i, k)
		_fx.set_item_tooltip(i, String(AKSpeechFx.PRESETS[k].tip))
	if cur == "custom":
		_fx.add_item("Custom (%d effects)" % v.effects.size())
		_fx.set_item_metadata(_fx.item_count - 1, "custom")
	for i in _fx.item_count:
		if String(_fx.get_item_metadata(i)) == cur:
			_fx.select(i)
	_fx_amount.set_value(v.effects_amount if v else 1.0)
	_size.set_value(v.size_semitones if v else 0.0)


func _on_edited() -> void:
	if _quiet:
		return
	line.source_text = _text.text
	_show_analysis()
	_schedule_replay()


func _schedule_replay() -> void:
	if _auto and _auto.button_pressed:
		if is_slow() and not (_live and _live.button_pressed and live_available()):
			_say("This voice took %.1f s to bake (no native core), so edits don't replay on their own: press Play." % (
				float(_bake_ms[voice_path]) / 1000.0))
		else:
			_replay_at = AUTO_DELAY_S


func _show_analysis() -> void:
	if _analysis == null:
		return
	line.compile()
	_analysis.text = AKSpeech.describe_analysis(line) if not line.words.is_empty() else ""
	_shown_word = -2


func _draw_subtitle(current: int) -> void:
	if _subtitle == null:
		return
	var text := line.display_text
	var out := ""
	var at := 0
	for wi in line.words.size():
		var w: Dictionary = line.words[wi]
		out += _escape(text.substr(at, int(w.start) - at))
		var word := _escape(text.substr(int(w.start), int(w.end) - int(w.start)))
		out += "[color=#ffcf3b]%s[/color]" % word if wi == current else word
		at = int(w.end)
	out += _escape(text.substr(at))
	_subtitle.text = out


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _say(text: String) -> void:
	if _status:
		_status.text = text


func _build() -> void:
	var title := Label.new()
	title.text = "Pseudo-Speech"
	title.add_theme_font_size_override(&"font_size", roundi(15 * AKUiScale.factor()))
	title.modulate = Color(1.0, 0.81, 0.23)
	add_child(title)
	_text = TextEdit.new()
	_text.text = DEFAULT_TEXT
	_text.custom_minimum_size = AKUiScale.px(0, 72)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "Type a line of dialogue."
	_text.text_changed.connect(_on_edited)
	add_child(_text)
	var row := HBoxContainer.new()
	add_child(row)
	var vl := Label.new()
	vl.text = "Voice"
	row.add_child(vl)
	_voice = OptionButton.new()
	_voice.custom_minimum_size = AKUiScale.px(160, 0)
	_voice.tooltip_text = "The kit's voices and yours (res://audio/speech/voices/)."
	_voice.item_selected.connect(func(i: int) -> void:
		_use_voice(i)
		if _auto and _auto.button_pressed and not is_slow():
			play())
	row.add_child(_voice)
	var p := Button.new()
	p.text = "Play"
	p.pressed.connect(play)
	row.add_child(p)
	var s := Button.new()
	s.text = "Stop"
	s.pressed.connect(stop)
	row.add_child(s)
	_auto = CheckBox.new()
	_auto.text = "Replay when edited"
	_auto.button_pressed = true
	_auto.tooltip_text = "Replay a moment after each edit (not for voices that take over %.1f s to bake)." % (SLOW_MS / 1000.0)
	row.add_child(_auto)
	_live = CheckBox.new()
	_live.text = "Live"
	_live.tooltip_text = "Play on the live synth: starts at once. Needs the native core and a patch voice (Scratch King always bakes)."
	_live.disabled = not AKSynth.available()
	row.add_child(_live)
	var row2 := HBoxContainer.new()
	add_child(row2)
	var sl := Label.new()
	sl.text = "Sound"
	row2.add_child(sl)
	_sound = OptionButton.new()
	_sound.custom_minimum_size = AKUiScale.px(220, 0)
	_sound.tooltip_text = "What the voice is made of: a synth patch (speech ones first, then the kit's, the GM bank's, yours) or scratched vowel records."
	_sound.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _sounds.size() and String(_sounds[i].path) != "":
			set_sound(String(_sounds[i].path)))
	row2.add_child(_sound)
	_edit_sound = Button.new()
	_edit_sound.text = "Edit sound"
	_edit_sound.tooltip_text = "Open the voice's patch on the Synth page (a kit patch is copied into the voice first)."
	_edit_sound.pressed.connect(edit_sound)
	row2.add_child(_edit_sound)
	_consonants = AKParamSlider.make("Consonants", -24.0, 12.0, 0.0, {unit = "dB", width = AKUiScale.px(84, 0).x,
		tip = CONSONANT_TIP})
	_consonants.custom_minimum_size.x = AKUiScale.px(260, 0).x
	_consonants.changed.connect(_set_consonants)
	row2.add_child(_consonants)
	var nl := Label.new()
	nl.text = "Name"
	row2.add_child(nl)
	_name = LineEdit.new()
	_name.custom_minimum_size = AKUiScale.px(140, 0)
	_name.tooltip_text = "The voice's file name in res://audio/speech/voices/."
	_name.text_changed.connect(func(_t: String) -> void: _show_save())
	_name.text_submitted.connect(func(_t: String) -> void: save_voice())
	row2.add_child(_name)
	_save = Button.new()
	_save.text = "Save as new"
	_save.pressed.connect(func() -> void: save_voice())
	row2.add_child(_save)
	_inspect = Button.new()
	_inspect.text = "Inspect"
	_inspect.tooltip_text = "Every setting of the voice in the Inspector (pitch, tempo, melody, consonant sounds ...); changes replay."
	_inspect.disabled = not Engine.is_editor_hint()
	_inspect.pressed.connect(inspect_voice)
	row2.add_child(_inspect)
	var row3 := HBoxContainer.new()
	add_child(row3)
	var fl := Label.new()
	fl.text = "Effects"
	row3.add_child(fl)
	_fx = OptionButton.new()
	_fx.custom_minimum_size = AKUiScale.px(150, 0)
	_fx.tooltip_text = "A character for the whole line, consonants included. Inspect edits the effects one by one."
	_fx.item_selected.connect(func(i: int) -> void:
		var k := String(_fx.get_item_metadata(i))
		if k != "custom":
			set_effects(k))
	row3.add_child(_fx)
	_fx_amount = AKParamSlider.make("Amount", 0.0, 1.0, 1.0, {width = AKUiScale.px(60, 0).x,
		tip = "How much of the effects: scales each one's mix. 0 = dry."})
	_fx_amount.custom_minimum_size.x = AKUiScale.px(220, 0).x
	_fx_amount.changed.connect(set_effects_amount)
	row3.add_child(_fx_amount)
	_size = AKParamSlider.make("Size", -12.0, 12.0, 0.0, {unit = "st", width = AKUiScale.px(44, 0).x,
		tip = "Body size at the same pitch: up is bigger (lower formants), down is smaller."})
	_size.custom_minimum_size.x = AKUiScale.px(220, 0).x
	_size.changed.connect(set_body_size)
	row3.add_child(_size)
	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.75)
	add_child(_stats)
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.add_theme_font_size_override(&"normal_font_size", roundi(20 * AKUiScale.factor()))
	_subtitle.tooltip_text = "The subtitle: each word lights as it's spoken."
	add_child(_subtitle)
	_wave = AKAuditionDock._Wave.new()
	_wave.custom_minimum_size = AKUiScale.px(0, 110)
	add_child(_wave)
	_curves = AKSpeechCurves.new()
	_curves.word_clicked.connect(func(i: int) -> void: audition_word(i))
	add_child(_curves)
	var crow := HBoxContainer.new()
	add_child(crow)
	var cl := Label.new()
	cl.text = "Curves"
	cl.modulate = Color(1, 1, 1, 0.6)
	crow.add_child(cl)
	for c in AKSpeechCurves.CURVES:
		var cb := CheckBox.new()
		cb.text = c
		cb.button_pressed = bool(_curves.shown.get(c, false))
		cb.add_theme_color_override(&"font_color", AKSpeechCurves.COLORS[c])
		cb.toggled.connect(func(on: bool) -> void: _curves.set_shown(c, on))
		crow.add_child(cb)
	var al := Label.new()
	al.text = "Analysis"
	al.modulate = Color(1, 1, 1, 0.6)
	add_child(al)
	_analysis = Label.new()
	_analysis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_analysis.tooltip_text = "Syllables split with ·, stressed ones in capitals (function words are never stressed)."
	add_child(_analysis)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.6)
	add_child(_status)
