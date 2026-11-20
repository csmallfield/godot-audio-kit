// SPDX-License-Identifier: Apache-2.0
// Reference values for GAK's DX7 pieces from msfa itself (Dexed, Apache-2.0;
// Copyright 2012 Google Inc., 2017 Pascal Gauthier): frequencies (Freqlut and
// Dx7Note::osc_freq, copied below with standard tuning), the pitch envelope
// (pitchenv.cc), the LFO (lfo.cc) and Dx7Note::compute's pitch and amp
// modulation. Reads commands from stdin, one per line:
//   freq <mode> <coarse> <fine> <detune> <midinote> <pitch_mod>
//     -> logfreq, phase increment (Freqlut::lookup(logfreq + pitch_mod) for ratio
//        mode; fixed mode ignores pitch_mod, as Dx7Note::compute)
//   penv <r1..r4> <l1..l4> <keyoff_block> <blocks>  -> level per block
//   lfo <speed> <delay> <wave> <sync> <pmd> <pms> <amd> <blocks>
//     -> per block: lfo value, delay, pitch_mod, amd_mod, then ldiff at level
//        3840<<16 for amp mod sensitivity 1, 2, 3
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include "synth.h"
#include "freqlut.h"
#include "pitchenv.h"
#include "lfo.h"
#include "sin.h"

void dexed_trace(const char *, const char *, ...) {}

// --- from msfa dx7note.cc ---
const int32_t coarsemul[] = {
    -16777216, 0, 16777216, 26591258, 33554432, 38955489, 43368474, 47099600,
    50331648, 53182516, 55732705, 58039632, 60145690, 62083076, 63876816,
    65546747, 67108864, 68576247, 69959732, 71268397, 72509921, 73690858,
    74816848, 75892776, 76922906, 77910978, 78860292, 79773775, 80654032,
    81503396, 82323963, 83117622
};
static const uint8_t pitchmodsenstab[] = { 0, 10, 20, 33, 55, 92, 153, 255 };
static const uint32_t ampmodsenstab[] = { 0, 4342338, 7171437, 16777216 };
int32_t osc_freq(int midinote, int mode, int coarse, int fine, int detune) {
    int32_t logfreq;
    if (mode == 0) {
        logfreq = 50857777 + ((1 << 24) / 12) * midinote;  // standard tuning
        double detuneRatio = 0.0209 * exp(-0.396 * (((float)logfreq)/(1<<24))) / 7;
        logfreq += detuneRatio * logfreq * (detune - 7);
        logfreq += coarsemul[coarse & 31];
        if (fine) {
            logfreq += (int32_t)floor(24204406.323123 * log(1 + 0.01 * fine) + 0.5);
        }
    } else {
        logfreq = (4458616 * ((coarse & 3) * 100 + fine)) >> 3;
        logfreq += detune > 7 ? 13457 * (detune - 7) : 0;
    }
    return logfreq;
}
// --- end ---

int main() {
    const double rate = 48000.0;
    Sin::init();
    Freqlut::init(rate);
    Lfo::init(rate);
    PitchEnv::init(rate);
    char cmd[16];
    while (scanf("%15s", cmd) == 1) {
        if (!strcmp(cmd, "freq")) {
            int mode, coarse, fine, detune, note, pm;
            scanf("%d %d %d %d %d %d", &mode, &coarse, &fine, &detune, &note, &pm);
            int32_t lf = osc_freq(note, mode, coarse, fine, detune);
            int32_t inc = Freqlut::lookup(mode ? lf : lf + pm);
            printf("%d %d\n", lf, inc);
        } else if (!strcmp(cmd, "penv")) {
            int r[4], l[4], keyoff, blocks;
            for (int i = 0; i < 4; i++) scanf("%d", &r[i]);
            for (int i = 0; i < 4; i++) scanf("%d", &l[i]);
            scanf("%d %d", &keyoff, &blocks);
            PitchEnv pe;
            pe.set(r, l);
            for (int b = 0; b < blocks; b++) {
                if (b == keyoff) pe.keydown(false);
                printf("%s%d", b ? " " : "", pe.getsample());
            }
            printf("\n");
        } else if (!strcmp(cmd, "lfo")) {
            int speed, delay, wave, sync, pmd_raw, pms, amd_raw, blocks;
            scanf("%d %d %d %d %d %d %d %d", &speed, &delay, &wave, &sync, &pmd_raw, &pms, &amd_raw, &blocks);
            // dx7render's Lfo is a stack object that reset() doesn't fully set (phase_,
            // randstate_): zeroed here, the state GAK starts from.
            Lfo lfo;
            memset((void *)&lfo, 0, sizeof(lfo));
            uint8_t params[6] = { (uint8_t)speed, (uint8_t)delay, (uint8_t)pmd_raw, (uint8_t)amd_raw, (uint8_t)sync, (uint8_t)wave };
            lfo.reset(params);
            lfo.keydown();
            // As Dx7Note::init and compute, with no controllers (pitch_mod, amp_mod 0; eg_mod 127).
            int pitchmoddepth = (pmd_raw * 165) >> 6;
            int pitchmodsens = pitchmodsenstab[pms & 7];
            int ampmoddepth = (amd_raw * 165) >> 6;
            for (int b = 0; b < blocks; b++) {
                int32_t lv = lfo.getsample(), ld = lfo.getdelay();
                uint32_t pmd = (uint32_t)((int64_t)pitchmoddepth * (int64_t)ld);
                int32_t senslfo = pitchmodsens * (lv - (1 << 23));
                int32_t pmod_1 = (int32_t)((((int64_t)pmd) * (int64_t)senslfo) >> 39);
                pmod_1 = abs(pmod_1);
                int32_t pitch_mod = pmod_1 * (senslfo < 0 ? -1 : 1);
                int32_t lv2 = (1 << 24) - lv;
                uint32_t amod_1 = (uint32_t)(((int64_t)ampmoddepth * (int64_t)ld) >> 8);
                amod_1 = (uint32_t)(((int64_t)amod_1 * (int64_t)lv2) >> 24);
                uint32_t amd_mod = amod_1;
                uint32_t amod_3 = (127 + 1) << 17;
                amd_mod = max((uint32_t)((1 << 24) - amod_3), amd_mod);
                printf("%s%d %d %d %u", b ? " " : "", lv, ld, pitch_mod, amd_mod);
                for (int s = 1; s <= 3; s++) {
                    int32_t level = 3840 << 16;
                    uint32_t sensamp = (uint32_t)(((uint64_t)amd_mod * (uint64_t)ampmodsenstab[s]) >> 24);
                    uint32_t pt = exp(((float)sensamp) / 262144 * 0.07 + 12.2);
                    uint32_t ldiff = (uint32_t)(((uint64_t)level * (((uint64_t)pt << 4))) >> 28);
                    printf(" %u", ldiff);
                }
            }
            printf("\n");
        }
    }
    return 0;
}
