// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "synth.h"

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <memory>
#include <mutex>
#include <vector>

namespace godot {

// A compiled patch (AKPatch.compile()) as the engine's struct.
ak::SynthPatch synth_patch_from(const Dictionary &d);

struct SynthShared {
	std::mutex mutex;
	ak::SynthEngine engine;
	bool playing = false;
	// The last SCOPE_SIZE frames played, mono, for scopes and meters.
	static constexpr int SCOPE_SIZE = 8192;
	std::vector<float> scope = std::vector<float>(SCOPE_SIZE, 0.0f);
	int scope_pos = 0;
	void tap(const float *l, const float *r, int frames) {
		for (int i = 0; i < frames; i++) {
			scope[scope_pos] = 0.5f * (l[i] + r[i]);
			scope_pos = (scope_pos + 1) % SCOPE_SIZE;
		}
	}
};

// A patch played live: an AudioStream to put on any AudioStreamPlayer (and
// any Godot bus). Notes and controllers go in from code or MIDI and sound at
// the next mix (or `delay_s` later, to the sample). The same engine bakes
// (AKSynth.render_notes), so what plays matches what bakes.
class AKSynthStream : public AudioStream {
	GDCLASS(AKSynthStream, AudioStream)

	std::shared_ptr<SynthShared> shared = std::make_shared<SynthShared>();
	Ref<Resource> patch;

	void _patch_changed();
	int64_t _at(double delay_s) const;

protected:
	static void _bind_methods();

public:
	Ref<AudioStreamPlayback> _instantiate_playback() const override;
	String _get_stream_name() const override { return "AKSynthStream"; }
	double _get_length() const override { return 0.0; }
	bool _is_monophonic() const override { return true; }

	void set_patch(const Ref<Resource> &p);
	Ref<Resource> get_patch() const { return patch; }
	// Use a compiled patch directly (what set_patch does after compiling).
	void set_patch_data(const Dictionary &compiled);

	void note_on(double note, double velocity, double delay_s);
	void note_off(double note, double delay_s);
	void set_bend(double value, double delay_s);
	void set_mod_wheel(double value, double delay_s);
	void set_aftertouch(double value, double delay_s);
	void set_sustain(bool down, double delay_s);
	void all_notes_off(double delay_s);
	void panic();
	// Schedule a note at an absolute engine frame (for sequencing).
	void schedule(int64_t frame, int type, double a, double b);

	int voice_count() const;
	int64_t get_frame() const;
	void set_playing(bool p);
	bool is_playing_now() const;
	// Render `frames` here, exactly as playback would: [l, r].
	Array render_offline(int frames);
	// The last `frames` frames played (up to 8192), mono, oldest first.
	PackedFloat32Array get_recent(int frames) const;

	std::shared_ptr<SynthShared> get_shared() const { return shared; }
};

class AKSynthPlayback : public AudioStreamPlaybackResampled {
	GDCLASS(AKSynthPlayback, AudioStreamPlaybackResampled)

	std::shared_ptr<SynthShared> shared;
	std::vector<float> tl, tr;

protected:
	static void _bind_methods() {}

public:
	void set_shared(std::shared_ptr<SynthShared> s) { shared = s; }
	void _start(double from_pos) override;
	void _stop() override;
	bool _is_playing() const override;
	double _get_playback_position() const override;
	int32_t _mix_resampled(AudioFrame *dst, int32_t frames) override;
	float _get_stream_sampling_rate() const override;
};

} // namespace godot
