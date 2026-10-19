// SPDX-License-Identifier: Apache-2.0
#include "live_core.h"

#include <algorithm>

namespace ak {

double LiveVoice::tick(int sr, bool &ok) {
	double f = freq.tick();
	double g = gain.tick();
	double c = cutoff.tick();
	double qq = q.tick();
	double w = width.tick();
	double nz = noise.tick();
	double dt = f / sr;
	double v;
	switch (shape) {
		case SAW:
			v = 2.0 * phase - 1.0 - blep(phase, dt);
			break;
		case SQUARE: {
			double ww = std::clamp(w, 0.01, 0.99);
			v = phase < ww ? 1.0 : -1.0;
			v += blep(phase, dt);
			double p2 = phase - ww;
			p2 -= std::floor(p2);
			v -= blep(p2, dt);
			break;
		}
		case TRIANGLE:
			v = 1.0 - 4.0 * std::fabs(phase - 0.5);
			break;
		case NOISE:
			v = 0.0;
			nz = 1.0;
			break;
		default:
			v = std::sin(TAU * phase);
	}
	if (nz > 0.0) {
		v = v * (1.0 - nz) + white() * nz;
	}
	phase += dt;
	phase -= std::floor(phase);
	if (filtered) {
		if ((counter++ & 15) == 0) {
			filt.set_q(qq);
			filt.set_cutoff(c, sr);
		}
		v = filt.tick(v, 0);
	}
	if (releasing) {
		release *= release_k;
		if (release < 1e-5) {
			ok = false;
		}
	}
	return v * g * release;
}

void ChainStep::reset(int sr) {
	lp[0] = lp[1] = 0.0;
	lim_g = 1.0;
	for (int ch = 0; ch < 2; ch++) {
		for (int s = 0; s < 2; s++) {
			svf[ch][s] = SVF();
			svf[ch][s].set_q(q);
			svf[ch][s].set_cutoff(cutoff, sr);
		}
	}
}

void LiveCore::seek(int64_t f) {
	frame = f < 0 ? 0 : f;
	if (reverb_on) {
		reverb.setup(sr, rv_room, rv_damp, rv_width, rv_small);
	}
	for (ChainStep &s : chain) {
		s.reset(sr);
	}
	hits.erase(std::remove_if(hits.begin(), hits.end(), [](const Hit &h) { return h.once; }), hits.end());
}

void LiveCore::render(float *out_l, float *out_r, int n) {
	if ((int)dl.size() < n) {
		dl.resize(n);
		dr.resize(n);
		sl.resize(n);
		sr_.resize(n);
	}
	std::fill(dl.begin(), dl.begin() + n, 0.0f);
	std::fill(dr.begin(), dr.begin() + n, 0.0f);
	std::fill(sl.begin(), sl.begin() + n, 0.0f);
	std::fill(sr_.begin(), sr_.begin() + n, 0.0f);
	const int64_t f0 = frame, f1 = frame + n;

	bool any_done = false;
	for (const Hit &h : hits) {
		const int64_t len = (int64_t)h.buf->l.size();
		const int64_t s = std::max(h.at, f0), e = std::min(h.at + len, f1);
		if (h.once && h.at + len <= f1) {
			any_done = true;
		}
		if (s >= e) {
			continue;
		}
		const float *bl = h.buf->l.data() + (s - h.at);
		const float *br = h.buf->r.data() + (s - h.at);
		float *pl = dl.data() + (s - f0);
		float *pr = dr.data() + (s - f0);
		const int m = (int)(e - s);
		for (int i = 0; i < m; i++) {
			pl[i] += bl[i] * h.gl;
			pr[i] += br[i] * h.gr;
		}
		if (h.gs > 0.0f) {
			float *ql = sl.data() + (s - f0);
			float *qr = sr_.data() + (s - f0);
			for (int i = 0; i < m; i++) {
				ql[i] += bl[i] * h.gs;
				qr[i] += br[i] * h.gs;
			}
		}
	}
	if (any_done) {
		hits.erase(std::remove_if(hits.begin(), hits.end(),
						   [f1](const Hit &h) { return h.once && h.at + (int64_t)h.buf->l.size() <= f1; }),
				hits.end());
	}

	for (auto it = voices.begin(); it != voices.end();) {
		LiveVoice &v = it->second;
		bool ok = true;
		for (int i = 0; i < n && ok; i++) {
			double x = v.tick(sr, ok);
			double p = v.pan.tick();
			double a = (std::clamp(p, -1.0, 1.0) + 1.0) * M_PI * 0.25;
			double gl = std::cos(a) * M_SQRT2, gr = std::sin(a) * M_SQRT2;
			double snd = v.send.tick();
			dl[i] += (float)(x * gl);
			dr[i] += (float)(x * gr);
			if (snd > 0.0) {
				sl[i] += (float)(x * gl * snd);
				sr_[i] += (float)(x * gr * snd);
			}
		}
		it = ok ? std::next(it) : voices.erase(it);
	}

	if (reverb_on) {
		for (int i = 0; i < n; i++) {
			float wl, wr;
			reverb.process(sl[i], sr_[i], wl, wr);
			dl[i] += (float)(wl * rv_return);
			dr[i] += (float)(wr * rv_return);
		}
	}

	for (ChainStep &s : chain) {
		switch (s.type) {
			case ChainStep::GAIN:
				for (int i = 0; i < n; i++) {
					dl[i] = (float)(dl[i] * s.gain);
					dr[i] = (float)(dr[i] * s.gain);
				}
				break;
			case ChainStep::HIGHPASS1:
			case ChainStep::LOWPASS1: {
				const bool hp = s.type == ChainStep::HIGHPASS1;
				float *ch[2] = { dl.data(), dr.data() };
				for (int c = 0; c < 2; c++) {
					double acc = s.lp[c];
					for (int i = 0; i < n; i++) {
						acc += s.coef * (ch[c][i] - acc);
						ch[c][i] = hp ? (float)(ch[c][i] - (float)acc) : (float)acc;
					}
					s.lp[c] = acc;
				}
				break;
			}
			case ChainStep::SVF_FILTER: {
				float *ch[2] = { dl.data(), dr.data() };
				for (int c = 0; c < 2; c++) {
					for (int st = 0; st < s.stages; st++) {
						for (int i = 0; i < n; i++) {
							ch[c][i] = (float)s.svf[c][st].tick(ch[c][i], s.mode);
						}
					}
				}
				break;
			}
			case ChainStep::FADE_END:
				for (int i = 0; i < n; i++) {
					const int64_t f = f0 + i;
					if (f < s.start) {
						continue;
					}
					double g = 0.0;
					if (f < s.end) {
						g = double(s.end - f) / std::max<double>(1.0, double(s.end - s.start));
						g *= g;
					}
					dl[i] = (float)(dl[i] * g);
					dr[i] = (float)(dr[i] * g);
				}
				break;
			case ChainStep::LIMIT: {
				double g = s.lim_g;
				for (int i = 0; i < n; i++) {
					double p = std::max(std::fabs((double)dl[i]), std::fabs((double)dr[i]));
					double need = p > s.ceiling ? s.ceiling / p : 1.0;
					g = need < g ? need : need - (need - g) * s.release_k;
					dl[i] = (float)(dl[i] * g);
					dr[i] = (float)(dr[i] * g);
				}
				s.lim_g = g;
				break;
			}
		}
	}

	std::copy(dl.begin(), dl.begin() + n, out_l);
	std::copy(dr.begin(), dr.begin() + n, out_r);
	frame = f1;
}

} // namespace ak
