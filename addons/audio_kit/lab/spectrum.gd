# SPDX-License-Identifier: Apache-2.0
## Spectra for the Sound Lab's spectrum view and for tests: a Hann-windowed
## FFT of a block of samples, as decibels per frequency bin.
##
##   var db := AKSpectrum.magnitudes_db(samples, 2048)   # size / 2 + 1 bins
##   var hz := AKSpectrum.bin_hz(i, 2048, 48000)
@tool
class_name AKSpectrum
extends RefCounted


## Decibels (0 dB = a full-scale sine) for bins 0 .. size/2 of the last
## `size` samples (zero-padded when there are fewer). `size` is rounded up to
## a power of two.
static func magnitudes_db(samples: PackedFloat32Array, size := 2048) -> PackedFloat32Array:
	var n := 1
	while n < size:
		n <<= 1
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(n)
	im.resize(n)
	var start := maxi(0, samples.size() - n)
	var count := mini(n, samples.size())
	var wsum := 0.0
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * float(i) / float(n))
		wsum += w
		re[i] = float(samples[start + i]) * w if i < count else 0.0
	fft(re, im)
	var out := PackedFloat32Array()
	out.resize(n / 2 + 1)
	# A full-scale sine's peak bin is wsum / 2.
	var norm := 2.0 / wsum
	for k in n / 2 + 1:
		var m := sqrt(re[k] * re[k] + im[k] * im[k]) * norm
		out[k] = 20.0 * log(maxf(m, 1e-9)) / log(10.0)
	return out


## The centre frequency of bin `k`.
static func bin_hz(k: int, size: int, sample_rate: int) -> float:
	return float(k) * float(sample_rate) / float(size)


## The frequency of the loudest bin above `min_hz`, refined between bins.
static func peak_hz(samples: PackedFloat32Array, sample_rate: int, size := 8192, min_hz := 20.0) -> float:
	var db := magnitudes_db(samples, size)
	var n := (db.size() - 1) * 2
	var best := maxi(1, int(ceil(min_hz * n / float(sample_rate))))
	for k in range(best, db.size() - 1):
		if db[k] > db[best]:
			best = k
	var off := 0.0
	if best > 0 and best < db.size() - 1:
		var a := db[best - 1]
		var b := db[best]
		var c := db[best + 1]
		var den := a - 2.0 * b + c
		if absf(den) > 1e-9:
			off = 0.5 * (a - c) / den
	return (float(best) + off) * float(sample_rate) / float(n)


## An in-place radix-2 FFT (the arrays' size must be a power of two).
static func fft(re: PackedFloat64Array, im: PackedFloat64Array) -> void:
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
	var len := 2
	while len <= n:
		var ang := -TAU / float(len)
		var wr := cos(ang)
		var wi := sin(ang)
		var half := len / 2
		var i := 0
		while i < n:
			var cr := 1.0
			var ci := 0.0
			for k in half:
				var a := i + k
				var b := a + half
				var xr := re[b] * cr - im[b] * ci
				var xi := re[b] * ci + im[b] * cr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
				var ncr := cr * wr - ci * wi
				ci = cr * wi + ci * wr
				cr = ncr
			i += len
		len <<= 1
