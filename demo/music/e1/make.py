#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""E1 Supergraphic music bed: bright electro at 120 bpm, modelled on the
original's structure (an arp-only opening, the full groove from the SCF
build, a short fading tail). Regenerate: python3 demo/music/e1/make.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../tools"))
from write_recipes import recipe, resource

D = os.path.dirname(os.path.abspath(__file__))
R = "res://demo/music/e1/"
S = "res://addons/audio_kit/sequencer/"

# ---- instruments
recipe(os.path.join(D, "bass.tres"), voice="wavetable", seed=31,
       params={"position": 0.66, "sub": 0.25, "cutoff_hz": 500.0, "env_octaves": 2.3, "filter_decay_s": 0.12, "q": 1.3,
               "attack_s": 0.002, "decay_s": 0.09, "sustain": 0.12, "release_s": 0.03},
       bind={"intensity": {"gain_db": [-8.0, 0.0]}})
recipe(os.path.join(D, "kick.tres"), voice="kick", seed=32,
       params={"tune_hz": 48.0, "punch": 3.0, "decay_s": 0.26, "click": 0.3, "drive": 0.25},
       bind={"intensity": {"gain_db": [-6.0, 0.0]}})
recipe(os.path.join(D, "clap.tres"), voice="clap", seed=33, send=0.3,
       params={"color_hz": 1300.0, "tail_decay_s": 0.1}, bind={"intensity": {"gain_db": [-6.0, 0.0]}})
recipe(os.path.join(D, "hat.tres"), voice="hat", seed=34, vary={"decay_s": 0.25}, vary_variants=4,
       params={"decay_s": 0.035, "tone_hz": 9000.0, "metal": 0.5}, bind={"intensity": {"gain_db": [-8.0, 0.0]}})
recipe(os.path.join(D, "pad.tres"), voice="wavetable", seed=35, send=0.45,
       params={"position": 0.6, "unison": 5, "detune_cents": 18.0, "cutoff_hz": 1500.0, "env_octaves": 0.6, "filter_decay_s": 1.0,
               "q": 0.7, "attack_s": 0.25, "decay_s": 0.6, "sustain": 0.7, "release_s": 0.25})

# ---- notes: the original's arp, A-A-G-C over four bars
ARP = [45, 57, 45, 52, 45, 55, 45, 60]
SHIFT = [0, 0, -2, 3]
bass_notes = [ARP[s % 8] + SHIFT[s // 16] - 12 for s in range(64)]
pad_roots = [57 + SHIFT[b] for b in range(4)]

bass = {"name": "bass", "recipe": R + "bass.tres", "steps": "Xxxx" * 16, "notes": bass_notes, "gate": 0.85, "gain_db": -2.0}
hat = {"name": "hat", "recipe": R + "hat.tres", "steps": ".o.o.o.o.o.x.o.o", "length": 16, "gain_db": -12.0, "pan": 0.2}
kick = {"name": "kick", "recipe": R + "kick.tres", "steps": "X...X...X...X...", "length": 16}
clap = {"name": "clap", "recipe": R + "clap.tres", "steps": "....X.......X...", "length": 16, "gain_db": -5.0}
pad = {"name": "pad", "recipe": R + "pad.tres", "steps": "x" + "." * 15, "notes": pad_roots, "chord": [0, 3, 7, 12],
       "gate": 15.0, "gain_db": -7.0}

P = "AKPattern"
resource(os.path.join(D, "arp.tres"), P, S + "pattern.gd", {"steps": 64, "seed": 1, "lanes": [bass, hat]}, typed={"lanes"})
resource(os.path.join(D, "full.tres"), P, S + "pattern.gd", {"steps": 64, "seed": 2, "lanes": [bass, kick, clap, hat, pad]}, typed={"lanes"})
resource(os.path.join(D, "light.tres"), P, S + "pattern.gd", {"steps": 64, "seed": 3, "lanes": [bass, kick]}, typed={"lanes"})
resource(os.path.join(D, "tempo.tres"), "AKTempoMap", S + "tempo_map.gd", {"bpm": 120.0, "beats_per_bar": 4, "offset_s": 0.25})

# Sections follow the picture: the MH part (to 5.25 s), the SCF build and
# hold (to 11.75 s), then a short tail that fades before the last frame.
resource(os.path.join(D, "e1_song.tres"), "AKSong", S + "song.gd", {
    "sections": [
        {"name": "arp", "bars": 2.5, "patterns": [R + "arp.tres"], "automation": {"bass.cutoff_hz": [[0.0, 280.0], [1.0, 420.0]]}},
        {"name": "full", "bars": 3.25, "patterns": [R + "full.tres"], "automation": {"bass.cutoff_hz": [[0.0, 500.0], [1.0, 800.0]]}},
        {"name": "light", "bars": 0.625, "patterns": [R + "light.tres"],
         "automation": {"bass.gain_db": [[0.0, 0.0], [1.0, -14.0]], "kick.gain_db": [[0.0, 0.0], [1.0, -10.0]], "bass.cutoff_hz": [[0.0, 600.0], [1.0, 300.0]]}},
    ],
    "gain_db": -3.0,
}, refs={"tempo": R + "tempo.tres"}, typed={"sections"})
print("wrote E1 music: 5 instruments, 3 patterns, tempo, song")
