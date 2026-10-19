// SPDX-License-Identifier: Apache-2.0
// The live mixer's engine, free of Godot types so it can be tested offline and
// driven from the audio thread. AKLiveStream owns one; its playback renders it.
//
// Signal flow per sample, mirroring AK.render_cues:
//   hits (pre-rendered buffers on an absolute frame timeline) + live voices
//     -> dry bus, and (scaled by each source's send) -> send bus
//   send bus -> Freeverb -> * return gain -> added to dry
//   dry -> master chain (gain, filters, end fade, limiter) -> out
#pragma once
#include "dsp.h"

#include <algorithm>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace ak {

struct Smooth {
	double v = 0.0, target = 0.0, k = 0.0;
	void reset(double x) { v = target = x; }
	void set(double x, double glide_s, int sr) {
		target = x;
		k = glide_s <= 0.0 ? 0.0 : std::exp(-1.0 / (glide_s * sr));
	}
	inline double tick() {
		v = target + (v - target) * k;
		return v;
	}
};

// A continuously running synth voice whose parameters glide while it plays.
struct LiveVoice {
	enum Shape { SINE, SAW, SQUARE, TRIANGLE, NOISE };
	int shape = SINE;
	double phase = 0.0;
	uint32_t rng = 0x9E3779B9u;
	Smooth freq, gain, cutoff, q, pan, send, width, noise;
	SVF filt;
	bool filtered = true;
	double release = 1.0, release_k = 1.0;
	bool releasing = false;
	int counter = 0;
	int bus = 0;

	inline double white() {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return (rng / 4294967295.0) * 2.0 - 1.0;
	}
	// One mono sample; `ok` false once the release has died away.
	double tick(int sr, bool &ok);
};

struct ChainStep {
	enum Type { GAIN, HIGHPASS1, LOWPASS1, SVF_FILTER, LIMIT, FADE_END, ROOM, ECHO, DRIVE, BITCRUSH };
	int type = GAIN;
	double gain = 1.0;
	double coef = 0.0;  // one-pole coefficient
	double ceiling = 1.0, release_k = 0.0, lim_g = 1.0;
	int mode = 0, stages = 1;
	int64_t start = 0, end = 0;
	double lp[2] = { 0.0, 0.0 };
	SVF svf[2][2];
	double cutoff = 1000.0, q = 0.707;
	// ROOM
	Freeverb fv;
	double room = 0.5, damp = 0.5, width = 1.0, mix = 0.2;
	bool small = false;
	// ECHO: w[i] = x[i] + fb * w[i - d]; out = x + mix * w[i - d]
	std::vector<float> line[2];
	int idx = 0;
	double fb = 0.35;
	// DRIVE / BITCRUSH
	double k = 1.0, norm = 1.0, steps = 128.0;
	int hold = 1;
	double held[2] = { 0.0, 0.0 };
	void reset(int sr);
};

struct LiveCore {
	struct Buf {
		std::vector<float> l, r;
	};
	struct Hit {
		std::shared_ptr<const Buf> buf;
		int64_t at = 0;
		float gl = 1.0f, gr = 1.0f, gs = 0.0f;
		int tag = 0;
		bool once = false;
		int bus = 0;
	};
	// A group of sources with a fader (gliding gain, scales dry and send) and
	// optional ducking under another bus (dry only).
	struct Bus {
		Smooth gain;
		int duck_source = -1;
		Ducker duck;
		std::vector<float> dl, dr, sl, sr;
		Bus() { gain.reset(1.0); }
	};
	std::map<int, Bus> buses;
	Bus &bus(int id) { return buses[id]; }

	std::mutex mutex;
	int sr = 48000;
	int64_t frame = 0;
	bool playing = false;

	std::unordered_map<int, std::shared_ptr<const Buf>> bufs;
	int next_buf = 1;
	std::vector<Hit> hits;

	bool reverb_on = false;
	double rv_room = 0.5, rv_damp = 0.5, rv_width = 1.0, rv_return = 1.0;
	bool rv_small = false;
	Freeverb reverb;

	std::vector<ChainStep> chain;

	std::map<int, LiveVoice> voices;
	int next_voice = 1;

	std::vector<float> dl, dr, sl, sr_;

	// All of these expect `mutex` held by the caller.
	void seek(int64_t f);
	void render(float *out_l, float *out_r, int n);
};

} // namespace ak
