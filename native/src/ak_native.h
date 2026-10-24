// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

// Native DSP kernels. Each mirrors a GDScript function in addons/audio_kit/dsp
// with the same algorithm, so output matches it closely (floating point aside).
// GDScript calls these through AKDsp.nat() and falls back to its own code when
// the extension isn't present. Arrays come in by value and go out as new
// arrays (Godot's packed arrays are copy-on-write).
class AKNative : public RefCounted {
	GDCLASS(AKNative, RefCounted)

protected:
	static void _bind_methods();

public:
	static String version();

	// AKDsp
	PackedFloat32Array glide(int n, int sr, double a, double b, double time_s);
	PackedFloat32Array mul(const PackedFloat32Array &a, const PackedFloat32Array &b);
	PackedFloat32Array add(const PackedFloat32Array &a, const PackedFloat32Array &b, double gain, int at);
	PackedFloat32Array scale(const PackedFloat32Array &a, double gain);

	// AKOsc
	PackedFloat32Array sine(const PackedFloat32Array &freq, int sr, double phase0);
	PackedFloat32Array sine_const(int n, double freq, int sr, double phase0);
	PackedFloat32Array saw(const PackedFloat32Array &freq, int sr, double phase0);
	PackedFloat32Array square(const PackedFloat32Array &freq, int sr, double width, double phase0);
	PackedFloat32Array triangle(const PackedFloat32Array &freq, int sr, double phase0);

	// AKEnv
	PackedFloat32Array env_decay(int n, int sr, double attack_s, double decay_s);
	PackedFloat32Array env_adsr(int n, int sr, double a, double d, double s, double r, double gate);

	// AKFilter: `cutoff` used when `cutoffs` is empty.
	PackedFloat32Array lowpass1(const PackedFloat32Array &x, const PackedFloat32Array &cutoffs, double cutoff, int sr);
	PackedFloat32Array svf(const PackedFloat32Array &x, const PackedFloat32Array &cutoffs, double cutoff, double q, int sr, int mode);

	// AKDelay
	PackedFloat32Array karplus(const PackedFloat32Array &init, int n, int sr, double decay_s, double brightness);

	// AKReverb: returns [l, r] of the wet signal, `tail` samples longer.
	Array reverb_wet(const PackedFloat32Array &l, const PackedFloat32Array &r, int sr, double room, double damp, double width, int tail, bool small);

	// AKDynamics
	Array limit(const PackedFloat32Array &l, const PackedFloat32Array &r, double ceiling, double release_k);
	double lufs(const PackedFloat32Array &l, const PackedFloat32Array &r, int sr);

	// Voices
	PackedFloat32Array fm(int n, int sr, double freq, double ratio, double index, double index_end, double index_decay_s, double ratio2, double index2);

	// AKDynamics.duck: returns [l, r] of the target ducked under the source.
	Array duck(const PackedFloat32Array &l, const PackedFloat32Array &r, const PackedFloat32Array &sl, const PackedFloat32Array &sr_, int sr, double depth_db, double full, double attack_s, double release_s);

	// AKSampler.play: read `data` from `start` at `rate` source samples per
	// output sample with 4-point Hermite interpolation, `n` samples out; with
	// `looping`, wraps between `loop_start` and `loop_end` (source samples).
	PackedFloat32Array sample_play(const PackedFloat32Array &data, double rate, int n, int start, int end, int loop_start, int loop_end, bool looping);

	// AKSynth: render a compiled patch (AKPatch.compile()) over `frames`
	// with events [[frame, type, a, b], ...] (see AKSynthCore): [l, r].
	Array synth_render(const Dictionary &patch, const Array &events, int frames, int sr);

	// AKStreamFx.process: a chain of compiled effect specs over stereo arrays: [l, r].
	Array fx_process(const Array &compiled, const PackedFloat32Array &l, const PackedFloat32Array &r, int sr);

	// AKBuffer.mix_into for both channels: returns [dst_l, dst_r] grown to fit.
	Array mix_into(const PackedFloat32Array &dl, const PackedFloat32Array &dr, const PackedFloat32Array &sl, const PackedFloat32Array &sr_, int at, double gain);
};

} // namespace godot
