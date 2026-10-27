# SPDX-License-Identifier: Apache-2.0
@tool
## Imports an Auxy project, from Auxy's "Export for Bitwig Studio" bundle
## (.axbw), as loops, drum kits and an AKArrangement.
##
##   var res := AKAuxy.import_file("/path/to/Song-bitwig.axbw", "res://audio/")
##   if res.ok:
##       var arr: AKArrangement = res.arrangement     # saved at res.path
##
## Why that export: it is Auxy's own model, not a translation. The bundle is
## a zip holding `manifest.json` (title, bpm, scale, channels with their
## preset names, colours and kind "instrument" or "drums", and the song as a
## list of scenes), one standard MIDI file per loop (`loop_<channel>_<slot>.mid`,
## its end-of-track marking the loop's length) and a rendered stem per
## channel (`stem_<channel>.wav`). Checked against the rendered stems, its
## scenes match the audio bar for bar, where Auxy's Ableton, Studio One and
## MIDI exports each get a few bars wrong around scenes that start mid-loop.
##
## The manifest's song is a list of scenes played one after another:
##   {loop_locations = ["3_0", "5_2"], number_of_bars = 3, start_offset = 1}
## Every listed loop plays for `number_of_bars`, starting `start_offset` bars
## into itself and repeating; a loop restarts at each scene (a two-bar loop
## in five one-bar scenes plays its first bar five times).
##
## What it makes (all under `save_dir`, named after the song):
##   - a loop per Auxy loop (`loops/<song>_<track>_<n>.tres`, flat so the
##     loop browser lists them), the whole bank, used or not. Instrument
##     channels become synth loops on a preset patch picked from the preset
##     name and the notes' register (pass `patches` to choose); drum channels
##     become percussive loops on a kit made for the channel.
##   - a kit per drum channel (`kits/<song>_<track>.tres`): Auxy's drum
##     notes count up from 36, so row = note - 36. When kit_from_pads has cut
##     this Auxy kit's own sounds (`kits/auxy_<kit>.tres`), the loops play
##     that kit instead and none is made. Kits in KIT_MAPS (Battery)
##     get a matching sound per pad; for others piece n is a copy of the base
##     kit's piece n (kick, snare, clap, closed hat ...), since Auxy doesn't
##     say which sound a pad is. Swap sounds in this kit once and every loop
##     follows.
##   - the arrangement (`arrangements/<song>.tres`): a track per channel that
##     has loops, Auxy's song on the timeline (a clip per stretch where a
##     loop plays on in phase, a marker wherever the set of loops changes)
##     and a scene per distinct set of loops, to launch from a game.
##   - the stems of channels the song uses (`stems/<song>/<track>.wav`),
##     listed in the arrangement's metadata `auxy`. Reference only: the
##     sequencer plays the loops, not the stems.
##
## Auxy doesn't export dynamics (every velocity is 127), mixer settings or
## its sounds; the stems are the only record of how it sounded.
class_name AKAuxy
extends RefCounted

const FORMAT_VERSIONS := ["0.1"]
## Auxy's first drum pad.
const DRUM_BASE_NOTE := 36
const BEATS_PER_BAR := 4

## Auxy drum kits whose pads are known, by preset name (lower case): a piece
## per pad from the first (note 36) up. Worked out from a one-hit-per-pad
## export of the kit: each pad's hit in the stem measured (brightness, low
## end, noisiness, decay, pitch) and matched to the closest library sound of
## its family, rendered alone; gains put each piece's peak at the Auxy pad's,
## so the kit keeps Auxy's balance. Pads Auxy cuts short (at the note's
## sixteenth) are gated. Unknown kits fall back to the base kit's pieces in order.
const KIT_MAPS := {
	"battery": [
		{name = "kick", sound = "res://addons/audio_kit/library/kicks/kick_click.tres", gain_db = -8.5},
		{name = "snare", sound = "res://addons/audio_kit/library/snares/snare_dusty.tres", gain_db = -9.9},
		{name = "kick_long", sound = "res://addons/audio_kit/library/kicks/kick_thump.tres", gain_db = -8.3},
		{name = "kick_short", sound = "res://addons/audio_kit/library/kicks/kick_tight.tres", gain_db = -7.2, gate = true},
		{name = "kick_sub", sound = "res://addons/audio_kit/library/kicks/kick_sub.tres", gain_db = -11.7, gate = true},
		{name = "wood", sound = "res://addons/audio_kit/library/perc/wood_block_high.tres", gain_db = -9.1},
		{name = "open_hat", sound = "res://addons/audio_kit/library/hats/hat_open_room.tres", gain_db = -14.5},
		{name = "clap", sound = "res://addons/audio_kit/library/claps/clap_dusty.tres", gain_db = -8.4},
	],
}

## Preset patches by words in an Auxy preset name, first match wins.
const PATCH_WORDS := [
	[["sub"], "sub_bass"],
	[["acid", "303"], "acid_bass"],
	[["wobble"], "wobble_bass"],
	[["bass", "basset", "808"], "wavetable_bass"],
	[["string", "viola", "violin", "cello"], "strings"],
	[["pad", "ghost", "choir", "air", "atmos"], "wavetable_pad"],
	[["vocal", "vox", "chop", "voice"], "vowel_pad"],
	[["bell", "chime", "glass"], "fm_bell"],
	[["piano", "keys", "rhodes", "ep"], "fm_epiano"],
	[["organ"], "organ"],
	[["brass", "horn"], "brass"],
	[["lead", "saw"], "saw_lead"],
	[["pluck", "harp", "micro", "arp"], "pluck"],
]


# ------------------------------------------------------------------ reading

## The bundle as plain data:
##   {ok, error, warnings, title, bpm, scale, creator, format_version,
##    channels: [{label, kind, color}],
##    loops: {"<c>_<s>": {channel, slot, beats, notes: [[beat, length_beats, key, velocity 0..1]]}},
##    scenes: [{loops: ["<c>_<s>", ...], bars, start_offset}],
##    stems: {channel: entry name in the zip}}
static func read(path: String) -> Dictionary:
	var out := {ok = false, error = "", warnings = [], title = "", bpm = 120.0, scale = "", creator = "", format_version = "",
		channels = [], loops = {}, scenes = [], stems = {}}
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		out.error = "can't open %s as a zip (is it an Auxy \"Export for Bitwig Studio\" .axbw?)" % path
		return out
	var files := zip.get_files()
	if not files.has("manifest.json"):
		zip.close()
		out.error = "%s has no manifest.json: not an Auxy Bitwig export" % path.get_file()
		return out
	var man: Variant = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not man is Dictionary:
		zip.close()
		out.error = "manifest.json isn't a JSON object"
		return out
	out.title = String(man.get("title", path.get_file().get_basename()))
	out.bpm = float(man.get("bpm", 120.0))
	out.scale = String(man.get("scale", ""))
	out.creator = String(man.get("creator", ""))
	out.format_version = str(man.get("format_version", ""))
	if not FORMAT_VERSIONS.has(out.format_version):
		out.warnings.append("manifest format_version %s is newer than this importer knows (%s); importing anyway" % [out.format_version, ", ".join(FORMAT_VERSIONS)])
	for c: Variant in man.get("channels", []):
		var cd: Dictionary = c if c is Dictionary else {}
		var hex := String(cd.get("color", "#808080"))
		out.channels.append({label = String(cd.get("label", "")), kind = String(cd.get("kind", "instrument")),
			color = Color.html(hex) if Color.html_is_valid(hex) else Color(0.5, 0.5, 0.5)})
	for f: String in files:
		var m := RegEx.create_from_string("^loop_(\\d+)_(\\d+)\\.mid$").search(f)
		if m:
			var key := "%s_%s" % [m.get_string(1), m.get_string(2)]
			var lp := _read_loop(zip.read_file(f))
			if lp.has("error"):
				out.warnings.append("%s: %s" % [f, lp.error])
			lp.erase("error")
			lp["channel"] = int(m.get_string(1))
			lp["slot"] = int(m.get_string(2))
			out.loops[key] = lp
			continue
		var s := RegEx.create_from_string("^stem_(\\d+)\\.wav$").search(f)
		if s:
			out.stems[int(s.get_string(1))] = f
	zip.close()
	for sc: Variant in man.get("scenes", []):
		var sd: Dictionary = sc if sc is Dictionary else {}
		var keys := []
		for k: Variant in sd.get("loop_locations", []):
			if out.loops.has(String(k)):
				keys.append(String(k))
			else:
				out.warnings.append("a scene lists loop %s, which isn't in the bundle" % k)
		out.scenes.append({loops = keys, bars = int(sd.get("number_of_bars", 0)), start_offset = int(sd.get("start_offset", 0))})
	out.ok = true
	return out


## A loop's notes and length from its MIDI file: beats are quarter notes.
static func _read_loop(bytes: PackedByteArray) -> Dictionary:
	var m := AKMidiFile.from_bytes(bytes)
	var out := {beats = 0.0, notes = []}
	if m.error != "":
		out["error"] = m.error
	var end_tick := 0
	for t: Dictionary in m.tracks:
		var open := {}
		for e: Dictionary in t.events:
			end_tick = maxi(end_tick, int(e.tick))
			match String(e.type):
				"note_on":
					var k := Vector2i(int(e.ch), int(e.key))
					if not open.has(k):
						open[k] = []
					open[k].append([int(e.tick), int(e.vel)])
				"note_off":
					var k := Vector2i(int(e.ch), int(e.key))
					if open.has(k) and not (open[k] as Array).is_empty():
						var on: Array = open[k].pop_front()
						out.notes.append([float(on[0]) / m.ppq, float(int(e.tick) - int(on[0])) / m.ppq, int(e.key), float(on[1]) / 127.0])
	out.notes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[2] < b[2]))
	out.beats = float(end_tick) / m.ppq
	if out.beats <= 0.0 and not out.notes.is_empty():
		var last: Array = out.notes.back()
		out.beats = float(last[0]) + float(last[1])
	return out


## A loop's length in whole bars (at least one).
static func loop_bars(lp: Dictionary) -> int:
	return maxi(1, ceili(float(lp.get("beats", 0.0)) / BEATS_PER_BAR - 1e-6))


## What each channel plays in each bar of the song: {channel: [[loop key, bar into the loop] or null per bar]}.
## The scenes expanded exactly as Auxy plays them; the answer the arrangement's timeline must give.
static func bar_map(model: Dictionary) -> Dictionary:
	var total := 0
	for sc: Dictionary in model.scenes:
		total += int(sc.bars)
	var out := {}
	for ci in model.channels.size():
		var row := []
		row.resize(total)
		out[ci] = row
	var bar := 0
	for sc: Dictionary in model.scenes:
		for k: String in sc.loops:
			var lp: Dictionary = model.loops[k]
			var L := loop_bars(lp)
			var ci := int(lp.channel)
			if not out.has(ci):
				var row := []
				row.resize(total)
				out[ci] = row
			for b in int(sc.bars):
				out[ci][bar + b] = [k, (int(sc.start_offset) + b) % L]
		bar += int(sc.bars)
	return out


# ------------------------------------------------------------------ sample kits: Auxy's own drum sounds

## A drum kit made of Auxy's own sounds, cut from a pad test: a song with a
## loop that hits each pad of the kit once, in order, with room between
## hits (a beat is enough for short sounds; give ringing ones a bar),
## exported for Bitwig. Saved as `kits/auxy_<kit>.tres`, the stand-in for
## pads a song's own stem doesn't have (see import_file's `drum_samples`), and
## the kit every import on that Auxy kit uses with `drum_samples = false`.
##
## The cutting (`_cut_kit`): each pad's hit is the one with the most room
## after it (and some before it, so an earlier hit's tail isn't in it), cut
## from its start to the next hit or the stem's end, the silence after it
## trimmed (60 dB under its peak), with a 5 ms fade where a tail is cut
## short. Writes `samples/auxy/<kit>/<nn>_<pad>.wav` and `.res` (an AKSample
## with the sound decoded inside, so it plays in exports). Pieces are named
## from KIT_MAPS when the kit is known (else pad_1 ...). Samples are mono
## (stereo is folded) and carry what Auxy put on the channel (its reverb).
##
## Options: channel (index; default the first drum channel), name (default
## the Auxy preset's). Returns {ok, error, warnings, kit, path, samples: [res paths],
## pads: [{note, name, start_s, length_s, peak_db, tail_cut_db}]}.
static func kit_from_pads(path: String, save_dir := "res://audio/", options := {}) -> Dictionary:
	var res := {ok = false, error = "", warnings = [], kit = null, path = "", samples = [], pads = []}
	var model := read(path)
	res.warnings.append_array(model.warnings)
	if not model.ok:
		res.error = model.error
		return res
	var ci := int(options.get("channel", -1))
	if ci < 0:
		for i in model.channels.size():
			if model.channels[i].kind == "drums" and not _channel_loops(model, i).is_empty():
				ci = i
				break
	if ci < 0 or ci >= model.channels.size():
		res.error = "no drum channel with loops in %s" % path.get_file()
		return res
	var audio := _stem(path, model, ci)
	if audio.error != "":
		res.error = audio.error
		return res
	var label := String(model.channels[ci].label)
	var kit_name := String(options.get("name", label))
	var dir := save_dir if save_dir.ends_with("/") else save_dir + "/"
	var cut := _cut_kit(model, ci, audio, dir + "samples/auxy/%s/" % slug(kit_name), kit_name, null, res.warnings)
	if cut.error != "":
		res.error = cut.error
		return res
	var kit: AKKit = cut.kit
	kit.resource_name = "auxy " + kit_name
	var kp := dir + "kits/auxy_%s.tres" % slug(kit_name)
	DirAccess.make_dir_recursive_absolute(kp.get_base_dir())
	if ResourceSaver.save(kit, kp) != OK:
		res.error = "couldn't save %s" % kp
		return res
	kit.take_over_path(kp)
	AK.refresh_editor_files()
	res.kit = kit
	res.path = kp
	res.samples = cut.samples
	res.pads = cut.pads
	res.ok = true
	return res


## A channel's stem decoded (mono): an AKAudioFile, `error` set when it isn't there.
static func _stem(path: String, model: Dictionary, ci: int) -> AKAudioFile:
	var bad := AKAudioFile.new()
	if not model.stems.has(ci):
		bad.error = "no stem for channel %d in %s" % [ci + 1, path.get_file()]
		return bad
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		bad.error = "can't open %s" % path
		return bad
	var audio := AKAudioFile.from_wav_bytes(zip.read_file(String(model.stems[ci])))
	zip.close()
	if audio.error != "":
		audio.error = "stem %d: %s" % [ci + 1, audio.error]
	return audio


## Every hit channel `ci` plays in the song: [[seconds, note], ...] in time order.
static func hits(model: Dictionary, ci: int) -> Array:
	var spb := 60.0 / float(model.bpm)
	var out := []
	var row: Array = bar_map(model).get(ci, [])
	for bar in row.size():
		if row[bar] == null:
			continue
		var lp: Dictionary = model.loops[row[bar][0]]
		var lb0 := float(int(row[bar][1]) * BEATS_PER_BAR)
		for nt: Array in lp.notes:
			if float(nt[0]) >= lb0 and float(nt[0]) < lb0 + BEATS_PER_BAR:
				out.append([(bar * BEATS_PER_BAR + float(nt[0]) - lb0) * spb, int(nt[2])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return out


## Cut a kit from channel `ci`'s stem: a sample per pad the song plays (the
## best-placed hit of it), and for pads it doesn't, `fallback`'s piece (or
## the punch kit's). The kit isn't saved; its samples are, under `sdir`.
## Returns {error, kit, samples, pads}.
static func _cut_kit(model: Dictionary, ci: int, audio: AKAudioFile, sdir: String, kit_name: String, fallback: AKKit, warnings: Array) -> Dictionary:
	var out := {error = "", kit = null, samples = [], pads = []}
	var hs := hits(model, ci)
	if hs.is_empty():
		out.error = "the song plays no notes on %s" % model.channels[ci].label
		return out
	var sr := audio.rate
	var data := audio.data
	var stem_end := float(data.size()) / sr
	# Each pad's best hit: the cleanest (least still ringing from earlier hits
	# just before it, against its own peak), then the most room after it
	# (up to 2 s; each dB cleaner counts as 20 ms more room). Two pads struck
	# at once can't be told apart, so such hits come last.
	var best := {}
	var pre_n := roundi(0.01 * sr)
	var peak_n := roundi(0.05 * sr)
	for i in hs.size():
		var t := float(hs[i][0])
		var note := int(hs[i][1])
		var after := stem_end - t
		for j in range(i + 1, hs.size()):
			if float(hs[j][0]) > t + 1e-6:
				after = float(hs[j][0]) - t
				break
		var simultaneous := false
		for j in hs.size():
			if j != i and absf(float(hs[j][0]) - t) < 1e-6:
				simultaneous = true
		var a := clampi(roundi(t * sr), 0, data.size())
		var pk := 0.0
		for x in range(a, mini(data.size(), a + peak_n)):
			pk = maxf(pk, absf(data[x]))
		var e := 0.0
		for x in range(maxi(0, a - pre_n), a):
			e += data[x] * data[x]
		var pre_db := clampf(10.0 * log(e / pre_n + 1e-20) / log(10.0) - 20.0 * log(pk + 1e-20) / log(10.0), -60.0, 0.0)
		var score := minf(after, 2.0) - 0.02 * pre_db - (100.0 if simultaneous else 0.0)
		if not best.has(note) or score > float(best[note].score):
			best[note] = {t = t, end = t + after, score = score, pre_db = pre_db}
	var label := String(model.channels[ci].label)
	var known: Array = KIT_MAPS.get(label.to_lower().strip_edges(), [])
	var top := 0
	for k: int in best:
		top = maxi(top, k - DRUM_BASE_NOTE)
	for key: String in _channel_loops(model, ci):
		for nt: Array in model.loops[key].notes:
			top = maxi(top, int(nt[2]) - DRUM_BASE_NOTE)   # pads in loops the song doesn't play get a stand-in
	if fallback:
		top = maxi(top, fallback.pieces.size() - 1)
	DirAccess.make_dir_recursive_absolute(sdir)
	var kit := AKKit.new()
	kit.category = "auxy"
	for pad in top + 1:
		var note := DRUM_BASE_NOTE + pad
		var pname := String(known[pad].name) if pad < known.size() else (fallback.piece_name(pad) if fallback and pad < fallback.pieces.size() else "pad_%d" % (pad + 1))
		if not best.has(note):
			var src: AKKit = fallback if fallback and pad < fallback.pieces.size() else _kit_for("punch", pad + 1)
			var stand_in: Dictionary = src.pieces[pad].duplicate(true)
			if fallback == null:
				warnings.append("%s: pad %d (note %d) isn't played: it gets the punch kit's %s" % [kit_name, pad + 1, note, stand_in.name])
			stand_in["name"] = pname
			kit.pieces.append(stand_in)
			continue
		var b: Dictionary = best[note]
		if float(b.pre_db) > -30.0:
			warnings.append("%s: pad %d (%s): even its cleanest hit has sound still ringing under it (%.0f dB under its peak, often its own last hit): the sample carries that and may play a little loud" % [kit_name, pad + 1, pname, -float(b.pre_db)])
		var a := clampi(roundi(float(b.t) * sr), 0, data.size())
		var z := clampi(roundi(float(b.end) * sr), a, data.size())
		var cut := data.slice(a, z)
		var peak := 0.0
		for v in cut:
			peak = maxf(peak, absf(v))
		if peak <= 0.0:
			warnings.append("%s: pad %d is silent in the stem" % [kit_name, pad + 1])
		# Trim the silence after the sound (60 dB under its peak).
		var floor_v := peak * 0.001
		var end := cut.size()
		while end > 1 and absf(cut[end - 1]) < floor_v:
			end -= 1
		var tail_db := -120.0
		var w := mini(cut.size(), roundi(0.01 * sr))
		if end == cut.size() and float(b.end) < stem_end - 1e-6 and w > 0:
			# Cut at the next hit: how loud was it still?
			var s2 := 0.0
			for i in range(cut.size() - w, cut.size()):
				s2 += cut[i] * cut[i]
			tail_db = 10.0 * log(s2 / w + 1e-20) / log(10.0) - 20.0 * log(peak + 1e-20) / log(10.0)
			if tail_db > -40.0:
				warnings.append("%s: pad %d (%s) still rings at %.0f dB under its peak where the next hit starts (best of its hits): its tail is cut" % [kit_name, pad + 1, pname, -tail_db])
		cut = cut.slice(0, end)
		var fade := mini(cut.size(), roundi(0.005 * sr))
		for i in fade:
			cut[cut.size() - 1 - i] *= float(i) / fade
		var buf := AKBuffer.new()
		buf.sample_rate = sr
		buf.l = cut
		buf.r = cut.duplicate()
		var base := "%02d_%s" % [pad + 1, pname]
		var wav := sdir + base + ".wav"
		if buf.save_wav(wav) != OK:
			out.error = "couldn't write %s" % wav
			return out
		var s := AKSample.new()
		s.source = wav
		s.resource_name = "%s %s" % [kit_name, pname]
		var err := s.import_source()
		if err != "":
			out.error = "%s: %s" % [wav, err]
			return out
		var sp := sdir + base + ".res"
		if ResourceSaver.save(s, sp) != OK:
			out.error = "couldn't save %s" % sp
			return out
		s.take_over_path(sp)
		out.samples.append(sp)
		kit.pieces.append({name = pname, sound = sp})
		out.pads.append({note = note, name = pname, start_s = float(b.t), length_s = float(cut.size()) / sr,
			peak_db = 20.0 * log(peak + 1e-20) / log(10.0), tail_cut_db = tail_db})
	out.kit = kit
	return out


## The sample kit kit_from_pads saved for an Auxy kit under save_dir, or "".
static func sample_kit_path(save_dir: String, label: String) -> String:
	var dir := save_dir if save_dir.ends_with("/") else save_dir + "/"
	var p := dir + "kits/auxy_%s.tres" % slug(label)
	return p if ResourceLoader.exists(p) else ""


# ------------------------------------------------------------------ importing

## Read `path` and write loops, kits, stems and an arrangement under
## `save_dir` (as the Sequencer's). Options:
##   drum_samples  cut each drum channel's kit from this song's own stem (default true): Auxy's
##             sounds as the song sets them (tuning, decay, effects differ per song); pads the song
##             doesn't play come from the kit below. Writes samples/auxy/<song>_<track>/
##   kits      {channel index or Auxy label: AKKit or path} for drum channels; without it, a kit
##             kit_from_pads saved under save_dir for the same Auxy kit is used (Auxy's own sounds)
##   kit       base kit for drum channels without a kit or pad map (a shipped kit name or an AKKit path; default "punch")
##   drum_maps {channel index or Auxy label: [piece per pad, from note 36]}, overriding KIT_MAPS
##   patches   {channel index or Auxy label: preset name or AKPatch path}, overriding the guess
##   stems     copy the used channels' stems (default true)
##   name      file name stem (default: the song title)
## Returns {ok, error, warnings, arrangement, path, loops: [paths], kits: [paths], stems: {track: path}, model,
## track_of: {channel: track name}, loop_paths: {"<c>_<s>": path}, drum_cuts: {track: [pad info as kit_from_pads]}}.
static func import_file(path: String, save_dir := "res://audio/", options := {}) -> Dictionary:
	var model := read(path)
	var res := {ok = false, error = model.error, warnings = model.warnings.duplicate(), arrangement = null, path = "",
		loops = [], kits = [], stems = {}, model = model, track_of = {}, loop_paths = {}}
	if not model.ok:
		return res
	var dir := save_dir if save_dir.ends_with("/") else save_dir + "/"
	var base := String(options.get("name", "")).strip_edges()
	if base == "":
		base = slug(String(model.title))
	if base == "":
		base = "auxy"
	var opts := options.duplicate()
	opts["save_dir"] = dir
	var arr := to_arrangement(model, opts, res.warnings)
	arr.resource_name = base

	# Kits and loops are saved first so the arrangement refers to them by path.
	DirAccess.make_dir_recursive_absolute(dir + "loops")
	DirAccess.make_dir_recursive_absolute(dir + "kits")
	DirAccess.make_dir_recursive_absolute(dir + "arrangements")
	var built: Dictionary = arr.get_meta(&"auxy_build")
	arr.remove_meta(&"auxy_build")
	# Drums in Auxy's own sounds, as this song plays them: cut from its stem.
	res["drum_cuts"] = {}
	if bool(options.get("drum_samples", true)):
		for ci: int in built.kits.keys():
			if not model.stems.has(ci):
				continue
			var tn := String(built.track_of[ci])
			var audio := _stem(path, model, ci)
			if audio.error != "":
				res.warnings.append(audio.error)
				continue
			var cut := _cut_kit(model, ci, audio, dir + "samples/auxy/%s_%s/" % [base, slug(tn)], tn, built.kits[ci], res.warnings)
			if cut.error != "":
				res.warnings.append("%s: no samples cut (%s); it plays %s" % [tn, cut.error, "its kit"])
				continue
			var kit: AKKit = cut.kit
			kit.resource_name = "%s %s" % [base, tn]
			built.kits[ci] = kit
			for key: String in built.loops:
				if int(model.loops[key].channel) == ci:
					(built.loops[key] as AKLoop).instrument = kit
			res.drum_cuts[tn] = cut.pads
	var saved_kits := {}
	for ci: int in built.kits:
		var kit: AKKit = built.kits[ci]
		if kit.resource_path != "" and not kit.resource_path.contains("::"):
			res.kits.append(kit.resource_path)   # a saved kit (Auxy's samples, or one passed in): shared, not copied
			continue
		var kp := dir + "kits/%s_%s.tres" % [base, slug(String(built.track_of[ci]))]
		if ResourceSaver.save(kit, kp) != OK:
			res.error = "couldn't save %s" % kp
			return res
		kit.take_over_path(kp)
		saved_kits[ci] = kp
		res.kits.append(kp)
	var loop_path := {}
	for key: String in built.loops:
		var l: AKLoop = built.loops[key]
		var lp := dir + "loops/%s.tres" % l.resource_name
		if ResourceSaver.save(l, lp) != OK:
			res.error = "couldn't save %s" % lp
			return res
		l.take_over_path(lp)
		loop_path[key] = lp
		res.loops.append(lp)
	res.loop_paths = loop_path
	res.track_of = built.track_of
	# Point scenes and clips at the saved files.
	for s: Dictionary in arr.scenes:
		var clips: Dictionary = s.clips
		for t: Variant in clips.keys():
			clips[t] = loop_path[String(clips[t])]
	for c: Dictionary in arr.timeline:
		c["loop"] = loop_path[String(c.loop)]

	var meta: Dictionary = arr.get_meta(&"auxy")
	if bool(options.get("stems", true)):
		var zip := ZIPReader.new()
		if zip.open(path) == OK:
			var used := {}
			for c: Dictionary in arr.timeline:
				used[String(c.track)] = true
			for ci: int in model.stems:
				if not built.track_of.has(ci) or not used.has(String(built.track_of[ci])):
					continue   # a channel the song doesn't play: its stem is silence
				var tn := String(built.track_of[ci])
				var sp := dir + "stems/%s/%s.wav" % [base, slug(tn)]
				DirAccess.make_dir_recursive_absolute(sp.get_base_dir())
				var f := FileAccess.open(sp, FileAccess.WRITE)
				if f == null:
					res.warnings.append("couldn't write %s" % sp)
					continue
				f.store_buffer(zip.read_file(String(model.stems[ci])))
				f.close()
				res.stems[tn] = sp
			zip.close()
		meta["stems"] = res.stems.duplicate()
	arr.set_meta(&"auxy", meta)

	var ap := dir + "arrangements/%s.tres" % base
	if ResourceSaver.save(arr, ap) != OK:
		res.error = "couldn't save %s" % ap
		return res
	arr.take_over_path(ap)
	AK.refresh_editor_files()
	res.arrangement = arr
	res.path = ap
	res.ok = true
	return res


## The model as an arrangement whose scenes and clips name loops by key
## ("<c>_<s>"); the loops and kits it needs are in its meta `auxy_build`
## ({loops: {key: AKLoop}, kits: {channel: AKKit}, track_of: {channel: track name}}).
## import_file saves them and swaps the keys for paths.
static func to_arrangement(model: Dictionary, options := {}, warnings: Array = []) -> AKArrangement:
	var arr := AKArrangement.new()
	arr.tempo = AKTempoMap.make(float(model.bpm), BEATS_PER_BAR)
	var base := String(options.get("name", ""))
	if base == "":
		base = slug(String(model.title))

	# Tracks: one per channel with loops, named after Auxy's preset (made unique).
	var has_loops := {}
	for key: String in model.loops:
		has_loops[int(model.loops[key].channel)] = true
	var track_of := {}
	var used_names := {}
	for ci in model.channels.size():
		var ch: Dictionary = model.channels[ci]
		if not has_loops.has(ci):
			warnings.append("channel %d (%s) has no loops: left out" % [ci + 1, ch.label])
			continue
		var tn := String(ch.label).strip_edges()
		if tn == "":
			tn = "drums" if ch.kind == "drums" else "track %d" % (ci + 1)
		var unique := tn
		var n := 2
		while used_names.has(unique):
			unique = "%s %d" % [tn, n]
			n += 1
		used_names[unique] = true
		track_of[ci] = unique
		arr.tracks.append({name = unique, color = ch.color})

	# Instruments: a kit per drum channel, a patch per instrument channel.
	var kits := {}
	var patch_of := {}
	for ci: int in track_of:
		var ch: Dictionary = model.channels[ci]
		var keys := _channel_loops(model, ci)
		if ch.kind == "drums":
			var top := 0
			for key: String in keys:
				for nt: Array in model.loops[key].notes:
					top = maxi(top, int(nt[2]) - DRUM_BASE_NOTE)
			# A kit given or cut from Auxy's sounds (kit_from_pads) first, then a pad map, then the base kit.
			var given: Dictionary = options.get("kits", {})
			var kv: Variant = given.get(ci, given.get(String(ch.label), null))
			if kv == null and options.has("save_dir"):
				var sp := sample_kit_path(String(options.save_dir), String(ch.label))
				if sp != "":
					kv = sp
			if (kv is String or kv is StringName) and ResourceLoader.exists(String(kv)):
				kv = load(String(kv))
			if kv is AKKit:
				kits[ci] = kv
				if top + 1 > (kv as AKKit).pieces.size():
					warnings.append("%s plays pad %d; its kit %s has %d pieces (the extra pads are silent)" % [track_of[ci], top + 1, (kv as AKKit).resource_path, (kv as AKKit).pieces.size()])
				continue
			var maps: Dictionary = options.get("drum_maps", {})
			var pads: Variant = maps.get(ci, maps.get(String(ch.label), KIT_MAPS.get(String(ch.label).to_lower().strip_edges())))
			var kit := _kit_from_pads(pads, top + 1) if pads is Array else _kit_for(options.get("kit", "punch"), top + 1)
			if pads is Array and top + 1 > (pads as Array).size():
				warnings.append("%s plays pad %d; the %s map knows %d pads (the rest are copies of the base kit's)" % [track_of[ci], top + 1, ch.label, (pads as Array).size()])
			kit.resource_name = "%s %s" % [base, track_of[ci]]
			kits[ci] = kit
		else:
			patch_of[ci] = _patch_for(model, ci, keys, options.get("patches", {}), warnings)

	# Loops, numbered per track in Auxy's slot order.
	var loops := {}
	for ci: int in track_of:
		var nth := 0
		for key: String in _channel_loops(model, ci):
			nth += 1
			var lp: Dictionary = model.loops[key]
			var l := AKLoop.new()
			l.bars = loop_bars(lp)
			l.beats_per_bar = BEATS_PER_BAR
			l.resource_name = "%s_%s_%d" % [base, slug(String(track_of[ci])), nth]
			if model.channels[ci].kind == "drums":
				l.kind = "percussive"
				l.instrument = kits[ci]
				l.category = "beat"
			else:
				l.kind = "synth"
				l.instrument = patch_of[ci]
				l.category = String((patch_of[ci] as AKPatch).category) if patch_of[ci] is AKPatch else ""
			for nt: Array in lp.notes:
				var row := int(nt[2]) - DRUM_BASE_NOTE if l.kind == "percussive" else int(nt[2])
				if row < 0:
					warnings.append("%s: drum note %d is below the first pad (%d): dropped" % [l.resource_name, nt[2], DRUM_BASE_NOTE])
					continue
				l.notes.append([roundi(float(nt[0]) * AKLoop.TICKS_PER_BEAT), maxi(1, roundi(float(nt[1]) * AKLoop.TICKS_PER_BEAT)), row, snappedf(float(nt[3]), 0.001)])
			loops[key] = l

	# Scenes: one per distinct set of loops, in the order the song first plays them.
	var scene_of := {}
	for sc: Dictionary in model.scenes:
		var sig := _signature(sc.loops)
		if sig == "" or scene_of.has(sig):
			continue
		var clips := {}
		for key: String in sc.loops:
			clips[track_of[int(model.loops[key].channel)]] = key
		scene_of[sig] = "scene %d" % (arr.scenes.size() + 1)
		arr.scenes.append({name = scene_of[sig], bars = 0.0, clips = clips})

	# Timeline: Auxy's scenes in order. A clip carries on while the same loop
	# keeps playing in phase; a loop that restarts (a new scene that starts it
	# from the top) starts a new clip.
	var open := {}   # track -> the clip being extended
	var bar := 0
	var last_sig := "\u0001"
	var marker_names := {}
	for sc: Dictionary in model.scenes:
		var sig := _signature(sc.loops)
		if sig != last_sig:
			var mn := String(scene_of.get(sig, "silence"))
			var k := 2
			var unique := mn
			while marker_names.has(unique):
				unique = "%s (%d)" % [mn, k]
				k += 1
			marker_names[unique] = true
			arr.markers.append({name = unique, bar = float(bar)})
			last_sig = sig
		var playing := {}
		for key: String in sc.loops:
			var lp: Dictionary = model.loops[key]
			var tn := String(track_of[int(lp.channel)])
			var L := loop_bars(lp)
			var phase := int(sc.start_offset) % L
			playing[tn] = true
			var c: Variant = open.get(tn)
			if c != null and String(c.loop) == key and int(float(c.bar) + float(c.bars)) == bar \
					and (int(c.offset_bars) + int(c.bars)) % L == phase:
				c.bars = float(c.bars) + float(sc.bars)
			else:
				var clip := {track = tn, loop = key, bar = float(bar), bars = float(sc.bars), offset_bars = float(phase)}
				arr.timeline.append(clip)
				open[tn] = clip
		for tn: Variant in open.keys():
			if not playing.has(tn):
				open.erase(tn)
		bar += int(sc.bars)
	arr.length_bars = float(bar)

	arr.set_meta(&"auxy", {title = model.title, scale = model.scale, creator = model.creator, bpm = model.bpm,
		format_version = model.format_version, channels = model.channels.map(func(c: Dictionary) -> Dictionary: return {label = c.label, kind = c.kind})})
	arr.set_meta(&"auxy_build", {loops = loops, kits = kits, track_of = track_of})
	return arr


## A file-name-safe lower-case name: "Hexedex - Not So Bad" -> "hexedex_not_so_bad".
static func slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


static func _channel_loops(model: Dictionary, ci: int) -> Array:
	var keys := []
	for key: String in model.loops:
		if int(model.loops[key].channel) == ci:
			keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(model.loops[a].slot) < int(model.loops[b].slot))
	return keys


static func _signature(keys: Array) -> String:
	var s := keys.duplicate()
	s.sort()
	return ",".join(s)


## A kit of `pieces` pieces, piece n a copy of the base kit's piece n (wrapping, renamed to stay unique).
static func _kit_for(base: Variant, pieces: int) -> AKKit:
	var src: AKKit = null
	if base is AKKit:
		src = base
	elif String(base).begins_with("res://") and ResourceLoader.exists(String(base)):
		src = load(String(base)) as AKKit
	else:
		src = AKLibrary.kit(String(base))
	if src == null:
		src = AKLibrary.kit("punch")
	var kit := AKKit.new()
	kit.category = "auxy"
	var names := {}
	for i in maxi(1, pieces):
		var p: Dictionary = src.pieces[i % src.pieces.size()].duplicate(true)
		var nm := String(p.get("name", "pad"))
		var unique := nm
		var n := 2
		while names.has(unique):
			unique = "%s_%d" % [nm, n]
			n += 1
		names[unique] = true
		p["name"] = unique
		kit.pieces.append(p)
	return kit


## A kit with a piece per known pad (and the base kit's pieces past the
## map's end, so every pad played has a sound).
static func _kit_from_pads(pads: Array, needed: int) -> AKKit:
	var kit := AKKit.new()
	kit.category = "auxy"
	for p: Dictionary in pads:
		kit.pieces.append(p.duplicate(true))
	if needed > pads.size():
		var rest := _kit_for("punch", needed)
		var names := {}
		for p: Dictionary in kit.pieces:
			names[String(p.name)] = true
		for i in range(pads.size(), needed):
			var q: Dictionary = rest.pieces[i].duplicate(true)
			while names.has(String(q.name)):
				q.name = String(q.name) + "_2"
			names[String(q.name)] = true
			kit.pieces.append(q)
	return kit


## The patch for an instrument channel: `choices` by channel index or label,
## else a preset by words in Auxy's preset name, else by the notes' register.
static func _patch_for(model: Dictionary, ci: int, keys: Array, choices: Dictionary, warnings: Array) -> AKPatch:
	var label := String(model.channels[ci].label)
	var pick: Variant = choices.get(ci, choices.get(label, null))
	if pick is AKPatch:
		return pick
	var name := ""
	if pick != null:
		name = String(pick)
	else:
		var low := label.to_lower()
		for rule: Array in PATCH_WORDS:
			for w: String in rule[0]:
				if low.contains(w):
					name = rule[1]
					break
			if name != "":
				break
		if name == "":
			var keys_played := []
			for key: String in keys:
				for nt: Array in model.loops[key].notes:
					keys_played.append(int(nt[2]))
			keys_played.sort()
			var mid := int(keys_played[keys_played.size() / 2]) if not keys_played.is_empty() else 60
			name = "wavetable_bass" if mid < 48 else ("pluck" if mid < 76 else "fm_bell")
	var path := name if name.begins_with("res://") else AKPatchLib.PRESET_DIR + name + ".tres"
	var p: AKPatch = load(path) as AKPatch if ResourceLoader.exists(path) else null
	if p == null:
		warnings.append("no patch %s for %s: using pluck" % [name, label])
		p = load(AKPatchLib.PRESET_DIR + "pluck.tres")
	return p
