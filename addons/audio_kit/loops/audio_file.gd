# SPDX-License-Identifier: Apache-2.0
@tool
## Reads audio files sample by sample, for AKSample. Godot imports project
## audio into streams the kit can't read back (often compressed), so this
## reads the source file itself:
##
## - **WAV**: the kit's own reader. PCM at 8, 16, 24 or 32 bits, 32- or 64-bit
##   float, plain or WAVE_FORMAT_EXTENSIBLE, any channel count and rate. A
##   `smpl` chunk's unity note and first loop are reported too.
## - **AIFF / AIFF-C**: PCM at 8, 16, 24 or 32 bits (big-endian, or
##   little-endian `sowt`), 32- or 64-bit float (`fl32`, `fl64`). An `INST`
##   chunk's base note and sustain loop are reported too.
## - **OGG Vorbis**: Godot's own decoder (AudioStreamOggVorbis.load_from_file),
##   pulled through its playback at exactly one source sample per output
##   sample, which reproduces the decoded samples to float rounding.
##
## The format is told by the file's first bytes, not its extension, so an
## AIFF file named .wav (as some sample packs ship) still reads.
##
##   var f := AKAudioFile.read("res://audio/kick_01.wav")
##   if f.error == "":
##       print(f.rate, " Hz, ", f.channels, " channels, ", f.data.size(), " frames")
##
## `data` is mono: the mean of the channels. A two-channel file also fills
## `left` and `right` (empty otherwise), for stereo samples.
class_name AKAudioFile
extends RefCounted

## Frames the Vorbis playback holds back at its start (its interpolator's
## history), dropped so the data starts on the file's first sample. Pinned by
## tests/test_loops.gd against a reference decode.
const OGG_LEAD_FRAMES := 2

var data := PackedFloat32Array()
## The channels of a two-channel file (empty for mono or more channels).
var left := PackedFloat32Array()
var right := PackedFloat32Array()
var rate := 0
var channels := 0
var bits := 0
## "" when the file read; otherwise what went wrong.
var error := ""
## From a WAV `smpl` or AIFF `INST` chunk: the unity (root) note, -1 when absent.
var root_note := -1
## From a WAV `smpl` or AIFF `INST` chunk: the first (sustain) loop in frames,
## [start, end] (end exclusive), empty when absent.
var loop := PackedInt32Array()


## Read a .wav, .aif(f) or .ogg (res://, user:// or an absolute path).
static func read(path: String) -> AKAudioFile:
	var f := AKAudioFile.new()
	if not FileAccess.file_exists(path):
		f.error = "no file at %s" % path
		return f
	var head := PackedByteArray()
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa:
		head = fa.get_buffer(12)
		fa.close()
	match sniff(head):
		"wav":
			f._read_wav(FileAccess.get_file_as_bytes(path))
		"aiff":
			f._read_aiff(FileAccess.get_file_as_bytes(path))
		"ogg":
			f._read_ogg(path)
		_:
			f.error = "can't read %s (WAV, AIFF and OGG Vorbis only)" % path.get_file()
	return f


## The format of a file from its first 12 bytes: "wav", "aiff", "ogg" or "".
static func sniff(head: PackedByteArray) -> String:
	if head.size() >= 4 and head.slice(0, 4).get_string_from_ascii() == "OggS":
		return "ogg"
	if head.size() < 12:
		return ""
	var a := head.slice(0, 4).get_string_from_ascii()
	var b := head.slice(8, 12).get_string_from_ascii()
	if a == "RIFF" and b == "WAVE":
		return "wav"
	if a == "FORM" and (b == "AIFF" or b == "AIFC"):
		return "aiff"
	return ""


## True for the extensions of the sound files this reader takes.
static func is_audio_ext(ext: String) -> bool:
	return ext.to_lower() in ["wav", "wave", "ogg", "oga", "aif", "aiff", "aifc"]


## Parse WAV bytes (exposed for tests).
static func from_wav_bytes(bytes: PackedByteArray) -> AKAudioFile:
	var f := AKAudioFile.new()
	f._read_wav(bytes)
	return f


## Parse AIFF or AIFF-C bytes (exposed for tests).
static func from_aiff_bytes(bytes: PackedByteArray) -> AKAudioFile:
	var f := AKAudioFile.new()
	f._read_aiff(bytes)
	return f


func _read_wav(b: PackedByteArray) -> void:
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		error = "not a RIFF WAVE file"
		return
	var fmt := -1
	var block := 0
	var data_at := -1
	var data_len := 0
	var pos := 12
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		var body := pos + 8
		match id:
			"fmt ":
				if size < 16 or body + 16 > b.size():
					error = "short fmt chunk"
					return
				fmt = b.decode_u16(body)
				channels = b.decode_u16(body + 2)
				rate = b.decode_u32(body + 4)
				block = b.decode_u16(body + 12)
				bits = b.decode_u16(body + 14)
				if fmt == 0xFFFE and size >= 40 and body + 26 <= b.size():
					fmt = b.decode_u16(body + 24)   # the sub-format GUID starts with the format tag
			"data":
				data_at = body
				data_len = mini(size, b.size() - body)   # a cut-off file keeps what's there
			"smpl":
				if size >= 36 and body + 36 <= b.size():
					var unity := b.decode_u32(body + 12)
					root_note = unity if unity <= 127 else -1   # some packs write garbage here
					var loops := b.decode_u32(body + 28)
					if loops > 0 and size >= 60 and body + 60 <= b.size():
						loop = PackedInt32Array([b.decode_u32(body + 44), b.decode_u32(body + 48) + 1])
		pos = body + size + (size & 1)
	if fmt < 0:
		error = "no fmt chunk"
		return
	if data_at < 0:
		error = "no data chunk"
		return
	if channels < 1 or rate < 1:
		error = "bad format (%d channels at %d Hz)" % [channels, rate]
		return
	var width := bits / 8
	var ok := (fmt == 1 and width in [1, 2, 3, 4]) or (fmt == 3 and width in [4, 8])
	if not ok:
		error = "unsupported WAV encoding (format %d, %d bits); save it as PCM or float" % [fmt, bits]
		return
	block = maxi(block, width * channels)
	_decode(b, data_at, data_len / block, block, width, fmt == 3)


## Little-endian samples from `data_at` into `data` (and `left`/`right` for
## two channels): `frames` of `block` bytes, `width` bytes a sample, 8-bit
## offset (WAV's) when integer.
func _decode(b: PackedByteArray, data_at: int, frames: int, block: int, width: int, is_float: bool) -> void:
	data.resize(frames)
	var two := channels == 2
	if two:
		left.resize(frames)
		right.resize(frames)
	var inv := 1.0 / channels
	for i in frames:
		var at := data_at + i * block
		var s := 0.0
		for c in channels:
			var o := at + c * width
			var v := 0.0
			if is_float:
				v = b.decode_float(o) if width == 4 else b.decode_double(o)
			else:
				match width:
					1: v = (b[o] - 128) / 128.0
					2: v = b.decode_s16(o) / 32768.0
					3: v = float((b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)) - (16777216 if b[o + 2] >= 128 else 0)) / 8388608.0
					4: v = b.decode_s32(o) / 2147483648.0
			if two:
				if c == 0:
					left[i] = v
				else:
					right[i] = v
			s += v
		data[i] = s * inv if channels > 1 else s


func _read_aiff(b: PackedByteArray) -> void:
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "FORM":
		error = "not an AIFF file"
		return
	var kind := b.slice(8, 12).get_string_from_ascii()
	if kind != "AIFF" and kind != "AIFC":
		error = "not an AIFF file"
		return
	var comp := "NONE"
	var frames := -1
	var data_at := -1
	var data_len := 0
	var markers := {}
	var base_note := -1
	var loop_ids := []
	var pos := 12
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := _be32(b, pos + 4)
		var body := pos + 8
		match id:
			"COMM":
				if size < 18 or body + 18 > b.size():
					error = "short COMM chunk"
					return
				channels = _be16(b, body)
				frames = _be32(b, body + 2)
				bits = _be16(b, body + 6)
				rate = roundi(_ext80(b, body + 8))
				if kind == "AIFC" and size >= 22 and body + 22 <= b.size():
					comp = b.slice(body + 18, body + 22).get_string_from_ascii()
			"SSND":
				if body + 8 <= b.size():
					var offset := _be32(b, body)
					data_at = body + 8 + offset
					data_len = clampi(mini(size - 8 - offset, b.size() - data_at), 0, b.size())
			"MARK":
				if body + 2 <= b.size():
					var n := _be16(b, body)
					var o := body + 2
					for k in n:
						if o + 7 > b.size():
							break
						markers[_be16(b, o)] = _be32(b, o + 2)
						var name_len: int = b[o + 6]
						o += 6 + 1 + name_len + (1 if (name_len + 1) % 2 == 1 else 0)   # pstring, padded to even
			"INST":
				if size >= 20 and body + 20 <= b.size():
					base_note = b[body]
					if _be16(b, body + 8) != 0:      # sustain loop plays (forward or back and forth)
						loop_ids = [_be16(b, body + 10), _be16(b, body + 12)]
		pos = body + size + (size & 1)
	if frames < 0:
		error = "no COMM chunk"
		return
	if data_at < 0:
		error = "no SSND chunk"
		return
	if channels < 1 or rate < 1:
		error = "bad format (%d channels at %d Hz)" % [channels, rate]
		return
	var is_float := comp.to_lower() in ["fl32", "fl64"]
	if is_float:
		bits = 32 if comp.to_lower() == "fl32" else 64
	if not (comp in ["NONE", "twos", "sowt"] or is_float):
		error = "unsupported AIFF-C compression '%s'; save it as PCM or float" % comp
		return
	var width := (bits + 7) / 8
	if not ((not is_float and width in [1, 2, 3, 4]) or (is_float and width in [4, 8])):
		error = "unsupported AIFF encoding (%d bits)" % bits
		return
	var block := width * channels
	frames = mini(frames, data_len / block)
	# To the little-endian layout _decode reads: swap each sample's bytes,
	# and turn AIFF's signed 8-bit into WAV's offset 8-bit.
	var le := b.slice(data_at, data_at + frames * block)
	if width == 1:
		for i in le.size():
			le[i] = (le[i] + 128) & 0xFF
	elif comp != "sowt":
		for i in range(0, le.size(), width):
			for k in width / 2:
				var t := le[i + k]
				le[i + k] = le[i + width - 1 - k]
				le[i + width - 1 - k] = t
	_decode(le, 0, frames, block, width, is_float)
	if base_note >= 0 and base_note <= 127:
		root_note = base_note
	if loop_ids.size() == 2 and markers.has(loop_ids[0]) and markers.has(loop_ids[1]):
		var a: int = markers[loop_ids[0]]
		var e: int = markers[loop_ids[1]]
		if e > a:
			loop = PackedInt32Array([a, e])


static func _be16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


static func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


## An 80-bit IEEE extended float (AIFF's sample rate).
static func _ext80(b: PackedByteArray, o: int) -> float:
	var e := ((b[o] & 0x7F) << 8) | b[o + 1]
	if e == 0:
		return 0.0
	var hi := float(_be32(b, o + 2))
	var lo := float(_be32(b, o + 6))
	var v := hi * pow(2.0, e - 16383 - 31) + lo * pow(2.0, e - 16383 - 63)
	return -v if b[o] & 0x80 else v


func _read_ogg(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var s := AudioStreamOggVorbis.load_from_file(abs_path)
	if s == null or s.packet_sequence == null:
		error = "Godot couldn't open %s as OGG Vorbis" % path
		return
	rate = roundi(s.packet_sequence.sampling_rate)
	bits = 32
	var pb := s.instantiate_playback()
	if rate < 1 or pb == null:
		error = "Godot couldn't decode %s" % path
		return
	# One source sample per output sample. The playback steps in 16.16 fixed
	# point, so nudge the scale up a hair to keep the step from truncating
	# to one below.
	var scale := AudioServer.get_mix_rate() / rate * (1.0 + 1e-6)
	pb.start(0.0)
	var out := PackedFloat32Array()
	var outl := PackedFloat32Array()
	var outr := PackedFloat32Array()
	var mono := true
	while pb.is_playing():
		var chunk: PackedVector2Array = pb.mix_audio(scale, 4096)
		if chunk.is_empty():
			break
		var at := out.size()
		out.resize(at + chunk.size())
		outl.resize(at + chunk.size())
		outr.resize(at + chunk.size())
		for i in chunk.size():
			var v := chunk[i]
			if v.x != v.y:
				mono = false
			out[at + i] = 0.5 * (v.x + v.y)
			outl[at + i] = v.x
			outr[at + i] = v.y
	channels = 1 if mono else 2
	var lead := OGG_LEAD_FRAMES
	data = out.slice(lead) if out.size() > lead else PackedFloat32Array()
	if not mono and out.size() > lead:
		left = outl.slice(lead)
		right = outr.slice(lead)
	if data.is_empty():
		error = "%s decoded to nothing" % path
