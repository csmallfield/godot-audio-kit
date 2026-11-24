# SPDX-License-Identifier: Apache-2.0
# Drum samples: the AIFF reader and format sniffing, stereo samples (stored,
# played and placed), and kit pieces with velocity layers and round-robin
# takes.
extends RefCounted

const SR := 48000
const TMP := "user://test_drum_samples/"


func _sample(l: PackedFloat32Array, r := PackedFloat32Array(), root := 60.0, mode := "oneshot") -> AKSample:
	var s := AKSample.new()
	s.data = l
	s.data_r = r
	s.data_rate = SR
	s.root_note = root
	s.mode = mode
	return s


func _tone(hz: float, seconds: float, amp := 0.5) -> PackedFloat32Array:
	var n := roundi(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = amp * sin(TAU * hz * i / SR) * (1.0 - float(i) / n)
	return out


func _const(v: float, frames := 400) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	out.fill(v)
	return out


# ------------------------------------------------------------------ AIFF

## AIFF (or AIFF-C with `comp`) bytes: `vals` on the left, half of them on
## the right when two channels; an INST base note and sustain loop when given.
func _aiff_bytes(bits: int, vals: Array, ch: int, rate: int, comp := "", root := -1, loop: Array = []) -> PackedByteArray:
	var is_float := comp.to_lower() in ["fl32", "fl64"]
	var w := (bits + 7) / 8
	var pcm := PackedByteArray()
	for v in vals:
		for c in ch:
			var x := float(v) * (1.0 if c == 0 else 0.5)
			var le := PackedByteArray()
			le.resize(w)
			if is_float:
				if w == 4:
					le.encode_float(0, x)
				else:
					le.encode_double(0, x)
			elif w == 1:
				le[0] = clampi(roundi(x * 128.0), -128, 127) & 0xFF
			elif w == 2:
				le.encode_s16(0, clampi(roundi(x * 32768.0), -32768, 32767))
			elif w == 3:
				var iv := clampi(roundi(x * 8388608.0), -8388608, 8388607)
				if iv < 0:
					iv += 16777216
				le[0] = iv & 255
				le[1] = (iv >> 8) & 255
				le[2] = (iv >> 16) & 255
			else:
				le.encode_s32(0, clampi(roundi(x * 2147483648.0), -2147483648, 2147483647))
			if comp != "sowt":
				le.reverse()
			pcm.append_array(le)
	var comm := PackedByteArray()
	comm.resize(18)
	_put16(comm, 0, ch)
	_put32(comm, 2, vals.size())
	_put16(comm, 6, bits)
	var ext := _ext80(rate)
	for i in 10:
		comm[8 + i] = ext[i]
	if comp != "":
		comm.append_array(comp.to_ascii_buffer())
		comm.append_array(PackedByteArray([0, 0]))   # empty pstring name, padded
	var ssnd := PackedByteArray()
	ssnd.resize(8)
	ssnd.append_array(pcm)
	var out := "FORM".to_ascii_buffer()
	out.resize(8)
	out.append_array(("AIFC" if comp != "" else "AIFF").to_ascii_buffer())
	out.append_array(_be_chunk("COMM", comm))
	if root >= 0:
		var mark := PackedByteArray()
		mark.resize(2)
		_put16(mark, 0, 2)
		for m in 2:
			var e := PackedByteArray()
			e.resize(6)
			_put16(e, 0, m + 1)
			_put32(e, 2, int(loop[m]))
			e.append_array(PackedByteArray([1, 65 + m]))   # pstring "A"/"B", even length
			mark.append_array(e)
		out.append_array(_be_chunk("MARK", mark))
		var inst := PackedByteArray()
		inst.resize(20)
		inst[0] = root
		_put16(inst, 8, 1)    # sustain loop: forward
		_put16(inst, 10, 1)
		_put16(inst, 12, 2)
		out.append_array(_be_chunk("INST", inst))
	out.append_array(_be_chunk("SSND", ssnd))
	_put32(out, 4, out.size() - 8)
	return out


func _put16(b: PackedByteArray, o: int, v: int) -> void:
	b[o] = (v >> 8) & 255
	b[o + 1] = v & 255


func _put32(b: PackedByteArray, o: int, v: int) -> void:
	for k in 4:
		b[o + k] = (v >> (24 - 8 * k)) & 255


## An integer rate as an 80-bit extended float.
func _ext80(rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(10)
	var e := 0
	while (1 << (e + 1)) <= rate:
		e += 1
	var exp := 16383 + e
	out[0] = (exp >> 8) & 0x7F
	out[1] = exp & 255
	var mant := rate << (31 - e)   # top 32 bits of the 64-bit mantissa
	_put32(out, 2, mant)
	return out


func _be_chunk(id: String, body: PackedByteArray) -> PackedByteArray:
	var c := id.to_ascii_buffer()
	c.resize(8)
	_put32(c, 4, body.size())
	c.append_array(body)
	if body.size() & 1:
		c.append(0)
	return c


func test_aiff_reader() -> String:
	var vals := [0.0, 0.5, -0.5, 0.25, -1.0, 0.999]
	for spec in [[8, ""], [16, ""], [24, ""], [32, ""], [16, "NONE"], [16, "sowt"], [24, "sowt"], [32, "fl32"], [64, "fl64"]]:
		var bits := int(spec[0])
		var comp := String(spec[1])
		var g := AKAudioFile.from_aiff_bytes(_aiff_bytes(bits, vals, 2, 39579, comp))
		if g.error != "" or g.rate != 39579 or g.channels != 2 or g.data.size() != vals.size():
			return "AIFF %s: %s, %d Hz, %d frames" % [spec, g.error, g.rate, g.data.size()]
		var tol := 1.0 / 128.0 if bits == 8 else (1.0 / 32768.0 if bits == 16 else 1e-6)
		for i in vals.size():
			var v := float(vals[i])
			if absf(g.left[i] - v) > tol or absf(g.right[i] - 0.5 * v) > tol or absf(g.data[i] - 0.75 * v) > tol:
				return "AIFF %s frame %d: L %.6f R %.6f, want %.6f %.6f" % [spec, i, g.left[i], g.right[i], v, 0.5 * v]
	var mono := AKAudioFile.from_aiff_bytes(_aiff_bytes(16, vals, 1, 22050))
	if mono.error != "" or mono.channels != 1 or not mono.left.is_empty() or absf(mono.data[1] - 0.5) > 1e-4:
		return "mono AIFF: %s, %d ch" % [mono.error, mono.channels]
	var inst := AKAudioFile.from_aiff_bytes(_aiff_bytes(16, vals, 1, 44100, "", 62, [1, 5]))
	if inst.root_note != 62 or inst.loop != PackedInt32Array([1, 5]):
		return "INST chunk: root %d loop %s" % [inst.root_note, inst.loop]
	if AKAudioFile.from_aiff_bytes(_aiff_bytes(16, vals, 1, 44100, "ima4")).error == "":
		return "a compressed AIFF-C should say it can't be read"
	if AKAudioFile.from_aiff_bytes(PackedByteArray([70, 79, 82, 77])).error == "":
		return "garbage should fail"
	return ""


func test_files_are_told_by_content_not_extension() -> String:
	DirAccess.make_dir_recursive_absolute(TMP)
	var vals := [0.0, 0.5, -0.5, 0.25]
	# An AIFF named .wav (the Roland SPD-8 set ships like this), and .aif.
	for name in ["misnamed.wav", "real.aif", "no_extension"]:
		var f := FileAccess.open(TMP + name, FileAccess.WRITE)
		f.store_buffer(_aiff_bytes(16, vals, 1, 30000))
		f.close()
		var got := AKAudioFile.read(TMP + name)
		if got.error != "" or got.rate != 30000 or absf(got.data[1] - 0.5) > 1e-4:
			return "%s: %s" % [name, got.error]
	var junk := FileAccess.open(TMP + "junk.wav", FileAccess.WRITE)
	junk.store_buffer("not audio at all".to_ascii_buffer())
	junk.close()
	if AKAudioFile.read(TMP + "junk.wav").error == "":
		return "junk with a .wav name should fail"
	if not AKAudioFile.is_audio_ext("AIFF") or AKAudioFile.is_audio_ext("txt"):
		return "is_audio_ext"
	# A sample imports from an AIFF like any file.
	var s := AKSample.new()
	s.source = TMP + "misnamed.wav"
	var err := s.import_source()
	if err != "" or s.data_rate != 30000 or s.data.size() != vals.size():
		return "importing an AIFF: %s" % err
	return ""


# ------------------------------------------------------------------ stereo

func test_stereo_samples_are_kept() -> String:
	DirAccess.make_dir_recursive_absolute(TMP)
	var l := _tone(220.0, 0.1)
	var r := _tone(330.0, 0.1, 0.3)
	var buf := AKBuffer.new(0, SR)
	buf.l = l
	buf.r = r
	buf.save_wav(TMP + "st.wav")
	var f := AKAudioFile.read(TMP + "st.wav")
	if f.error != "" or f.left.size() != l.size() or f.right.size() != r.size():
		return "stereo WAV channels: %s" % f.error
	var s := AKSample.new()
	s.source = TMP + "st.wav"
	if s.import_source() != "" or not s.is_stereo() or s.data_r.size() != r.size():
		return "a stereo file should import as stereo"
	var worst := 0.0
	for i in l.size():
		worst = maxf(worst, maxf(absf(s.data[i] - l[i]), absf(s.data_r[i] - r[i])))
	if worst > 4.0 / 32768.0:
		return "stereo channels off by %.6f" % worst
	var m: PackedFloat32Array = s.samples()[0]
	if absf(m[100] - 0.5 * (s.data[100] + s.data_r[100])) > 1e-7:
		return "samples() should be the mono mix of a stereo sample"
	# Identical channels: kept mono (half the storage, same sound).
	var pcm := PackedByteArray()
	pcm.resize(l.size() * 4)
	for i in l.size():
		var v := clampi(roundi(l[i] * 32767.0), -32768, 32767)
		pcm.encode_s16(4 * i, v)
		pcm.encode_s16(4 * i + 2, v)
	var hdr := "RIFF".to_ascii_buffer()
	hdr.resize(8)
	hdr.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 2)
	fmt.encode_u32(8, SR)
	fmt.encode_u32(12, SR * 4)
	fmt.encode_u16(16, 4)
	fmt.encode_u16(18, 16)
	hdr.append_array(fmt)
	hdr.append_array("data".to_ascii_buffer())
	var dl := PackedByteArray()
	dl.resize(4)
	dl.encode_u32(0, pcm.size())
	hdr.append_array(dl)
	hdr.append_array(pcm)
	hdr.encode_u32(4, hdr.size() - 8)
	var df := FileAccess.open(TMP + "dual.wav", FileAccess.WRITE)
	df.store_buffer(hdr)
	df.close()
	var d := AKSample.new()
	d.source = TMP + "dual.wav"
	d.import_source()
	if d.is_stereo() or not d.data_r.is_empty():
		return "a file with identical channels should be kept mono"
	# A recipe sample stays mono.
	if AKSample.from_recipe(AKRecipe.make(&"pluck", {freq_hz = 220.0})).is_stereo():
		return "recipe samples are mono"
	return ""


func test_stereo_samples_play_in_stereo() -> String:
	var l := _tone(220.0, 0.1)
	var r := _tone(330.0, 0.1, 0.3)
	var st := _sample(l, r)
	var both := AK.render(st.to_recipe(), 0.8)
	var only_l := AK.render(_sample(l).to_recipe(), 0.8)
	var only_r := AK.render(_sample(r).to_recipe(), 0.8)
	if both.frames() != only_l.frames():
		return "length %d vs %d" % [both.frames(), only_l.frames()]
	# The mono path plays a centred signal at full level on both sides, so
	# each channel of the stereo render is that channel's mono render.
	for i in both.frames():
		if both.l[i] != only_l.l[i] or both.r[i] != only_r.r[i]:
			return "frame %d: stereo (%.6f, %.6f), channels alone (%.6f, %.6f)" % [i, both.l[i], both.r[i], only_l.l[i], only_r.r[i]]
	# A layer's pan is a balance on a stereo sound: right turns the left down.
	var rec := AKRecipe.new()
	rec.layers = [{voice = &"sample", params = {sample = st, freq_hz = st.root_hz()}, pan = 0.5}]
	var panned := AK.render(rec)
	if absf(panned.l[200] - 0.5 * both.l[200] / 0.8) > 1e-6 or absf(panned.r[200] - both.r[200] / 0.8) > 1e-6:
		return "balance: %.6f %.6f" % [panned.l[200], panned.r[200]]
	# Mono samples render as they always have (same both sides).
	if only_l.l[300] != only_l.r[300]:
		return "a mono sample should stay centred"
	# Reversed, gated and retuned stereo plays both channels alike.
	var g := _sample(l, r, 60.0, "gate")
	g.reverse = true
	var gb := AK.render(g.to_recipe(), 1.0, {}, 0, {_gate_s = 0.05, _note_hz = 440.0})
	var gl := _sample(l, PackedFloat32Array(), 60.0, "gate")
	gl.reverse = true
	var glb := AK.render(gl.to_recipe(), 1.0, {}, 0, {_gate_s = 0.05, _note_hz = 440.0})
	if gb.frames() != glb.frames() or gb.l[500] != glb.l[500]:
		return "a gated, reversed, retuned stereo sample's left should match the mono one"
	return ""


func test_stereo_changes_the_bake_key() -> String:
	var l := _tone(220.0, 0.05)
	var s := _sample(l)
	var mono_key := AK.bake_key(s.to_recipe())
	if String(s.describe().sound.data) != AKSample._hash(l):
		return "a mono sample's content key should be what it always was"
	s.data_r = _tone(300.0, 0.05)
	if AK.bake_key(s.to_recipe()) == mono_key:
		return "adding a right channel should change the bake key"
	var k := AK.bake_key(s.to_recipe())
	s.data_r = _tone(310.0, 0.05)
	if AK.bake_key(s.to_recipe()) == k:
		return "a new right channel should change the bake key"
	return ""


# ------------------------------------------------------------------ layers

## A kit of one piece; `piece` gives its keys.
func _kit_of(piece: Dictionary) -> AKKit:
	var k := AKKit.new()
	piece.name = "snare"
	k.pieces = [piece]
	return k


## The level mid-sound of a render: which constant-valued take played, and
## how loud.
func _mid(buf: AKBuffer) -> float:
	return buf.l[buf.frames() / 2]


func test_velocity_layers_pick_by_velocity() -> String:
	var soft := _sample(_const(0.1))
	var mid := _sample(_const(0.2))
	var hard := _sample(_const(0.4))
	# Given out of order: sorted softest first.
	var kit := _kit_of({layers = [{sound = hard, up_to = 1.0}, {sound = soft, up_to = 0.3}, {sound = mid, up_to = 0.7}]})
	var ls := kit.piece_layers(0)
	if ls.size() != 3 or float(ls[0].up_to) != 0.3 or float(ls[2].up_to) != 1.0:
		return "layers should be sorted softest first"
	if kit.piece_sample(0) != hard:
		return "the representative sample is the top layer's"
	var r := kit.piece_recipe(0)
	for c in [[0.2, 0.1], [0.3, 0.1], [0.5, 0.2], [0.7, 0.2], [0.71, 0.4], [1.0, 0.4]]:
		var v := float(c[0])
		var got := _mid(AK.render(r, v))
		var want := float(c[1]) * v      # the layer's level, scaled by velocity
		if absf(got - want) > 1e-5:
			return "velocity %.2f: %.5f, want %.5f" % [v, got, want]
	if AK.bake_key(r, 0.2) == AK.bake_key(r, 0.9):
		return "different velocities should bake apart"
	# A top below 1.0 still takes louder hits.
	var capped := _kit_of({layers = [{sound = soft, up_to = 0.3}, {sound = mid, up_to = 0.6}]})
	if absf(_mid(AK.render(capped.piece_recipe(0), 0.9)) - 0.2 * 0.9) > 1e-5:
		return "velocities above the top layer should play the top layer"
	return ""


func test_round_robin_cycles_takes() -> String:
	var a := _sample(_const(0.1))
	var b := _sample(_const(0.2))
	var c := _sample(_const(0.3))
	var kit := _kit_of({sound = [a, b, c]})
	var r := kit.piece_recipe(0)
	if r.round_robin != 3:
		return "three takes: round_robin %d" % r.round_robin
	var want := [0.1, 0.2, 0.3, 0.1, 0.2, 0.3]
	for hit in want.size():
		var got := _mid(AK.render(r, 1.0, {}, hit))
		if absf(got - float(want[hit])) > 1e-5:
			return "hit %d: %.5f, want %.2f" % [hit, got, want[hit]]
	if AK.bake_key(r, 1.0, {}, 0) != AK.bake_key(r, 1.0, {}, 3) or AK.bake_key(r, 1.0, {}, 0) == AK.bake_key(r, 1.0, {}, 1):
		return "hits a cycle apart should share a bake, others not"
	# Layers with 2 and 3 takes cycle every 6 hits; each layer cycles its own.
	var kit2 := _kit_of({layers = [{sound = [a, b], up_to = 0.5}, {sound = [a, b, c], up_to = 1.0}]})
	var r2 := kit2.piece_recipe(0)
	if r2.round_robin != 6:
		return "2 and 3 takes: round_robin %d, want 6" % r2.round_robin
	for hit in 6:
		var soft := _mid(AK.render(r2, 0.5, {}, hit))
		var loud := _mid(AK.render(r2, 1.0, {}, hit))
		if absf(soft - 0.5 * [0.1, 0.2][hit % 2]) > 1e-5 or absf(loud - [0.1, 0.2, 0.3][hit % 3]) > 1e-5:
			return "hit %d: soft %.5f loud %.5f" % [hit, soft, loud]
	# Through a song, hits on a lane count up: a loop of four plays a b c a.
	var loop := AKLoop.new()
	loop.kind = "percussive"
	loop.instrument = kit
	loop.bars = 1
	for k in 4:
		loop.add_note(k * AKLoop.TICKS_PER_BEAT, 12, 0, 1.0)
	var song := AKSong.new()
	song.tempo = AKTempoMap.new()
	song.tempo.bpm = 120.0
	song.master_fx = []
	song.sections = [{name = "a", bars = 1, patterns = [loop.to_pattern()]}]
	var mix: AKBuffer = song.render(false, false).mix
	var beat := SR / 2
	for k in 4:
		var v := mix.l[k * beat + 200]
		if absf(v - float(want[k])) > 1e-4:
			return "song hit %d: %.5f, want %.2f" % [k, v, want[k]]
	return ""


func test_layered_pieces_keep_kit_behaviour() -> String:
	var soft := _sample(_const(0.1, 4800))
	var hard := _sample(_const(0.4, 4800))
	# Gated: every take plays gated.
	var kit := _kit_of({layers = [{sound = soft, up_to = 0.5}, {sound = [hard, soft], up_to = 1.0}], gate = true, tune_semitones = 12.0})
	var r := kit.piece_recipe(0)
	for l: Dictionary in r.params.layers:
		var takes: Array = l.sample if l.sample is Array else [l.sample]
		for t: AKSample in takes:
			if t.mode != "gate":
				return "a gated piece's takes should be gated"
	# Tuned up an octave: twice as fast, half as long.
	var plain := AK.render(_kit_of({sound = hard}).piece_recipe(0))
	var up := AK.render(_kit_of({layers = [{sound = soft, up_to = 0.5}, {sound = hard, up_to = 1.0}], tune_semitones = 12.0}).piece_recipe(0))
	if absi(up.frames() * 2 - plain.frames()) > 4:
		return "tuning: %d frames, plain %d" % [up.frames(), plain.frames()]
	# describe() lists the layers; a plain piece's has no layers key.
	if not (kit.describe().pieces[0] as Dictionary).has("layers"):
		return "a layered piece's describe should list its layers"
	if (_kit_of({sound = hard}).describe().pieces[0] as Dictionary).has("layers"):
		return "a plain piece's describe should be as before"
	if kit.piece_take_count(0) != 3:
		return "take count %d" % kit.piece_take_count(0)
	# Paths work as takes, and a recipe sound in a layer is wrapped.
	var rec := AKRecipe.make(&"pluck", {freq_hz = 220.0})
	var mixed := _kit_of({layers = [{sound = rec, up_to = 0.5}, {sound = hard, up_to = 1.0}]})
	if mixed.piece_layers(0).size() != 2 or AK.render(mixed.piece_recipe(0), 0.3).frames() == 0:
		return "a recipe layer should play"
	# A piece with nothing playable has no recipe.
	if _kit_of({layers = [{sound = null, up_to = 1.0}]}).piece_layers(0).size() != 0:
		return "empty layers are dropped"
	return ""


func test_stereo_takes_in_layers() -> String:
	var l := _tone(220.0, 0.05)
	var r := _tone(330.0, 0.05, 0.3)
	var kit := _kit_of({layers = [{sound = _sample(_const(0.1, 2400)), up_to = 0.5}, {sound = _sample(l, r), up_to = 1.0}]})
	var rec := kit.piece_recipe(0)
	var loud := AK.render(rec, 1.0)
	var soft := AK.render(rec, 0.4)
	if loud.l[100] == loud.r[100]:
		return "the stereo layer should play in stereo"
	if soft.l[100] != soft.r[100]:
		return "the mono layer should play centred"
	return ""
