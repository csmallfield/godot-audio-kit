# SPDX-License-Identifier: Apache-2.0
extends RefCounted

const SR := 48000


func _sine_buffer(freq: float, seconds: float, amp: float, both := true) -> AKBuffer:
	var n := roundi(seconds * SR)
	var x := AKDsp.scale(AKOsc.sine(AKDsp.filled(n, freq), SR), amp)
	var b := AKBuffer.new(0, SR)
	b.l = x
	b.r = x.duplicate() if both else AKDsp.filled(n, 0.0)
	return b


func test_lufs_reference_sine() -> String:
	# BS.1770: a 0 dBFS 1 kHz sine reads -3.01 LUFS in one channel, 0.0 in two.
	var one := AKDynamics.lufs(_sine_buffer(1000.0, 3.0, 1.0, false))
	var two := AKDynamics.lufs(_sine_buffer(1000.0, 3.0, 1.0, true))
	if absf(one + 3.01) > 0.1:
		return "mono sine read %.2f LUFS, expected -3.01" % one
	if absf(two) > 0.1:
		return "stereo sine read %.2f LUFS, expected 0.0" % two
	return ""


func test_loudness_sets_target() -> String:
	var b := _sine_buffer(440.0, 2.0, 0.1)
	AKDynamics.loudness(b, -16.0)
	var got := AKDynamics.lufs(b)
	return "" if absf(got + 16.0) < 0.05 else "got %.2f LUFS" % got


func test_limiter_ceiling() -> String:
	var b := _sine_buffer(200.0, 0.5, 2.0)
	AKDynamics.limit(b, -1.5)
	var p := b.peak()
	return "" if p <= AKDsp.db_to_gain(-1.5) + 1e-6 else "peak %.4f above ceiling" % p


func test_lowpass_attenuates_highs() -> String:
	var hi := _sine_buffer(8000.0, 0.5, 1.0)
	var y := AKFilter.svf(hi.l, 500.0, 0.707, SR, &"low")
	var p := 0.0
	for i in range(SR / 10, y.size()):
		p = maxf(p, absf(y[i]))
	return "" if p < 0.02 else "8 kHz through a 500 Hz low-pass peaked at %.3f" % p


func test_osc_pitch() -> String:
	# Count zero crossings of a 440 Hz saw over one second.
	var x := AKOsc.saw(AKDsp.filled(SR, 440.0), SR)
	var crossings := 0
	for i in range(1, x.size()):
		if x[i - 1] > 0.0 and x[i] <= 0.0:
			crossings += 1
	return "" if absi(crossings - 440) <= 1 else "saw crossed %d times" % crossings


func test_mix_into_offsets() -> String:
	var a := AKBuffer.new(0, SR)
	var b := AKBuffer.from_mono(AKDsp.filled(10, 0.5), SR)
	b.mix_into(a, 100)
	if a.frames() != 110 or a.first_above(0.1) != 100:
		return "placed at %d, length %d" % [a.first_above(0.1), a.frames()]
	var c := AKBuffer.new(50, SR)
	b.mix_into(c, -5)
	return "" if c.first_above(0.1) == 0 and absf(c.l[4] - 0.5) < 1e-6 and c.l[5] == 0.0 else "negative offset not trimmed"
