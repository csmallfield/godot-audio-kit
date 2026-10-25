# SPDX-License-Identifier: Apache-2.0
## The Sound Lab's Loops tab: write a loop on a grid while it plays.
##
##   Left      the project's loops (res://audio/loops/) and the sound
##             library (the kit-made sounds beside the project's own)
##   Toolbar   name, New (synth, sample or percussive), Type, Instrument
##             (patches, samples or kits) and Open, Bars, Division, Swing,
##             Play/Stop, Tempo, Save
##   Grid      AKLoopGrid: notes with length and velocity, selection, undo
##   Tools     octave, transpose, duplicate, double, halve, velocity ramp
##             and randomise, Context (play other loops with this one)
##   Guides    Scale and Root tint the scale's rows (Fold hides the rest);
##             Chord tints a chord's rows and names the intervals (pick a
##             root and type, or type a symbol: Cm9, G7b9, F/A)
##   Import    a lane of a song, pattern or .mid file as a new loop
##   Panels    the sample's settings (root note with Detect, mode, trim,
##             loop points, release) or the kit's pieces (sound, level, pan,
##             tune, choke group, gate)
##
## The loop plays live through AKLive with the native core, and an edit
## reaches the notes not yet sounding, so changes are heard without
## stopping; without the native core Play renders the loop and plays the
## bake. Kits from the kit are edited as copies; Save writes the loop to
## res://audio/loops/<name>.tres (and an edited kit to res://audio/kits/).
@tool
class_name AKLoopLab
extends HSplitContainer

## Open this patch in the Synth tab.
signal open_patch(patch: AKPatch)

const SAVE_DIR := "res://audio/"
const PATCH_DIRS := [["res://addons/audio_kit/patches/", "kit"], ["res://addons/audio_kit/bank/patches/", "bank"]]
const BARS := [1, 2, 4, 8]
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
## Chord roots as lead sheets usually spell them.
const CHORD_ROOTS := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
const CATEGORIES := ["", "beat", "bass", "chords", "lead", "pad", "arp", "perc", "fx", "other"]
const NEW_KINDS := ["synth", "sample", "percussive"]

var loop: AKLoop
var loop_path := ""
var save_dir := SAVE_DIR
var bpm := 120.0
## The chord shown on the grid ("" = none); see set_chord.
var chord_symbol := ""
var grid: AKLoopGrid
var loops: AKLoopBrowser
var sounds: AKSoundBrowser
var live: AKLive
var player: AudioStreamPlayer
var audition_player: AudioStreamPlayer
## Other loops played with this one when `context_on`.
var context: Array[AKLoop] = []
var context_on := false
var last_saved := ""
## The song Play last started (live or baked).
var song: AKSong

var _playing := false
var _baked: AKBuffer
var _status: Label
var _name: LineEdit
var _category: OptionButton
var _new: MenuButton
var _kind: OptionButton
var _instrument: OptionButton
var _inst_paths: Array = []
var _bars: OptionButton
var _division: OptionButton
var _swing: HSlider
var _scale: OptionButton
var _root: OptionButton
var _fold: CheckBox
var _chord_on: CheckBox
var _chord_root: OptionButton
var _chord_quality: OptionButton
var _chord_text: LineEdit
var _chord_notes: Label
var _play: Button
var _tempo: SpinBox
var _context_btn: CheckBox
var _context_info: Label
var _panel_box: VBoxContainer
var _quiet := false
var _shown_inst: Resource
var _imp_path: LineEdit
var _imp_lane: OptionButton
var _imp_section: OptionButton
var _imp_bars: SpinBox
var _shown_kind := ""


func _init() -> void:
	name = "Loops"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	player = AudioStreamPlayer.new()
	add_child(player)
	audition_player = AudioStreamPlayer.new()
	add_child(audition_player)
	if AKLive.available():
		live = AKLive.new()
		live.lookahead_s = 0.25
		player.stream = live.stream
	_build()
	new_loop("percussive")


## Off: nothing is sent to the speakers (tests pull the live stream
## themselves with render_playing).
var audio_output := true


func _ready() -> void:
	_start_output()


## The live stream plays through `player` from the first Play on.
func _start_output() -> void:
	if live and audio_output and is_inside_tree() and not player.playing:
		player.play()


func _process(_delta: float) -> void:
	if live:
		live.update()
	if _playing and loop and is_visible_in_tree():
		grid.playhead = playhead_ticks()


## Save under `dir`: loops/, kits/ and samples (beside their files) there.
func set_save_dir(dir: String) -> void:
	save_dir = dir if dir.ends_with("/") else dir + "/"
	loops.folders = [save_dir + "loops/"]
	loops.refresh()
	sounds.project_dir = save_dir
	sounds.refresh()


## The Sound Lab passes the editor's undo history here.
func set_undo(u: Object) -> void:
	grid.undo = u


# ------------------------------------------------------------------ loops

## Start a new loop of `kind` (synth, sample or percussive) with a default
## instrument: the first preset, the library's epiano, the punch kit.
func new_loop(kind: String) -> AKLoop:
	var l := AKLoop.new()
	l.kind = kind
	l.resource_name = "new_" + ("beat" if kind == "percussive" else kind)
	l.instrument = _default_instrument(kind)
	l.category = "beat" if kind == "percussive" else ""
	loop_path = ""
	_set_loop(l)
	_say("New %s loop: click the grid to add notes, then Save." % kind)
	return l


func open_loop(v: Variant) -> AKLoop:
	var l: AKLoop = v if v is AKLoop else (ResourceLoader.load(String(v), "", ResourceLoader.CACHE_MODE_REUSE) as AKLoop if ResourceLoader.exists(String(v)) else null)
	if l == null:
		_say("Not a loop: %s" % v)
		return null
	loop_path = l.resource_path
	_set_loop(l)
	loops.select_path(loop_path)
	_say("Loop: %s" % (loop_path if loop_path != "" else l.resource_name))
	return l


## Save to save_dir/loops/<name>.tres and go on editing the saved file.
## An edited kit that isn't saved anywhere is kept inside the loop.
func save_loop() -> String:
	if loop == null:
		return ""
	var base := _name.text.strip_edges().validate_filename()
	if base == "":
		base = "loop"
	var path := save_dir + "loops/" + base + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	loop.resource_name = base
	if ResourceSaver.save(loop, path) != OK:
		_say("Couldn't save %s" % path)
		return ""
	if loop.resource_path != path:
		loop.take_over_path(path)
	loop_path = path
	last_saved = path
	AK.refresh_editor_files()
	loops.refresh()
	loops.select_path(path)
	_say("Saved %s" % path)
	return path


## Save the loop's kit as save_dir/kits/<name>.tres (a copy of a shipped kit
## becomes yours) and point the loop at it.
func save_kit(kit_name := "") -> String:
	var kit := loop.instrument as AKKit if loop else null
	if kit == null:
		return ""
	var base := (kit_name if kit_name != "" else String(kit.resource_name)).validate_filename()
	var path := save_dir + "kits/" + (base if base != "" else "kit") + ".tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	kit.resource_name = path.get_file().get_basename()
	if ResourceSaver.save(kit, path) != OK:
		return ""
	kit.take_over_path(path)
	AK.refresh_editor_files()
	_fill_instruments()
	_say("Saved kit %s" % path)
	return path


# ------------------------------------------------------------------ settings (undoable)

func set_kind(kind: String) -> void:
	if loop == null or kind == loop.kind:
		return
	_commit(loop, {kind = kind, instrument = _default_instrument(kind)}, "Loop type")


## Choices for the instrument menu: [{label, path}].
func instrument_choices() -> Array:
	var out := []
	match loop.kind if loop else "synth":
		"synth":
			for src in PATCH_DIRS + [[save_dir + "patches/", "yours"]]:
				for f in _files(src[0]):
					out.append({label = "%s · %s" % [f.get_basename(), src[1]], path = src[0] + f})
		"sample":
			for e in sounds.entries():
				out.append({label = "%s · %s" % [e.name, e.folder], path = e.path})
		"percussive":
			for src in [[AKLibrary.KITS_DIR, "kit"], [save_dir + "kits/", "yours"]]:
				for f in _files(src[0]):
					out.append({label = "%s · %s" % [f.get_basename(), src[1]], path = src[0] + f})
	return out


## Play the loop with this instrument: a patch, sample or kit (or its path;
## for sample loops also a library recipe or a .wav/.ogg, which gets an
## AKSample beside it, kick_01.wav -> kick_01.sample.tres).
func set_instrument(v: Variant) -> void:
	if loop == null:
		return
	var inst: Resource = null
	if v is Resource:
		inst = v
	else:
		var path := String(v)
		if loop.kind == "sample":
			inst = _sample_from(path)
		elif ResourceLoader.exists(path):
			inst = load(path)
	var ok := (loop.kind == "synth" and inst is AKPatch) or (loop.kind == "sample" and inst is AKSample) or (loop.kind == "percussive" and inst is AKKit)
	if not ok:
		_say("Not a %s instrument: %s" % [loop.kind, v])
		return
	_commit(loop, {instrument = inst}, "Instrument")


func set_bars(n: int) -> void:
	_commit(loop, {bars = maxi(1, n)}, "Bars")


func set_division(d: int) -> void:
	_commit(loop, {division = d}, "Division")


func set_swing(s: float) -> void:
	_commit(loop, {swing = clampf(s, 0.5, 0.8)}, "Swing")


func set_scale_key(scale_name: String, root := 0) -> void:
	grid.scale_name = scale_name if AKNotes.SCALES.has(scale_name) else ""
	grid.scale_root = posmod(root, 12)
	if _scale:
		_scale.select(AKNotes.SCALES.keys().find(grid.scale_name) + 1)
		_root.select(grid.scale_root)
	grid._resize()
	grid.queue_redraw()


## Highlight a chord's notes on the grid: a symbol such as "Cm9", "G7b9",
## "F/A" or "D minor 7" (AKChords.parse). False, with the reason shown, if it
## can't be read; the previous chord stays.
func set_chord(symbol: String) -> bool:
	var c := AKChords.parse(symbol)
	if not c.ok:
		if _chord_notes:
			_chord_notes.text = "?  " + String(c.error)
		return false
	chord_symbol = symbol.strip_edges()
	grid.chord = c
	grid.queue_redraw()
	if _chord_on:
		_quiet = true
		_chord_on.button_pressed = true
		_chord_root.select(int(c.root))
		var tail := chord_symbol.substr(_root_length(chord_symbol))
		var qi := -1
		for i in AKChords.COMMON.size():
			if AKChords.COMMON[i][0] == tail:
				qi = i
		if qi >= 0:
			_chord_quality.select(qi)
		_chord_text.text = chord_symbol
		_chord_notes.text = AKChords.note_names(c)
		_quiet = false
	return true


## Stop highlighting a chord.
func clear_chord() -> void:
	chord_symbol = ""
	grid.chord = {}
	grid.queue_redraw()
	if _chord_on:
		_quiet = true
		_chord_on.button_pressed = false
		_chord_notes.text = ""
		_quiet = false


func _chord_menu_symbol() -> String:
	var q: String = AKChords.COMMON[maxi(0, _chord_quality.selected)][0]
	return String(CHORD_ROOTS[maxi(0, _chord_root.selected)]) + q


func _root_length(symbol: String) -> int:
	var n := 1
	while n < symbol.length() and symbol[n] in ["#", "b"]:
		n += 1
	return n


func set_fold(on: bool) -> void:
	grid.fold = on
	grid._resize()
	grid.queue_redraw()


func set_tempo(p_bpm: float) -> void:
	bpm = clampf(p_bpm, 20.0, 400.0)
	if _tempo and not is_equal_approx(_tempo.value, bpm):
		_tempo.set_value_no_signal(bpm)
	if _playing:
		play()


## Shift the selection (or every note) by semitones; not for kits.
func transpose(semitones: int) -> void:
	if loop.kind == "percussive":
		return
	grid.move_notes(grid._targets(), 0, semitones, "Transpose")


## Twice as long, the notes copied into the new half.
func double_loop() -> void:
	var L := loop.length_ticks()
	var ns := grid._notes()
	for n: Array in grid._notes():
		if int(n[0]) < L:
			n[0] = int(n[0]) + L
			ns.append(n)
	_commit(loop, {bars = loop.bars * 2, notes = ns}, "Double")


## Half as long (at least a bar), dropping the notes past the new end.
func halve_loop() -> void:
	var bars := maxi(1, loop.bars / 2)
	var end := bars * loop.beats_per_bar * AKLoop.TICKS_PER_BEAT
	var ns := grid._notes().filter(func(n: Array) -> bool: return int(n[0]) < end)
	_commit(loop, {bars = bars, notes = ns}, "Halve")


## A copy of this loop as a new, unsaved loop.
func duplicate_loop() -> AKLoop:
	var l: AKLoop = loop.duplicate(true)
	l.instrument = loop.instrument
	l.resource_name = loop.resource_name + "_copy"
	loop_path = ""
	_set_loop(l)
	_say("A copy: Save keeps it as %s" % l.resource_name)
	return l


# ------------------------------------------------------------------ from songs, patterns and .mid files

## What a song, pattern or .mid file offers to turn into loops:
## {lanes: [names], sections: [names]} (patterns have one section, "pattern").
func import_source(path: String) -> Dictionary:
	var src: Variant = _import_resource(path)
	if src is AKSong:
		var lanes := []
		for sec in (src as AKSong).sections:
			for pv in sec.get("patterns", []):
				var pat := AKSong._pattern(pv)
				for l in (pat.lanes if pat else []):
					if not lanes.has(String(l.get("name", ""))):
						lanes.append(String(l.get("name", "")))
		return {lanes = lanes, sections = (src as AKSong).sections.map(func(x: Dictionary) -> String: return String(x.get("name", "")))}
	if src is AKPattern:
		return {lanes = (src as AKPattern).lanes.map(func(l: Dictionary) -> String: return String(l.get("name", ""))), sections = ["pattern"]}
	return {}


## Make a new (unsaved) loop from lanes of a song, pattern or .mid file, its
## notes quantised to ticks (or to `quantize` cells a bar): drum lanes
## together become a beat on a kit of their sounds; a pitched lane a synth or
## sample loop. `section` (index) and `bars` from `from_bar` pick the stretch.
func loop_from(path: String, lanes: Array, section := 0, bars := 0, from_bar := 0.0, quantize := 0) -> AKLoop:
	var src: Variant = _import_resource(path)
	var l: AKLoop = null
	if src is AKSong:
		l = AKLoop.from_song(src, lanes, section, from_bar, bars, quantize)
	elif src is AKPattern:
		l = AKLoop.from_pattern(src, lanes, bars, 4, from_bar, quantize)
	if l == null or l.notes.is_empty():
		_say("Nothing to make a loop of in %s %s" % [path.get_file(), lanes])
		return null
	l.resource_name = "%s_%s" % [path.get_file().get_basename(), l.resource_name]
	loop_path = ""
	_set_loop(l)
	_say("A %s loop from %s: %d notes (Save keeps it)" % [l.kind, path.get_file(), l.notes.size()])
	return l


var _imported := {}


func _import_resource(path: String) -> Variant:
	if _imported.has(path):
		return _imported[path]
	var r: Variant = null
	var ext := path.get_extension().to_lower()
	if ext in ["mid", "midi"]:
		r = AKMidi.import_file(path)
	elif ResourceLoader.exists(path):
		r = load(path)
	_imported[path] = r
	return r


# ------------------------------------------------------------------ samples and kits

## Set a setting of the loop's sample (root_note, mode, start_s ...), undoably.
func set_sample_param(key: String, value: Variant) -> void:
	var s := loop.instrument as AKSample
	if s:
		_commit(s, {key: value}, "Sample " + key)


## The root note a sample sounds at, by the harmonic pitch test over MIDI
## 24..108 on its loudest stretch; -1 when it has no clear pitch.
static func detect_root(s: AKSample) -> int:
	var got: Array = s.samples()
	var d: PackedFloat32Array = got[0]
	var rate: int = got[1]
	var n := 4096
	if d.size() < n:
		return -1
	# Start a little after the attack: the loudest 10 ms block, plus 30 ms.
	var best_at := 0
	var best_e := 0.0
	for b in range(0, d.size() - n, maxi(1, rate / 100)):
		var e := 0.0
		for i in range(b, mini(b + rate / 100, d.size())):
			e += d[i] * d[i]
		if e > best_e:
			best_e = e
			best_at = b
	var at := mini(best_at + rate * 3 / 100, d.size() - n)
	var best := -1
	var score := -INF
	for m in range(24, 109):
		var f := 440.0 * pow(2.0, (m - 69) / 12.0)
		var sc := 0.0
		for h in [1, 2, 3]:
			if f * h >= rate * 0.5:
				sc += log(1e-12)
			else:
				sc += log(_goertzel(d, at, n, f * h, rate) + 1e-12)
		if sc > score:
			score = sc
			best = m
	return best


static func _goertzel(d: PackedFloat32Array, start: int, n: int, f: float, rate: int) -> float:
	var c := 2.0 * cos(TAU * f / rate)
	var s1 := 0.0
	var s2 := 0.0
	for i in n:
		var s0 := d[start + i] * (0.5 - 0.5 * cos(TAU * i / (n - 1))) + c * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - c * s1 * s2


## Set a kit piece's setting (name, sound, gain_db, pan, tune_semitones,
## choke, gate), undoably. A shipped kit becomes an edited copy first.
func set_piece(i: int, key: String, value: Variant) -> void:
	var kit := _own_kit()
	if kit == null or i < 0 or i >= kit.pieces.size():
		return
	var ps := kit.pieces.duplicate(true)
	ps[i][key] = value
	_commit(kit, {pieces = ps}, "Kit " + key)


func add_piece(piece_name: String, sound: String) -> void:
	var kit := _own_kit()
	if kit == null:
		return
	var ps := kit.pieces.duplicate(true)
	ps.append({name = piece_name, sound = sound, gain_db = -6.0})
	_commit(kit, {pieces = ps}, "Add piece")


func _own_kit() -> AKKit:
	var kit := loop.instrument as AKKit if loop else null
	if kit and kit.resource_path.begins_with("res://addons/"):
		var copy: AKKit = kit.duplicate(true)
		copy.resource_name = kit.resource_name + "_edit"
		_commit(loop, {instrument = copy}, "Copy kit")
		kit = copy
	return kit


# ------------------------------------------------------------------ context

## Play another loop with this one (when Context is on).
func add_context(v: Variant) -> void:
	var l: AKLoop = v if v is AKLoop else (load(String(v)) as AKLoop if ResourceLoader.exists(String(v)) else null)
	if l and l != loop and not context.has(l):
		context.append(l)
	_update_context_info()
	_restart_if_playing()


func clear_context() -> void:
	context.clear()
	_update_context_info()
	_restart_if_playing()


func set_context(on: bool) -> void:
	context_on = on
	if _context_btn:
		_context_btn.set_pressed_no_signal(on)
	_restart_if_playing()


# ------------------------------------------------------------------ playing

## The song Play plays: one section, the loop (and its context) repeating.
func compiled_song() -> AKSong:
	var s := AKSong.new()
	s.tempo = AKTempoMap.make(bpm, loop.beats_per_bar)
	var bars := loop.bars
	var others: Array[AKLoop] = []
	if context_on:
		others = context
	for c in others:
		bars = maxi(bars, c.bars)
	var beats := float(bars * loop.beats_per_bar)
	var pats := [_pattern(loop, beats)]
	for c in others:
		pats.append(c.to_pattern(beats))
	s.sections = [{name = "loop", bars = bars, patterns = pats}]
	s.master_fx = [{type = &"dcblock"}, {type = &"limit", ceiling_db = -1.0}]
	return s


func _pattern(l: AKLoop, beats: float) -> AKPattern:
	var p := l.to_pattern(beats)
	if l == loop and not grid.muted.is_empty() and l.instrument is AKKit:
		for lane in p.lanes:
			for row in grid.muted:
				if String(lane.name) == "drums." + (l.instrument as AKKit).piece_name(row):
					lane["mute"] = true
	return p


func play() -> void:
	if loop == null:
		return
	song = compiled_song()
	_playing = true
	if live:
		_start_output()
		var m := AKCueMap.new()
		m.master_fx = song.master_fx
		m.reverb = song.reverb
		live.prepare([], m)
		live.song_play(song, &"loop")
	else:
		_play_baked(0.0)
	if _play:
		_play.text = "Stop"
	_say("Playing at %.0f bpm%s" % [bpm, " (live)" if live else " (baked)"])


func stop() -> void:
	_playing = false
	if live:
		live.song_stop(&"now")
		live.stream.clear()
	elif player.playing:
		player.stop()
	grid.playhead = -1.0
	if _play:
		_play.text = "Play"


func is_playing() -> bool:
	return _playing


## Where the loop's playhead is, in ticks into the loop.
func playhead_ticks() -> float:
	if not _playing or loop == null:
		return -1.0
	var beats := 0.0
	if live:
		var pos := live.song_position()
		if pos.is_empty():
			return -1.0
		beats = float(pos.bar) * loop.beats_per_bar + float(pos.beat)
	elif player.playing:
		beats = player.get_playback_position() * bpm / 60.0
	return fmod(beats * AKLoop.TICKS_PER_BEAT, float(loop.length_ticks()))


## The loop changed: re-derive what hasn't sounded yet (live), or re-render
## and carry on from the same place (baked).
func _on_loop_edited(_label := "") -> void:
	if not _playing:
		return
	var s := compiled_song()
	if live and song:
		song.sections = s.sections
		song.tempo = s.tempo
		live.song_changed()
	else:
		_play_baked(player.get_playback_position() if player.playing else 0.0)


func _play_baked(from_s: float) -> void:
	song = compiled_song()
	var out: Dictionary = song.render()
	_baked = out.mix
	var frames := roundi(song.length_s() * AK.sample_rate)
	var st := _baked.to_stream()
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = mini(frames, _baked.frames())
	player.stream = st
	if player.is_inside_tree():
		player.play(fmod(from_s, maxf(0.01, song.length_s())))


func _restart_if_playing() -> void:
	if _playing:
		play()


## Play one row: a note of the patch or sample, or a kit piece.
func audition_row(row: int) -> AKBuffer:
	var r: AKRecipe = null
	var ov := {_gate_s = 0.3}
	match loop.kind:
		"percussive":
			var kit := loop.instrument as AKKit
			r = kit.piece_recipe(row) if kit and row < kit.piece_count() else null
		"sample":
			var s := loop.instrument as AKSample
			r = s.to_recipe() if s else null
			ov["_note_hz"] = AKNotes.midi_to_hz(row)
		_:
			r = AKRecipe.make(&"patch", {patch = loop.instrument})
			ov["_note_hz"] = AKNotes.midi_to_hz(row)
	if r == null:
		return null
	var buf := AK.render(r, grid.default_velocity, {}, 0, ov)
	_play_buffer(buf)
	return buf


func audition_sound(path: String) -> void:
	var s := AKSoundBrowser.sample_for(path)
	if s:
		_play_buffer(AK.render(s.to_recipe()))


func _play_buffer(buf: AKBuffer) -> void:
	if buf == null or buf.frames() == 0 or not audition_player.is_inside_tree():
		return
	audition_player.stream = buf.to_stream()
	audition_player.play()


# ------------------------------------------------------------------ internals

func _set_loop(l: AKLoop) -> void:
	if loop and loop.changed.is_connected(_on_loop_changed):
		loop.changed.disconnect(_on_loop_changed)
	loop = l
	loop.changed.connect(_on_loop_changed)
	grid.set_loop(loop)
	_sync_toolbar()
	_rebuild_panels()
	if _playing:
		play()


## Undo and redo (and edits from the inspector) arrive as `changed`.
func _on_loop_changed() -> void:
	if _quiet:
		return
	grid._resize()
	grid.queue_redraw()
	_on_loop_edited()


## One undoable action setting properties of `obj` (the loop, its sample or
## kit). The loop's own edits reach the music through its `changed`; a
## sample's or kit's are pushed here. Panels are rebuilt when the shape
## changes (type, instrument, pieces) and on undo, not while a value is typed.
func _commit(obj: Object, props: Dictionary, label: String) -> void:
	var undo := grid.undo
	var action := "Loop: " + label
	var is_kit := obj is AKKit
	var other := obj != loop
	var shape := props.has("kind") or props.has("instrument") or (props.has("pieces") and (props.pieces as Array).size() != (obj.get("pieces") as Array).size())
	if undo == null:
		for k in props:
			obj.set(k, props[k])
		if is_kit:
			obj.refresh()
		obj.emit_changed()
		_after_undoable(shape, other)
	elif undo is UndoRedo:
		undo.create_action(action)
		for k in props:
			undo.add_do_property(obj, k, props[k])
			undo.add_undo_property(obj, k, _copy(obj.get(k)))
		if is_kit:
			undo.add_do_method(obj.refresh)
			undo.add_undo_method(obj.refresh)
		undo.add_do_method(obj.emit_changed)
		undo.add_undo_method(obj.emit_changed)
		undo.add_do_method(_after_undoable.bind(shape, other))
		undo.add_undo_method(_after_undoable.bind(true, other))
		undo.commit_action()
	else:
		undo.call(&"create_action", action, UndoRedo.MERGE_DISABLE, obj)
		for k in props:
			undo.call(&"add_do_property", obj, k, props[k])
			undo.call(&"add_undo_property", obj, k, _copy(obj.get(k)))
		if is_kit:
			undo.call(&"add_do_method", obj, &"refresh")
			undo.call(&"add_undo_method", obj, &"refresh")
		undo.call(&"add_do_method", obj, &"emit_changed")
		undo.call(&"add_undo_method", obj, &"emit_changed")
		undo.call(&"add_do_method", self, &"_after_undoable", shape, other)
		undo.call(&"add_undo_method", self, &"_after_undoable", true, other)
		undo.call(&"commit_action")


func _after_undoable(rebuild_panels := false, other := false) -> void:
	if loop == null:
		return
	if rebuild_panels:
		grid.set_loop(loop)
	grid._resize()
	grid.queue_redraw()
	_sync_toolbar()
	if rebuild_panels:
		_rebuild_panels.call_deferred()
	if other:
		_on_loop_edited()


static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


func _default_instrument(kind: String) -> Resource:
	match kind:
		"percussive":
			return AKLibrary.kit("punch")
		"sample":
			return _sample_from(AKLibrary.path_of("keys", "epiano"))
	var p := "res://addons/audio_kit/patches/pluck.tres"
	return load(p) if ResourceLoader.exists(p) else AKPatch.new()


## An AKSample for a picked sound. A project .wav/.ogg gets one saved
## beside it (kick_01.wav -> kick_01.sample.tres), reused if it's there.
func _sample_from(path: String) -> AKSample:
	var ext := path.get_extension().to_lower()
	if ext in ["wav", "ogg"]:
		var beside := path.get_basename() + ".sample.tres"
		if ResourceLoader.exists(beside):
			return load(beside) as AKSample
		var s := AKSoundBrowser.sample_for(path)
		if s == null:
			return null
		var det := detect_root(s)
		if det >= 0 and s.root_note == 60.0:
			s.root_note = det
		if ResourceSaver.save(s, beside) == OK:
			s.take_over_path(beside)
			AK.refresh_editor_files()
		return s
	var lib := AKSoundBrowser.sample_for(path)
	# A pitched library sound follows the note's length (gate); drums play out.
	if lib and lib.recipe and int(lib.recipe.get_meta(&"ak_root_note", -1)) >= 0:
		lib.mode = "gate"
		lib.release_s = 0.08
	return lib


func _files(dir: String) -> Array:
	if not DirAccess.dir_exists_absolute(dir):
		return []
	var out := []
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres") or f.ends_with(".res"):
			out.append(f)
	out.sort()
	return out


func _instrument_path(inst: Resource) -> String:
	if inst == null:
		return ""
	if inst is AKSample:
		var s := inst as AKSample
		if s.resource_path != "" and not s.resource_path.contains("::"):
			return s.resource_path
		if s.recipe and s.recipe.resource_path != "":
			return s.recipe.resource_path
		return s.source
	return inst.resource_path


func _say(text: String) -> void:
	if _status:
		_status.text = text


# ------------------------------------------------------------------ building

func _build() -> void:
	var left := TabContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	add_child(left)
	loops = AKLoopBrowser.new()
	loops.name = "Loops"
	loops.folders = [save_dir + "loops/"]
	loops.refresh()
	loops.loop_selected.connect(func(p: String) -> void:
		if context_on and loop and p != loop_path:
			add_context(p)
		else:
			open_loop(p))
	loops.loop_activated.connect(func(_p: String) -> void: play())
	left.add_child(loops)
	sounds = AKSoundBrowser.new()
	sounds.name = "Sounds"
	sounds.project_dir = save_dir
	sounds.refresh()
	sounds.audition.connect(audition_sound)
	sounds.sound_activated.connect(func(p: String) -> void:
		if loop and loop.kind == "sample":
			set_instrument(p))
	left.add_child(sounds)

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(centre)
	var bar := HFlowContainer.new()
	centre.add_child(bar)
	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(120, 0)
	_name.placeholder_text = "loop name"
	_name.text_submitted.connect(func(_t: String) -> void: save_loop())
	_name.text_changed.connect(func(t: String) -> void:
		if loop and not _quiet:
			loop.resource_name = t.strip_edges())
	bar.add_child(_name)
	_new = MenuButton.new()
	_new.text = "New"
	_new.flat = false
	for i in NEW_KINDS.size():
		_new.get_popup().add_item(NEW_KINDS[i], i)
	_new.get_popup().id_pressed.connect(func(id: int) -> void: new_loop(NEW_KINDS[id]))
	bar.add_child(_new)
	_kind = _option(bar, "Type", NEW_KINDS, func(i: int) -> void: set_kind(NEW_KINDS[i]))
	_instrument = OptionButton.new()
	_instrument.custom_minimum_size = Vector2(170, 0)
	_instrument.tooltip_text = "Instrument: a patch, a sample or a kit"
	_instrument.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _inst_paths.size():
			set_instrument(_inst_paths[i]))
	bar.add_child(_instrument)
	_button(bar, "Open", _open_instrument)
	_bars = _option(bar, "Bars", BARS.map(func(b: int) -> String: return "%d bar%s" % [b, "" if b == 1 else "s"]),
		func(i: int) -> void: set_bars(BARS[i]))
	_division = _option(bar, "Division", AKLoop.DIVISIONS.map(func(d: int) -> String: return "1/%d" % d),
		func(i: int) -> void: set_division(AKLoop.DIVISIONS[i]))
	var sw := Label.new()
	sw.text = "Swing"
	bar.add_child(sw)
	_swing = HSlider.new()
	_swing.min_value = 0.5
	_swing.max_value = 0.8
	_swing.step = 0.01
	_swing.custom_minimum_size = Vector2(70, 0)
	_swing.value_changed.connect(func(v: float) -> void:
		if not _quiet:
			set_swing(v))
	bar.add_child(_swing)
	_play = _button(bar, "Play", func() -> void:
		if _playing:
			stop()
		else:
			play())
	_tempo = SpinBox.new()
	_tempo.min_value = 20
	_tempo.max_value = 400
	_tempo.step = 1
	_tempo.value = bpm
	_tempo.suffix = "bpm"
	_tempo.custom_minimum_size = Vector2(96, 0)
	_tempo.value_changed.connect(set_tempo)
	bar.add_child(_tempo)
	_category = _option(bar, "Category", CATEGORIES.map(func(c: String) -> String: return c if c != "" else "(category)"),
		func(i: int) -> void: _commit(loop, {category = CATEGORIES[i]}, "Category"))
	_button(bar, "Save", save_loop)

	var tools := HFlowContainer.new()
	centre.add_child(tools)
	_button(tools, "Oct-", func() -> void: grid.shift_octave(-1))
	_button(tools, "Oct+", func() -> void: grid.shift_octave(1))
	_button(tools, "-1 st", func() -> void: transpose(-1))
	_button(tools, "+1 st", func() -> void: transpose(1))
	_button(tools, "Duplicate", duplicate_loop)
	_button(tools, "Double", double_loop)
	_button(tools, "Halve", halve_loop)
	_button(tools, "Ramp up", func() -> void: grid.velocity_ramp(0.4, 1.0))
	_button(tools, "Ramp down", func() -> void: grid.velocity_ramp(1.0, 0.4))
	_button(tools, "Humanize", func() -> void: grid.randomise_velocity(0.15, randi()))
	_button(tools, "Undo", func() -> void: grid.undo_last())
	_button(tools, "Redo", func() -> void: grid.redo_last())
	_context_btn = CheckBox.new()
	_context_btn.text = "Context"
	_context_btn.tooltip_text = "Play other loops with this one: with Context on, click loops in the browser to add them"
	_context_btn.toggled.connect(set_context)
	tools.add_child(_context_btn)
	_button(tools, "Clear context", clear_context)
	_context_info = Label.new()
	tools.add_child(_context_info)

	# Guides: the scale (cool rows) and a chord (warm rows, intervals by the keys).
	var guides := HFlowContainer.new()
	centre.add_child(guides)
	var gl := Label.new()
	gl.text = "Guides:"
	guides.add_child(gl)
	var scale_keys: Array = AKNotes.SCALES.keys()
	_scale = _option(guides, "Scale", ["no scale"] + scale_keys.map(func(k: String) -> String: return AKNotes.scale_label(k)),
		func(i: int) -> void: set_scale_key(scale_keys[i - 1] if i > 0 else "", _root.selected))
	_root = _option(guides, "Root", NOTE_NAMES, func(i: int) -> void: set_scale_key(grid.scale_name, i))
	_fold = CheckBox.new()
	_fold.text = "Fold"
	_fold.tooltip_text = "Show only the rows in the scale"
	_fold.toggled.connect(set_fold)
	guides.add_child(_fold)
	guides.add_child(VSeparator.new())
	_chord_on = CheckBox.new()
	_chord_on.text = "Chord"
	_chord_on.tooltip_text = "Highlight a chord's notes"
	_chord_on.toggled.connect(func(on: bool) -> void:
		if _quiet:
			return
		if on:
			set_chord(_chord_menu_symbol())
		else:
			clear_chord())
	guides.add_child(_chord_on)
	_chord_root = _option(guides, "Chord root", CHORD_ROOTS, func(_i: int) -> void: set_chord(_chord_menu_symbol()))
	_chord_quality = _option(guides, "Chord type", AKChords.COMMON.map(func(q: Array) -> String:
		return "%s  %s" % [q[0] if q[0] != "" else "maj", q[1]]),
		func(_i: int) -> void: set_chord(_chord_menu_symbol()))
	_chord_quality.fit_to_longest_item = false
	_chord_quality.custom_minimum_size = Vector2(190, 0)
	_chord_text = LineEdit.new()
	_chord_text.placeholder_text = "or type: Cm9, G7b9, F/A"
	_chord_text.tooltip_text = "A chord symbol (Enter to show it)"
	_chord_text.custom_minimum_size = Vector2(150, 0)
	_chord_text.text_submitted.connect(func(t: String) -> void: set_chord(t))
	guides.add_child(_chord_text)
	_chord_notes = Label.new()
	_chord_notes.tooltip_text = "The chord's notes"
	guides.add_child(_chord_notes)

	var imp := HFlowContainer.new()
	centre.add_child(imp)
	var il := Label.new()
	il.text = "From a song, pattern or .mid:"
	imp.add_child(il)
	_imp_path = LineEdit.new()
	_imp_path.placeholder_text = "res://music/tune.mid"
	_imp_path.custom_minimum_size = Vector2(220, 0)
	imp.add_child(_imp_path)
	_button(imp, "Load", func() -> void: _load_import(_imp_path.text.strip_edges()))
	_imp_lane = OptionButton.new()
	_imp_lane.tooltip_text = "Lane (drum lanes: the whole kit)"
	imp.add_child(_imp_lane)
	_imp_section = OptionButton.new()
	_imp_section.tooltip_text = "Section"
	imp.add_child(_imp_section)
	_imp_bars = _spin(imp, "bars", 2, 1, 64, 1, func(_v: float) -> void: pass)
	_button(imp, "Make loop", func() -> void:
		var lanes := _imp_lanes_picked()
		if not lanes.is_empty():
			loop_from(_imp_path.text.strip_edges(), lanes, maxi(0, _imp_section.selected), int(_imp_bars.value)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_child(scroll)
	grid = AKLoopGrid.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.audition.connect(func(row: int) -> void: audition_row(row))
	grid.mutes_changed.connect(func() -> void: _on_loop_edited())
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		grid.undo = Engine.get_singleton(&"EditorInterface").call(&"get_editor_undo_redo")   # Ctrl+Z in the editor
	scroll.add_child(grid)

	var pscroll := ScrollContainer.new()
	pscroll.custom_minimum_size = Vector2(0, 150)
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	centre.add_child(pscroll)
	_panel_box = VBoxContainer.new()
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pscroll.add_child(_panel_box)
	_status = Label.new()
	centre.add_child(_status)


func _load_import(path: String) -> void:
	var info := import_source(path)
	_imp_lane.clear()
	_imp_section.clear()
	if info.is_empty():
		_say("Not a song, pattern or .mid file: %s" % path)
		return
	var lanes: Array = info.lanes
	if lanes.any(func(n: String) -> bool: return n.begins_with("drums.")):
		_imp_lane.add_item("drums (all)")
	for n in lanes:
		_imp_lane.add_item(n)
	for n in info.sections:
		_imp_section.add_item(n)
	_say("%s: %d lanes, %d sections" % [path.get_file(), lanes.size(), info.sections.size()])


func _imp_lanes_picked() -> Array:
	if _imp_lane.selected < 0:
		return []
	var t := _imp_lane.get_item_text(_imp_lane.selected)
	if t == "drums (all)":
		var info := import_source(_imp_path.text.strip_edges())
		return (info.get("lanes", []) as Array).filter(func(n: String) -> bool: return n.begins_with("drums."))
	return [t]


func _sync_toolbar() -> void:
	if loop == null or _kind == null:
		return
	_quiet = true
	if _name.text.strip_edges() != String(loop.resource_name):
		_name.text = String(loop.resource_name)
	_kind.select(NEW_KINDS.find(loop.kind))
	var bi := BARS.find(loop.bars)
	if bi < 0:
		_bars.add_item("%d bars" % loop.bars)
		bi = _bars.item_count - 1
	_bars.select(bi)
	_division.select(AKLoop.DIVISIONS.find(loop.division))
	_swing.set_value_no_signal(loop.swing)
	_category.select(maxi(0, CATEGORIES.find(loop.category)))
	if _shown_inst != loop.instrument or _shown_kind != loop.kind:
		_fill_instruments()
	_quiet = false


func _fill_instruments() -> void:
	_shown_inst = loop.instrument
	_shown_kind = loop.kind
	_instrument.clear()
	_inst_paths.clear()
	var cur := _instrument_path(loop.instrument)
	var sel := -1
	for c in instrument_choices():
		_instrument.add_item(c.label)
		_inst_paths.append(c.path)
		if c.path == cur:
			sel = _inst_paths.size() - 1
	if sel < 0 and loop.instrument:
		_instrument.add_item("%s (this loop's)" % (String(loop.instrument.resource_name) if loop.instrument.resource_name != "" else loop.kind))
		_inst_paths.append(loop.instrument)
		sel = _inst_paths.size() - 1
	if sel >= 0:
		_instrument.select(sel)


func _open_instrument() -> void:
	if loop == null:
		return
	if loop.instrument is AKPatch:
		open_patch.emit(loop.instrument)
		_say("Opening the patch in the Synth tab")
	else:
		_say("The %s's settings are below the grid" % ("sample" if loop.kind == "sample" else "kit"))


func _update_context_info() -> void:
	if _context_info:
		_context_info.text = "with: " + ", ".join(context.map(func(l: AKLoop) -> String: return l.lane_name())) if not context.is_empty() else ""


func _rebuild_panels() -> void:
	if _panel_box == null:
		return
	for c in _panel_box.get_children():
		_panel_box.remove_child(c)
		c.queue_free()
	if loop == null:
		return
	if loop.instrument is AKSample:
		_build_sample_panel(loop.instrument)
	elif loop.instrument is AKKit:
		_build_kit_panel(loop.instrument)


func _build_sample_panel(s: AKSample) -> void:
	var row := HFlowContainer.new()
	_panel_box.add_child(row)
	var t := Label.new()
	t.text = "Sample: %s" % _instrument_path(s).get_file()
	row.add_child(t)
	_spin(row, "Root", s.root_note, 0, 127, 1, func(v: float) -> void: set_sample_param("root_note", v))
	_button(row, "Detect", func() -> void:
		var m := detect_root(s)
		if m >= 0:
			set_sample_param("root_note", float(m))
			_say("Detected root %s (check it by ear)" % AKNotes.midi_to_name(m))
		else:
			_say("No clear pitch"))
	var modes := ["oneshot", "gate", "loop"]
	var mo := _option(row, "Mode", modes, func(i: int) -> void: set_sample_param("mode", modes[i]))
	mo.select(maxi(0, modes.find(s.mode)))
	_spin(row, "Start s", s.start_s, 0, 60, 0.001, func(v: float) -> void: set_sample_param("start_s", v))
	_spin(row, "End s", s.end_s, 0, 60, 0.001, func(v: float) -> void: set_sample_param("end_s", v))
	_spin(row, "Loop from", s.loop_start_s, 0, 60, 0.001, func(v: float) -> void: set_sample_param("loop_start_s", v))
	_spin(row, "Loop to", s.loop_end_s, 0, 60, 0.001, func(v: float) -> void: set_sample_param("loop_end_s", v))
	_spin(row, "Release s", s.release_s, 0.001, 10, 0.001, func(v: float) -> void: set_sample_param("release_s", v))
	_spin(row, "Gain dB", s.gain_db, -48, 24, 0.1, func(v: float) -> void: set_sample_param("gain_db", v))
	var rv := CheckBox.new()
	rv.text = "Reverse"
	rv.button_pressed = s.reverse
	rv.toggled.connect(func(on: bool) -> void: set_sample_param("reverse", on))
	row.add_child(rv)


func _build_kit_panel(kit: AKKit) -> void:
	var head := HBoxContainer.new()
	_panel_box.add_child(head)
	var t := Label.new()
	t.text = "Kit: %s%s" % [kit.resource_name, "  (shipped: edits make a copy)" if kit.resource_path.begins_with("res://addons/") else ""]
	head.add_child(t)
	_button(head, "Save kit", func() -> void: save_kit())
	_button(head, "+ Piece", func() -> void:
		var p := sounds.selected()
		if p != "":
			add_piece(p.get_file().get_basename(), p)
		else:
			_say("Pick a sound in Sounds first"))
	for i in kit.piece_count():
		var p: Dictionary = kit.pieces[i]
		var row := HBoxContainer.new()
		_panel_box.add_child(row)
		var nm := LineEdit.new()
		nm.text = kit.piece_name(i)
		nm.custom_minimum_size = Vector2(90, 0)
		nm.text_submitted.connect(func(v: String) -> void: set_piece(i, "name", v))
		row.add_child(nm)
		var snd := Label.new()
		var sv: Variant = p.get("sound")
		snd.text = (String(sv).get_file().get_basename() if sv is String else (sv.resource_name if sv is Resource else "?"))
		snd.custom_minimum_size = Vector2(120, 0)
		snd.clip_text = true
		row.add_child(snd)
		_button(row, "Use selected", func() -> void:
			if sounds.selected() != "":
				set_piece(i, "sound", sounds.selected()))
		_spin(row, "dB", float(p.get("gain_db", 0.0)), -48, 12, 0.5, func(v: float) -> void: set_piece(i, "gain_db", v))
		_spin(row, "Pan", float(p.get("pan", 0.0)), -1, 1, 0.05, func(v: float) -> void: set_piece(i, "pan", v))
		_spin(row, "Tune", float(p.get("tune_semitones", 0.0)), -24, 24, 0.1, func(v: float) -> void: set_piece(i, "tune_semitones", v))
		var ch := LineEdit.new()
		ch.placeholder_text = "choke"
		ch.text = kit.choke_of(i)
		ch.custom_minimum_size = Vector2(60, 0)
		ch.text_submitted.connect(func(v: String) -> void: set_piece(i, "choke", v))
		row.add_child(ch)
		var g := CheckBox.new()
		g.text = "Gate"
		g.button_pressed = kit.is_gated(i)
		g.toggled.connect(func(on: bool) -> void: set_piece(i, "gate", on))
		row.add_child(g)
		_button(row, "▶", func() -> void: audition_row(i))


func _option(parent: Control, tip: String, items: Array, f: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.tooltip_text = tip
	for it in items:
		o.add_item(String(it))
	o.item_selected.connect(func(i: int) -> void:
		if not _quiet:
			f.call(i))
	parent.add_child(o)
	return o


func _spin(parent: Control, label: String, value: float, lo: float, hi: float, step: float, f: Callable) -> SpinBox:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.value = value
	s.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v: float) -> void: f.call(v))
	parent.add_child(s)
	return s


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b
