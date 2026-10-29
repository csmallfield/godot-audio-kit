# SPDX-License-Identifier: Apache-2.0
@tool
## Numbers that describe a short sound, for checking generated sounds without
## ears: how long it is, how its loudness moves, how bright and how noisy it
## is, and which way its pitch goes.
##
##   var f := AKSoundFeatures.of(AK.render(recipe))
##   f.length_s, f.centroid_hz, f.pitch_start_hz, f.pitch_end_hz, f.flatness ...
class_name AKSoundFeatures
extends RefCounted

const FFT_N := 1024
const RMS_WINDOW_S := 0.01


## Measure `buf` (mixed to mono). Returns:
##   length_s        to the last sample within 60 dB of the peak
##   peak_db, lufs   level
##   attack_s        time to the loudest 10 ms window
##   decay_s         from the loudest window to the last one within 20 dB of it
##   rms_env         10 ms RMS windows over the sound, in dB below the loudest
##   onsets          how many times the RMS jumps up by 6 dB or more (notes, hits)
##   centroid_hz     energy-weighted spectral centroid (brightness)
##   tonality        share of the energy in bins standing 6 dB above their
##                   neighbourhood (±6 bins), energy-weighted: near 1 for
##                   tones and harmonics, around 0.1 for noise of any colour
##   pitch_start_hz, pitch_end_hz   the strongest spectral peak over the first
##                   50 ms and the last third of the active part (to the
##                   last 10 ms window within 30 dB of the loudest), median
##                   of loud frames, for pitch direction
static func of(buf: AKBuffer) -> Dictionary:
	var sr := buf.sample_rate
	var n := buf.frames()
	var mono := PackedFloat32Array()
	mono.resize(n)
	var peak := 0.0
	for i in n:
		mono[i] = 0.5 * (buf.l[i] + buf.r[i])
		peak = maxf(peak, absf(mono[i]))
	var out := {length_s = 0.0, peak_db = linear_to_db(buf.peak()) if buf.peak() > 0.0 else -INF,
		lufs = AKDynamics.lufs(buf) if n > 0 else -INF, attack_s = 0.0, decay_s = 0.0, rms_env = PackedFloat32Array(),
		onsets = 0, centroid_hz = 0.0, tonality = 0.0, pitch_start_hz = 0.0, pitch_end_hz = 0.0}
	if peak <= 0.0:
		return out
	var floor_v := peak * 0.001
	var last := n - 1
	while last > 0 and absf(mono[last]) < floor_v:
		last -= 1
	out.length_s = float(last + 1) / sr

	# Loudness envelope.
	var w := maxi(1, roundi(RMS_WINDOW_S * sr))
	var env := PackedFloat32Array()
	var top := 0.0
	var top_i := 0
	for s in range(0, last + 1, w):
		var acc := 0.0
		var e := mini(s + w, last + 1)
		for i in range(s, e):
			acc += mono[i] * mono[i]
		var rms := sqrt(acc / maxf(1.0, e - s))
		env.append(rms)
		if rms > top:
			top = rms
			top_i = env.size() - 1
	var env_db := PackedFloat32Array()
	var tail_i := top_i
	var active_i := top_i
	for i in env.size():
		var d := linear_to_db(maxf(env[i], 1e-9) / top)
		env_db.append(d)
		if i >= top_i and d > -20.0:
			tail_i = i
		if d > -30.0:
			active_i = i
	out.rms_env = env_db
	out.attack_s = top_i * RMS_WINDOW_S
	out.decay_s = (tail_i - top_i + 1) * RMS_WINDOW_S
	# An onset: a rise of 6 dB from the last dip to within 24 dB of the top;
	# the next needs a 6 dB fall first.
	var onsets := 0
	var low := -60.0
	var high := -60.0
	var armed := true
	for d in env_db:
		if armed:
			low = minf(low, d)
			if d - low >= 6.0 and d > -24.0:
				onsets += 1
				armed = false
				high = d
		else:
			high = maxf(high, d)
			if d < high - 6.0:
				armed = true
				low = d
	out.onsets = maxi(1, onsets)

	# Spectrum, frame by frame over the audible part.
	var hop := FFT_N / 2
	var win := PackedFloat32Array()
	win.resize(FFT_N)
	for i in FFT_N:
		win[i] = 0.5 - 0.5 * cos(TAU * i / (FFT_N - 1))
	var c_num := 0.0
	var c_den := 0.0
	var ton_sum := 0.0
	var ton_w := 0.0
	var mags := PackedFloat32Array()
	mags.resize(FFT_N / 2 - 1)
	var peaks: Array[float] = []
	var weights: Array[float] = []
	var start := 0
	var active_end := mini(last, (active_i + 1) * w)
	while start < active_end:
		var re := PackedFloat32Array()
		re.resize(FFT_N)
		var im := PackedFloat32Array()
		im.resize(FFT_N)
		var energy := 0.0
		for i in FFT_N:
			var j := start + i
			var v := mono[j] * win[i] if j <= active_end else 0.0
			re[i] = v
			energy += v * v
		start += hop
		if energy < 1e-7:
			peaks.append(-1.0)
			weights.append(0.0)
			continue
		_fft(re, im)
		var e_sum := 0.0
		var f_sum := 0.0
		var best := 0.0
		var best_k := 1
		var bins := FFT_N / 2
		for k in range(1, bins):
			var m := re[k] * re[k] + im[k] * im[k]
			var hz := float(k) * sr / FFT_N
			e_sum += m
			f_sum += m * hz
			mags[k - 1] = m
			if m > best:
				best = m
				best_k = k
		c_num += f_sum
		c_den += e_sum
		var strong := 0.0
		var nb := mags.size()
		for k in nb:
			var acc := 0.0
			var cnt := 0
			for q in range(maxi(0, k - 6), mini(nb, k + 7)):
				if q != k:
					acc += mags[q]
					cnt += 1
			if mags[k] > 4.0 * acc / cnt:
				strong += mags[k]
		ton_sum += strong / maxf(e_sum, 1e-20) * energy
		ton_w += energy
		peaks.append(_refine(re, im, best_k) * sr / FFT_N)
		weights.append(energy)
	out.centroid_hz = c_num / maxf(c_den, 1e-12)
	out.tonality = ton_sum / maxf(ton_w, 1e-20)
	var wmax := 0.0
	for x in weights:
		wmax = maxf(wmax, x)
	var head := clampi(ceili(0.05 * sr / hop), 2, peaks.size())
	var third := maxi(1, peaks.size() / 3)
	out.pitch_start_hz = _median_loud(peaks.slice(0, head), weights.slice(0, head), wmax)
	out.pitch_end_hz = _median_loud(peaks.slice(peaks.size() - third), weights.slice(peaks.size() - third), wmax)
	return out


## Median of the values whose frames carry at least 1% of the loudest
## frame's energy (`mx`).
static func _median_loud(vals: Array, ws: Array, mx: float) -> float:
	var keep: Array[float] = []
	for i in vals.size():
		if float(ws[i]) >= mx * 0.01 and float(vals[i]) > 0.0:
			keep.append(float(vals[i]))
	if keep.is_empty():
		return 0.0
	keep.sort()
	return keep[keep.size() / 2]


## Parabolic interpolation of a spectral peak (log magnitude), in bins.
static func _refine(re: PackedFloat32Array, im: PackedFloat32Array, k: int) -> float:
	if k <= 0 or k >= re.size() / 2 - 1:
		return float(k)
	var a := log(re[k - 1] * re[k - 1] + im[k - 1] * im[k - 1] + 1e-20)
	var b := log(re[k] * re[k] + im[k] * im[k] + 1e-20)
	var c := log(re[k + 1] * re[k + 1] + im[k + 1] * im[k + 1] + 1e-20)
	var d := a - 2.0 * b + c
	return float(k) + (0.5 * (a - c) / d if absf(d) > 1e-12 else 0.0)


## In-place iterative radix-2 FFT (size a power of two).
static func _fft(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j |= bit
		if i < j:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var size := 2
	while size <= n:
		var half := size / 2
		var ang := -TAU / size
		for s in range(0, n, size):
			for k in half:
				var wr := cos(ang * k)
				var wi := sin(ang * k)
				var a := s + k
				var b := a + half
				var xr := re[b] * wr - im[b] * wi
				var xi := re[b] * wi + im[b] * wr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
		size *= 2
