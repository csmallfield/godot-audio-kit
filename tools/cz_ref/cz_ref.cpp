// SPDX-License-Identifier: BSD-3-Clause
// CZ reference renders: MAME's uPD933 (the CZ's sound chip, BSD-3-Clause, Devin Acker), unchanged,
// driven by a small firmware stand-in that steps the envelopes.
//
//   cz_ref <script.txt> <out.wav>
//
// The script (written by make_ref.py from a tone's data) holds whitespace-separated lines:
//   samples N                              length of the render, at the chip's 40 kHz
//   write T REG VALUE                      a register write at sample T (VALUE 16 bits)
//   env KIND V T_ON T_OFF SUSTAIN END n s0 .. s(n-1)
//       an 8-step envelope for voice V: KIND 0 DCA, 2 DCO, 4 DCW (register base 0x00, 0x10,
//       0x20); s are the step registers. Step 0 is written at T_ON. Each time the chip says a
//       step reached its level (its interrupt), the next step is written, up to END; the step
//       SUSTAIN holds until T_OFF, when the envelope moves on to the step after it.
// No CZ ROM is available: this stepping is the documented behaviour, not the firmware's code.
#include <array>
#include <vector>
#include <string>
#include <fstream>
#include <iostream>
#include <algorithm>
#include <climits>
#include <cmath>
#include <numbers>
#include "emu.h"
// The chip's source is built into this file with its private parts opened, so the harness can
// read the envelopes' interrupt flags and pull one sample at a time (the code itself is unchanged).
#define private public
#define protected public
#include "upd933.cpp"
#undef private
#undef protected

struct Env { int kind, v; long t_on, t_off; int sustain, end; std::vector<u16> steps; int idx = -1; bool released = false; };

static void reg_write(upd933_device &c, int reg, u16 value)
{
	c.write(u8(reg)); c.write(u8(value >> 8)); c.write(u8(value & 0xff));
}

static upd933_device::env_t &chip_env(upd933_device &c, const Env &e)
{
	return e.kind == 0 ? c.m_dca[e.v] : e.kind == 2 ? c.m_dco[e.v] : c.m_dcw[e.v];
}

// The step's direction (bit 15) is set from where the envelope is now, as the firmware must:
// the scripts give each step's rate (bits 8-14) and level (bits 0-6, a DCO's units in bit 6).
static void step_to(upd933_device &c, Env &e, int idx)
{
	e.idx = idx;
	u16 v = e.steps[idx] & 0x7fff;
	const u32 lv = v & 0x7f;
	u32 target = e.kind == 0 ? lv << 18 : e.kind == 4 ? lv << 19 : ((lv & 0x3f) << 16) << ((lv & 0x40) ? 5 : 0);
	if (target < chip_env(c, e).m_current)
		v |= 0x8000;
	reg_write(c, e.kind * 8 + e.v, v);
}

int main(int argc, char **argv)
{
	if (argc < 3) { std::cerr << "usage: cz_ref script.txt out.wav\n"; return 2; }
	std::ifstream in(argv[1]);
	long n = 0;
	struct W { long t; int reg; u16 value; };
	std::vector<W> writes;
	std::vector<Env> envs;
	std::string tok;
	while (in >> tok) {
		if (tok == "samples") in >> n;
		else if (tok == "write") { W w; long v; in >> w.t >> w.reg >> v; w.value = u16(v); writes.push_back(w); }
		else if (tok == "env") {
			Env e; int cnt; in >> e.kind >> e.v >> e.t_on >> e.t_off >> e.sustain >> e.end >> cnt;
			for (int i = 0; i < cnt; i++) { long v; in >> v; e.steps.push_back(u16(v)); }
			envs.push_back(e);
		} else { std::cerr << "unknown: " << tok << "\n"; return 2; }
	}
	machine_config mc;
	upd933_device chip(mc, "upd933", nullptr, 4480000);  // the CZ-101's 8.96 MHz / 2: 40 kHz
	chip.device_start();
	chip.device_reset();
	chip.cs_w(0);
	std::vector<float> out(n);
	size_t wi = 0;
	for (long t = 0; t < n; t++) {
		for (auto &w : writes) if (w.t == t) reg_write(chip, w.reg, w.value);
		for (auto &e : envs) {
			if (t == e.t_on) { e.released = false; step_to(chip, e, 0); }
			if (t == e.t_off && e.idx >= 0) {
				e.released = true;
				if (e.idx <= e.sustain && e.sustain < e.end) step_to(chip, e, e.sustain + 1);
			}
		}
		chip.m_s.n = 1; chip.m_s.out = &out[t];
		chip.sound_stream_update(chip.m_s);
		for (auto &e : envs) {
			auto &ce = chip_env(chip, e);
			if (e.idx < 0 || !ce.m_irq) continue;
			ce.m_irq = false;
			if (e.idx < e.end && (e.released || e.idx != e.sustain)) step_to(chip, e, e.idx + 1);
		}
	}
	(void)wi;
	std::ofstream f(argv[2], std::ios::binary);
	auto u32w = [&](u32 v) { f.write((const char *)&v, 4); };
	auto u16w = [&](u16 v) { f.write((const char *)&v, 2); };
	u32 bytes = u32(n * 4);
	f.write("RIFF", 4); u32w(36 + bytes); f.write("WAVEfmt ", 8); u32w(16); u16w(3); u16w(1);
	u32w(40000); u32w(160000); u16w(4); u16w(32); f.write("data", 4); u32w(bytes);
	f.write((const char *)out.data(), bytes);
	return 0;
}
