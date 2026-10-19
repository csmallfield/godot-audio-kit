// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "live_core.h"

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback_resampled.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

// A live 48 kHz mix: pre-rendered buffers scheduled at exact timeline frames,
// continuous voices whose parameters glide, a shared reverb send and a master
// chain. Assign it to an AudioStreamPlayer; the GDScript side (AKLive) keeps
// it fed. Everything is thread-safe against the audio thread.
class AKLiveStream : public AudioStream {
	GDCLASS(AKLiveStream, AudioStream)

	std::shared_ptr<ak::LiveCore> core = std::make_shared<ak::LiveCore>();

protected:
	static void _bind_methods();

public:
	Ref<AudioStreamPlayback> _instantiate_playback() const override;
	String _get_stream_name() const override { return "AKLive"; }
	double _get_length() const override { return 0.0; }
	bool _is_monophonic() const override { return true; }

	// Buffers: register once, schedule many times.
	int add_buffer(const PackedFloat32Array &l, const PackedFloat32Array &r);
	void remove_buffer(int id);
	int buffer_count() const;

	// A hit on the timeline at an absolute frame (survives seeks).
	void schedule(int buffer, int64_t at_frame, double gain_l, double gain_r, double send, int tag, int bus);
	// A one-shot `delay_frames` after the current position (dropped on seek).
	void play_now(int buffer, double gain_l, double gain_r, double send, int64_t delay_frames, int bus);
	void cancel(int tag);
	// Drop hits with `tag` that start at or after `from_frame` (rescheduling).
	void cancel_after(int tag, int64_t from_frame);

	// Buses: a fader (linear gain, glides) and optional ducking of the bus's
	// dry signal under `source` (depth_db 0 = off).
	void set_bus_gain(int id, double gain, double glide_s);
	void set_bus_duck(int id, int source, double depth_db, double full, double attack_s, double release_s);
	void clear();
	int hit_count() const;

	void set_reverb(bool enabled, double room, double damp, double width, bool small, double return_gain);
	// Steps: {type: gain|highpass1|lowpass1|svf|limit|fade_end, ...}.
	void set_chain(const Array &steps);

	// Continuous voices. Params: shape (sine|saw|square|triangle|noise),
	// freq_hz, gain, cutoff_hz (0 = unfiltered), q, pan, send, width, noise,
	// attack_s. Set glides a parameter; stop releases with a time constant.
	int voice_start(const Dictionary &params);
	void voice_set(int id, const String &param, double value, double glide_s);
	void voice_stop(int id, double release_s);
	int voice_count() const;

	int64_t get_frame() const;
	void seek_frame(int64_t frame);
	void set_playing(bool p);
	bool is_playing_now() const;
	// Render `frames` here, advancing the timeline exactly as playback would.
	Array render_offline(int frames);

	std::shared_ptr<ak::LiveCore> get_core() const { return core; }
};

class AKLivePlayback : public AudioStreamPlaybackResampled {
	GDCLASS(AKLivePlayback, AudioStreamPlaybackResampled)

	std::shared_ptr<ak::LiveCore> core;
	std::vector<float> tl, tr;

protected:
	static void _bind_methods() {}

public:
	void set_core(std::shared_ptr<ak::LiveCore> c) { core = c; }

	void _start(double from_pos) override;
	void _stop() override;
	bool _is_playing() const override;
	double _get_playback_position() const override;
	void _seek(double pos) override;
	int32_t _mix_resampled(AudioFrame *dst, int32_t frames) override;
	float _get_stream_sampling_rate() const override;
};

} // namespace godot
