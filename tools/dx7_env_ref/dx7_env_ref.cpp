// SPDX-License-Identifier: Apache-2.0
// Reference levels for the `dx7` envelope mode, from msfa itself.
//
// Built against Dexed's msfa sources (env.cc, Apache-2.0; Copyright 2012
// Google Inc., 2017 Pascal Gauthier). The scaling functions below are copied
// from msfa's dx7note.cc unchanged. Reads cases from stdin, one per line:
//   r1 r2 r3 r4 l1 l2 l3 l4 output_level break_point left_depth right_depth
//   left_curve right_curve rate_scaling velocity_sens midi_note midi_velocity
//   keyoff_block blocks
// and writes, per case, the outlevel, the rate scaling and then the Q24 level
// after each getsample() call (one per 64-sample block, key-up applied
// before block `keyoff_block`), and finally msfa's isActive() per block as
// a run of 0/1 characters.
#include "env.h"
#include <cstdio>

// --- from msfa dx7note.cc ---
const uint8_t velocity_data[64] = {
    0, 70, 86, 97, 106, 114, 121, 126, 132, 138, 142, 148, 152, 156, 160, 163,
    166, 170, 173, 174, 178, 181, 184, 186, 189, 190, 194, 196, 198, 200, 202,
    205, 206, 209, 211, 214, 216, 218, 220, 222, 224, 225, 227, 229, 230, 232,
    233, 235, 237, 238, 240, 241, 242, 243, 244, 246, 246, 248, 249, 250, 251,
    252, 253, 254
};
int ScaleVelocity(int velocity, int sensitivity) {
    int clamped_vel = max(0, min(127, velocity));
    int vel_value = velocity_data[clamped_vel >> 1] - 239;
    int scaled_vel = ((sensitivity * vel_value + 7) >> 3) << 4;
    return scaled_vel;
}
int ScaleRate(int midinote, int sensitivity) {
    int x = min(31, max(0, midinote / 3 - 7));
    int qratedelta = (sensitivity * x) >> 3;
    return qratedelta;
}
const uint8_t exp_scale_data[] = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 14, 16, 19, 23, 27, 33, 39, 47, 56, 66,
    80, 94, 110, 126, 142, 158, 174, 190, 206, 222, 238, 250
};
int ScaleCurve(int group, int depth, int curve) {
    int scale;
    if (curve == 0 || curve == 3) {
        scale = (group * depth * 329) >> 12;
    } else {
        int n_scale_data = sizeof(exp_scale_data);
        int raw_exp = exp_scale_data[min(group, n_scale_data - 1)];
        scale = (raw_exp * depth * 329) >> 15;
    }
    if (curve < 2) {
        scale = -scale;
    }
    return scale;
}
int ScaleLevel(int midinote, int break_pt, int left_depth, int right_depth,
               int left_curve, int right_curve) {
    int offset = midinote - break_pt - 17;
    if (offset >= 0) {
        return ScaleCurve((offset+1) / 3, right_depth, right_curve);
    } else {
        return ScaleCurve(-(offset-1) / 3, left_depth, left_curve);
    }
}
// --- end of dx7note.cc ---

void dexed_trace(const char *, const char *, ...) {}

int main() {
    Env::init_sr(48000.0);
    int r[4], l[4], ol, bp, ld, rd, lc, rc, rs, vs, note, vel, keyoff, blocks;
    while (scanf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
            &r[0], &r[1], &r[2], &r[3], &l[0], &l[1], &l[2], &l[3], &ol, &bp, &ld, &rd, &lc, &rc,
            &rs, &vs, &note, &vel, &keyoff, &blocks) == 20) {
        int outlevel = Env::scaleoutlevel(ol);
        outlevel += ScaleLevel(note, bp, ld, rd, lc, rc);
        outlevel = min(127, outlevel);
        outlevel = outlevel << 5;
        outlevel += ScaleVelocity(vel, vs);
        outlevel = max(0, outlevel);
        int rate_scaling = ScaleRate(note, rs);
        Env env;
        env.init(r, l, outlevel, rate_scaling);
        printf("%d %d", outlevel, rate_scaling);
        char active[100000];
        for (int b = 0; b < blocks && b < 99999; b++) {
            if (b == keyoff) {
                env.keydown(false);
            }
            printf(" %d", (int)env.getsample());
            active[b] = env.isActive() ? '1' : '0';
            active[b + 1] = 0;
        }
        printf(" %s\n", active);
    }
    return 0;
}
