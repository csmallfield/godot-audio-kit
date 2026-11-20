// dx7render: render one DX7 voice to a WAV of held notes, offline.
//
// Built against Dexed's DX7 engine (msfa, Apache-2.0, plus Dexed's GPL-3 "Mark I"
// operator engine), fetched by build.ps1 into a folder outside this repo. This file
// only drives the engine the way Dexed's PluginProcessor does: same inits, same 64-sample
// blocks, same LFO calls, same output scaling and clipping.
//
// usage: dx7render <voice.bin> <out.wav> [--notes 36,48,60,72,84] [--velocity 100]
//                  [--hold 2.0] [--release 2.5] [--gap 0.25] [--rate 48000] [--engine mki|msfa]
// voice.bin: 155 unpacked DX7 voice bytes (VCED order), optionally a 156th byte with the
// operator on/off mask (default 0x3f, all on).
// Output: mono 16-bit PCM (the engine's own resolution). Notes play one after another: each is held `hold` seconds,
// then released and left to ring for `release` seconds, then `gap` seconds of silence.
// Each note starts from zeroed engine state (Lfo and Dx7Note storage), so renders are
// deterministic: msfa never initialises Lfo::phase_/randstate_ or Dx7Note::fb_buf_.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <vector>

#include "msfa/synth.h"
#include "msfa/aligned_buf.h"
#include "msfa/controllers.h"
#include "msfa/dx7note.h"
#include "msfa/env.h"
#include "msfa/exp2.h"
#include "msfa/fm_core.h"
#include "msfa/freqlut.h"
#include "msfa/lfo.h"
#include "msfa/pitchenv.h"
#include "msfa/porta.h"
#include "msfa/sin.h"
#include "msfa/tuning.h"
#include "engine/EngineMkI.h"

static void put32(FILE *f, uint32_t v) { fwrite(&v, 4, 1, f); }
static void put16(FILE *f, uint16_t v) { fwrite(&v, 2, 1, f); }

// The engine's output is 16-bit (Dexed keeps the top 16 bits), so the WAV is 16-bit PCM.
static bool write_wav16(const char *path, const std::vector<int16_t> &s, int rate) {
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    uint32_t data = (uint32_t)s.size() * 2;
    fwrite("RIFF", 1, 4, f); put32(f, 36 + data); fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f); put32(f, 16); put16(f, 1); put16(f, 1);
    put32(f, rate); put32(f, rate * 2); put16(f, 2); put16(f, 16);
    fwrite("data", 1, 4, f); put32(f, data);
    fwrite(s.data(), 2, s.size(), f);
    fclose(f);
    return true;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: dx7render <voice.bin> <out.wav> [--notes a,b,..] [--velocity v] "
                        "[--hold s] [--release s] [--gap s] [--rate hz] [--engine mki|msfa]\n");
        return 2;
    }
    std::vector<int> notes = {36, 48, 60, 72, 84};
    int velocity = 100, rate = 48000;
    double hold = 2.0, release = 2.5, gap = 0.25;
    std::string engine = "mki";
    for (int i = 3; i + 1 < argc; i += 2) {
        std::string k = argv[i], v = argv[i + 1];
        if (k == "--notes") {
            notes.clear();
            size_t p = 0;
            while (p < v.size()) {
                size_t q = v.find(',', p);
                notes.push_back(atoi(v.substr(p, q == std::string::npos ? std::string::npos : q - p).c_str()));
                if (q == std::string::npos) break;
                p = q + 1;
            }
        } else if (k == "--velocity") velocity = atoi(v.c_str());
        else if (k == "--hold") hold = atof(v.c_str());
        else if (k == "--release") release = atof(v.c_str());
        else if (k == "--gap") gap = atof(v.c_str());
        else if (k == "--rate") rate = atoi(v.c_str());
        else if (k == "--engine") engine = v;
        else { fprintf(stderr, "unknown option %s\n", k.c_str()); return 2; }
    }

    uint8_t patch[156];
    FILE *vf = fopen(argv[1], "rb");
    if (!vf) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
    size_t got = fread(patch, 1, 156, vf);
    fclose(vf);
    if (got < 155) { fprintf(stderr, "voice file must hold 155 or 156 bytes\n"); return 1; }
    if (got == 155) patch[155] = 0x3f;

    // Same static inits as Dexed (PluginProcessor constructor and prepareToPlay).
    Exp2::init();
    Tanh::init();
    Sin::init();
    Freqlut::init(rate);
    Lfo::init(rate);
    PitchEnv::init(rate);
    Env::init_sr(rate);
    Porta::init_sr(rate);

    FmCore msfa;
    EngineMkI mki;
    Controllers ctrl;
    ctrl.core = engine == "msfa" ? (FmCore *)&msfa : (FmCore *)&mki;
    ctrl.pitch_range_up = 3;
    ctrl.pitch_range_dn = 3;
    ctrl.pitch_step = 0;
    ctrl.masterTune = 0;
    ctrl.pitch_cc = 0x2000;
    ctrl.modwheel_cc = 0;
    ctrl.foot_cc = 0;
    ctrl.breath_cc = 0;
    ctrl.aftertouch_cc = 0;
    ctrl.portamento_enable_cc = false;
    ctrl.portamento_cc = 0;
    ctrl.portamento_gliss_cc = false;
    ctrl.mpeEnabled = false;
    ctrl.refresh();

    auto tuning = createStandardTuning();
    std::vector<int16_t> out;
    const int hold_n = (int)(hold * rate), rel_n = (int)(release * rate), gap_n = (int)(gap * rate);

    for (int note : notes) {
        int pitch = note + (int)patch[144] - 24;  // voice transpose, as Dexed's keydown
        if (pitch < 0) pitch = 0;
        if (pitch > 127) pitch = 127;
        // msfa leaves some per-note state uninitialised (Lfo::phase_ unless key sync,
        // Lfo::randstate_, and Dx7Note::fb_buf_, which the constructor never clears), so a
        // stack object would start from whatever was in memory. Zero both before use.
        Lfo lfo;
        memset((void *)&lfo, 0, sizeof(lfo));
        lfo.reset(patch + 137);
        lfo.keydown();
        alignas(Dx7Note) unsigned char note_mem[sizeof(Dx7Note)];
        memset(note_mem, 0, sizeof(note_mem));
        Dx7Note &dn = *new (note_mem) Dx7Note(tuning, nullptr);
        dn.init(patch, pitch, velocity, 1, &ctrl);
        int total = hold_n + rel_n;
        bool released = false;
        for (int pos = 0; pos < total; pos += N) {
            if (!released && pos >= hold_n) { dn.keyup(); released = true; }
            AlignedBuf<int32_t, N> buf;
            for (int j = 0; j < N; ++j) buf.get()[j] = 0;
            int32_t lv = lfo.getsample(), ld = lfo.getdelay();
            dn.compute(buf.get(), lv, ld, &ctrl);
            for (int j = 0; j < N && pos + j < total; ++j) {
                int32_t val = buf.get()[j] >> 4;
                int clip = val < -(1 << 24) ? -0x8000 : val >= (1 << 24) ? 0x7fff : val >> 9;
                out.push_back((int16_t)clip);
            }
        }
        dn.~Dx7Note();
        out.insert(out.end(), gap_n, (int16_t)0);
    }
    if (!write_wav16(argv[2], out, rate)) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    return 0;
}
