# SPDX-License-Identifier: Apache-2.0
@tool
## Reads audio files sample by sample, for AKSample. Godot imports project
## audio into streams the kit can't read back (often compressed), so this
## reads the source file itself:
##
## - **WAV**: the kit's own reader. PCM at 8, 16, 24 or 32 bits, 32- or 64-bit
##   float, plain or WAVE_FORMAT_EXTENSIBLE, any channel count and rate. A
##   `smpl` chunk's unity note and first loop are reported too.
## - **OGG Vorbis**: Godot's own decoder (AudioStreamOggVorbis.load_from_file),
##   pulled through its playback at exactly one source sample per output
##   sample, which reproduces the decoded samples to float rounding.
##
##   var f := AKAudioFile.read("res://audio/kick_01.wav")
##   if f.error == "":
##       print(f.rate, " Hz, ", f.channels, " channels, ", f.data.size(), " frames")
##
## `data` is mono: the mean of the channels (samples play through the kit's
## mono voices; the recipe or lane pans them).
class_name AKAudioFile
extends RefCounted

## Frames the Vorbis playback holds back at its start (its interpolator's
## history), dropped so the data starts on the file's first sample. Pinned by
## tests/test_loops.gd against a reference decode.
const OGG_LEAD_FRAMES := 2

var data := PackedFloat32Array()
var rate := 0
var channels := 0
var bits := 0
## "" when the file read; otherwise what went wrong.
var error := ""
## From a WAV `smpl` chunk: the unity (root) note, -1 when absent.
var root_note := -1
## From a WAV `smpl` chunk: the first loop in frames, [start, end] (end
## exclusive), empty when absent.
var loop := PackedInt32Array()


## Read a .wav or .ogg (res://, user:// or an absolute path).
static func read(path: String) -> AKAudioFile:
	var f := AKAudioFile.new()
	var ext := path.get_extension().to_lower()
	if not FileAccess.file_exists(path):
		f.error = "no file at %s" % path
	elif ext == "wav" or ext == "wave":
		f._read_wav(FileAccess.get_file_as_bytes(path))
	elif ext == "ogg" or ext == "oga":
		f._read_ogg(path)
	else:
		f.error = "can't read .%s files (WAV and OGG Vorbis only)" % ext
	return f


## Parse WAV bytes (exposed for tests).
static func from_wav_bytes(bytes: PackedByteArray) -> AKAudioFile:
	var f := AKAudioFile.new()
	f._read_wav(bytes)
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
					root_note = b.decode_u32(body + 12)
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
	var frames := data_len / block
	data.resize(frames)
	var inv := 1.0 / channels
	for i in frames:
		var at := data_at + i * block
		var s := 0.0
		for c in channels:
			var o := at + c * width
			if fmt == 3:
				s += b.decode_float(o) if width == 4 else b.decode_double(o)
			else:
				match width:
					1: s += (b[o] - 128) / 128.0
					2: s += b.decode_s16(o) / 32768.0
					3: s += float((b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)) - (16777216 if b[o + 2] >= 128 else 0)) / 8388608.0
					4: s += b.decode_s32(o) / 2147483648.0
		data[i] = s * inv if channels > 1 else s


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
	var mono := true
	while pb.is_playing():
		var chunk: PackedVector2Array = pb.mix_audio(scale, 4096)
		if chunk.is_empty():
			break
		var at := out.size()
		out.resize(at + chunk.size())
		for i in chunk.size():
			var v := chunk[i]
			if v.x != v.y:
				mono = false
			out[at + i] = 0.5 * (v.x + v.y)
	channels = 1 if mono else 2
	data = out.slice(OGG_LEAD_FRAMES) if out.size() > OGG_LEAD_FRAMES else PackedFloat32Array()
	if data.is_empty():
		error = "%s decoded to nothing" % path
