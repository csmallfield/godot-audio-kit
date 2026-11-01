// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <vector>

namespace godot {

// The number crunching behind AKSampleMatch (addons/audio_kit/lab/sample_match.gd): matching a recording
// as a patch. Measuring harmonics, the harmonic score and the lite fit's loss run thousands of times over
// a whole recording, far too slow in GDScript, so the matcher needs the native core.
class AKMatch : public RefCounted {
	GDCLASS(AKMatch, RefCounted)

protected:
	static void _bind_methods();

public:
	// A second-order Butterworth high-pass run forwards then backwards (no phase shift).
	PackedFloat32Array highpass(const PackedFloat32Array &x, double sr, double hz);
	// |FFT| of x[start, start + n) under a Hann window, zero-padded to `nfft` (a power of two), scaled so a
	// sine of amplitude a peaks near a.
	PackedFloat64Array spectrum(const PackedFloat32Array &x, int start, int n, int nfft);
	// The complex amplitude at each frequency of x[start, start + n) under a Hann window (2 x the windowed
	// mean of x e^(-2 pi i f t)), with t = t0 at the first sample: [re, im, re, im, ...].
	PackedFloat64Array dft(const PackedFloat32Array &x, int start, int n, const PackedFloat64Array &freqs, double sr, double t0);
	// The harmonic features of one note: frames every 10 ms (windows of 4 periods of f0) of each harmonic's
	// level (up to kmax and fmax) and of the noise between the harmonics in four bands, in dB.
	// Returns [harmonics (frames x K), noise (frames x 4), frames, K].
	Array features(const PackedFloat32Array &x, int start, int length, double f0, double sr, int kmax, double fmax);

	// The harmonic score: slots of the original's features (a) against a render's (b), in dB.
	void clear();
	void add_slot(double note, const PackedFloat64Array &ha, const PackedFloat64Array &na, int frames_a,
			const PackedFloat64Array &hb, const PackedFloat64Array &nb, int frames_b, int k, double first_s);
	// The lite fit's model: corrections to b's harmonics for a one-zone patch centred on `center`, with
	// `semis` the patch's transposition (cents included), `kp` the keys of the level curve and `neq` EQs.
	void setup(double center, double semis, const PackedFloat64Array &kp, int neq, double sr);
	// [score, level offset] of b against a with the corrections in `stages` (1 filter, 2 EQ, 4 level by
	// key) from params: [log cutoff, key tracking, log Q, key -> amp, env2 oct, env3 oct, the EQs (7 each:
	// log low Hz, dB, log mid Hz, dB, log Q, log high Hz, dB), a dB per key of kp]. `off` < -900 matches
	// the level; otherwise it is the offset, with `floor` the floor.
	PackedFloat64Array score(const PackedFloat64Array &params, int stages, double off, double floor);
	// The score of each slot alone at a fixed offset and floor (no corrections).
	PackedFloat64Array slot_scores(double off, double floor);
	// Each slot's level difference, 10 log10(energy of a / energy of b), with the corrections and offset.
	PackedFloat64Array slot_levels(const PackedFloat64Array &params, int stages, double off);
	int slot_count() const { return (int)slots.size(); }

private:
	struct Slot {
		double note;
		int fa, fb, k;
		double first_s;
		std::vector<double> ha, na, hb, nb;
	};
	std::vector<Slot> slots;
	double center = 72, semis = 0, sr = 44100;
	int neq = 0;
	std::vector<double> kp;
	void correct(const std::vector<double> &p, int stages, std::vector<std::vector<double>> &out) const;
	double score_of(const std::vector<std::vector<double>> &hb, double off, double fl, bool match, double &off_out) const;
};

} // namespace godot
