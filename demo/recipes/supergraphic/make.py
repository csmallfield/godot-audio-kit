#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Recipes for the E1 Supergraphic port, in the supergraphic palette.
Regenerate: python3 demo/recipes/supergraphic/make.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../tools"))
from write_recipes import recipe, cue_map

D = os.path.dirname(os.path.abspath(__file__))
PAL = "res://addons/audio_kit/palettes/supergraphic.tres"
R = "res://demo/recipes/supergraphic/"
level = lambda lo, hi: {"intensity": {"gain_db": [lo, hi]}}

recipes = {
    "wipe": dict(voice="whoosh", params={"length_s": 0.42, "low_hz": 250.0, "high_hz": "$whoosh_high_hz", "peak": 0.7, "shape": 1.8, "noise": "&pink"},
                 bind=level(-12.0, -2.0), vary={"high_hz": 0.2, "length_s": 0.1}, send=0.25, seed=11),
    "m_land": dict(voice="boing", params={"start_hz": "$hit_hz", "end_hz": 110.0, "drop_s": 0.05, "decay_s": 0.25, "wobble_hz": "$wobble_hz",
                   "wobble_semitones": 3.0, "sub": 0.4, "click": 0.3}, bind=level(-8.0, 0.0), send=0.2, seed=12),
    "m_stack": dict(voice="click", params={"freq_hz": 3000.0, "mode": "&band", "q": 4.0, "decay_s": 0.006, "body_hz": 140.0, "body": 0.7},
                    bind=level(-16.0, -6.0), seed=13),
    "slide": dict(voice="whoosh", params={"length_s": 0.3, "low_hz": 400.0, "high_hz": 3500.0, "peak": 0.5, "noise": "&pink"},
                  bind=level(-18.0, -8.0), send=0.2, seed=14),
    "letter": dict(voice="pluck", params={"freq_hz": "$root_hz", "brightness": 0.35, "decay_s": 0.3, "tone_hz": 3200.0},
                   bind={"intensity": {"gain_db": [-14.0, -6.0]}, "data.pitch": "pitch_scale"}, vary={"decay_s": 0.1}, send=0.25, seed=15),
    "rule": dict(voice="ratchet", params={"length_s": 0.45, "start_rate_hz": 60.0, "end_rate_hz": 24.0, "click_hz": 5000.0, "q": 4.0, "fade": 0.5},
                 bind=level(-20.0, -10.0), seed=16),
    "disc_pop": dict(voice="tone", params={"wave": "&sine", "freq_hz": 380.0, "end_hz": 900.0, "glide_s": 0.03, "decay_s": 0.09, "gate_s": 0.1, "length_s": 0.16},
                     layers=[{"voice": "&click", "params": {"freq_hz": 2500.0, "mode": "&band", "q": 2.0, "decay_s": 0.003}, "gain_db": -10.0}],
                     bind={"intensity": {"gain_db": [-16.0, -6.0]}, "data.pitch": "pitch_scale"}, send=0.2, seed=17),
    "land": dict(voice="boing", params={"start_hz": 260.0, "end_hz": 82.0, "drop_s": 0.06, "decay_s": 0.22, "wobble_hz": 7.0, "wobble_semitones": 2.0,
                 "sub": 0.7, "click": 0.4}, bind={"intensity": {"gain_db": [-8.0, 0.0]}, "data.pitch": "pitch_scale"}, send=0.2, seed=18),
    "edge": dict(voice="click", params={"freq_hz": 6000.0, "mode": "&high", "decay_s": 0.004}, bind=level(-22.0, -12.0), vary={"freq_hz": 0.15}, seed=19),
    "node": dict(voice="mallet", params={"freq_hz": "$root_hz", "material": "$mallet", "hardness": "$mallet_hardness", "decay_s": 0.3},
                 bind={"intensity": {"gain_db": [-16.0, -8.0]}, "data.pitch": "pitch_scale"}, send=0.3, seed=20),
    "word": dict(voice="whoosh", params={"length_s": 0.35, "low_hz": 500.0, "high_hz": 7000.0, "peak": 0.35, "shape": 2.2},
                 layers=[{"voice": "&tone", "params": {"wave": "&triangle", "freq_hz": "$fifth_hz", "decay_s": 0.12, "gate_s": 0.12, "length_s": 0.3}, "gain_db": -10.0, "offset_s": 0.08}],
                 bind=level(-14.0, -6.0), send=0.25, seed=21),
    "pill": dict(voice="tone", params={"wave": "&triangle", "freq_hz": 880.0, "end_hz": 1320.0, "glide_s": 0.02, "decay_s": 0.07, "gate_s": 0.08, "length_s": 0.15},
                 bind={"intensity": {"gain_db": [-16.0, -8.0]}, "data.pitch": "pitch_scale"}, send=0.2, seed=22),
    "launch": dict(voice="tone", params={"wave": "&sine", "freq_hz": 200.0, "end_hz": 900.0, "glide_s": 0.18, "attack_s": 0.004, "decay_s": 0.3, "gate_s": 0.3, "length_s": 0.42},
                   layers=[{"voice": "&whoosh", "params": {"length_s": 0.4, "low_hz": 400.0, "high_hz": 3000.0, "peak": 0.6}, "gain_db": -8.0}],
                   bind={"intensity": {"gain_db": [-10.0, -2.0]}, "data.pitch": "pitch_scale"}, send=0.25, seed=23),
}
# The outro runs build sounds backwards: reversed, starting early so the
# reversed tail swells into the cue frame.
rev = [{"type": "reverse"}]
recipes["pill_out"] = dict(recipes["pill"], transforms=rev, offset_s=-0.15)
recipes["word_out"] = dict(recipes["word"], transforms=rev, offset_s=-0.35)
recipes["node_out"] = dict(recipes["node"], params=dict(recipes["node"]["params"], decay_s=0.15, length_s=0.5), transforms=rev, offset_s=-0.5)
recipes["disc_out"] = dict(recipes["disc_pop"], transforms=rev, offset_s=-0.16)

for name, f in recipes.items():
    recipe(os.path.join(D, name + ".tres"), palette=PAL, **f)

cue_map(os.path.join(D, "e1_map.tres"), {
    "wipe.*": R + "wipe.tres", "m.land": R + "m_land.tres", "m.stack": R + "m_stack.tres", "m.slide": R + "slide.tres",
    "letter": R + "letter.tres", "rule.draw": R + "rule.tres", "disc.pop": R + "disc_pop.tres", "land.*": R + "land.tres",
    "edge": R + "edge.tres", "node": R + "node.tres", "word": R + "word.tres", "pill": R + "pill.tres",
    "pill.out": R + "pill_out.tres", "word.out": R + "word_out.tres", "node.out": R + "node_out.tres",
    "launch": R + "launch.tres", "disc.out": R + "disc_out.tres",
}, master_fx=[{"type": "dcblock"}, {"type": "loudness", "target_lufs": -16.0}, {"type": "limit", "ceiling_db": -1.5}],
   reverb={"room": 0.45, "damp": 0.55, "width": 1.0, "quality": "&full", "return_db": 0.0})
print("wrote", len(recipes), "recipes and e1_map.tres")
