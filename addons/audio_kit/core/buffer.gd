# SPDX-License-Identifier: Apache-2.0
## A stereo, 32-bit float audio buffer: the kit's working format between
## voices, effects, the cue renderer and the final `AudioStreamWAV`.
##
## Sample 0 is where the sound's cue lands; nothing is padded in front.
class_name AKBuffer
extends RefCounted

var l := PackedFloat32Array()
var r := PackedFloat32Array()
var sample_rate := 48000
## Reverb send level set by AK.render from the recipe (0..1); render_cues
## feeds this much of the sound to the shared reverb.
var send := 0.0


func _init(frames := 0, p_sample_rate := 48000) -> void:
	sample_rate = p_sample_rate
	resize(frames)


func frames() -> int:
	return l.size()


func seconds() -> float:
	return float(l.size()) / sample_rate


func resize(frames: int) -> void:
	var old := l.size()
	l.resize(frames)
	r.resize(frames)
	for i in range(old, frames):
		l[i] = 0.0
		r[i] = 0.0


## A stereo buffer from a mono signal, placed with an equal-power `pan`
## (-1 left, 0 centre, 1 right), scaled so a centred signal keeps its full
## level on both channels.
static func from_mono(mono: PackedFloat32Array, p_sample_rate := 48000, pan := 0.0) -> AKBuffer:
	var b := AKBuffer.new(0, p_sample_rate)
	var a := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
	var gl := cos(a) * sqrt(2.0)
	var gr := sin(a) * sqrt(2.0)
	b.l = mono.duplicate()
	b.r = mono.duplicate()
	if not is_equal_approx(gl, 1.0) or not is_equal_approx(gr, 1.0):
		var n := mono.size()
		for i in n:
			b.l[i] = mono[i] * gl
			b.r[i] = mono[i] * gr
	return b


func duplicate_buffer() -> AKBuffer:
	var b := AKBuffer.new(0, sample_rate)
	b.l = l.duplicate()
	b.r = r.duplicate()
	return b


## Add this buffer into `dst` starting at sample `at` (may be negative: the
## part before `dst`'s start is dropped). `dst` grows to fit.
func mix_into(dst: AKBuffer, at: int, gain := 1.0) -> void:
	var nn := AKDsp.nat()
	if nn:
		var res: Array = nn.mix_into(dst.l, dst.r, l, r, at, gain)
		dst.l = res[0]
		dst.r = res[1]
		return
	var n := frames()
	var start := maxi(0, -at)
	if at + n > dst.frames():
		dst.resize(at + n)
	for i in range(start, n):
		var j := at + i
		dst.l[j] += l[i] * gain
		dst.r[j] += r[i] * gain


func apply_gain(gain: float) -> void:
	if is_equal_approx(gain, 1.0):
		return
	l = AKDsp.scale(l, gain)
	r = AKDsp.scale(r, gain)


func peak() -> float:
	var p := 0.0
	for i in frames():
		p = maxf(p, maxf(absf(l[i]), absf(r[i])))
	return p


## Index of the first sample whose magnitude exceeds `threshold`, or -1.
func first_above(threshold := 1e-4) -> int:
	for i in frames():
		if absf(l[i]) > threshold or absf(r[i]) > threshold:
			return i
	return -1


## 16-bit PCM `AudioStreamWAV` with seeded TPDF dither, so the same buffer
## always encodes to the same bytes.
func to_stream(dither_seed := 0) -> AudioStreamWAV:
	var n := frames()
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = dither_seed
	const LSB := 1.0 / 32768.0
	for i in n:
		var vl := clampf(l[i] + (rng.randf() - rng.randf()) * LSB, -1.0, 1.0)
		var vr := clampf(r[i] + (rng.randf() - rng.randf()) * LSB, -1.0, 1.0)
		bytes.encode_s16(i * 4, clampi(roundi(vl * 32767.0), -32768, 32767))
		bytes.encode_s16(i * 4 + 2, clampi(roundi(vr * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = true
	s.mix_rate = sample_rate
	s.data = bytes
	return s


## Write a 16-bit stereo WAV file.
func save_wav(path: String, dither_seed := 0) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return to_stream(dither_seed).save_to_wav(path)
